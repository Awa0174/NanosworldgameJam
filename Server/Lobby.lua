-- Server/Lobby.lua
-- Verwaltet, wo jeder Spieler gerade ist, und eroeffnet neue Tische.
--
--   Join ──> Hub (Friedhof, eigene Dimension pro HUB_CAPACITY Spieler)
--        ──> Warteschlange (automatisch, alle im Hub warten)
--        ──> genug Spieler: Countdown ──> neuer Tisch mit bis zu TABLE_SEATS Spielern
--        ──> nach der Show zurueck in den Hub und wieder in die Warteschlange
--
-- Die Warteschlange gilt fuer ALLE Hubs zusammen: Spieler aus verschiedenen Hubs
-- koennen am selben Tisch landen. Es koennen viele Tische gleichzeitig laufen.

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
	bot_count = 0,     -- Debug: Bots fuer den naechsten Tisch
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

-- Teilnehmer, die ein neuer Tisch haette (echte Spieler + Debug-Bots)
local function NextTableSize()
	local real = math.min(QueueSize(), Config.TABLE_SEATS)
	return math.min(real + Lobby.bot_count, Config.TABLE_SEATS), real
end

function Lobby.BuildLobbyState()
	local players = 0
	for _ in pairs(Lobby.where) do players = players + 1 end
	local total, _ = NextTableSize()
	return {
		online = players,
		queued = QueueSize(),
		needed = Config.MIN_PLAYERS,
		next_table = total,
		seats = Config.TABLE_SEATS,
		bots = Lobby.bot_count,
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

-- Prueft, ob ein neuer Tisch starten kann, und stellt den Countdown passend
function Lobby.CheckQueue()
	local total, real = NextTableSize()
	local can_open = real >= 1 and total >= Config.MIN_PLAYERS and #Lobby.matches < Config.MAX_MATCHES

	if (not can_open) then
		CancelCountdown()
	elseif (not Lobby.countdown) then
		StartCountdown(total >= Config.TABLE_SEATS and Config.QUEUE_COUNTDOWN_FULL or Config.QUEUE_COUNTDOWN)
	elseif (total >= Config.TABLE_SEATS) then
		-- Tisch ist voll: Countdown verkuerzen, falls er noch laenger laeuft
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
	local total, real = NextTableSize()
	if (real < 1 or total < Config.MIN_PLAYERS or #Lobby.matches >= Config.MAX_MATCHES) then
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
	-- (z. B. wenn 300 Spieler gleichzeitig joinen)
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
	Lobby.CheckQueue()
end

function Lobby.OnPlayerJoin(player)
	Chat.SendMessage(player, Text.Format(Text.HUB_JOIN, { name = player:GetName() }))
	Lobby.SendToHub(player)
end

function Lobby.OnPlayerLeave(player)
	local place = Lobby.where[player]
	Lobby.where[player] = nil
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

-- Ausgeschiedener Spieler will nicht mehr zuschauen (/leave)
function Lobby.LeaveMatch(player)
	local place = Lobby.where[player]
	if (not place or not place.match) then return false end
	local match = place.match
	local seat = match:FindSeatByPlayer(player)
	if (seat and seat.alive and match.state ~= DeathBox.Match.STATE.ENDED) then
		return false   -- wer noch lebt, kann nicht einfach gehen
	end
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
	for _, player in ipairs(players) do
		local place = Lobby.where[player]
		if (place and place.match == match) then
			Lobby.SendToHub(player)
		end
	end
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
		local style = (seat and seat.alive) and "bold" or "grey"   -- Zuschauer grau
		line = "<" .. style .. ">" .. name .. "</>: " .. Plain(message, Config.CHAT_MAX_LENGTH)
		for _, other in ipairs(place.match.seats) do
			if (other.player) then table.insert(recipients, other.player) end
		end
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
