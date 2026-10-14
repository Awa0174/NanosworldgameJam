-- Server/Net.lua
-- Alles, was zwischen Server und Clients hin- und hergeht. Vollstaendige Liste: docs/PROTOCOL.md.
-- Nachrichten gehen immer nur an die Dimension (Instanz), die sie betreffen.
--
-- Server -> Client:
--   "DeathBox:Place"     (kind, info) "hub" oder "match": wo der Spieler gerade ist
--   "DeathBox:Lobby"     JSON: Warteschlange, Countdown, laufende Tische (an einen Hub)
--   "DeathBox:State"     JSON: oeffentlicher Zustand eines Tisches (an dessen Dimension)
--   "DeathBox:Say"       Jacks Untertitel
--   "DeathBox:Fx"        (kind, seat) kurzer HUD-/Sound-Effekt: "click", "bang", "safety", "dodge", ...
--   "DeathBox:Show"      JSON: Regieanweisung fuer die Praesentation (Jack, Licht, Musik, 3D-Effekte, HUD-Karten)
--                        Der Client baut daraus alles lokal (Client/Presentation.lua) -> kein Sync-Ruckeln.
--   "DeathBox:Choice"    JSON: Abfrage fuer genau einen Spieler { ask, event, kind, options, seconds, ... }
--   "DeathBox:ChoiceEnd" (ask) Abfrage schliessen
--   "DeathBox:Hand"      JSON: PRIVAT, die eigene Kartenhand { cards = [ { uid, id, rounds_left? } ] }
--
-- Client -> Server (jede Eingabe wird hier grob und danach im Spiel streng geprueft):
--   "DeathBox:Input"         (ask_id, choice) – Match:HandleInput / Context:HandleInput
--   "DeathBox:Aim"           (ask_id, seat) – Revolver-Zielmodus: Zwischenstand der Zielwahl (0 = niemand), gedrosselt
--   "DeathBox:RequestState"  HUD ist bereit und moechte den aktuellen Zustand (gedrosselt)
--   "DeathBox:PlayCard"      (uid, target_seat) – Hand.Play (Server/Cards.lua)
--   "DeathBox:Leave"         Knopf "Next show": Ausgeschiedener/Nachruecker geht in die naechste Show (Lobby.LeaveMatch)
--
-- Warum JSON? Ein einziges, klar definiertes Format fuer Lua und JavaScript.

DeathBox.Net = {}

local Net = DeathBox.Net

function Net.Now()
	return Server.GetTime()
end

-- Zeitanzeige fuer das HUD: { total, ends_at } -> { total, remaining }
function Net.MakeTimer(seconds)
	if (not seconds or seconds <= 0) then return nil end
	return { total = seconds, ends_at = Net.Now() + seconds * 1000 }
end

function Net.TimerSnapshot(timer)
	if (not timer) then return nil end
	local remaining = math.max(0, (timer.ends_at - Net.Now()) / 1000)
	return { total = timer.total, remaining = remaining }
end

-- Sagt dem Client, wo er ist. Der Client baut daraufhin den Ort lokal (Friedhof oder Zelt).
--   kind = "hub" | "match", info = { seat_count = 16, jack_yaw = 0 } (nur bei "match")
function Net.Place(player, kind, info)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:Place", player, Reliability.Reliable, kind, JSON.stringify(info or {}))
end

function Net.SendLobby(dimension, data)
	Events.BroadcastRemoteDimension("DeathBox:Lobby", dimension, Reliability.Reliable, JSON.stringify(data))
end

function Net.SendLobbyTo(player, data)
	Events.CallRemote("DeathBox:Lobby", player, Reliability.Reliable, JSON.stringify(data))
end

function Net.SendState(dimension, snapshot)
	Events.BroadcastRemoteDimension("DeathBox:State", dimension, Reliability.Reliable, JSON.stringify(snapshot))
end

function Net.SendStateTo(player, snapshot)
	Events.CallRemote("DeathBox:State", player, Reliability.Reliable, JSON.stringify(snapshot))
end

function Net.Say(dimension, text)
	Events.BroadcastRemoteDimension("DeathBox:Say", dimension, Reliability.Reliable, text)
end

function Net.Fx(dimension, kind, seat)
	Events.BroadcastRemoteDimension("DeathBox:Fx", dimension, Reliability.Reliable, kind, seat or 0)
end

-- Regieanweisung an alle in einer Dimension. data wird um "action" ergaenzt.
function Net.Show(dimension, action, data)
	data = data or {}
	data.action = action
	Events.BroadcastRemoteDimension("DeathBox:Show", dimension, Reliability.Reliable, JSON.stringify(data))
end

function Net.ShowTo(player, action, data)
	if (not player or not player:IsValid()) then return end
	data = data or {}
	data.action = action
	Events.CallRemote("DeathBox:Show", player, Reliability.Reliable, JSON.stringify(data))
end

