-- Server/Index.lua
-- Einstiegspunkt auf dem Server. Der Server entscheidet ueber alles (autoritativ).

Console.Log("[DeathBox] Server-Package geladen (Version %s)", DEATHBOX_VERSION)

-- Waehlt einen Spawnpunkt der Map, sonst die Mitte der Map
local function GetSpawnLocation()
	local spawn_points = Server.GetMapSpawnPoints()
	if (#spawn_points > 0) then
		local point = spawn_points[math.random(#spawn_points)]
		return point.location, point.rotation
	end
	return Vector(0, 0, 100), Rotator()
end

-- Erzeugt einen Character und gibt dem Spieler die Kontrolle darueber
local function SpawnPlayerCharacter(player)
	local location, rotation = GetSpawnLocation()
	local character = Character(location, rotation, "nanos-world::SK_Male")
	player:Possess(character)
end

-- Spieler betritt den Server
Player.Subscribe("Spawn", function(player)
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> hat den Tisch betreten")
	SpawnPlayerCharacter(player)
end)

-- Spieler verlaesst den Server: Character aufraeumen
Player.Subscribe("Destroy", function(player)
	local character = player:GetControlledCharacter()
	if (character) then
		character:Destroy()
	end
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> hat den Tisch verlassen")
end)

-- Bei einem Package-Reload sind Spieler schon verbunden: ihnen auch einen Character geben
Package.Subscribe("Load", function()
	for _, player in pairs(Player.GetPairs()) do
		if (not player:GetControlledCharacter()) then
			SpawnPlayerCharacter(player)
		end
	end
end)
