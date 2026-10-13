-- Client/Index.lua
-- Laeuft bei jedem Spieler: HUD (WebUI) und Testtasten.

Package.Require("HUD.lua")

Console.Log("[DeathBox] Client-Package geladen (Version %s)", DeathBox.VERSION)

DeathBox.HUD.Create()

-- Taste B: Noclip anfragen. Der Client entscheidet NICHTS selbst,
-- er fragt nur beim Server an. Der Server prueft, ob es erlaubt ist (Server/Cheats.lua).
if (DeathBox.Config.DEBUG_COMMANDS) then
	Input.Register("DeathBoxNoClip", "B", "Noclip on/off (test mode)")

	Input.Bind("DeathBoxNoClip", InputEvent.Pressed, function()
		Events.CallRemote("DeathBox:ToggleNoClip", Reliability.Reliable)
	end)
end

-- Beim Entladen (z. B. Package-Reload) Maus und HUD sauber zuruecksetzen
Package.Subscribe("Unload", function()
	DeathBox.HUD.Destroy()
end)
