-- Server/Cheats.lua
-- Test-Cheats: Noclip (Taste B), /god, /arena, /sit, /sitpos.
-- Nur aktiv, wenn Config.DEBUG_COMMANDS = true. Waehrend einer Partie fuer Spieler am Tisch gesperrt.
--
-- Ablauf bei Noclip:
--   Client drueckt B  ->  Events.CallRemote("DeathBox:ToggleNoClip")
--   Server empfaengt  ->  prueft Erlaubnis  ->  schaltet um
-- Der Server vertraut dem Client nie blind: jede Anfrage wird hier geprueft.

DeathBox.Cheats = {}

local Cheats = DeathBox.Cheats
local Characters = DeathBox.Characters

-- Darf dieser Spieler gerade cheaten? Gibt (true) oder (false, Grund) zurueck.
local function IsAllowed(player)
	if (not DeathBox.Config.DEBUG_COMMANDS) then
		return false, "Cheats are disabled."
	end

	local Game = DeathBox.Game
	if (Game.state == Game.STATE.PLAYING) then
		local seat = DeathBox.Table.FindSeatByPlayer(player)
		if (seat and seat.alive) then
			return false, "Not while you are seated at the table."
		end
	end

	return true
end

-- Holt die Figur des Spielers und prueft die Erlaubnis. Sagt dem Spieler Bescheid, wenn es nicht geht.
local function GetCheatCharacter(player)
	local allowed, reason = IsAllowed(player)
	if (not allowed) then
		Chat.SendMessage(player, reason)
		return nil
	end

	local character = player:GetControlledCharacter()
	if (not character or character:IsDead()) then
		Chat.SendMessage(player, "You have no living character right now.")
		return nil
	end
	return character
end

function Cheats.ToggleNoClip(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	Characters.StandUp(character)   -- wer sitzt, steht zuerst auf

	local enabled = not character:GetValue("DeathBox_NoClip")
	character:SetFlyingMode(enabled)
	character:SetCollision(enabled and CollisionType.NoCollision or CollisionType.Normal)
	character:SetValue("DeathBox_NoClip", enabled)

	Chat.SendMessage(player, "Noclip: " .. (enabled and "on" or "off"))
end

function Cheats.ToggleGod(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	local enabled = not character:GetValue("DeathBox_God")
	character:SetInvulnerable(enabled)
	character:SetValue("DeathBox_God", enabled)

	Chat.SendMessage(player, "Godmode: " .. (enabled and "on" or "off"))
end

function Cheats.TeleportToArena(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	Characters.StandUp(character)

	local location, rotation = DeathBox.Arena.GetSpawnLocation()
	character:SetLocation(location)
	character:SetRotation(rotation)
	Chat.SendMessage(player, "Back in the parlour.")
end

-- /sit: auf den naechsten Stuhl setzen bzw. wieder aufstehen (zum Testen in der Lobby)
function Cheats.ToggleSit(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	if (Characters.IsSitting(player)) then
		Characters.StandUp(character)
		Chat.SendMessage(player, "You stood up.")
		return
	end

	local chair_index = DeathBox.Arena.GetNearestChairIndex(character:GetLocation())
	Characters.SitOnChair(player, chair_index)
	Chat.SendMessage(player, "Seated on chair " .. chair_index .. ". Adjust with /sitpos <height> <forward>, /sit to stand up.")
end

-- /sitpos <hoehe> <vor>: Sitzposition live aendern, ohne Neustart.
-- Gilt nur bis zum Neustart. Passende Werte danach in Shared/Config.lua eintragen.
function Cheats.SetSitPosition(player, argument)
	if (not DeathBox.Config.DEBUG_COMMANDS) then return end

	local height, forward = string.match(argument or "", "^(%-?%d+)%s+(%-?%d+)$")
	height, forward = tonumber(height), tonumber(forward)
	if (not height or not forward or math.abs(height) > 300 or math.abs(forward) > 200) then
		local cfg = DeathBox.Config.ARENA
		Chat.SendMessage(player, string.format("Usage: /sitpos <height> <forward>  (current: %d %d)", cfg.SIT_HEIGHT, cfg.SIT_FORWARD))
		return
	end

	DeathBox.Config.ARENA.SIT_HEIGHT = height
	DeathBox.Config.ARENA.SIT_FORWARD = forward

	-- Alle Sitzenden an die neue Position setzen
	for _, p in pairs(Player.GetPairs()) do
		local character = p:GetControlledCharacter()
		if (character and character:GetValue("DeathBox_Sitting")) then
			Characters.SitOnChair(p, character:GetValue("DeathBox_Chair"))
		end
	end

	Chat.SendMessage(player, string.format("Sit position: SIT_HEIGHT = %d, SIT_FORWARD = %d (copy into Config.lua when it fits)", height, forward))
end

-- Schaltet alle Cheats einer Figur ab (z. B. bevor sie an den Tisch gestellt oder ausgeschaltet wird)
function Cheats.Reset(character)
	if (not character) then return end

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

-- Taste B kommt vom Client (siehe Client/Index.lua)
Events.SubscribeRemote("DeathBox:ToggleNoClip", function(player)
	Cheats.ToggleNoClip(player)
end)

-- Chat-Befehle (werden in GameState.HandleChatCommand mit ausgewertet)
DeathBox.Game.DebugCommands.god = function(player) Cheats.ToggleGod(player) end
DeathBox.Game.DebugCommands.arena = function(player) Cheats.TeleportToArena(player) end
DeathBox.Game.DebugCommands.noclip = function(player) Cheats.ToggleNoClip(player) end
DeathBox.Game.DebugCommands.sit = function(player) Cheats.ToggleSit(player) end
DeathBox.Game.DebugCommands.sitpos = function(player, argument) Cheats.SetSitPosition(player, argument) end
