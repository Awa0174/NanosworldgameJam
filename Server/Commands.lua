-- Server/Commands.lua
-- Chat-Befehle und Test-Cheats.
--   Immer aktiv:  /leave (Zuschauer zurueck in den Hub)
--   Nur fuer Admins: /bots, /start, /stop, /status, /event, /card, /god, /noclip (Taste B), /hub, /sitpos
-- Admin ist, wer in der SERVER-KONSOLE (Pterodactyl) freigeschaltet wurde:  db_admin <name oder id>
-- (gilt bis zum Verlassen des Servers). Config.DEBUG_COMMANDS = true macht ALLE zu Admins (nur zum Testen!).
-- Cheats (god, noclip, hub) sind fuer lebende Spieler am Tisch gesperrt. /card ist gerade dort zum Testen da.

DeathBox.Commands = {
	admins = {},   -- player -> true
}

local Commands = DeathBox.Commands
local Config = DeathBox.Config
local Lobby = DeathBox.Lobby
local Characters = DeathBox.Characters

-- Schaltet alle Cheats einer Figur ab (z. B. bevor sie hingesetzt oder ausgeschaltet wird)
function Commands.ResetCheats(character)
	if (not character or not character:IsValid()) then return end
	if (character:GetValue("DeathBox_NoClip")) then
		character:SetFlyingMode(false)
		character:SetCollision(CollisionType.Normal)
		character:SetValue("DeathBox_NoClip", false)
	end
	if (character:GetValue("DeathBox_God")) then
		character:SetInvulnerable(false)
		character:SetValue("DeathBox_God", false)
	end
end

function Commands.IsAdmin(player)
	return Config.DEBUG_COMMANDS == true or (player ~= nil and Commands.admins[player] == true)
end

-- Darf dieser Spieler gerade cheaten?
local function CheatCharacter(player)
	if (not Commands.IsAdmin(player)) then return nil end
	local match = Lobby.GetMatchOf(player)
	if (match) then
		local seat = match:FindSeatByPlayer(player)
		if (seat and seat.alive) then
			Chat.SendMessage(player, "Not while you are seated at the table.")
			return nil
		end
	end
	local character = player:GetControlledCharacter()
	if (not character or character:IsDead()) then
		Chat.SendMessage(player, "You have no living character right now.")
		return nil
	end
	return character
end

local function ToggleNoClip(player)
	local character = CheatCharacter(player)
	if (not character) then return end
	local enabled = not character:GetValue("DeathBox_NoClip")
	character:SetFlyingMode(enabled)
	character:SetCollision(enabled and CollisionType.NoCollision or CollisionType.Normal)
	character:SetValue("DeathBox_NoClip", enabled)
	Chat.SendMessage(player, "Noclip: " .. (enabled and "on" or "off"))
end

local PUBLIC = {
	-- /leave  – als Ausgeschiedener zurueck in den Hub
	leave = function(player)
		if (not Lobby.LeaveMatch(player)) then
			Chat.SendMessage(player, "You can only leave when you are out of the show.")
		end
	end,
}

