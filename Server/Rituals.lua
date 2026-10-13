-- Server/Rituals.lua
-- Ritual-System: Register, Auswahl und Ablauf eines einzelnen Rituals.
--
-- Ein Ritual ist ein Modul (siehe Server/Rituals/*.lua) mit dieser Schnittstelle:
--   id            eindeutiger Name, z. B. "chamber"
--   weight        wie haeufig es gewaehlt wird (relativ zu den anderen)
--   min_alive     braucht mindestens so viele lebende Spieler
--   OnGameStart() optional: Zustand fuer eine neue Partie zuruecksetzen
--   Start(ctx)    Ritual beginnt, ctx.actor_index ist der gewaehlte Platz
--   OnInput(ctx, seat_index, choice)   gepruefte Eingabe eines Spielers
--   OnSeatLeft(ctx, seat_index)        optional: jemand hat den Tisch verlassen
--   GetPublic(ctx) optional: Daten fuer das HUD (fuer alle sichtbar)
--
-- Das Ritual beendet sich selbst mit ctx:Finish(). Danach geht der Ablauf in GameState weiter.
--
-- Sicherheitsprinzip: Ein Spieler kann nur dann etwas eingeben, wenn das Ritual genau
-- auf IHN wartet (ctx.awaiting) und seine Wahl in der erlaubten Liste steht.

DeathBox.Rituals = {
	registry = {},     -- id -> Ritual-Definition
	active = nil,      -- laufender Kontext (ctx) oder nil
	last_id = nil,     -- zuletzt gespieltes Ritual (keine direkte Wiederholung)
	forced_next = nil, -- Debug: /ritual <id> erzwingt das naechste Ritual
	timer_id = nil,    -- genau ein Timer fuer das laufende Ritual
}

local Rituals = DeathBox.Rituals
local Text = DeathBox.Text
local Net = DeathBox.Net
local DBTable = DeathBox.Table

-- ===================================================================
-- Register und Auswahl
-- ===================================================================

function Rituals.Register(def)
	assert(type(def.id) == "string", "Ritual braucht eine id")
	assert(type(def.Start) == "function", "Ritual braucht Start()")
	assert(type(def.OnInput) == "function", "Ritual braucht OnInput()")
	def.weight = def.weight or 1
	def.min_alive = def.min_alive or 2
	Rituals.registry[def.id] = def
	Console.Log("[DeathBox] Ritual registriert: %s", def.id)
end

function Rituals.Exists(id)
	return Rituals.registry[id] ~= nil
end

function Rituals.GetIds()
	local ids = {}
	for id in pairs(Rituals.registry) do table.insert(ids, id) end
	table.sort(ids)
	return ids
end

-- Waehlt das naechste Ritual: gewichtet zufaellig, nicht zweimal dasselbe hintereinander
function Rituals.Pick(alive_count)
	if (Rituals.forced_next and Rituals.registry[Rituals.forced_next]) then
		local def = Rituals.registry[Rituals.forced_next]
		Rituals.forced_next = nil
		return def
	end

	local candidates, total = {}, 0
	for _, def in pairs(Rituals.registry) do
		if (alive_count >= def.min_alive) then
			table.insert(candidates, def)
		end
	end

	-- Wiederholung vermeiden, aber nur wenn es eine Alternative gibt
	if (#candidates > 1) then
		for i = #candidates, 1, -1 do
			if (candidates[i].id == Rituals.last_id) then
				table.remove(candidates, i)
			end
		end
	end

	table.sort(candidates, function(a, b) return a.id < b.id end)   -- feste Reihenfolge, gleiche Zufallsverteilung
	for _, def in ipairs(candidates) do total = total + def.weight end
	if (total <= 0) then return nil end

	local roll = math.random() * total
	for _, def in ipairs(candidates) do
		roll = roll - def.weight
		if (roll <= 0) then return def end
	end
	return candidates[#candidates]
end

function Rituals.ResetForGame()
	Rituals.Cancel()
	Rituals.last_id = nil
	for _, def in pairs(Rituals.registry) do
		if (def.OnGameStart) then def.OnGameStart() end
	end
end

-- ===================================================================
-- Timer (genau einer pro Ritual)
-- ===================================================================

local function ClearRitualTimer()
	if (Rituals.timer_id and Timer.IsValid(Rituals.timer_id)) then
		Timer.ClearTimeout(Rituals.timer_id)
	end
	Rituals.timer_id = nil
end

local function SetRitualTimer(seconds, callback)
	ClearRitualTimer()
	Rituals.timer_id = Timer.SetTimeout(function()
		Rituals.timer_id = nil
		callback()
	end, seconds * 1000)
end

-- ===================================================================
-- Kontext: die Werkzeuge, mit denen ein Ritual arbeitet
-- ===================================================================

local Context = {}
Context.__index = Context

function Context:Seat(index)
	return DBTable.seats[index]
end

function Context:Name(index)
	local seat = DBTable.seats[index]
	return seat and seat.name or "?"
end

function Context:IsAlive(index)
	local seat = DBTable.seats[index]
	return seat ~= nil and seat.alive
end

-- Alle lebenden Plaetze, optional ohne einen bestimmten
function Context:AliveSeats(except_index)
	local result = {}
	for index, seat in ipairs(DBTable.seats) do
		if (seat.alive and index ~= except_index) then
			table.insert(result, index)
		end
	end
	return result
end

-- Madame spricht. lines = Liste oder Text aus DeathBox.Text, values = Platzhalter
function Context:Say(lines, values)
	Net.Say(Text.Format(lines, values))
end

-- Nach seconds Sekunden callback ausfuehren (ersetzt den vorherigen Ritual-Timer)
function Context:After(seconds, callback)
	if (self.finished) then return end
	SetRitualTimer(seconds, function()
		if (not self.finished) then callback() end
	end)
end

-- Fragt einen Platz nach einer Wahl.
--   kind     z. B. "target"
--   options  Liste erlaubter Werte (z. B. Platznummern)
--   seconds  Zeitlimit
--   on_timeout  wird aufgerufen, wenn niemand rechtzeitig waehlt
-- Bots waehlen nach kurzer "Bedenkzeit" zufaellig.
function Context:Ask(seat_index, kind, options, seconds, on_timeout)
	local seat = DBTable.seats[seat_index]
	self.awaiting = seat_index
	self.ask = { kind = kind, options = options }

	if (seat.is_bot or not seat.player) then
		self:After(DeathBox.Config.BOT_THINK_TIME, function()
			local choice = options[math.random(#options)]
			self:CloseAsk()
			self.def.OnInput(self, seat_index, choice)
		end)
		Net.SetTimer(nil)
		Net.PushState()
		return
	end

	Net.SetTimer(seconds)
	Net.SendChoice(seat.player, {
		ritual = self.id,
		kind = kind,
		options = options,
		seconds = seconds,
	})
	self:After(seconds, function()
		self:CloseAsk()
		on_timeout()
	end)
	Net.PushState()
end

function Context:CloseAsk()
	if (self.awaiting) then
		local seat = DBTable.seats[self.awaiting]
		if (seat and seat.player) then
			Net.EndChoice(seat.player)
		end
	end
	self.awaiting = nil
	self.ask = nil
	Net.SetTimer(nil)
end

-- Versucht einen Platz auszuschalten. Gibt zurueck:
--   "ward"  Karte The Ward hat gerettet
--   "dead"  Spieler ist ausgeschieden
--   "gone"  war schon nicht mehr am Leben
function Context:Kill(index)
	local seat = DBTable.seats[index]
	if (not seat or not seat.alive) then return "gone" end

	if (DBTable.ConsumeCard(seat, "ward")) then
		Net.Fx("ward", index)
		return "ward"
	end

	DeathBox.Game.Eliminate(seat)
	return "dead"
end

function Context:Push()
	Net.PushState()
end

-- Ritual beenden. Darf mehrfach aufgerufen werden, wirkt nur einmal.
function Context:Finish()
	if (self.finished) then return end
	self:CloseAsk()
	self.finished = true
	ClearRitualTimer()
	if (Rituals.active == self) then
		Rituals.active = nil
	end
	Net.PushState()
	if (self.on_finish) then self.on_finish() end
end

-- ===================================================================
-- Ablauf
-- ===================================================================

function Rituals.Run(def, actor_index, on_finish)
	Rituals.Cancel()

	local ctx = setmetatable({
		def = def,
		id = def.id,
		actor_index = actor_index,
		data = {},
		awaiting = nil,
		finished = false,
		on_finish = on_finish,
	}, Context)

	Rituals.active = ctx
	Rituals.last_id = def.id
	Console.Log("[DeathBox] Ritual '%s' startet, Platz %d", def.id, actor_index)
	def.Start(ctx)
end

-- Bricht das laufende Ritual ohne Weitergabe ab (z. B. Partie-Ende, /stop)
function Rituals.Cancel()
	local ctx = Rituals.active
	ClearRitualTimer()
	if (ctx) then
		ctx.on_finish = nil
		ctx:CloseAsk()
		ctx.finished = true
	end
	Rituals.active = nil
end

-- Eingabe eines Spielers pruefen und an das Ritual weitergeben
function Rituals.HandleInput(player, ritual_id, choice)
	local ctx = Rituals.active
	if (not ctx or ctx.finished or ctx.id ~= ritual_id or not ctx.awaiting) then return end
	if (DeathBox.Game.state ~= DeathBox.Game.STATE.PLAYING) then return end

	local seat, index = DBTable.FindSeatByPlayer(player)
	if (not seat or index ~= ctx.awaiting or not seat.alive) then return end

	-- Wahl muss exakt in der erlaubten Liste stehen
	local valid = false
	for _, option in ipairs(ctx.ask.options) do
		if (option == choice) then valid = true break end
	end
	if (not valid) then
		Console.Warn("[DeathBox] Ungueltige Eingabe von %s: %s", player:GetName(), tostring(choice))
		return
	end

	ctx:CloseAsk()
	ctx.def.OnInput(ctx, index, choice)
end

-- Jemand hat den Tisch verlassen, waehrend ein Ritual laeuft
function Rituals.OnSeatLeft(index)
	local ctx = Rituals.active
	if (not ctx or ctx.finished) then return end

	if (ctx.def.OnSeatLeft) then
		ctx.def.OnSeatLeft(ctx, index)
	elseif (index == ctx.actor_index or index == ctx.awaiting) then
		ctx:Finish()
	end
end

-- Daten fuer das HUD
function Rituals.GetPublicState()
	local ctx = Rituals.active
	if (not ctx) then return nil end

	local texts = Text.RITUALS[ctx.id] or {}
	return {
		id = ctx.id,
		name = texts.name or ctx.id,
		actor = ctx.actor_index,
		awaiting = ctx.awaiting,
		instruction_actor = texts.instruction_actor,
		instruction_others = Text.Format(texts.instruction_others or "", { name = ctx:Name(ctx.actor_index) }),
		data = ctx.def.GetPublic and ctx.def.GetPublic(ctx) or nil,
	}
end
