-- Server/Index.lua
-- Einstiegspunkt auf dem Server: laedt die Module und verbindet sie mit den nanos-world-Events.
-- Die eigentliche Spiellogik steht in GameState.lua.

-- Reihenfolge ist wichtig: spaetere Module benutzen die frueheren
Package.Require("Arena.lua")
Package.Require("Characters.lua")
Package.Require("Table.lua")
Package.Require("Net.lua")
Package.Require("Rituals.lua")
Package.Require("Rituals/Chamber.lua")
Package.Require("GameState.lua")
Package.Require("Cheats.lua")

local Game = DeathBox.Game
local Characters = DeathBox.Characters

Console.Log("[DeathBox] Server-Package geladen (Version %s)", DeathBox.VERSION)

-- Arena sofort bauen, damit sie steht, bevor der erste Spieler spawnt
DeathBox.Arena.Build()

-- Spieler betritt den Server
Player.Subscribe("Spawn", function(player)
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> entered the parlour")
	Characters.EnsureAlive(player)
	Game.OnPlayerJoin(player)
end)

-- Spieler verlaesst den Server: zuerst die Spiellogik informieren, dann aufraeumen
Player.Subscribe("Destroy", function(player)
	DeathBox.Net.leaving_player = player   -- nicht mehr in der Lobby-Zaehlung beruecksichtigen
	Game.OnPlayerLeave(player)
	DeathBox.Net.leaving_player = nil
	Characters.Remove(player)
	Chat.BroadcastMessage("<cyan>" .. player:GetName() .. "</> left the parlour")
end)

-- Chat-Befehle abfangen (/start, /bots, /stop, /status, /ritual, Cheats)
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
	DeathBox.Rituals.Cancel()
end)
