-- Server/Cheats.lua
-- Test-Cheats: Noclip (Taste B), /god, /arena.
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
		return false, "Cheats sind deaktiviert."
	end

	local Game = DeathBox.Game
	if (Game.state == Game.STATE.PLAYING) then
		local seat = DeathBox.Table.FindSeatByPlayer(player)
		if (seat and seat.alive) then
			return false, "Nicht waehrend du am Tisch sitzt."
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
		Chat.SendMessage(player, "Du hast gerade keine lebende Figur.")
		return nil
	end
	return character
end

function Cheats.ToggleNoClip(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	local enabled = not character:GetValue("DeathBox_NoClip")
	character:SetFlyingMode(enabled)
	character:SetCollision(enabled and CollisionType.NoCollision or CollisionType.Normal)
	character:SetValue("DeathBox_NoClip", enabled)

	Chat.SendMessage(player, "Noclip: " .. (enabled and "an" or "aus"))
end

function Cheats.ToggleGod(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	local enabled = not character:GetValue("DeathBox_God")
	character:SetInvulnerable(enabled)
	character:SetValue("DeathBox_God", enabled)

	Chat.SendMessage(player, "Godmode: " .. (enabled and "an" or "aus"))
end

function Cheats.TeleportToArena(player)
	local character = GetCheatCharacter(player)
	if (not character) then return end

	local location, rotation = DeathBox.Arena.GetSpawnLocation()
	character:SetLocation(location)
	character:SetRotation(rotation)
	Chat.SendMessage(player, "Zurueck in der Arena.")
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

-- Chat-Befehle /god und /arena (werden in GameState.HandleChatCommand mit ausgewertet)
DeathBox.Game.DebugCommands.god = function(player) Cheats.ToggleGod(player) end
DeathBox.Game.DebugCommands.arena = function(player) Cheats.TeleportToArena(player) end
DeathBox.Game.DebugCommands.noclip = function(player) Cheats.ToggleNoClip(player) end
