-- Client/Index.lua
-- Laeuft bei jedem Spieler. Im MVP passiert fast alles ueber den Chat.
-- Spaeter: UI (Kartenhand), Kamera am Tisch, Sounds.

Console.Log("[DeathBox] Client-Package geladen (Version %s)", DeathBox.VERSION)

-- Taste B: Noclip anfragen. Der Client entscheidet NICHTS selbst,
-- er fragt nur beim Server an. Der Server prueft, ob es erlaubt ist (Server/Cheats.lua).
if (DeathBox.Config.DEBUG_COMMANDS) then
	Input.Register("DeathBoxNoClip", "B", "Noclip an/aus (nur Testmodus)")

	Input.Bind("DeathBoxNoClip", InputEvent.Pressed, function()
		Events.CallRemote("DeathBox:ToggleNoClip")
	end)
end
