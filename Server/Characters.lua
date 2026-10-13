-- Server/Characters.lua
-- Alles rund um die Spielfiguren: spawnen, wiederbeleben, ausschalten.

DeathBox.Characters = {}

local Characters = DeathBox.Characters

-- Spawnpunkt in der Arena. Falls die Arena nicht gebaut werden konnte: Spawnpunkt der Map als Notloesung.
local function GetSpawnLocation()
	if (DeathBox.Arena.built) then
		return DeathBox.Arena.GetSpawnLocation()
	end

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
		DeathBox.Cheats.Reset(character)   -- Godmode wuerde den Schuss sonst abfangen
		Characters.StandUp(character)      -- Schwerkraft wieder an, damit die Figur vom Stuhl faellt
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

-- Setzt die Figur auf einen Stuhl: Schwerkraft und Kollision aus, Sitz-Animation in Schleife, Bewegung gesperrt
function Characters.SitOnChair(player, chair_index)
	if (not player or not player:IsValid()) then return end

	local character = player:GetControlledCharacter()
	if (not character or character:IsDead()) then return end
	if (not DeathBox.Arena.built) then return end   -- ohne Arena keine Stuehle

	local location, body_rotation, look_rotation = DeathBox.Arena.GetChairSitTransform(chair_index)

	DeathBox.Cheats.Reset(character)   -- kein Noclip/Godmode am Tisch

	character:SetCollision(CollisionType.NoCollision)   -- sonst schiebt der Stuhl die Figur weg
	character:SetGravityEnabled(false)                  -- sonst faellt sie durch den Stuhl
	character:SetLocation(location)
	character:SetRotation(body_rotation)
	character:SetInputEnabled(false)
	character:PlayAnimation(DeathBox.Config.ARENA.SIT_ANIMATION, AnimationSlotType.FullBody, true)
	character:SetValue("DeathBox_Sitting", true)
	character:SetValue("DeathBox_Chair", chair_index)
	player:SetCameraRotation(look_rotation)
end

-- Laesst eine sitzende Figur wieder aufstehen
function Characters.StandUp(character)
	if (not character or not character:GetValue("DeathBox_Sitting")) then return end

	character:StopAnimation(DeathBox.Config.ARENA.SIT_ANIMATION)
	character:SetCollision(CollisionType.Normal)
	character:SetGravityEnabled(true)
	character:SetInputEnabled(true)
	character:SetValue("DeathBox_Sitting", false)
end

function Characters.IsSitting(player)
	local character = player and player:GetControlledCharacter()
	return character ~= nil and character:GetValue("DeathBox_Sitting") == true
end

-- Belebt alle verbundenen Spieler wieder und gibt ihnen die Bewegung zurueck (z. B. zurueck in der Lobby)
function Characters.ReviveAll()
	for _, player in pairs(Player.GetPairs()) do
		Characters.StandUp(player:GetControlledCharacter())
		Characters.EnsureAlive(player)
		local character = player:GetControlledCharacter()
		if (character) then
			character:SetInputEnabled(true)
		end
	end
end
