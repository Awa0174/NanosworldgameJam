-- Server/Index.lua
-- Einstiegspunkt auf dem Server: laedt die Module und verbindet sie mit den nanos-world-Events.

-- Reihenfolge ist wichtig: spaetere Module benutzen die frueheren
Package.Require("Instances.lua")
Package.Require("Characters.lua")
Package.Require("Net.lua")
Package.Require("Cards.lua")
Package.Require("Events.lua")
-- Toedliche Events
Package.Require("Events/Revolver.lua")
Package.Require("Events/KnifeToss.lua")
Package.Require("Events/FireBreath.lua")
Package.Require("Events/Stab.lua")
Package.Require("Events/AngryClown.lua")
Package.Require("Events/Gallery.lua")
Package.Require("Events/Vote.lua")
Package.Require("Events/Pumpkin.lua")
Package.Require("Events/Bomb.lua")
Package.Require("Events/Duel.lua")
-- Atempausen (niemand stirbt)
Package.Require("Events/Deal.lua")
Package.Require("Events/SplitSteal.lua")
Package.Require("Events/ChooseCard.lua")
Package.Require("Match.lua")
Package.Require("Lobby.lua")
Package.Require("Commands.lua")
Package.Require("Rescue.lua")
Package.Require("Diag.lua")      -- Selbstdiagnose der Clients (nur Testmodus) -> deathbox_diag.txt

local Lobby = DeathBox.Lobby

Console.Log("[DeathBox] Server-Package geladen (Version %s)", DeathBox.VERSION)

-- Ersten Hub sofort bauen, damit er steht, bevor der erste Spieler spawnt
Lobby.Init()

Player.Subscribe("Spawn", function(player)
	Lobby.OnPlayerJoin(player)
end)

-- Client ist fertig geladen: jetzt kommt auch eine Chat-Zeile sicher an
Player.Subscribe("Ready", function(player)
	Lobby.OnPlayerReady(player)
end)

-- Spieler verlaesst den Server: zuerst die Spiellogik informieren, dann aufraeumen
Player.Subscribe("Destroy", function(player)
	Lobby.OnPlayerLeave(player)
	DeathBox.Characters.Remove(player)
end)

-- Chat: Befehle abfangen, alles andere nur an die eigene Instanz (Lobby.Chat). Die Engine-Nachricht wird
-- immer unterdrueckt, weil sie an alle Spieler des Servers ginge. Flutschutz: eine Zeile pro CHAT_INTERVAL.
local last_chat = {}

Chat.Subscribe("PlayerSubmit", function(message, player)
	if (DeathBox.Commands.Handle(player, message)) then
		return false   -- Befehl nicht als Chat-Nachricht anzeigen
	end
	local now, id = Server.GetTime(), player:GetID()
	if (not last_chat[id] or now - last_chat[id] >= DeathBox.Config.CHAT_INTERVAL * 1000) then
		last_chat[id] = now
		Lobby.Chat(player, message)
	end
	return false
end)

Player.Subscribe("Destroy", function(player)
	last_chat[player:GetID()] = nil
end)

-- Package wurde (neu) geladen: bereits verbundene Spieler in den Hub holen
Package.Subscribe("Load", function()
	for _, player in pairs(Player.GetPairs()) do
		if (not Lobby.where[player]) then
			Lobby.OnPlayerJoin(player)
		end
	end
end)
