-- Server/Match.lua
-- Ein Match = ein Tisch = eine Show in einem eigenen Zelt (eigene Dimension).
-- Beliebig viele Matches laufen gleichzeitig und wissen nichts voneinander.
--
--   INTRO ──(Jack springt aus der Box)──> PLAYING ──(1 oder 0 uebrig)──> ENDED ──(Zeit um)──> aufgeloest
--
-- Eine Runde (alles Regieanweisungen an die Clients, siehe Net.Show / Client/Presentation.lua).
-- State.stage sagt dem HUD jederzeit, wo die Runde steht (Stage-Zeile, docs/PROTOCOL.md "Klarheit"):
--   spin  (SPIN_TIME)  Spieluhr (zufaellige Melodie), Jack dreht sich langsam 1-2 Umdrehungen, Ticks pro Platz
--   hold  (HOLD_TIME)  Stille + Herzschlag, Jack starrt das Opfer an (gehoert zu stage "spin")
--   (skip)             Karte Skip: Jack dreht weiter zu jemand anderem                 (SKIP_TIME)
--   pop                "POP!" – Jack schnellt nach vorne, Spot, Name gross im Bild   (REVEAL_TIME)
--   card               Event-Karte: Name, wer, so geht's, "YOU: ..."                 (CARD_TIME / CARD_TIME_REPEAT)
--   event              Server/Events/*.lua (Stage-Zeilen je Phase, Context:Stage)
--   result             "round_end": wer ist raus, wer hat ueberlebt                    (RESULT_PAUSE)
--
-- Der Server entscheidet alles (wer gewaehlt wird, was passiert). Die Clients zeigen es nur an.
-- Jede neue Runde zaehlt verfallende Karten herunter (Hand.Tick). Faellt das Opfer vor dem Event aus
-- (Server verlassen), dreht Jack neu, ohne dass eine Runde vergeht (Match:Spin).
-- Timer-Regel: Das Match hat genau EINEN eigenen Timer (zwischen den Events),
-- das laufende Event hat eigene Timer im Kontext. Beide laufen nie gleichzeitig.

local Config = DeathBox.Config
local Text = DeathBox.Text
local Net = DeathBox.Net
local Layout = DeathBox.Layout
local Characters = DeathBox.Characters
local EventSystem = DeathBox.Events
local Hand = DeathBox.Hand

local BOT_NAMES = {
	"Mr. Giggles", "Bonzo", "Pennywhistle", "Rattles", "Grimsby", "Tilly", "Nibbles", "Doodle",
	"Sprocket", "Mumbles", "Ziggy", "Wobble", "Crumble", "Fizz", "Patches", "Pip",
	"Snickers", "Bubbles", "Chuckles", "Dimples", "Jingles", "Noodle", "Pockets", "Squeaky",
	"Tickles", "Wiggles", "Bingo", "Cuddles", "Gizmo", "Lolli", "Muffin",
}

local STATE = { INTRO = "STARTING", PLAYING = "PLAYING", ENDED = "ENDED" }   -- "STARTING" = Name im HUD
local ATAN2 = math.atan2 or math.atan   -- Lua 5.1 (Simulation) / 5.4 (nanos)

-- Felder in Regieanweisungen, die einen Platz meinen: der Client bekommt zusaetzlich die Stuhl-Nummer
local SEAT_FIELDS = { "seat", "seat2", "new_seat", "shooter", "holder", "from", "target" }

local Match = { STATE = STATE, next_id = 1 }
Match.__index = Match
DeathBox.Match = Match

local function Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function Log(match, text, ...)
	Console.Log("[DeathBox] [Tisch %d] " .. text, match.id, ...)
end

-- ===================================================================
-- Aufbau
-- ===================================================================

-- players = echte Spieler, bot_count = Bots zum Auffuellen
function Match.Create(players, bot_count)
	local seat_count = Config.TABLE_SEATS

	local match = setmetatable({
		id = Match.next_id,
		dimension = DeathBox.Instances.Acquire(Config.DIMENSION_MATCH_FIRST),
		seat_count = seat_count,
		seats = {},
		state = STATE.INTRO,
		current_index = 0,
		winner_index = 0,
		jack_yaw = 0,          -- wohin Jack gerade schaut (Grad), damit Clients nach Neuladen richtig stehen
		timer_id = nil,
		hud_timer = nil,
		event = nil,
		last_event_id = nil,
		forced_event = nil,
		seen_events = {},      -- Events, die in dieser Show schon dran waren (kuerzere Karte)
		spectators = {},       -- player -> true: ausgeschiedene Spieler, die noch zuschauen
		disposed = false,
		round = 0,             -- laufende Runde (State.round), 0 im Intro
		stage = "intro",       -- wo die Runde steht (State.stage)
		round_out = {},        -- seit dem letzten Rundenergebnis ausgeschieden (Reihenfolge), fuer "round_end"
		round_left = {},       -- ... davon gegangen
		last_tune = Config.INTRO_MUSIC,   -- zuletzt gespielte Spieluhr-Melodie (nie zweimal hintereinander dieselbe)
		turned = {},           -- seat_index -> true: sitzende Figur schaut nicht zur Mitte (Revolver-Halter zielt)
	}, Match)
	Match.next_id = Match.next_id + 1

	-- Plaetze: echte Spieler + Bots, zufaellig gemischt
	local names = {}
	for _, name in ipairs(BOT_NAMES) do table.insert(names, name) end
	Shuffle(names)

	for _, player in ipairs(players) do
		table.insert(match.seats, { name = player:GetName(), player = player, is_bot = false, alive = true, cards = {} })
	end
	for i = 1, bot_count do
		table.insert(match.seats, { name = names[i] or ("Bot " .. i), player = nil, is_bot = true, alive = true, cards = {} })
	end
	Shuffle(match.seats)

	-- Stuehle gleichmaessig verteilen, auch wenn der Kreis nicht voll ist.
	-- Platznummern laufen in Stuhl-Reihenfolge (aufsteigend = im Uhrzeigersinn, siehe Context:NextAlive).
	for index, seat in ipairs(match.seats) do
		seat.chair = math.floor((index - 1) * seat_count / #match.seats) + 1
	end

	-- Figuren hinsetzen und markieren (DB_Seat / DB_Chair, synchron: Clients finden so die Figur eines Platzes)
	for index, seat in ipairs(match.seats) do
		local location, rotation, look = Layout.SitTransform(seat.chair, seat_count)
		if (seat.player) then
			Net.Place(seat.player, "match", match:PlaceInfo())
			local character = Characters.Place(seat.player, match.dimension, location, rotation)
			Characters.Sit(character, location, rotation)
			Characters.MarkSeat(character, index, seat.chair)
			seat.player:SetCameraRotation(look)
		else
			seat.bot_character = Characters.SpawnBot(match.dimension, location, rotation)
			Characters.MarkSeat(seat.bot_character, index, seat.chair)
		end
	end

	-- Startkarten (nach Place, damit die Hand beim Client im Zelt ankommt)
	Hand.DealStart(match, Config.CARDS.START)

	Log(match, "eroeffnet in Dimension %d mit %d Spielern und %d Bots", match.dimension, #players, bot_count)

	match:PushState()
	match:Show("intro", { duration = Config.INTRO_TIME, pop_at = Config.INTRO_POP_AT, music = Config.INTRO_MUSIC })
	-- Begruessung direkt nach dem POP aus der Kiste
	match:SetMatchTimer(math.min(Config.INTRO_POP_AT + 0.4, Config.INTRO_TIME * 0.95), function()
		match:Say(Text.Format(Text.JACK.GAME_START))
	end)
	-- Erst nach dem Intro geht es los (eigener Timer, der Begruessungs-Timer oben wird dabei ersetzt)
	Timer.SetTimeout(function()
		if (match.disposed or match.state ~= STATE.INTRO) then return end
		match:StartPlaying()
	end, Config.INTRO_TIME * 1000)
	return match
end

-- Infos, die ein Client braucht, um das Zelt lokal zu bauen
function Match:PlaceInfo()
	return { seat_count = self.seat_count, jack_yaw = self.jack_yaw, match = self.id }
end

-- ===================================================================
-- Hilfen
-- ===================================================================

function Match:SetMatchTimer(seconds, callback)
	self:ClearMatchTimer()
	self.timer_id = Timer.SetTimeout(function()
		self.timer_id = nil
		if (not self.disposed) then callback() end
	end, math.max(0, math.floor(seconds * 1000 + 0.5)))
end

function Match:ClearMatchTimer()
	if (self.timer_id and Timer.IsValid(self.timer_id)) then
		Timer.ClearTimeout(self.timer_id)
	end
	self.timer_id = nil
end

-- Zeitbalken im HUD
function Match:SetTimer(seconds)
	self.hud_timer = Net.MakeTimer(seconds)
end

function Match:Say(text)
	Net.Say(self.dimension, text)
end

function Match:Fx(kind, seat)
	Net.Fx(self.dimension, kind, seat)
end

-- Regieanweisung an alle am Tisch. Plaetze bekommen ihre Stuhl-Nummer dazu.
function Match:Show(action, data)
	if (self.disposed) then return end
	data = data or {}
	for _, field in ipairs(SEAT_FIELDS) do
		local index = data[field]
		if (type(index) == "number" and self.seats[index]) then
			data[field .. "_chair"] = self.seats[index].chair
		end
	end
	data.seat_count = self.seat_count
	Net.Show(self.dimension, action, data)
end

function Match:CountAlive()
	local alive = 0
	for _, seat in ipairs(self.seats) do
		if (seat.alive) then alive = alive + 1 end
	end
	return alive
end

function Match:AliveIndices()
	local result = {}
	for index, seat in ipairs(self.seats) do
		if (seat.alive) then table.insert(result, index) end
	end
	return result
end

function Match:FindSeatByPlayer(player)
	for index, seat in ipairs(self.seats) do
		if (seat.player == player) then return seat, index end
	end
	return nil, nil
end

function Match:HasPlayer(player)
	return self:FindSeatByPlayer(player) ~= nil or self.spectators[player] == true
end

function Match:CountHumans()
	local count = 0
	for _, seat in ipairs(self.seats) do
		if (seat.player) then count = count + 1 end
	end
	return count
end

function Match:ChairAngle(seat_index)
	local seat = self.seats[seat_index]
	return seat and Layout.ChairAngle(seat.chair, self.seat_count) or 0
end

-- Jack dreht sich kurz zu einem Platz (z. B. zum Ziel des Revolvers)
function Match:PointAt(seat_index)
	if (not self.seats[seat_index]) then return end
	self.jack_yaw = self:ChairAngle(seat_index)
	self:Show("point", { seat = seat_index })
end

-- Figur eines Platzes (Spieler oder Bot), nil wenn keine da ist
function Match:SeatCharacter(index)
	local seat = self.seats[index]
	if (not seat) then return nil end
	local character
	if (seat.player and seat.player:IsValid()) then
		character = seat.player:GetControlledCharacter()
	else
		character = seat.bot_character
	end
	if (character and character:IsValid()) then return character end
	return nil
end

-- Sitzende Figur eines Platzes zu einem anderen Platz drehen (Revolver-Halter zeigt aufs Ziel, alle sehen es).
-- Ohne Ziel (oder auf sich selbst) schaut sie wieder zur Mitte. Alle Plaetze liegen auf einem Kreis: die Richtung
-- zu einem anderen Platz weicht immer weniger als 90 Grad von der Mitte ab, niemand sitzt verkehrt herum.
function Match:TurnSeatToward(index, target_index)
	local seat = self.seats[index]
	if (not seat or not seat.alive) then return end
	local character = self:SeatCharacter(index)
	if (not character) then return end
	local location, rotation = Layout.SitTransform(seat.chair, self.seat_count)
	local yaw = rotation.Yaw
	local target = target_index and target_index ~= index and self.seats[target_index]
	if (target) then
		local to = Layout.SitTransform(target.chair, self.seat_count)
		yaw = (math.deg(ATAN2(to.Y - location.Y, to.X - location.X)) + Config.WORLD.SIT_YAW_OFFSET) % 360
		self.turned[index] = true
	else
		self.turned[index] = nil
	end
	Characters.TurnSeated(character, yaw)
end

-- Alle gedrehten Figuren wieder zur Mitte (Event-Ende)
function Match:ResetTurns()
	local turned = self.turned
	self.turned = {}
	for index in pairs(turned) do
		self:TurnSeatToward(index, nil)
	end
end

-- Spieluhr-Melodie fuer den naechsten Spin: zufaellig aus SPIN_TUNES, nie zweimal hintereinander dieselbe
function Match:PickTune()
	local tunes = Config.SPIN_TUNES or {}
	if (#tunes == 0) then return Config.SPIN_MUSIC end
	local choices = {}
	for _, name in ipairs(tunes) do
		if (name ~= self.last_tune or #tunes == 1) then table.insert(choices, name) end
	end
	if (#choices == 0) then choices = tunes end
	local tune = choices[math.random(#choices)]
	self.last_tune = tune
	return tune
end

local function Copy(list)
	local out = {}
	for i, value in ipairs(list or {}) do out[i] = value end
	return out
end

-- ===================================================================
-- Ablauf
-- ===================================================================

function Match:StartPlaying()
	self.state = STATE.PLAYING
	self:PushState()
	self:NextTurn()
end

-- Neue Runde: verfallende Karten zaehlen herunter, vielleicht spielt ein Bot eine Karte, dann waehlt Jack
function Match:NextTurn()
	if (self.state ~= STATE.PLAYING) then return end
	self.round = self.round + 1
	Hand.Tick(self)
	Hand.BotTurn(self)
	self:Spin()
end

-- Event und Opfer wuerfeln, Jack dreht sich hin. Auch fuer das Neu-Drehen, wenn das Opfer vorher ausfaellt.
function Match:Spin()
	if (self.state ~= STATE.PLAYING) then return end

	local alive = self:AliveIndices()
	if (#alive <= 1) then
		self:End()
		return
	end

	local def = EventSystem.Pick(#alive, self.last_event_id, self.forced_event)
	self.forced_event = nil
	if (not def or #alive < def.actors) then
		self:End()
		return
	end

	-- Server wuerfelt die Spieler. Jack dreht sich danach nur hin.
	Shuffle(alive)
	local actors = {}
	for i = 1, def.actors do actors[i] = alive[i] end
	local victim = actors[1]

	self.current_index = victim
	local start_yaw = self.jack_yaw
	self.jack_yaw = self:ChairAngle(victim)
	self.stage = "spin"
	self:SetTimer(nil)
	self:PushState()

	-- 1) Spieluhr + langsame Drehung: ab Jacks Blickrichtung SPIN_TURNS volle Umdrehungen plus der Rest bis zum Opfer
	--    (1-2 Umdrehungen, jeder Stuhl wird mindestens einmal gestreift). Immer gleich lang, kein schneller Spin:
	--    Lesbarkeit vor Tempo. Die Clients berechnen Jacks Bewegung und die Ticks selbst.
	self:Show("spin", {
		seat = victim,
		start_yaw = start_yaw,
		target_yaw = self.jack_yaw,
		turns = Config.SPIN_TURNS,
		duration = Config.SPIN_TIME,
		hold = Config.HOLD_TIME,
		music = self:PickTune(),
		actors = Copy(actors),   -- alle Gewaehlten (Duell, Split or Steal: zwei), [1] = seat
	})

	-- 2) "POP!" nach Drehung + Stille
	self:SetMatchTimer(Config.SPIN_TIME + Config.HOLD_TIME, function() self:Reveal(def, actors, true) end)
end

function Match:ActorsAlive(actors)
	for _, index in ipairs(actors) do
		if (not self.seats[index].alive) then return false end
	end
	return true
end

-- Karte Skip: Ein Gewaehlter gibt die Auswahl an einen zufaelligen anderen Lebenden weiter.
-- Nur in Events, in denen die Gewaehlten selbst in Gefahr sind (Shared/Cards.lua). Bei zwei Gewaehlten (Duell)
-- greift das Skip des ersten, der eins hat. Keine Kette: Der Ersatz wurde von der Karte bestimmt, nicht von Jack,
-- deshalb greift sein eigenes Skip nicht mehr (hoechstens ein Skip pro Runde).
-- Gibt true zurueck, wenn Skip gegriffen hat. Der Ersatz steht dann vorne in actors (der POP zeigt ihn);
-- die Reihenfolge der Duellanten ist egal.
function Match:TrySkip(def, actors)
	if (not DeathBox.CardWorksIn("skip", def.id)) then return false end
	local slot
	for i, index in ipairs(actors) do
		if (Hand.Has(self, index, "skip")) then
			slot = i
			break
		end
	end
	if (not slot) then return false end
	local victim = actors[slot]

	local taken = {}
	for _, index in ipairs(actors) do taken[index] = true end
	local candidates = {}
	for _, index in ipairs(self:AliveIndices()) do
		if (not taken[index]) then table.insert(candidates, index) end
	end
	if (#candidates == 0) then return false end   -- niemand sonst da: Skip greift nicht, Karte bleibt

	Hand.Consume(self, victim, "skip")
	local new_victim = candidates[math.random(#candidates)]
	table.remove(actors, slot)
	table.insert(actors, 1, new_victim)
	self.current_index = new_victim
	self.jack_yaw = self:ChairAngle(new_victim)

	local name, new_name = self.seats[victim].name, self.seats[new_victim].name
	Log(self, "%s spielt Skip, jetzt dran: %s", name, new_name)
	self.stage = "skip"
	self:SetTimer(Config.SKIP_TIME)
	self:Show("skip", { seat = victim, new_seat = new_victim, name = name, new_name = new_name, target_yaw = self.jack_yaw })
	self:Say(Text.Format(Text.JACK.SKIPPED, { name = name, new = new_name }))
	self:PushState()
	return true
end

-- 2) POP: der Gewaehlte wird enthuellt. Vorher darf eine Skip-Karte die Auswahl einmal weitergeben.
function Match:Reveal(def, actors, allow_skip)
	if (self.state ~= STATE.PLAYING) then return end
	if (not self:ActorsAlive(actors)) then   -- in der Zwischenzeit gegangen: neu drehen
		self:Spin()
		return
	end

	if (allow_skip and self:TrySkip(def, actors)) then
		self:SetMatchTimer(Config.SKIP_TIME, function() self:Reveal(def, actors, false) end)
		return
	end

	local victim = actors[1]
	self.stage = "pop"
	self:SetTimer(Config.REVEAL_TIME)   -- Restzeit im HUD (bis zur Event-Karte)
	self:Show("pop", { seat = victim, name = self.seats[victim].name, actors = Copy(actors) })
	self:Say(Text.Format(Text.JACK.CHOSEN, { name = self.seats[victim].name }))
	self:Fx("chosen", victim)
	self:PushState()

	self:SetMatchTimer(Config.REVEAL_TIME, function() self:ShowEventCard(def, actors) end)
end

-- 3) Event-Karte, danach 4) das Event selbst
function Match:ShowEventCard(def, actors)
	if (self.state ~= STATE.PLAYING) then return end
	if (not self:ActorsAlive(actors)) then
		self:Spin()
		return
	end

	-- Karte: Name, wer, 2-3 Stichpunkte, "YOU: ..." (fuer die Gewaehlten bzw. alle anderen). Beim ersten Mal laenger.
	local texts = Text.EVENTS[def.id] or {}
	local first = not self.seen_events[def.id]
	local card_time = first and Config.CARD_TIME or Config.CARD_TIME_REPEAT
	self.seen_events[def.id] = true
	local values = { name = self.seats[actors[1]].name, name2 = actors[2] and self.seats[actors[2]].name or nil }
	local how = {}
	for i, line in ipairs(texts.how or {}) do how[i] = Text.Format(line, values) end
	self.stage = "card"
	self:SetTimer(card_time)
	self:Show("card", {
		event = def.id,
		name = texts.name or def.id,
		tagline = texts.tagline or "",
		rules = texts.rules or "",
		duration = card_time,
		seat = actors[1],
		seat2 = actors[2],
		actors = Copy(actors),
		who = Text.Format(texts.who or "", values),
		how = how,
		you_actor = Text.Format(texts.you_actor or "", values),
		you_others = Text.Format(texts.you_others or "", values),
		first = first,
		round = self.round,
	})
	self:PushState()

	self:SetMatchTimer(card_time, function()
		if (self.state ~= STATE.PLAYING) then return end
		if (not self:ActorsAlive(actors)) then
			self:Spin()
			return
		end
		self:RunEvent(def, actors)
	end)
end

function Match:RunEvent(def, actors)
	self.last_event_id = def.id
	self.stage = "event"
	self:SetTimer(nil)   -- Zeiten setzt ab jetzt das Event (Abfragen, Context:Stage)
	local ctx
	ctx = EventSystem.NewContext(self, def, actors, function()
		self.event = nil
		self:OnEventFinished(ctx)
	end)
	self.event = ctx
	Log(self, "Event '%s' startet, Platz %d", def.id, actors[1])
	def.Start(ctx)
end

-- 5) Rundenergebnis ("round_end"): wer ist raus, wer war in Gefahr und lebt noch. Dann durchatmen (RESULT_PAUSE).
function Match:OnEventFinished(ctx)
	if (self.state ~= STATE.PLAYING) then return end
	self:ResetTurns()
	local survived = {}
	for _, index in ipairs(ctx and ctx.endangered or {}) do
		if (self.seats[index] and self.seats[index].alive) then table.insert(survived, index) end
	end
	self.stage = "result"
	self:SetTimer(Config.RESULT_PAUSE)
	self:Show("round_end", {
		round = self.round,
		alive = self:CountAlive(),
		out = Copy(self.round_out),
		survived = survived,
		left = (#self.round_left > 0) and Copy(self.round_left) or nil,
	})
	self.round_out, self.round_left = {}, {}   -- wer in der Pause geht, zaehlt zur naechsten Runde
	self:PushState()
	self:SetMatchTimer(Config.RESULT_PAUSE, function()
		if (self:CountAlive() <= 1) then
			self:End()
		else
			self:NextTurn()
		end
	end)
end

function Match:Eliminate(index)
	local seat = self.seats[index]
	if (not seat or not seat.alive) then return end
	seat.alive = false
	table.insert(self.round_out, index)
	Hand.TakeAll(self, index)   -- Karten sind fuer Ausgeschiedene wertlos (Hand im HUD wird leer)
	Log(self, "%s ausgeschieden, noch %d im Spiel", seat.name, self:CountAlive())

	self:Show("death", { seat = index, name = seat.name })
	self:Fx("death", index)

	if (seat.player) then
		local player = seat.player
		Characters.Kill(player:GetControlledCharacter())
		self.spectators[player] = true
		-- Nach kurzer Zeit als Zuschauer hinter dem Stuhlkreis aufstehen
		Timer.SetTimeout(function()
			if (self.disposed or not player:IsValid() or not self.spectators[player]) then return end
			local location, rotation = Layout.SpectatorTransform(seat.chair, self.seat_count)
			Characters.Place(player, self.dimension, location, rotation)
		end, Config.DEAD_RESPAWN_DELAY * 1000)
	elseif (seat.bot_character) then
		Characters.Kill(seat.bot_character)
	end
	self:PushState()
end

function Match:End()
	if (self.state == STATE.ENDED or self.disposed) then return end
	self:ClearMatchTimer()
	if (self.event) then
		self.event:Cancel()
		self.event = nil
	end
	self.state = STATE.ENDED
	self.stage = "ended"

	local winner_index = 0
	local alive = self:AliveIndices()
	if (#alive == 1) then winner_index = alive[1] end
	self.winner_index = winner_index

	if (winner_index > 0) then
		local winner = self.seats[winner_index]
		Log(self, "Sieger: %s", winner.name)
		self.jack_yaw = self:ChairAngle(winner_index)
		self:Show("winner", { seat = winner_index, name = winner.name })
		self:Say(Text.Format(Text.JACK.WINNER, { winner = winner.name }))
		self:Fx("winner", winner_index)
	else
		Log(self, "kein Sieger")
		self:Show("winner", { seat = 0, name = "" })
		self:Say(Text.Format(Text.JACK.NO_WINNER))
	end

	self:SetTimer(Config.GAME_END_DELAY)
	self:PushState()
	self:SetMatchTimer(Config.GAME_END_DELAY, function() self:Dispose() end)
end

-- Raeumt auf und schickt alle zurueck in den Hub
function Match:Dispose()
	if (self.disposed) then return end
	self:ClearMatchTimer()
	if (self.event) then
		self.event:Cancel()
		self.event = nil
	end
	self.disposed = true

	local players = {}
	for _, seat in ipairs(self.seats) do
		if (seat.player and seat.player:IsValid()) then table.insert(players, seat.player) end
		if (seat.bot_character and seat.bot_character:IsValid()) then seat.bot_character:Destroy() end
	end
	for player in pairs(self.spectators) do
		local listed = false
		for _, p in ipairs(players) do if (p == player) then listed = true end end
		if (not listed and player:IsValid()) then table.insert(players, player) end
	end

	Log(self, "aufgeloest")
	DeathBox.Lobby.OnMatchDisposed(self, players)
	DeathBox.Instances.Release(self.dimension)
end

-- ===================================================================
-- Spieler gehen
-- ===================================================================

-- Spieler verlaesst den Server oder die Show. Lebend = ausgeschieden.
-- Das laufende Event erfaehrt es immer (auch von Ausgeschiedenen, die z. B. gerade abstimmen).
function Match:OnPlayerLeave(player)
	self.spectators[player] = nil

	local seat, index = self:FindSeatByPlayer(player)
	if (not seat) then return end
	seat.player = nil   -- keine Referenz auf ein ungueltiges Player-Objekt behalten
	seat.cards = {}

	local was_alive = seat.alive and self.state ~= STATE.ENDED
	if (was_alive) then
		seat.alive = false
		table.insert(self.round_out, index)
		table.insert(self.round_left, index)
		self:Say(Text.Format(Text.JACK.LEFT_TABLE, { name = seat.name }))
		self:Show("death", { seat = index, name = seat.name, left = true })
	end
	if (self.event) then
		self.event:CloseAsk(index)
		if (self.event.def.OnSeatLeft) then
			self.event.def.OnSeatLeft(self.event, index, was_alive)
		elseif (was_alive and index == self.event.actor_index) then
			self.event:Finish()
		end
	end

	-- Keine echten Spieler mehr: Show sofort beenden, spart Server-Leistung
	if (self:CountHumans() == 0 and next(self.spectators) == nil) then
		self:Dispose()
		return
	end

	if (self.state == STATE.PLAYING and self:CountAlive() <= 1) then
		self:End()
		return
	end
	self:PushState()
end

-- ===================================================================
-- Eingaben und HUD
-- ===================================================================

function Match:HandleInput(player, ask_id, choice)
	if (self.state ~= STATE.PLAYING or not self.event) then return end
	local seat, index = self:FindSeatByPlayer(player)
	if (not seat) then return end
	-- Ausgeschiedene duerfen nur antworten, wenn ihr Platz gefragt ist (Abstimmung)
	if (not seat.alive and not self.event:IsAsking(index)) then return end
	-- Abgelehnte Eingaben (Doppelklick, veraltete Abfrage, ungueltige Wahl) still ignorieren.
	-- Nur im Testmodus loggen, damit 999 Spieler das Log nicht fluten koennen.
	if (not self.event:HandleInput(index, ask_id, choice) and Config.DEBUG_COMMANDS) then
		Console.Warn("[DeathBox] Ungueltige Eingabe von %s: %s", player:GetName(), tostring(choice))
	end
end

-- Revolver-Zielmodus: Zwischenstand der Zielwahl (DeathBox:Aim). Die eigentliche Pruefung (offene Abfrage mit
-- aim = true, Ziel unter den Optionen) macht Context:HandleAim. Gibt true zurueck, wenn angenommen.
function Match:HandleAim(player, ask_id, target)
	if (self.state ~= STATE.PLAYING or not self.event) then return false end
	local seat, index = self:FindSeatByPlayer(player)
	if (not seat or not seat.alive) then return false end
	return self.event:HandleAim(index, ask_id, target)
end

-- Oeffentlicher Zustand: nur, was ALLE sehen duerfen (Anzahl Karten, nicht welche)
function Match:BuildSnapshot()
	local seats = {}
	for index, seat in ipairs(self.seats) do
		table.insert(seats, {
			seat = index,
			chair = seat.chair,
			angle = Layout.ChairAngle(seat.chair, self.seat_count),
			name = seat.name,
			id = seat.player and seat.player:IsValid() and seat.player:GetID() or -1,
			bot = seat.is_bot,
			alive = seat.alive,
			cards = #seat.cards,
		})
	end
	return {
		match = self.id,
		phase = self.state,
		seats = seats,
		seat_count = self.seat_count,
		turn = self.current_index,
		round = self.round,
		stage = self.stage,
		winner = self.winner_index,
		jack_yaw = self.jack_yaw,
		timer = Net.TimerSnapshot(self.hud_timer),
		event = self.event and self.event:GetPublic() or nil,
	}
end

function Match:PushState()
	if (self.disposed) then return end
	Net.SendState(self.dimension, self:BuildSnapshot())
end

-- Kompletter Stand fuer einen Spieler (HUD neu geladen): Tisch und eigene Hand
function Match:SendStateTo(player)
	Net.SendStateTo(player, self:BuildSnapshot())
	local _, index = self:FindSeatByPlayer(player)
	if (index) then Hand.Sync(self, index) end
end
