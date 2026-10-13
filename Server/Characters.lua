-- Server/Characters.lua
-- Alles rund um die Spielfiguren: spawnen, wiederbeleben, ausschalten.

DeathBox.Characters = {}

local Characters = DeathBox.Characters

-- Waehlt einen Spawnpunkt der Map, sonst die Mitte der Map
local function GetSpawnLocation()
	local spawn_points = Server.GetMapSpawnPoints()
	if (#spawn_points > 0) then
		local point = spawn_points[math.random(#spawn_points)]
		return point.location, point.rotation
	end
	return Vector(0, 0, 100), Rotator()
end

-- Gibt dem Spieler eine lebende Figur: neu erzeugen, wiederbeleben oder vorhandene lassen
function Characters.EnsureAlive(player)
	if (not player or not player:IsValid()) then return end

	local character = player:GetControlledCharacter()
	local location, rotation = GetSpawnLocation()

	if (not character) then
		character = Character(location, rotation, "nanos-world::SK_Male")
		player:Possess(character)
	elseif (character:IsDead()) then
		character:Respawn(location, rotation)
	end
end

-- Schaltet die Figur eines Spielers aus (Pistole hat gezuendet)
function Characters.Kill(player)
	if (not player or not player:IsValid()) then return end

	local character = player:GetControlledCharacter()
	if (character and not character:IsDead()) then
		-- Bewusst mehr Schaden als noetig, damit eventuelle Schadens-Multiplikatoren keine Rolle spielen
		character:ApplyDamage(character:GetMaxHealth() * 10)
	end
end

-- Entfernt die Figur, wenn der Spieler den Server verlaesst
function Characters.Remove(player)
	local character = player:GetControlledCharacter()
	if (character) then
		character:Destroy()
	end
end

-- Belebt alle verbundenen Spieler wieder (z. B. zurueck in der Lobby)
function Characters.ReviveAll()
	for _, player in pairs(Player.GetPairs()) do
		Characters.EnsureAlive(player)
	end
end
