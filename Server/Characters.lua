-- Server/Characters.lua
-- Alles rund um die Spielfiguren: spawnen, wiederbeleben, ausschalten.

DeathBox.Characters = {}

local Characters = DeathBox.Characters

-- Spawnpunkt in der Arena (statt auf der Map)
local function GetSpawnLocation()
	return DeathBox.Arena.GetSpawnLocation()
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

-- Stellt die Figur an ihren Platz am Tisch und friert die Bewegung ein
function Characters.PlaceAtSeat(player, location, rotation)
	if (not player or not player:IsValid()) then return end

	local character = player:GetControlledCharacter()
	if (not character) then return end

	character:SetLocation(location)
	character:SetRotation(rotation)
	character:SetInputEnabled(false)
	player:SetCameraRotation(rotation)
end

-- Belebt alle verbundenen Spieler wieder und gibt ihnen die Bewegung zurueck (z. B. zurueck in der Lobby)
function Characters.ReviveAll()
	for _, player in pairs(Player.GetPairs()) do
		Characters.EnsureAlive(player)
		local character = player:GetControlledCharacter()
		if (character) then
			character:SetInputEnabled(true)
		end
	end
end
