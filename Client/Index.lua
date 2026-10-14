-- Client/Index.lua
-- Laeuft bei jedem Spieler: lokale Welt (Friedhof/Zelt), Jack, Regie, Ton, Bildlook, HUD und Testtasten.

-- Reihenfolge ist wichtig: spaetere Module benutzen die frueheren
Package.Require("World/Builder.lua")
Package.Require("Audio.lua")
Package.Require("World/World.lua")
Package.Require("Atmosphere.lua")
Package.Require("World/Jack.lua")
Package.Require("World/Tent.lua")
Package.Require("World/Hub.lua")
Package.Require("World/Revolver.lua")
Package.Require("Highlight.lua")
Package.Require("Presentation.lua")
Package.Require("Poses.lua")
Package.Require("Aim.lua")
Package.Require("HUD.lua")
Package.Require("Diag.lua")

Console.Log("[DeathBox] Client-Package geladen (Version %s)", DeathBox.VERSION)

DeathBox.HUD.Create()

-- Taste C: Kartenhand auf-/zuklappen (Maus frei zum Ausspielen)
Input.Register("DeathBoxCards", "C", "Open / close your cards")
Input.Bind("DeathBoxCards", InputEvent.Pressed, function()
	DeathBox.HUD.SetCardsOpen(not DeathBox.HUD.cards_open)
end)

-- Taste B: Noclip anfragen. Der Client entscheidet NICHTS selbst,
-- er fragt nur beim Server an. Der Server prueft, ob es erlaubt ist (Server/Commands.lua).
if (DeathBox.Config.DEBUG_COMMANDS) then
	Input.Register("DeathBoxNoClip", "B", "Noclip on/off (test mode)")

	Input.Bind("DeathBoxNoClip", InputEvent.Pressed, function()
		Events.CallRemote("DeathBox:ToggleNoClip", Reliability.Reliable)
	end)
end

-- Beim Entladen (z. B. Package-Reload) Maus, HUD, Welt und Ton sauber zuruecksetzen
Package.Subscribe("Unload", function()
	DeathBox.HUD.Destroy()
	DeathBox.World.Leave()
	DeathBox.Audio.StopAll()
end)
