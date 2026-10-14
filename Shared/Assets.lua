-- Shared/Assets.lua
-- Zentrale Zuordnung: logischer Name -> Asset-Schluessel.
--
-- Der Code benutzt NIE direkt "nanos-world::SM_..." sondern immer DeathBox.Asset("clown_head").
-- Solange es noch kein eigenes Asset Pack gibt, kommen Platzhalter aus dem Standard-Pack.
--
-- Eigenes Asset Pack einbinden (siehe docs/ASSETS.md):
--   1. Pack in Unreal (ADK) bauen, cooken und nach Server/Assets/deathbox-assets/ kopieren
--   2. In Package.toml unter assets_requirements "deathbox-assets" eintragen
--   3. Unten in CUSTOM die fertigen Schluessel eintragen, z. B. clown_head = "deathbox-assets::SM_Jack_Head"
--      (Static Meshes; ein Jack mit Skelett laeuft ueber CharacterSimple oder Blueprint, siehe docs/ASSETS.md Schritt 3b)
-- Alles, was in CUSTOM steht, ersetzt den Platzhalter. Fehlt ein Eintrag, bleibt der Platzhalter.
-- Jacks Teile baut Client/World/Jack.lua noch aus Grundformen (nur clown_hat kommt von hier): eigene Teile erst nach
-- der Anpassung aus docs/ASSETS.md Schritt 5 sichtbar.

DeathBox = DeathBox or {}

local DEFAULT = {
	-- Welt
	cube = "nanos-world::SM_Cube",
	cylinder = "nanos-world::SM_Cylinder",
	sphere = "nanos-world::SM_Sphere",
	cone = "nanos-world::SM_Cone",
	torus = "nanos-world::SM_Torus",
	material_lit = "nanos-world::M_Default_Masked_Lit",
	material_unlit = "nanos-world::M_Default_Masked_Unlit",
	chair = "nanos-world::SM_WoodenChair",
	grave_1 = "nanos-world::SM_Grave_01",
	grave_2 = "nanos-world::SM_Grave_03",
	grave_3 = "nanos-world::SM_Grave_06",
	grave_4 = "nanos-world::SM_Grave_09",
	pumpkin = "nanos-world::SM_Fruit_Pumpkin_01",
	ghost = "nanos-world::SM_Ghost",
	torch = "nanos-world::SM_Torch",
	oil_lamp = "nanos-world::SM_OilLamp",
	tree = "nanos-world::SM_Tree_Acacia_02",
	rock = "nanos-world::SM_Rock_05",
	balloon_1 = "nanos-world::SM_Balloon_01",
	balloon_2 = "nanos-world::SM_Balloon_03",
	balloon_3 = "nanos-world::SM_Balloon_05",
	kids_box = "nanos-world::SM_KidsBox_03",
	gramophone = "nanos-world::SM_Gramophone",
	barrel = "nanos-world::SM_Barrel_01",
	crate = "nanos-world::SM_Crate_03",
	knife_throw = "nanos-world::SM_Kunai_01",
	knife_stab = "nanos-world::SM_Cleaver_01",

	-- Jack (Platzhalter aus Grundformen, bis ein eigenes Modell da ist)
	clown_box = "nanos-world::SM_Cube",
	clown_spring = "nanos-world::SM_Cylinder",
	clown_body = "nanos-world::SM_Sphere",
	clown_head = "nanos-world::SM_Sphere",
	clown_nose = "nanos-world::SM_Sphere",
	clown_hat = "nanos-world::SM_TopHat",
	clown_ruff = "nanos-world::SM_Torus",
	clown_arm = "nanos-world::SM_Cylinder",

	-- Figuren
	player_mesh = "nanos-world::SK_Male",
	bot_mesh = "nanos-world::SK_Mannequin",
	sit_animation = "nanos-world::A_Mannequin_Sit_Bench",

	-- Partikel
	fire = "nanos-world::P_Fire_02",
	dust = "nanos-world::P_HangingParticulates",
	smoke = "nanos-world::P_Smoke_03",
	magic_circle = "nanos-world::P_FXVariety_MagicCircle",
	confetti = "nanos-world::P_Burst_01",
	fire_big = "nanos-world::P_Fire_05",
	fire_breath = "nanos-world::P_FXVariety_FireBall",

	-- Sounds
	snd_whoosh = "nanos-world::A_Whoosh",
	snd_rattle = "nanos-world::A_Rattle",
	snd_load = "nanos-world::A_Pistol_Load",
	snd_dry = "nanos-world::A_Pistol_Dry",
	snd_shot = "nanos-world::A_Python_Shot",
	snd_safety = "nanos-world::A_Teleport_Committed",
	snd_laugh_1 = "nanos-world::A_Male_03_Laugh",
	snd_laugh_2 = "nanos-world::A_Male_05_Laugh",
	snd_laugh_3 = "nanos-world::A_Female_02_Laugh",
	snd_scream = "nanos-world::A_Female_01_Scream",
	snd_pop = "nanos-world::A_Balloon_Pop",
	snd_hover = "nanos-world::A_Button_Hover_Cue",
	snd_click = "nanos-world::A_Button_Click_Cue",
	snd_whitenoise = "nanos-world::A_WhiteNoise",
	snd_flesh = "nanos-world::A_Flesh_Impact_MS",
	snd_block = "nanos-world::A_MetalHeavy_Impact_MS",
	snd_fire = "nanos-world::A_Gas_Leak_Burst_01",
	snd_qte = "nanos-world::A_VR_Click_02",
}

-- Eigene Assets: hier eintragen, sobald das Pack gecookt auf dem Server liegt
local CUSTOM = {
	-- clown_head = "deathbox-assets::SM_Jack_Head",
}

function DeathBox.Asset(name)
	local key = CUSTOM[name] or DEFAULT[name]
	if (not key) then
		Console.Warn("[DeathBox] Unbekanntes Asset '%s'", tostring(name))
		return "nanos-world::SM_Error"
	end
	return key
end

-- Gibt true zurueck, wenn fuer diesen Namen schon ein eigenes Asset eingetragen ist
function DeathBox.HasCustomAsset(name)
	return CUSTOM[name] ~= nil
end

-- ===================================================================
-- Eigene Dateien im Package (ohne Unreal, werden beim Joinen heruntergeladen)
--   Sounds:    Client/sounds/<name>.ogg    (Ogg Vorbis, selbst synthetisiert)
--   Texturen:  Client/textures/<name>.png  (selbst generiert)
-- Pfad-Format laut nanos-Doku ("SpecialPath"): package://<package-ordner>/<datei>
-- ===================================================================

local package_name = Package.GetName()

function DeathBox.SoundFile(name)
	return "package://" .. package_name .. "/Client/sounds/" .. name .. ".ogg"
end

function DeathBox.TextureFile(name)
	return "package://" .. package_name .. "/Client/textures/" .. name .. ".png"
end
