-- Server/Lobby.lua
-- Verwaltet, wo jeder Spieler gerade ist, und eroeffnet neue Tische.
--
--   Join ──> Hub (Friedhof) ──> Warteschlange
--        ──> laeuft eine Show mit lebenden Bots?  ──> ins Zelt, zuschauen ("Nachruecker"),
--                                                     zur naechsten Runde einen Bot-Platz uebernehmen (Match:AdmitJoiners)
--        ──> sonst: Countdown ──> neuer Tisch (Menschen + Bots bis TABLE_SEATS)
--        ──> nach der Show zurueck in den Hub und wieder in die Warteschlange
--
-- Leitlinie (v0.11, Server mit 12 Plaetzen, 2 Tische a 8): Spieler sollen mit SPIELERN spielen. Deshalb wird
-- immer zuerst der laufende Tisch mit den meisten Menschen aufgefuellt (Bots machen Platz), erst wenn dort kein
-- Bot mehr uebernommen werden kann, oeffnet ein weiterer Tisch. Ausnahme: Warten genug Spieler fuer einen
-- KOMPLETTEN neuen Tisch (z. B. alle aus einer gerade beendeten Show), starten sie zusammen neu.
-- Die Warteschlange gilt fuer ALLE Hubs zusammen.

local Config = DeathBox.Config
local Text = DeathBox.Text
local Net = DeathBox.Net
local Layout = DeathBox.Layout
local Characters = DeathBox.Characters

DeathBox.Lobby = {
	where = {},        -- player -> { hub = hub } oder { match = match }
	hubs = {},         -- Liste: { dimension, count, members } (gebaut wird der Friedhof beim Client)
	queue = {},        -- wartende Spieler in Reihenfolge
	matches = {},      -- laufende Matches
	countdown = nil,   -- { timer_id, ends = Net-Timer }
	bot_count = 0,     -- Debug (/bots): mindestens so viele Bots am naechsten Tisch
	avoid = {},        -- player -> match: diese Show hat er selbst verlassen (nicht wieder dorthin einteilen)
}

local Lobby = DeathBox.Lobby

local function Log(text, ...)
	Console.Log("[DeathBox] " .. text, ...)
end

-- ===================================================================
-- Hubs
-- ===================================================================