function Net.SendChoice(player, data)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:Choice", player, Reliability.Reliable, JSON.stringify(data))
end

function Net.EndChoice(player, ask_id)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:ChoiceEnd", player, Reliability.Reliable, ask_id or 0)
end

-- Private Kartenhand an genau diesen Spieler
function Net.SendHand(player, data)
	if (not player or not player:IsValid()) then return end
	Events.CallRemote("DeathBox:Hand", player, Reliability.Reliable, JSON.stringify(data))
end

local function IsInteger(value)
	return type(value) == "number" and value == math.floor(value) and value >= 0 and value < 2 ^ 31
end

-- Flutschutz pro Spieler und Nachricht (Token-Eimer): hoechstens rate Nachrichten pro Sekunde, kurze Spitzen
-- bis rate erlaubt. Gibt false zurueck, wenn die Nachricht verworfen werden soll.
local budgets = {}   -- kind -> player_id -> { tokens, at }
local function Allow(kind, player, rate)
	local list = budgets[kind]
	if (not list) then
		list = {}
		budgets[kind] = list
	end
	local now, id = Net.Now(), player:GetID()
	local budget = list[id]
	if (not budget) then
		budget = { tokens = rate, at = now }
		list[id] = budget
	end
	budget.tokens = math.min(rate, budget.tokens + (now - budget.at) / 1000 * rate)
	budget.at = now
	if (budget.tokens < 1) then return false end
	budget.tokens = budget.tokens - 1
	return true
end

local INPUT_RATE = 12      -- DeathBox:Input pro Sekunde (Feuer-Klicks sind die schnellsten echten Eingaben)
local CARD_RATE = 3        -- DeathBox:PlayCard pro Sekunde
local LEAVE_RATE = 1       -- DeathBox:Leave pro Sekunde

-- Eingaben vom Client. Hier wird nur der Typ grob geprueft, die eigentliche
-- Pruefung (ist der Spieler gefragt? gueltige Wahl? richtige Abfrage?) macht Match.HandleInput.
Events.SubscribeRemote("DeathBox:Input", function(player, ask_id, choice)
	if (type(ask_id) ~= "number") then return end
	if (not Allow("input", player, INPUT_RATE)) then return end
	if (type(choice) == "string") then
		if (#choice > 32) then return end
	elseif (type(choice) ~= "number") then
		return
	end
	local match = DeathBox.Lobby.GetMatchOf(player)
	if (match) then
		match:HandleInput(player, ask_id, choice)
	end
end)

-- Revolver-Zielmodus: Zwischenstand der Zielwahl (ask_id, Platz oder 0). Pro Spieler hoechstens
-- Config.REVOLVER.AIM_RATE Nachrichten pro Sekunde (Token-Eimer, der Rest wird verworfen). Ob der Absender wirklich
-- der Halter in der Wahl-Phase ist und der Platz erlaubt, prueft Match:HandleAim / Context:HandleAim.
Events.SubscribeRemote("DeathBox:Aim", function(player, ask_id, seat)
	if (not IsInteger(ask_id) or not IsInteger(seat)) then return end
	if (not Allow("aim", player, DeathBox.Config.REVOLVER.AIM_RATE)) then return end
	local match = DeathBox.Lobby.GetMatchOf(player)
	if (match) then
		match:HandleAim(player, ask_id, seat)
	end
end)

-- Karte ausspielen: uid der Karte, Ziel-Platz (0 = keins). Pruefung in Hand.Play.
Events.SubscribeRemote("DeathBox:PlayCard", function(player, uid, target_seat)
	if (not IsInteger(uid) or not IsInteger(target_seat)) then return end
	if (not Allow("card", player, CARD_RATE)) then return end
	if (not DeathBox.Hand.Play(player, uid, target_seat) and DeathBox.Config.DEBUG_COMMANDS) then
		Console.Warn("[DeathBox] Karte abgelehnt von %s: uid %d, Ziel %d", player:GetName(), uid, target_seat)
	end
end)

-- Das HUD meldet sich, sobald es geladen ist. Gedrosselt, damit niemand den Server zuspammen kann.
local last_request = {}
Events.SubscribeRemote("DeathBox:RequestState", function(player)
	local now = Net.Now()
	local id = player:GetID()
	if (last_request[id] and now - last_request[id] < 1000) then return end
	last_request[id] = now
	DeathBox.Lobby.SendCurrentStateTo(player)
end)

-- Knopf "Next show" im HUD (Ausgeschiedene und Nachruecker): wie /leave
Events.SubscribeRemote("DeathBox:Leave", function(player)
	if (not Allow("leave", player, LEAVE_RATE)) then return end
	DeathBox.Lobby.LeaveMatch(player)
end)

Player.Subscribe("Destroy", function(player)
	local id = player:GetID()
	last_request[id] = nil
	for _, list in pairs(budgets) do list[id] = nil end
end)
