-- Server/Index.lua
-- Einstiegspunkt auf dem Server: laedt die Module und verbindet sie mit den nanos-world-Events.
-- Die eigentliche Spiellogik steht in GameState.lua.

Package.Require("Arena.lua")
Package.Require("Characters.lua")
Package.Require("Table.lua")
Package.Require("GameState.lua")
Package.Require("Cheats.lua")

local Game = DeathBox.Game
local Characters = DeathBox.Characters

Console.Log("[DeathBox] Server-Package geladen (Version %s)", DeathBox.VERSION)

-- Arena sofort bauen, damit sie steht, bevor der erste Spieler spawnt
DeathBox.Arena.Build()

-- Spieler betritt den Server
Player.Subscribe("Spawn", function(player)
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> hat den Tisch betreten")
	Characters.EnsureAlive(player)
	Game.OnPlayerJoin(player)
end)

-- Spieler verlaesst den Server: zuerst die Spiellogik informieren, dann aufraeumen
Player.Subscribe("Destroy", function(player)
	Game.OnPlayerLeave(player)
	Characters.Remove(player)
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> hat den Tisch verlassen")
end)

-- Chat-Befehle abfangen (/start, /bots, /stop, /status, /god, /arena, /noclip)
Chat.Subscribe("PlayerSubmit", function(message, player)
	if (Game.HandleChatCommand(player, message)) then
		return false   -- Befehl nicht als Chat-Nachricht anzeigen
	end
end)

-- Package wurde (neu) geladen: bereits verbundene Spieler versorgen
Package.Subscribe("Load", function()
	for _, player in pairs(Player.GetPairs()) do
		Characters.EnsureAlive(player)
	end
	Game.CheckAutoStart()
end)

-- Package wird entladen (z. B. Reload): laufenden Timer aufraeumen
Package.Subscribe("Unload", function()
	Game.ClearTimer()
end)
