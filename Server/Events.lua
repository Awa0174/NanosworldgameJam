-- Server/Events.lua
-- Event-System: Register, Auswahl und der Kontext, mit dem ein laufendes Event arbeitet.
--
-- Ein Event ist ein Modul (siehe Server/Events/*.lua) mit dieser Schnittstelle:
--   id            eindeutiger Name, z. B. "revolver". Haeufigkeit: Config.EVENT_WEIGHTS[id] (je Phase, zentral abgestimmt)
--   min_alive     braucht mindestens so viele lebende Spieler
--   actors        wie viele Spieler Jack auswaehlt (Standard 1, Split or Steal: 2)
--   kinds         Abfrage-Arten, die das Event stellt (z. B. { "target" }). Ausgewuerfelt wird es nur, wenn das HUD
--                 alle anzeigen kann (Config.HUD_CHOICE_KINDS).
--   Start(ctx)    Event beginnt, ctx.actors = Liste der gewaehlten Plaetze
--   OnInput(ctx, seat_index, choice, kind)   gepruefte Eingabe eines Spielers (oder Bots)
--   OnSeatLeft(ctx, seat_index, was_alive)   optional: jemand hat die Show verlassen
--   OnAim(ctx, seat_index, target)           optional: Zwischenstand einer Zielwahl (Abfrage mit extra.aim = true,
--                                            DeathBox:Aim, schon geprueft: target = 0 oder erlaubte Option)
--   GetPublic(ctx)                           optional: Daten fuer das HUD (fuer alle sichtbar)
--
-- Klarheit (docs/PROTOCOL.md): Jede Phase setzt mit ctx:Stage(...) ihre Stage-Zeile (Texte in Shared/Text.lua,
-- EVENTS.<id>.stage): was die Beteiligten tun muessen ("YOUR TURN - ...", "GET READY - ...") und was alle anderen sehen.
-- Feste Wartezeiten bis zur naechsten Abfrage ("GET READY") bekommen ihre Restzeit: ctx:Stage(key, values, involved, seconds).
--
-- Steht das Ergebnis fest, ruft das Event ctx:Conclude(seconds) (State.event.final, Ergebnis-Pause, dann Finish).
-- Das Event beendet sich selbst mit ctx:Finish(). Danach geht es in Match.lua weiter.
-- Ein Event-Kontext gehoert immer zu genau einem Match (Tisch).
--
-- Sicherheitsprinzip: Ein Spieler kann nur antworten, wenn fuer SEINEN Platz eine Abfrage
-- offen ist, die ID stimmt und seine Wahl in der erlaubten Liste steht. Bei Abfragen, deren Antwort
-- ein Platz ist ("target", "pass"), muss dieser Platz ausserdem noch leben.

DeathBox.Events = {
	registry = {},
	next_ask_id = 0,
}

local EventSystem = DeathBox.Events
local Config = DeathBox.Config
local Text = DeathBox.Text
local Net = DeathBox.Net
local Hand = DeathBox.Hand

-- Abfragen, deren Antwort ein Platz ist (muss bei der Antwort noch leben)
local SEAT_KINDS = { target = true, pass = true }
-- Todesarten, bei denen Safety greifen kann (in den Events, fuer die die Karte gilt)
local GUNSHOT = { shot = true, ricochet = true }
-- extra-Felder einer Abfrage, die nur der Server kennt (gehen nicht ans HUD)
local SERVER_ONLY = { bot_pick = true, bot_delay = true, no_timer = true }
-- Regieanweisungen, bei denen ein Platz (seat, beim Duell auch seat2) in Gefahr ist: "survived" im Rundenergebnis
local DANGER_CUES = {
	revolver_aim = true, angry_aim = true, knife_raise = true, fire_breath = true, stab_raise = true, vote_start = true,
	pumpkin_start = true, pumpkin_pass = true, bomb_start = true, duel_start = true, ricochet = true,
}

-- ===================================================================
-- Register und Auswahl
-- ===================================================================

function EventSystem.Register(def)
	assert(type(def.id) == "string", "Event braucht eine id")
	assert(type(def.Start) == "function", "Event braucht Start()")
	assert(type(def.OnInput) == "function", "Event braucht OnInput()")
	def.min_alive = def.min_alive or 2
	def.actors = def.actors or 1
	def.kinds = def.kinds or {}
	EventSystem.registry[def.id] = def
	Console.Log("[DeathBox] Event registriert: %s", def.id)
end

-- Kann das HUD jede Abfrage dieses Events anzeigen?
function EventSystem.IsPresentable(def)
	for _, kind in ipairs(def.kinds) do
		if (not Config.HUD_CHOICE_KINDS[kind]) then return false end
	end
	return true
end

local function Fits(def, alive_count)
	return alive_count >= def.min_alive and alive_count >= def.actors
end

function EventSystem.Exists(id)
	return EventSystem.registry[id] ~= nil
end

function EventSystem.GetIds()
	local ids = {}
	for id in pairs(EventSystem.registry) do table.insert(ids, id) end
	table.sort(ids)
	return ids
end

-- Gewicht nach Phase: riesig / viele / mittel / wenige Lebende (Config.EVENT_PHASES).
-- Ohne Zeile in Config.EVENT_WEIGHTS gilt 1 (neues Event, noch nicht abgestimmt).
function EventSystem.WeightOf(def, alive_count)
	local weights = Config.EVENT_WEIGHTS[def.id]
	if (not weights) then return 1 end
	if (alive_count >= Config.EVENT_PHASES.HUGE) then return weights[1] end
	if (alive_count >= Config.EVENT_PHASES.MANY) then return weights[2] end
	if (alive_count >= Config.EVENT_PHASES.MID) then return weights[3] end
	return weights[4]
end

-- Gewichtet zufaellig, nicht zweimal dasselbe hintereinander (wenn es eine Alternative gibt).
-- forced_id (Debug: /event) gewinnt, wenn genug leben, auch ohne HUD-Panel (zum Testen).
function EventSystem.Pick(alive_count, last_id, forced_id)
	local forced = forced_id and EventSystem.registry[forced_id]
	if (forced and Fits(forced, alive_count)) then
		return forced
	end

	local candidates = {}
	for _, def in pairs(EventSystem.registry) do
		if (Fits(def, alive_count) and EventSystem.IsPresentable(def) and EventSystem.WeightOf(def, alive_count) > 0) then
			table.insert(candidates, def)
		end
	end
	if (#candidates > 1) then
		for i = #candidates, 1, -1 do
			if (candidates[i].id == last_id) then table.remove(candidates, i) end
		end
	end
	table.sort(candidates, function(a, b) return a.id < b.id end)   -- feste Reihenfolge, gleiche Verteilung

	local total = 0
	for _, def in ipairs(candidates) do total = total + EventSystem.WeightOf(def, alive_count) end
	if (total <= 0) then return nil end

	local roll = math.random() * total
	for _, def in ipairs(candidates) do
		roll = roll - EventSystem.WeightOf(def, alive_count)
		if (roll <= 0) then return def end
	end
	return candidates[#candidates]
end

-- ===================================================================
-- Kontext
-- ===================================================================

local Context = {}
Context.__index = Context

function EventSystem.NewContext(match, def, actors, on_finish)
	return setmetatable({
		match = match,
		def = def,
		id = def.id,
		actors = actors,
		actor_index = actors[1],
		data = {},
		asks = {},       -- seat_index -> { id, kind, options, on_timeout, extra, ends_at, timer, bot_timer }
		timers = {},
		finished = false,
		on_finish = on_finish,
		endangered = {},      -- Plaetze, die in diesem Event in Gefahr waren (Reihenfolge), fuer "round_end"
		endangered_set = {},
	}, Context)
end

function Context:Seat(index) return self.match.seats[index] end

function Context:Name(index)
	local seat = self.match.seats[index]
	return seat and seat.name or "?"
end

function Context:IsAlive(index)
	local seat = self.match.seats[index]
	return seat ~= nil and seat.alive
end

-- Alle lebenden Plaetze, optional ohne einen bestimmten
function Context:AliveSeats(except_index)
	local result = {}
	for index, seat in ipairs(self.match.seats) do
		if (seat.alive and index ~= except_index) then table.insert(result, index) end
	end
	return result
end

-- Naechster lebender Platz in einer Richtung (+1 = aufsteigende Platznummer = im Uhrzeigersinn, -1 = dagegen).
-- Plaetze sind in Stuhl-Reihenfolge nummeriert. nil, wenn sonst niemand lebt.
function Context:NextAlive(index, direction)
	local count = #self.match.seats
	for step = 1, count - 1 do
		local other = ((index - 1 + direction * step) % count) + 1
		if (self:IsAlive(other)) then return other end
	end
	return nil
end

-- Linker und rechter lebender Nachbar (bei zwei Lebenden derselbe, dann nur einmal)
function Context:Neighbours(index)
	local result = {}
	for _, direction in ipairs({ -1, 1 }) do
		local other = self:NextAlive(index, direction)
		if (other and other ~= index and other ~= result[1]) then table.insert(result, other) end
	end
	return result
end

-- Jack spricht. lines = Liste oder Text aus DeathBox.Text, values = Platzhalter
function Context:Say(lines, values)
	self.match:Say(Text.Format(lines, values))
end

function Context:Fx(kind, seat)
	self.match:Fx(kind, seat)
end

function Context:Push()
	self.match:PushState()
end

-- Regieanweisung an alle Clients am Tisch (3D-Effekte, Jack, Licht, Musik). Plaetze werden fuer den
-- Client um die Stuhl-Nummer ergaenzt, damit er die Position selbst berechnen kann (Shared/Layout.lua).
function Context:Show(action, data)
	if (DANGER_CUES[action] and data) then
		self:Endanger(data.seat)
		if (action == "duel_start") then self:Endanger(data.seat2) end
	end
	self.match:Show(action, data)
end

-- Platz war in Gefahr (lebt er am Ende noch, steht er in "survived" des Rundenergebnisses)
function Context:Endanger(index)
	if (type(index) == "number" and self.match.seats[index] and not self.endangered_set[index]) then
		self.endangered_set[index] = true
		table.insert(self.endangered, index)
	end
end

local function StageValues(self, values)
	local merged = { name = self:Name(self.actors[1]), name2 = self.actors[2] and self:Name(self.actors[2]) or nil }
	for key, value in pairs(values or {}) do merged[key] = value end
	return merged
end

-- Stage-Zeile der aktuellen Phase (State.event.instruction_actor / instruction_others, docs/PROTOCOL.md "Klarheit").
--   key       Phase in Text.EVENTS[id].stage: ein Text fuer alle oder { actor = ..., others = ... }
--   values    Platzhalter ({name}/{name2} = Gewaehlte, wenn nicht angegeben)
--   involved  Plaetze, fuer die der actor-Text gilt, auch ohne offene Abfrage (z. B. "GET READY" im Intro)
--   seconds   optional: so lange dauert diese Phase (Zeitbalken im HUD, State.timer), z. B. "GET READY" bis zur
--             ersten Abfrage. Nie bei geheimen Zeiten (Duell bis "DRAW!"). Die naechste Abfrage ersetzt ihn.
-- Schickt keinen Zustand; das macht der naechste Push des Events.
function Context:Stage(key, values, involved, seconds)
	local lines = (Text.EVENTS[self.id] or {}).stage or {}
	local entry = lines[key]
	if (not entry) then
		Console.Warn("[DeathBox] Stage-Zeile fehlt: %s.%s", self.id, tostring(key))
		return
	end
	if (seconds) then self.match:SetTimer(seconds) end
	local merged = StageValues(self, values)
	if (type(entry) == "table") then
		self.data.stage_actor = Text.Format(entry.actor or "", merged)
		self.data.stage_others = Text.Format(entry.others or "", merged)
	else
		self.data.stage_actor = Text.Format(entry, merged)
		self.data.stage_others = self.data.stage_actor
	end
	self.data.involved = involved
end

-- Wie Stage, aber mit einem fertigen Text fuer alle (Text.STAGE, z. B. Ricochet und Safety in jedem Schuss-Event)
function Context:StageText(text, values)
	self.data.stage_actor = Text.Format(text, StageValues(self, values))
	self.data.stage_others = self.data.stage_actor
	self.data.involved = nil
end

local function ClearTimer(id)
	if (id and Timer.IsValid(id)) then Timer.ClearTimeout(id) end
end

-- Nach seconds Sekunden callback ausfuehren (nur solange das Event laeuft)
function Context:After(seconds, callback)
	if (self.finished) then return end
	local id
	id = Timer.SetTimeout(function()
		self.timers[id] = nil
		if (not self.finished) then callback() end
	end, math.max(0, math.floor(seconds * 1000 + 0.5)))
	self.timers[id] = true
	return id
end

-- Zufaellige Zahl zwischen range[1] und range[2] (Config-Wertepaare wie { 0.6, 2.0 })
function Context:Between(range)
	return range[1] + math.random() * (range[2] - range[1])
end

-- Ist diese Wahl fuer die offene Abfrage erlaubt?
function Context:IsValidChoice(ask, choice)
	for _, option in ipairs(ask.options) do
		if (option == choice) then
			return not SEAT_KINDS[ask.kind] or self:IsAlive(choice)
		end
	end
	return false
end

local function Declares(def, kind)
	for _, declared in ipairs(def.kinds) do
		if (declared == kind) then return true end
	end
	return false
end

-- Oeffnet eine Abfrage fuer einen Platz (ohne HUD-Zeitbalken und ohne Push, das machen Ask/AskMany)
local function OpenAsk(self, seat_index, kind, options, seconds, on_timeout, extra)
	local seat = self.match.seats[seat_index]
	if (not seat or #options == 0) then return false end
	extra = extra or {}
	-- Nicht angemeldete Art: die HUD-Sperre (EventSystem.IsPresentable) wuerde dieses Event nicht aufhalten
	if (not Declares(self.def, kind)) then
		Console.Warn("[DeathBox] Event '%s' fragt '%s', ohne es in kinds anzumelden", self.id, kind)
	end

	self:CloseAsk(seat_index)
	EventSystem.next_ask_id = EventSystem.next_ask_id + 1
	local ask = {
		id = EventSystem.next_ask_id, kind = kind, options = options,
		on_timeout = on_timeout, extra = extra, ends_at = Net.Now() + seconds * 1000,
	}
	self.asks[seat_index] = ask

	ask.timer = self:After(seconds, function()
		if (self.asks[seat_index] ~= ask) then return end
		self:CloseAsk(seat_index)
		on_timeout(seat_index)
	end)

	if (seat.is_bot or not seat.player) then
		local delay = math.min(extra.bot_delay or Config.BOT_THINK_TIME, seconds * 0.9)
		ask.bot_timer = self:After(delay, function()
			if (self.asks[seat_index] ~= ask) then return end
			local choice
			if (extra.bot_pick) then
				choice = extra.bot_pick(options)
			else
				choice = options[math.random(#options)]
			end
			-- nil = Bot verpasst es (Zeitlimit greift). Ungueltig (Ziel inzwischen weg) ebenso.
			if (choice == nil or not self:IsValidChoice(ask, choice)) then return end
			self:CloseAsk(seat_index)
			self.def.OnInput(self, seat_index, choice, kind)
		end)
	else
		local payload = { ask = ask.id, event = self.id, kind = kind, options = options, seconds = seconds }
		for key, value in pairs(extra) do
			if (not SERVER_ONLY[key]) then payload[key] = value end
		end
		Net.SendChoice(seat.player, payload)
	end
	return true
end

-- Fragt einen Platz nach einer Wahl. Mehrere Plaetze duerfen gleichzeitig gefragt werden.
--   kind        "target" (Ring), "qte" (Taste), "click" (springender Knopf), "vote", "splitsteal", "pass", "pickcard",
--               "wire" (muss in def.kinds stehen)
--   options     Liste erlaubter Werte (Zahlen oder Texte)
--   seconds     Zeitlimit (gilt auch fuer Bots)
--   on_timeout  function(seat_index) wenn niemand rechtzeitig waehlt
--   extra       optional: weitere Felder fuer das HUD (z. B. prompt, x, y, progress) und nur fuer den Server:
--                 bot_pick(options) -> Wahl oder nil (nil = Bot verpasst es, Zeitlimit greift)
--                 bot_delay         -> Sekunden bis der Bot antwortet (Standard BOT_THINK_TIME)
--                 no_timer          -> kein Zeitbalken im HUD (z. B. Kuerbis: die echte Zeit ist geheim)
function Context:Ask(seat_index, kind, options, seconds, on_timeout, extra)
	if (OpenAsk(self, seat_index, kind, options, seconds, on_timeout, extra)) then
		if (not (extra and extra.no_timer)) then self.match:SetTimer(seconds) end
		self:Push()
	end
end

-- Dieselbe Frage an viele Plaetze auf einmal (z. B. Abstimmung). Ein Zustand-Push statt vieler.
--   extra_for(seat_index) -> extra fuer diesen Platz (optional)
function Context:AskMany(indices, kind, options, seconds, on_timeout, extra_for)
	local opened = false
	for _, seat_index in ipairs(indices) do
		local extra = extra_for and extra_for(seat_index) or nil
		if (OpenAsk(self, seat_index, kind, options, seconds, on_timeout, extra)) then opened = true end
	end
	if (opened) then
		self.match:SetTimer(seconds)
		self:Push()
	end
end

-- Stellt eine offene Abfrage mit neuen Optionen erneut (Restzeit bleibt), z. B. wenn ein moegliches Ziel
-- die Show verlassen hat. So zeigt das HUD nie einen Platz an, der nicht mehr waehlbar ist.
function Context:UpdateAsk(seat_index, options)
	local ask = self.asks[seat_index]
	if (not ask or #options == 0) then return end
	local remaining = math.max(0.5, (ask.ends_at - Net.Now()) / 1000)
	self:Ask(seat_index, ask.kind, options, remaining, ask.on_timeout, ask.extra)
end

-- Entfernt einen Platz aus allen offenen Platz-Abfragen ("target", "pass"), die ihn anbieten
function Context:DropOption(seat_index)
	local updates = {}   -- erst sammeln: UpdateAsk veraendert self.asks
	for asked, ask in pairs(self.asks) do
		if (SEAT_KINDS[ask.kind]) then
			local options, found = {}, false
			for _, option in ipairs(ask.options) do
				if (option == seat_index) then found = true else table.insert(options, option) end
			end
			if (found) then updates[asked] = options end
		end
	end
	for asked, options in pairs(updates) do
		self:UpdateAsk(asked, options)
	end
end

function Context:IsAsking(seat_index)
	return self.asks[seat_index] ~= nil
end

-- Bietet die offene Abfrage von asked_seat diese Option an?
function Context:Offers(asked_seat, option)
	local ask = self.asks[asked_seat]
	if (not ask) then return false end
	for _, value in ipairs(ask.options) do
		if (value == option) then return true end
	end
	return false
end

function Context:CloseAsk(seat_index)
	local ask = self.asks[seat_index]
	if (not ask) then return end
	self.asks[seat_index] = nil
	for _, id in ipairs({ ask.timer, ask.bot_timer }) do
		ClearTimer(id)
		self.timers[id] = nil
	end
	local seat = self.match.seats[seat_index]
	if (seat and seat.player) then
		Net.EndChoice(seat.player, ask.id)
	end
	if (next(self.asks) == nil) then
		self.match:SetTimer(nil)
	end
end

function Context:CloseAllAsks()
	for seat_index in pairs(self.asks) do
		self:CloseAsk(seat_index)
	end
end

-- Zwischenstand einer Zielwahl (Revolver-Zielmodus, DeathBox:Aim). Nur fuer die offene Abfrage dieses Platzes mit
-- passender ID und extra.aim = true; target = 0 (zielt auf niemanden) oder eine erlaubte, lebende Option.
-- Gibt true zurueck, wenn er angenommen wurde.
function Context:HandleAim(seat_index, ask_id, target)
	local ask = self.asks[seat_index]
	if (self.finished or not ask or ask.id ~= ask_id or not ask.extra.aim or not self.def.OnAim) then return false end
	if (target ~= 0 and not self:IsValidChoice(ask, target)) then return false end
	self.def.OnAim(self, seat_index, target)
	return true
end

-- Gepruefte Eingabe. Gibt true zurueck, wenn sie angenommen wurde.
function Context:HandleInput(seat_index, ask_id, choice)
	local ask = self.asks[seat_index]
	if (self.finished or not ask or ask.id ~= ask_id) then return false end
	if (not self:IsValidChoice(ask, choice)) then return false end

	self:CloseAsk(seat_index)
	self.def.OnInput(self, seat_index, choice, ask.kind)
	return true
end

-- ===================================================================
-- Treffer und Karten
-- ===================================================================

-- Was ein Treffer bewirken wuerde, ohne etwas zu veraendern. Karten greifen nur bei Schuessen und nur in Events,
-- fuer die sie gelten (Shared/Cards.lua), in dieser Reihenfolge:
--   "ricochet"  Kugel wird auf einen zufaelligen anderen Lebenden abgelenkt (nur direkte Schuesse, keine Kette)
--   "safety"    Karte rettet
--   "dead"      Treffer
--   "gone"      lebt schon nicht mehr
function Context:HitOutcome(index, cause)
	if (not self:IsAlive(index)) then return "gone" end
	if (cause == "shot" and DeathBox.CardWorksIn("ricochet", self.id) and Hand.Has(self.match, index, "ricochet")
		and #self:AliveSeats(index) > 0) then
		return "ricochet"
	end
	if (GUNSHOT[cause] and DeathBox.CardWorksIn("safety", self.id) and Hand.Has(self.match, index, "safety")) then
		return "safety"
	end
	return "dead"
end

-- Ricochet ausloesen: Karte verbrauchen, neues Opfer wuerfeln (auch der Schuetze ist moeglich), Regieanweisung.
-- Gibt den neuen Platz zurueck. Nur aufrufen, wenn HitOutcome "ricochet" ergab.
local function Deflect(self, index)
	Hand.Consume(self.match, index, "ricochet")
	local others = self:AliveSeats(index)
	local victim = others[math.random(#others)]
	self:Show("ricochet", { from = index, seat = victim })
	self:StageText(Text.STAGE.RICOCHET, { target = self:Name(index) })
	self:Push()
	return victim
end

-- Versucht einen Platz auszuschalten. Bei Schuessen greifen die Karten (siehe HitOutcome).
--   cause  "shot" (direkter Schuss) | "ricochet" (abgelenkte Kugel) | "knife" | "fire" | "vote" | "explosion" ...
-- Gibt zurueck: Ergebnis, getroffener Platz
--   Ergebnis "dead" | "safety" | "gone" gilt fuer den Platz, den es am Ende getroffen hat. Nach einem Ricochet
--   ist das ein anderer als index (die abgelenkte Kugel trifft sofort; mit Pause: Context:Shoot).
function Context:Kill(index, cause)
	local outcome = self:HitOutcome(index, cause)
	if (outcome == "gone") then return "gone", index end

	if (outcome == "ricochet") then
		return self:Kill(Deflect(self, index), "ricochet")
	end

	if (outcome == "safety") then
		Hand.Consume(self.match, index, "safety")
		self:StageText(Text.STAGE.SAFETY, { target = self:Name(index) })
		self:Show("card_trigger", { seat = index, card = "safety" })
		self:Fx("safety", index)
		self:Push()
		return "safety", index
	end

	-- Abgelenkte Kugel: die Stage-Zeile sagt noch "RICOCHET! ... bounces off ...", jetzt steht fest, wen es erwischt hat
	-- (der Zustand von Eliminate traegt die Zeile schon). Die Events setzen danach evtl. ihre eigene ("bang").
	if (cause == "ricochet") then self:StageText(Text.STAGE.OUT, { target = self:Name(index) }) end
	self.match:Eliminate(index)
	return "dead", index
end

-- Schuss ohne eigenen Schuss-Cue (Duell; Revolver/Angry/Gallery ueber Context:Shoot): wie Kill(index, "shot"), aber
-- ein Querschlaeger fliegt erst RICOCHET_TIME lang (Cue "ricochet", Stage-Zeile "RICOCHET!"), bevor er sein neues
-- Opfer trifft. on_done(result, victim) wie die Rueckgabe von Kill, bei einem Querschlaeger erst nach der Pause.
function Context:Strike(index, on_done)
	if (self:HitOutcome(index, "shot") == "ricochet") then
		local victim = Deflect(self, index)
		self:Say(Text.JACK.RICOCHET, { target = self:Name(index) })
		self:After(Config.RICOCHET_TIME, function()
			on_done(self:Kill(victim, "ricochet"))
		end)
		return
	end
	on_done(self:Kill(index, "shot"))
end

-- Schuss mit Regieanweisung "revolver_shot" (Revolver, Angry Clown). Der Schuss-Cue kommt vor seinen Folgen:
--   revolver_shot -> [ricochet -> RICOCHET_TIME Pause (Kugel fliegt)] -> death oder card_trigger (Safety)
-- shot     Zusatzfelder fuer "revolver_shot" (shooter, chamber, chambers); seat und result setzt Shoot
-- on_done  function(result, victim) wie die Rueckgabe von Kill
function Context:Shoot(target, shot, on_done)
	local outcome = self:HitOutcome(target, "shot")
	if (outcome == "gone") then
		on_done("gone", target)
		return
	end

	shot.seat = target
	shot.result = outcome
	self:Fx("bang", target)
	self:Show("revolver_shot", shot)
	self:Strike(target, on_done)   -- Ricochet: Pause, dann das neue Opfer
end

-- ===================================================================
-- Ende
-- ===================================================================

-- Das Ergebnis steht fest (niemand muss mehr etwas tun, keine Kugel ist mehr unterwegs): State.event.final, das HUD
-- zeigt "You survived!" bzw. "It's over" statt veralteter Hinweise. Nach seconds Sekunden Ergebnis-Pause: Finish.
function Context:Conclude(seconds)
	self.data.final = true
	self:Push()
	self:After(seconds, function() self:Finish() end)
end

-- Event beenden. Darf mehrfach aufgerufen werden, wirkt nur einmal.
function Context:Finish()
	if (self.finished) then return end
	self:CloseAllAsks()
	self.finished = true
	for id in pairs(self.timers) do ClearTimer(id) end
	self.timers = {}
	self.match:SetTimer(nil)
	local on_finish = self.on_finish
	self.on_finish = nil
	if (on_finish) then on_finish() end
end

-- Abbrechen ohne Weitergabe (Partie-Ende)
function Context:Cancel()
	self.on_finish = nil
	self:Finish()
end

function Context:GetPublic()
	local texts = Text.EVENTS[self.id] or {}
	local awaiting = {}
	for seat_index in pairs(self.asks) do table.insert(awaiting, seat_index) end
	table.sort(awaiting)
	-- Wer den actor-Text sieht: alle mit offener Abfrage plus die, die sich gerade vorbereiten (Context:Stage)
	local involved, seen = {}, {}
	for _, list in ipairs({ awaiting, self.data.involved or {} }) do
		for _, seat_index in ipairs(list) do
			if (not seen[seat_index]) then
				seen[seat_index] = true
				table.insert(involved, seat_index)
			end
		end
	end
	table.sort(involved)
	-- Events aendern Fokus und Stage-Zeile unterwegs (z. B. "BLOCK!" fuer das Opfer, neuer Revolver-Halter)
	local focus = self.data.focus or self.actor_index
	local values = { name = self:Name(focus), name2 = self.actors[2] and self:Name(self.actors[2]) or nil }
	-- Ergebnis steht fest (Context:Conclude): wer in Gefahr war (fuer "You survived!")
	local endangered
	if (self.data.final) then
		endangered = {}
		for i, seat_index in ipairs(self.endangered) do endangered[i] = seat_index end
	end
	return {
		id = self.id,
		name = texts.name or self.id,
		actors = self.actors,
		awaiting = awaiting,
		involved = involved,
		focus = focus,
		instruction_actor = self.data.stage_actor or Text.Format(texts.instruction_actor or "", values),
		instruction_others = self.data.stage_others or Text.Format(texts.instruction_others or "", values),
		final = self.data.final or nil,
		endangered = endangered,
		data = self.def.GetPublic and self.def.GetPublic(self) or nil,
	}
end
