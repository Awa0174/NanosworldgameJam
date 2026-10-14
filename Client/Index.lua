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

-- Taste N: als Ausgeschiedener oder Nachruecker in die naechste Show (statt zuzuschauen)
Input.Register("DeathBoxNextShow", "N", "Next show (when you are out)")
Input.Bind("DeathBoxNextShow", InputEvent.Pressed, function()
	DeathBox.HUD.RequestNextShow()
end)

-- Taste B: Noclip anfragen (nur Admins: DEBUG_COMMANDS oder per "db_admin" in der Server-Konsole freigeschaltet).
-- Der Client entscheidet NICHTS selbst, er fragt nur beim Server an (Server/Commands.lua).
local noclip_bound = false
local function BindNoClip()
	if (noclip_bound) then return end
	noclip_bound = true
	Input.Register("DeathBoxNoClip", "B", "Noclip on/off (admin)")
	Input.Bind("DeathBoxNoClip", InputEvent.Pressed, function()
		Events.CallRemote("DeathBox:ToggleNoClip", Reliability.Reliable)
	end)
end
if (DeathBox.Config.DEBUG_COMMANDS) then BindNoClip() end
Events.SubscribeRemote("DeathBox:Admin", function(enabled)
	if (enabled) then BindNoClip() end
end)

-- Beim Entladen (z. B. Package-Reload) Maus, HUD, Welt und Ton sauber zuruecksetzen
Package.Subscribe("Unload", function()
	DeathBox.HUD.Destroy()
	DeathBox.World.Leave()
	DeathBox.Audio.StopAll()
end)