local DEBUG = {
	-- /bots <anzahl>  – Bots fuer den naechsten Tisch
	bots = function(player, argument)
		local count = tonumber(argument)
		local max = Config.TABLE_SEATS - 1
		if (not count or count < 0 or count > max or count % 1 ~= 0) then
			Chat.SendMessage(player, "Usage: /bots <0-" .. max .. ">")
			return
		end
		Lobby.bot_count = count
		Chat.SendMessage(player, "Bots for the next table: " .. count)
		Lobby.CheckQueue()
	end,

	-- /start  – naechsten Tisch sofort eroeffnen
	start = function(player)
		Lobby.OpenTable()
	end,

	-- /stop  – eigenen Tisch beenden
	stop = function(player)
		local match = Lobby.GetMatchOf(player)
		if (not match) then
			Chat.SendMessage(player, "You are not at a table.")
			return
		end
		match:Dispose()
	end,

	-- /event <id>  – naechstes Event am eigenen Tisch erzwingen
	event = function(player, argument)
		local match = Lobby.GetMatchOf(player)
		local id = string.lower(argument or "")
		if (not match or not DeathBox.Events.Exists(id)) then
			Chat.SendMessage(player, "Usage (at a table): /event <" .. table.concat(DeathBox.Events.GetIds(), "|") .. ">")
			return
		end
		match.forced_event = id
		local def = DeathBox.Events.registry[id]
		local note = DeathBox.Events.IsPresentable(def) and "" or " - the HUD cannot show its question yet (HUD_CHOICE_KINDS)"
		Chat.SendMessage(player, string.format("Next event: %s (needs %d alive)%s", id, math.max(def.min_alive, def.actors), note))
	end,

	-- /card <id>  – sich selbst eine Karte geben (lebend am eigenen Tisch)
	card = function(player, argument)
		local match = Lobby.GetMatchOf(player)
		local id = string.lower(argument or "")
		local seat, index
		if (match) then seat, index = match:FindSeatByPlayer(player) end
		if (not seat or not seat.alive or not DeathBox.IsValidCard(id)) then
			Chat.SendMessage(player, "Usage (alive at a table): /card <" .. table.concat(DeathBox.CARD_IDS, "|") .. ">")
			return
		end
		if (not DeathBox.Hand.Give(match, index, id)) then
			Chat.SendMessage(player, "Your hand is full (" .. Config.CARDS.MAX_HAND .. " cards).")
			return
		end
		match:Show("card_gain", { seat = index, count = 1 })
		match:PushState()
		Chat.SendMessage(player, "Card added: " .. DeathBox.Cards[id].name)
	end,

	-- /status  – Ueberblick
	status = function(player)
		local hubs = {}
		for _, hub in ipairs(Lobby.hubs) do table.insert(hubs, hub.dimension .. ":" .. hub.count) end
		Chat.SendMessage(player, string.format("Hubs [%s] | Queue: %d | Tables: %d | Bots next: %d",
			table.concat(hubs, " "), #Lobby.queue, #Lobby.matches, Lobby.bot_count))
		local match = Lobby.GetMatchOf(player)
		if (match) then
			local event = match.event and match.event.id or "-"
			Chat.SendMessage(player, string.format("Your table %d (dim %d): %s | event %s | alive %d/%d",
				match.id, match.dimension, match.state, event, match:CountAlive(), #match.seats))
		end
	end,

	god = function(player)
		local character = CheatCharacter(player)
		if (not character) then return end
		local enabled = not character:GetValue("DeathBox_God")
		character:SetInvulnerable(enabled)
		character:SetValue("DeathBox_God", enabled)
		Chat.SendMessage(player, "Godmode: " .. (enabled and "on" or "off"))
	end,

	noclip = ToggleNoClip,

	-- /hub  – zurueck zum Spawn des eigenen Hubs
	hub = function(player)
		local character = CheatCharacter(player)
		local place = Lobby.where[player]
		if (not character or not place or not place.hub) then return end
		local location, rotation = DeathBox.Layout.HubSpawn()
		Characters.Place(player, place.hub.dimension, location, rotation)
	end,

	-- /sitpos <hoehe> <vor> [drehung]  – Sitzposition live aendern (gilt sofort am eigenen Tisch)
	sitpos = function(player, argument)
		local cfg = Config.WORLD
		local height, forward, yaw = string.match(argument or "", "^(%-?%d+)%s+(%-?%d+)%s*(%-?%d*)$")
		height, forward, yaw = tonumber(height), tonumber(forward), tonumber(yaw)
		if (not height or not forward or math.abs(height) > 300 or math.abs(forward) > 200) then
			Chat.SendMessage(player, string.format("Usage: /sitpos <height> <forward> [yaw]  (current: %d %d %d)",
				cfg.SIT_HEIGHT, cfg.SIT_FORWARD, cfg.SIT_YAW_OFFSET))
			return
		end
		cfg.SIT_HEIGHT, cfg.SIT_FORWARD = height, forward
		if (yaw) then cfg.SIT_YAW_OFFSET = yaw % 360 end

		-- Alle Sitzenden am eigenen Tisch neu setzen
		local match = Lobby.GetMatchOf(player)
		if (match) then
			for _, seat in ipairs(match.seats) do
				local character = seat.player and seat.player:GetControlledCharacter() or seat.bot_character
				if (seat.alive and character and character:IsValid()) then
					local location, rotation = DeathBox.Layout.SitTransform(seat.chair, match.seat_count)
					Characters.Sit(character, location, rotation)
				end
			end
		end
		Chat.SendMessage(player, string.format("Sit position: SIT_HEIGHT = %d, SIT_FORWARD = %d, SIT_YAW_OFFSET = %d (copy into Config.lua when it fits)",
			cfg.SIT_HEIGHT, cfg.SIT_FORWARD, cfg.SIT_YAW_OFFSET))
	end,
}

-- Gibt true zurueck, wenn die Nachricht ein Befehl war (dann nicht im Chat anzeigen)
function Commands.Handle(player, message)
	local command, argument = string.match(message, "^/(%a+)%s*(.*)$")
	if (not command) then return false end
	command = string.lower(command)

	local handler = PUBLIC[command] or (Commands.IsAdmin(player) and DEBUG[command])
	if (not handler) then return false end

	handler(player, argument)
	return true
end

-- Taste B kommt vom Client (siehe Client/Index.lua)
Events.SubscribeRemote("DeathBox:ToggleNoClip", function(player)
	ToggleNoClip(player)
end)

-- ===================================================================
-- Server-Konsole (nur der Server-Betreiber hat Zugriff)
-- ===================================================================

local function FindPlayer(query)
	query = tostring(query or "")
	local id = tonumber(query)
	local found
	for _, player in pairs(Player.GetPairs()) do
		if (id and player:GetID() == id) then return player end
		if (query ~= "" and string.find(string.lower(player:GetName()), string.lower(query), 1, true)) then
			if (found) then return nil, "mehrere Spieler passen, bitte genauer oder die ID angeben" end
			found = player
		end
	end
	if (not found) then return nil, "kein Spieler gefunden" end
	return found
end

-- db_admin <name|id>: Admin-Befehle fuer einen Spieler ein- oder ausschalten
Console.RegisterCommand("db_admin", function(query)
	local player, err = FindPlayer(query)
	if (not player) then
		Console.Warn("[DeathBox] db_admin: %s", err)
		for _, p in pairs(Player.GetPairs()) do Console.Log("  %d  %s", p:GetID(), p:GetName()) end
		return
	end
	local enabled = not Commands.admins[player]
	Commands.admins[player] = enabled or nil
	Events.CallRemote("DeathBox:Admin", player, Reliability.Reliable, enabled)
	Chat.SendMessage(player, enabled and "Admin commands enabled (/status, /event, /card, /bots, /start, /stop, B = noclip)." or "Admin commands disabled.")
	Console.Log("[DeathBox] Admin %s: %s", enabled and "an" or "aus", player:GetName())
end, "DeathBox: Admin-Befehle fuer einen Spieler an/aus", { "name oder id" })

-- db_status: Ueberblick in der Server-Konsole
Console.RegisterCommand("db_status", function()
	Console.Log("[DeathBox] Version %s | Warteschlange %d | Tische %d/%d", DeathBox.VERSION, #Lobby.queue, #Lobby.matches, Config.MAX_MATCHES)
	for _, match in ipairs(Lobby.matches) do
		Console.Log("  Tisch %d: %s, Runde %d, %d/%d leben, %d Menschen, %d Nachruecker", match.id, match.state, match.round,
			match:CountAlive(), #match.seats, match:CountHumans(), #match.joiners)
	end
end, "DeathBox: Tische und Warteschlange anzeigen", {})

Player.Subscribe("Destroy", function(player)
	Commands.admins[player] = nil
end)