local function CreateHub()
	local dimension = DeathBox.Instances.Acquire(Config.DIMENSION_HUB_FIRST)
	local hub = { dimension = dimension, count = 0, members = {} }
	table.insert(Lobby.hubs, hub)
	Log("Hub in Dimension %d gebaut (%d Hubs)", dimension, #Lobby.hubs)
	return hub
end

-- Hub mit freiem Platz (der volle ist nicht noetig: lieber auffuellen als verteilen)
local function FindHubWithSpace()
	for _, hub in ipairs(Lobby.hubs) do
		if (hub.count < Config.HUB_CAPACITY) then return hub end
	end
	return CreateHub()
end

-- Leere Zusatz-Hubs abreissen (der erste bleibt immer stehen)
local function CleanupHubs()
	for i = #Lobby.hubs, 2, -1 do
		local hub = Lobby.hubs[i]
		if (hub.count == 0) then
			DeathBox.Instances.Release(hub.dimension)
			table.remove(Lobby.hubs, i)
			Log("Hub in Dimension %d abgebaut", hub.dimension)
		end
	end
end

-- ===================================================================
-- Warteschlange
-- ===================================================================

local function RemoveFromQueue(player)
	for i, p in ipairs(Lobby.queue) do
		if (p == player) then
			table.remove(Lobby.queue, i)
			return
		end
	end
end

local function CancelCountdown()
	if (Lobby.countdown and Timer.IsValid(Lobby.countdown.timer_id)) then
		Timer.ClearTimeout(Lobby.countdown.timer_id)
	end
	Lobby.countdown = nil
end

local function QueueSize()
	return #Lobby.queue
end

-- Teilnehmer, die ein neuer Tisch haette: echte Spieler + Bots.
-- Mit BOT_FILL wird jeder Tisch bis TABLE_SEATS mit Bots aufgefuellt (jede Show sieht voll aus und dauert
-- gleich lang; spaeter Kommende uebernehmen die Bot-Plaetze). /bots kann zum Testen weniger Plaetze erzwingen nicht,
-- nur mehr Bots als Menschen (ohne BOT_FILL).
local function NextTableSize()
	local real = math.min(QueueSize(), Config.TABLE_SEATS)
	local bots = Lobby.bot_count
	if (Config.BOT_FILL) then bots = math.max(bots, Config.TABLE_SEATS - real) end
	return math.min(real + bots, Config.TABLE_SEATS), real
end

-- ===================================================================
-- Nachruecker: laufende Show mit freien Bot-Plaetzen
-- ===================================================================

-- Laufende Show, in die ein wartender Spieler nachruecken kann: lebende Bots, die noch kein anderer
-- Nachruecker "reserviert" hat, und genug Lebende (Config.JOIN_MIN_ALIVE). Bevorzugt die Show mit den
-- meisten Menschen (erst einen Tisch fuellen), bei Gleichstand die aeltere.
local function FindJoinableMatch(player)
	if (not Config.JOIN_RUNNING) then return nil end
	local best, best_humans
	for _, match in ipairs(Lobby.matches) do
		if (Lobby.avoid[player] ~= match and match:OpenBotSeats() > 0) then
			local humans = match:CountHumans() + #match.joiners
			if (not best or humans > best_humans or (humans == best_humans and match.id < best.id)) then
				best, best_humans = match, humans
			end
		end
	end
	return best
end

-- Koennte ein Nachruecker von match woanders spielen? (freier Platz fuer einen neuen Tisch oder ein anderer
-- laufender Tisch mit freien Bot-Plaetzen)
function Lobby.HasRoomElsewhere(match)
	if (#Lobby.matches < Config.MAX_MATCHES) then return true end
	for _, other in ipairs(Lobby.matches) do
		if (other ~= match and other:OpenBotSeats() > 0) then return true end
	end
	return false
end

-- Verteilt Wartende auf laufende Shows mit freien Bot-Plaetzen. Gibt die Zahl der Verteilten zurueck.
local function Distribute()
	local moved = 0
	local i = 1
	while (i <= #Lobby.queue) do
		local player = Lobby.queue[i]
		local match = player:IsValid() and FindJoinableMatch(player) or nil
		if (match) then
			table.remove(Lobby.queue, i)
			local place = Lobby.where[player]
			if (place and place.hub) then
				place.hub.count = place.hub.count - 1
				place.hub.members[player] = nil
			end
			Lobby.where[player] = { match = match }
			match:AddJoiner(player)
			moved = moved + 1
		else
			i = i + 1
		end
	end
	if (moved > 0) then CleanupHubs() end
	return moved
end

function Lobby.BuildLobbyState()
	local players = 0
	for _ in pairs(Lobby.where) do players = players + 1 end
	local total, real = NextTableSize()
	return {
		online = players,
		queued = QueueSize(),
		needed = Config.MIN_PLAYERS,
		next_table = total,
		humans = real,             -- Menschen am naechsten Tisch (Rest: Bots, die Nachruecker spaeter uebernehmen)
		seats = Config.TABLE_SEATS,
		bots = total - real,
		tables = #Lobby.matches,
		max_tables = Config.MAX_MATCHES,
		timer = Lobby.countdown and Net.TimerSnapshot(Lobby.countdown.ends) or nil,
	}
end

-- Lobby-Anzeige an alle Hubs. Gesammelt und hoechstens alle LOBBY_PUSH_INTERVAL Sekunden,
-- damit 999 gleichzeitige Joins nicht 999 x 999 Nachrichten erzeugen.
local LOBBY_PUSH_INTERVAL = 0.5
local lobby_dirty = false

function Lobby.PushLobby()
	lobby_dirty = true
end

local function FlushLobby()
	if (not lobby_dirty) then return end
	lobby_dirty = false
	local data = Lobby.BuildLobbyState()
	for _, hub in ipairs(Lobby.hubs) do
		if (hub.count > 0) then Net.SendLobby(hub.dimension, data) end
	end
end

local function StartCountdown(seconds)
	CancelCountdown()
	local countdown = { ends = Net.MakeTimer(seconds) }
	countdown.timer_id = Timer.SetTimeout(function()
		Lobby.countdown = nil
		Lobby.OpenTable()
	end, seconds * 1000)
	Lobby.countdown = countdown
end

-- Prueft, ob ein neuer Tisch starten kann, und stellt den Countdown passend.
-- Reihenfolge: (1) genug Wartende fuer einen KOMPLETTEN Tisch und Platz dafuer -> zusammen neu starten (kurzer
-- Countdown); (2) sonst Wartende auf laufende Shows mit freien Bot-Plaetzen verteilen; (3) Rest: Countdown fuer
-- einen neuen Tisch, solange einer frei ist.
function Lobby.CheckQueue()
	local room = #Lobby.matches < Config.MAX_MATCHES
	if (not (room and QueueSize() >= Config.TABLE_SEATS)) then
		Distribute()
	end

	local total, real = NextTableSize()
	local can_open = real >= 1 and total >= math.max(2, Config.MIN_PLAYERS) and room

	if (not can_open) then
		CancelCountdown()
	elseif (not Lobby.countdown) then
		StartCountdown(real >= Config.TABLE_SEATS and Config.QUEUE_COUNTDOWN_FULL or Config.QUEUE_COUNTDOWN)
	elseif (real >= Config.TABLE_SEATS) then
		-- Genug MENSCHEN fuer einen vollen Tisch: Countdown verkuerzen, falls er noch laenger laeuft
		local remaining = (Lobby.countdown.ends.ends_at - Net.Now()) / 1000
		if (remaining > Config.QUEUE_COUNTDOWN_FULL) then
			StartCountdown(Config.QUEUE_COUNTDOWN_FULL)
		end
	end
	Lobby.PushLobby()
end

-- Eroeffnet einen Tisch mit den ersten Spielern der Schlange
function Lobby.OpenTable()
	CancelCountdown()
	-- Waehrend des Countdowns kann ein laufender Tisch wieder Platz bekommen haben (Nachruecker ging): erst dorthin
	if (QueueSize() < Config.TABLE_SEATS) then Distribute() end
	local total, real = NextTableSize()
	if (real < 1 or total < math.max(2, Config.MIN_PLAYERS) or #Lobby.matches >= Config.MAX_MATCHES) then
		Lobby.CheckQueue()
		return
	end

	local function Open(count, bots)
		local players = {}
		for _ = 1, count do
			local player = table.remove(Lobby.queue, 1)
			table.insert(players, player)
			local place = Lobby.where[player]
			if (place and place.hub) then
				place.hub.count = place.hub.count - 1
				place.hub.members[player] = nil
			end
		end
		local match = DeathBox.Match.Create(players, bots)
		table.insert(Lobby.matches, match)
		for _, player in ipairs(players) do
			Lobby.where[player] = { match = match }
		end
	end

	Open(real, total - real)
	Lobby.bot_count = 0

	-- Warten noch genug fuer weitere VOLLE Tische, starten die sofort mit
	while (QueueSize() >= Config.TABLE_SEATS and #Lobby.matches < Config.MAX_MATCHES) do
		Open(Config.TABLE_SEATS, 0)
	end

	CleanupHubs()
	Lobby.CheckQueue()   -- Rest bekommt einen neuen Countdown
end

-- ===================================================================
-- Spieler kommen, gehen, wechseln
-- ===================================================================

-- In einen Hub bringen und in die Warteschlange stellen
function Lobby.SendToHub(player)
	if (not player or not player:IsValid()) then return end
	local hub = FindHubWithSpace()
	hub.count = hub.count + 1
	hub.members[player] = true
	Lobby.where[player] = { hub = hub }

	local location, rotation = Layout.HubSpawn()
	Net.Place(player, "hub")
	Net.SendHand(player, { cards = {} })   -- Karten gibt es nur am Tisch
	Characters.Place(player, hub.dimension, location, rotation)

	RemoveFromQueue(player)
	table.insert(Lobby.queue, player)
	if (not Lobby.batching) then Lobby.CheckQueue() end
end

function Lobby.OnPlayerJoin(player)
	Lobby.SendToHub(player)
end

-- Begruessung erst, wenn der Client fertig geladen hat (beim Spawn kaeme die Chat-Zeile evtl. nicht an)
function Lobby.OnPlayerReady(player)
	if (not player or not player:IsValid()) then return end
	Chat.SendMessage(player, Text.Format(Text.HUB_JOIN, { name = player:GetName() }))
end

function Lobby.OnPlayerLeave(player)
	local place = Lobby.where[player]
	Lobby.where[player] = nil
	Lobby.avoid[player] = nil
	RemoveFromQueue(player)

	if (place and place.hub) then
		place.hub.count = place.hub.count - 1
		place.hub.members[player] = nil
		CleanupHubs()
	elseif (place and place.match) then
		place.match:OnPlayerLeave(player)
	end
	Lobby.CheckQueue()
end

-- Ausgeschiedener Spieler (oder Nachruecker) will nicht mehr zuschauen: /leave bzw. Knopf "Next show" im HUD.
-- Er kommt nicht wieder an DIESEN Tisch (Lobby.avoid), sondern an einen anderen oder in die naechste Show.
function Lobby.LeaveMatch(player)
	local place = Lobby.where[player]
	if (not place or not place.match) then return false end
	local match = place.match
	local seat = match:FindSeatByPlayer(player)
	if (seat and seat.alive and match.state ~= DeathBox.Match.STATE.ENDED) then
		return false   -- wer noch lebt, kann nicht einfach gehen
	end
	Lobby.avoid[player] = match
	match:OnPlayerLeave(player)
	if (Lobby.where[player] and Lobby.where[player].match == match) then
		Lobby.SendToHub(player)
	end
	return true
end

-- Match ist vorbei: alle zurueck in den Hub
function Lobby.OnMatchDisposed(match, players)
	for i, m in ipairs(Lobby.matches) do
		if (m == match) then
			table.remove(Lobby.matches, i)
			break
		end
	end
	for player, avoided in pairs(Lobby.avoid) do
		if (avoided == match) then Lobby.avoid[player] = nil end
	end
	-- Alle zuerst in den Hub, DANN einmal verteilen: so bleibt eine Gruppe, die zusammen gespielt hat, zusammen
	-- (ein ganzer Tisch startet gemeinsam neu, statt einzeln auf freie Bot-Plaetze verteilt zu werden).
	-- Jeder einzeln geschuetzt: ein Fehler bei einem Spieler darf die anderen nicht im aufgeloesten Tisch zuruecklassen.
	Lobby.batching = true
	for _, player in ipairs(players) do
		local place = Lobby.where[player]
		if (place and place.match == match) then
			local ok, err = pcall(Lobby.SendToHub, player)
			if (not ok) then Console.Error("[DeathBox] Rueckkehr in den Hub fehlgeschlagen: %s", tostring(err)) end
		end
	end
	Lobby.batching = false
	Lobby.CheckQueue()
end

-- ===================================================================
-- Chat pro Instanz
-- ===================================================================
-- Die Engine schickt Chat-Zeilen an ALLE Spieler des Servers (sie kennt keine Dimensionen). Deshalb verteilt
-- der Server sie selbst: nur an den eigenen Hub-Bereich bzw. den eigenen Tisch (Lebende und Zuschauer).

-- Keine Text-Stile einschleusen (<red>, <bold> ...) und kein halbes UTF-8-Zeichen am Ende
local function Plain(text, max_length)
	text = string.gsub(text, "<", "\226\128\185")   -- "‹"
	if (#text > max_length) then
		text = string.gsub(string.sub(text, 1, max_length), "[\192-\255][\128-\191]*$", "")
	end
	return text
end

function Lobby.Chat(player, message)
	local place = Lobby.where[player]
	if (not place or type(message) ~= "string" or not string.find(message, "%S")) then return end

	local name = Plain(player:GetName(), 32)
	local line
	local recipients = {}
	if (place.hub) then
		line = "<bold>" .. name .. "</>: " .. Plain(message, Config.CHAT_MAX_LENGTH)
		for member in pairs(place.hub.members) do table.insert(recipients, member) end
	else
		local seat = place.match:FindSeatByPlayer(player)
		local style = (seat and seat.alive) and "bold" or "grey"   -- Zuschauer und Nachruecker grau
		line = "<" .. style .. ">" .. name .. "</>: " .. Plain(message, Config.CHAT_MAX_LENGTH)
		for _, other in ipairs(place.match.seats) do
			if (other.player) then table.insert(recipients, other.player) end
		end
		for _, joiner in ipairs(place.match.joiners) do table.insert(recipients, joiner) end
	end
	for _, recipient in ipairs(recipients) do
		if (recipient:IsValid()) then Chat.SendMessage(recipient, line) end
	end
end

function Lobby.GetMatchOf(player)
	local place = Lobby.where[player]
	return place and place.match or nil
end

function Lobby.SendCurrentStateTo(player)
	local place = Lobby.where[player]
	if (not place) then return end
	if (place.match) then
		Net.Place(player, "match", place.match:PlaceInfo())
		place.match:SendStateTo(player)
	else
		Net.Place(player, "hub")
		Net.SendHand(player, { cards = {} })   -- Karten gibt es nur am Tisch
		Net.SendLobbyTo(player, Lobby.BuildLobbyState())
	end
end

-- Start: ersten Hub bauen, Lobby-Anzeige regelmaessig verschicken
function Lobby.Init()
	if (#Lobby.hubs == 0) then CreateHub() end
	if (not Lobby.flush_timer) then
		Lobby.flush_timer = Timer.SetInterval(function() FlushLobby() end, LOBBY_PUSH_INTERVAL * 1000)
	end
end
