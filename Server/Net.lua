-- Server/Net.lua
-- Alles, was zwischen Server und Clients hin- und hergeht, laeuft ueber diese Datei.
--
-- Server -> Client (Remote Events):
--   "DeathBox:State"    JSON-Snapshot des oeffentlichen Spielzustands (an alle)
--   "DeathBox:Say"      Madames Untertitel (an alle)
--   "DeathBox:Fx"       kurzer Effekt: Sound/Anzeige, z. B. "click", "bang", "ward" (an alle)
--   "DeathBox:Choice"   JSON: Auswahl fuer genau einen Spieler (z. B. Ziele im Chamber)
--   "DeathBox:ChoiceEnd"   Auswahl schliessen
--
-- Client -> Server:
--   "DeathBox:Input"         (ritual_id, choice) – wird in Rituals.HandleInput streng geprueft
--   "DeathBox:RequestState"  HUD ist bereit und moechte den aktuellen Zustand
--
-- Warum JSON? Ein einziges, klar definiertes Format fuer Lua und JavaScript.
-- Der Client reicht den Text unveraendert an die WebUI weiter, dort wird er mit JSON.parse gelesen.

DeathBox.Net = {
	timer = nil,            -- { total = Sekunden, ends_at = ms } fuer den Zeitbalken im HUD
	leaving_player = nil,   -- Spieler, der gerade den Server verlaesst (nicht mitzaehlen)
}

local Net = DeathBox.Net

local function Now()
	return Server.GetTime()
end

-- Zeitbalken setzen (seconds = nil entfernt ihn)
function Net.SetTimer(seconds)
	if (seconds and seconds > 0) then
		Net.timer = { total = seconds, ends_at = Now() + seconds * 1000 }
	else
		Net.timer = nil
	end
end

local function TimerSnapshot()
	if (not Net.timer) then return nil end
	local remaining = math.max(0, (Net.timer.ends_at - Now()) / 1000)
	return { total = Net.timer.total, remaining = remaining }
end

-- Baut den oeffentlichen Zustand. Enthaelt nur, was ALLE sehen duerfen
-- (z. B. Anzahl Karten, aber nicht welche Karten).
local function BuildSnapshot()
	local Game = DeathBox.Game
	local seats = {}

	local seat_count = #DeathBox.Table.seats
	for index, seat in ipairs(DeathBox.Table.seats) do
		-- Winkel des Stuhls am Tisch, damit das HUD die Sitzordnung genauso zeigt wie im Raum
		local angle = 0
		if (DeathBox.Arena.built) then
			local chair = DeathBox.Arena.chairs[DeathBox.Arena.GetChairIndex(index, seat_count)]
			angle = chair and chair.angle or 0
		end

		table.insert(seats, {
			seat = index,
			angle = angle,
			name = seat.name,
			id = seat.player and seat.player:IsValid() and seat.player:GetID() or -1,
			bot = seat.is_bot,
			alive = seat.alive,
			cards = #seat.cards,
		})
	end

	local snapshot = {
		phase = Game.state,
		seats = seats,
		turn = Game.current_index,
		winner = Game.winner_index,
		timer = TimerSnapshot(),
		lobby = {
			players = #DeathBox.Game.GetConnectedPlayers(Net.leaving_player),
			bots = Game.bot_count,
			needed = DeathBox.Config.MIN_PLAYERS,
		},
		ritual = DeathBox.Rituals.GetPublicState(),
	}
	return snapshot
end

-- Schickt den aktuellen Zustand an alle. Wird nach jeder sichtbaren Aenderung aufgerufen.
function Net.PushState()
	Events.BroadcastRemote("DeathBox:State", Reliability.Reliable, JSON.stringify(BuildSnapshot()))
end

-- Schickt den Zustand an einen einzelnen Spieler (z. B. direkt nach dem Joinen)
function Net.SendStateTo(player)
	Events.CallRemote("DeathBox:State", player, Reliability.Reliable, JSON.stringify(BuildSnapshot()))
end

-- Madame spricht (Untertitel fuer alle) und zusaetzlich im Chat, damit man es nachlesen kann
function Net.Say(text)
	Events.BroadcastRemote("DeathBox:Say", Reliability.Reliable, text)
	Console.Log("[Madame] %s", text)
end

-- Kurzer Effekt fuer alle: kind = "click" | "bang" | "ward" | "chosen" | ...
-- seat = betroffener Platz (fuer Hervorhebung im HUD), optional
function Net.Fx(kind, seat)
	Events.BroadcastRemote("DeathBox:Fx", Reliability.Reliable, kind, seat or 0)
end

-- Oeffnet bei genau einem Spieler eine Auswahl
-- data = { ritual = "chamber", kind = "target", options = { 2, 5, 7 }, seconds = 8 }
function Net.SendChoice(player, data)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:Choice", player, Reliability.Reliable, JSON.stringify(data))
end

function Net.EndChoice(player)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:ChoiceEnd", player, Reliability.Reliable)
end

-- Eingaben vom Client. Hier wird nur der Typ grob geprueft, die eigentliche
-- Pruefung (ist der Spieler dran? gueltige Wahl?) macht Rituals.HandleInput.
Events.SubscribeRemote("DeathBox:Input", function(player, ritual_id, choice)
	if (type(ritual_id) ~= "string" or #ritual_id > 32) then return end
	if (type(choice) ~= "number" and type(choice) ~= "string") then return end
	DeathBox.Rituals.HandleInput(player, ritual_id, choice)
end)

-- Das HUD meldet sich, sobald es geladen ist. Gedrosselt, damit niemand den Server zuspammen kann.
local last_request = {}
Events.SubscribeRemote("DeathBox:RequestState", function(player)
	local now = Now()
	local id = player:GetID()
	if (last_request[id] and now - last_request[id] < 1000) then return end
	last_request[id] = now
	Net.SendStateTo(player)
end)

Player.Subscribe("Destroy", function(player)
	last_request[player:GetID()] = nil
end)
