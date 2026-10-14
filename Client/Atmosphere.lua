-- Client/Atmosphere.lua
-- Nachthimmel, Nebel und Bildlook (PostProcess). Alles lokal beim Client.
--
-- Wichtig gegen den "rosa-roten" Look: Die automatische Belichtung von UE hellt dunkle Szenen so lange auf,
-- bis eine einzelne farbige Lampe alles flutet. Deshalb wird die Belichtung auf einen engen Bereich
-- festgelegt (PostProcess.SetExposure). Die genauen Werte haengen von den Lichteinheiten ab und koennen
-- im Spiel mit Konsolenbefehlen nachgestellt werden:
--   db_exposure <ausgleich> <min_ev> <max_ev>     z. B. db_exposure 1 -1 3
--   db_light <faktor>                             alle flackernden Lampen heller/dunkler (Standard 1)
--   db_look <vignette> <filmkorn> <saettigung>    z. B. db_look 0.8 0.25 0.8

DeathBox.Atmosphere = {
	exposure = { 1, -1.5, 3 },
	look = { vignette = 0.8, grain = 0.25, saturation = 0.82 },
	tension = 0,
	sky_ready = false,
}

local Atmosphere = DeathBox.Atmosphere

local function ApplyExposure()
	local e = Atmosphere.exposure
	PostProcess.SetExposure(e[1], e[2], e[3])
end

-- Einmal beim Laden: Nachthimmel mit Mond (auf der leeren Map gibt es sonst gar keinen Himmel)
function Atmosphere.SetupSky()
	if (Atmosphere.sky_ready) then return end
	Atmosphere.sky_ready = true
	Sky.Spawn(false, true)
	Sky.SetAnimateTimeOfDay(false)
	Sky.SetTimeOfDay(0, 0)
	Sky.SetSkyMode(SkyMode.NoClouds)
	Sky.SetNightBrightness(0.12)
	Sky.SetMoonPhase(15)
	Sky.SetMoonScale(1.6)
	Sky.SetMoonAngle(210, 28)
	Sky.SetMoonLightIntensity(0.6)
	Sky.SetFog(10)
	Sky.Reconstruct()   -- erst nach allen Einstellungen (Modus braucht es zwingend)
	Client.SetSettingGammaOverride(true, 1.0)   -- dunkle Szenen bleiben dunkel
end

-- Grundlook je Ort
function Atmosphere.Apply(kind)
	Atmosphere.SetupSky()
	ApplyExposure()
	PostProcess.SetBloom(1.15, -1)
	PostProcess.SetGlobalContrast(Color(1, 1, 1, 1.12))
	PostProcess.SetGlobalGain(Color(1.04, 0.98, 0.92, 1))
	PostProcess.SetFilm(0.8, 0.6, 0.26, 0.01, 0.3)
	Sky.SetFog(kind == "hub" and 28 or 6)
	Atmosphere.SetTension(0)
end

-- Anspannung 0..1: mehr Vignette, Farbsaum, weniger Farbe. Wird waehrend der Auswahl hochgefahren.
function Atmosphere.SetTension(level)
	Atmosphere.tension = level
	local look = Atmosphere.look
	PostProcess.SetImageEffects(math.min(1.6, look.vignette + 0.6 * level), look.grain + 0.2 * level)
	PostProcess.SetChromaticAberration(0.06 + 0.55 * level, 0.45)
	PostProcess.SetGlobalSaturation(Color(1, 1, 1, math.max(0.2, look.saturation - 0.45 * level)))
end

-- Kurzer Farbblitz ueber das ganze Bild (rot bei Tod, weiss beim POP)
function Atmosphere.Flash(color, alpha, duration)
	local player = Client.GetLocalPlayer()
	if (not player) then return end
	player:StartCameraFade(alpha or 0.5, 0, duration or 0.6, color or Color(0.6, 0, 0), false, false)
end

-- Schwarzblende beim Ortswechsel (verdeckt das Aufbauen der Welt)
function Atmosphere.FadeIn(seconds)
	local player = Client.GetLocalPlayer()
	if (not player) then return end
	player:StartCameraFade(1, 0, seconds or 1.5, Color(0, 0, 0), true, false)
end

-- ===================================================================
-- Konsolenbefehle zum Einstellen im Spiel
-- ===================================================================

Console.RegisterCommand("db_exposure", function(comp, min_ev, max_ev)
	Atmosphere.exposure = { tonumber(comp) or 1, tonumber(min_ev) or -1.5, tonumber(max_ev) or 3 }
	ApplyExposure()
	Console.Log("[DeathBox] Belichtung: %s %s %s", tostring(Atmosphere.exposure[1]), tostring(Atmosphere.exposure[2]), tostring(Atmosphere.exposure[3]))
end, "DeathBox: Belichtung festlegen", { "ausgleich", "min_ev", "max_ev" })

Console.RegisterCommand("db_light", function(factor)
	DeathBox.World.light_scale = tonumber(factor) or 1
	Console.Log("[DeathBox] Lampen-Faktor: %s", tostring(DeathBox.World.light_scale))
end, "DeathBox: Helligkeit der Lampen", { "faktor" })

Console.RegisterCommand("db_look", function(vignette, grain, saturation)
	local look = Atmosphere.look
	look.vignette = tonumber(vignette) or look.vignette
	look.grain = tonumber(grain) or look.grain
	look.saturation = tonumber(saturation) or look.saturation
	Atmosphere.SetTension(Atmosphere.tension)
end, "DeathBox: Bildlook", { "vignette", "filmkorn", "saettigung" })
