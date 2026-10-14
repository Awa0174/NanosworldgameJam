-- Client/Poses.lua
-- Sitz-Pose fuer ALLE Figuren, auch fuer Spieler, die spaeter dazukommen.
--
-- Warum: PlayAnimation vom Server wird nur einmal an die Clients geschickt, die gerade da sind, und nirgends
-- gespeichert. Wer erst danach in den Raum kommt, saehe Figuren in der Luft zappeln. Deshalb setzt der Server
-- nur einen synchronisierten Wert "DB_SitAnim" an der Figur (Server/Characters.lua), und jeder Client spielt
-- die Animation selbst ab – beim Erscheinen der Figur und bei jeder Aenderung des Werts.

local KEY = "DB_SitAnim"

local function Apply(character)
	if (not character or not character:IsValid()) then return end
	local anim = character:GetValue(KEY)
	if (anim) then
		character:PlayAnimation(anim, AnimationSlotType.FullBody, true, 0.2, 0.2)
		character:SetValue("DB_SitPlayed", anim)
	else
		local played = character:GetValue("DB_SitPlayed")
		if (played) then
			character:StopAnimation(played)
			character:SetValue("DB_SitPlayed", nil)
		end
	end
end

Character.Subscribe("Spawn", function(character)
	-- Werte sind im Spawn-Moment evtl. noch nicht gesetzt: einen Tick spaeter pruefen
	Timer.SetTimeout(function() Apply(character) end, 0)
end)

Character.Subscribe("ValueChange", function(character, key)
	if (key == KEY) then Apply(character) end
end)

-- Package neu geladen: vorhandene Figuren sofort versorgen
for _, character in pairs(Character.GetPairs()) do
	Apply(character)
end

-- ===================================================================
-- Zielpose (Oberkoerper) fuer den Revolver in der Hand
-- ===================================================================
-- Jeder Client spielt sie selbst ab, gesteuert von der Regie (revolver_aiming / revolver_aim, Client/Presentation.lua):
-- nur der Oberkoerper (AnimationSlotType.UpperBody), die Beine bleiben in der Sitz-Animation. Die Figur dreht der Server
-- zum Ziel, die Pose hebt den Arm, der Revolver selbst zielt exakt (Client/World/Revolver.lua, Hand-Modus).
-- Konsole: db_aimanim <animation> [rate] [hold]
--   rate  Abspielgeschwindigkeit (winzig = die Pose bleibt fast stehen; Standard 0.05)
--   hold  "hold" = einmal abspielen und die letzte Pose halten (statt Schleife)
-- Beispiel: "db_aimanim nanos-world::A_Mannequin_Taunt_Point 0.6 hold"

DeathBox.Poses = {
	aim_anim = "nanos-world::A_Mannequin_Sight_Fire_Pistol",
	aim_rate = 0.05,
	aim_hold = false,
	aiming = {},       -- Figur -> laufende Ziel-Animation
}

local Poses = DeathBox.Poses

local function PlayAim(character)
	if (Poses.aim_hold) then
		character:PlayAnimation(Poses.aim_anim, AnimationSlotType.UpperBody, false, 0.25, -1, Poses.aim_rate)
	else
		character:PlayAnimation(Poses.aim_anim, AnimationSlotType.UpperBody, true, 0.25, 0.25, Poses.aim_rate)
	end
	Poses.aiming[character] = Poses.aim_anim
end

-- Arm mit dem Revolver heben (on = true) oder senken
function Poses.SetAiming(character, on)
	if (not character or not character:IsValid()) then return end
	local playing = Poses.aiming[character]
	if (on) then
		if (playing == Poses.aim_anim) then return end
		if (playing) then character:StopAnimation(playing) end
		PlayAim(character)
	elseif (playing) then
		character:StopAnimation(playing)
		Poses.aiming[character] = nil
	end
end

function Poses.IsAiming(character)
	return Poses.aiming[character] ~= nil
end

-- Alle Zielposen beenden (neue Runde, Ortswechsel)
function Poses.StopAllAiming()
	for character, anim in pairs(Poses.aiming) do
		if (character:IsValid()) then character:StopAnimation(anim) end
	end
	Poses.aiming = {}
end

Console.RegisterCommand("db_aimanim", function(anim, rate, mode)
	if (anim and anim ~= "") then
		Poses.aim_anim = string.find(anim, "::", 1, true) and anim or ("nanos-world::" .. anim)
	end
	Poses.aim_rate = math.max(0.001, math.min(5, tonumber(rate) or Poses.aim_rate))
	Poses.aim_hold = (mode == "hold")
	-- laufende Posen sofort mit der neuen Animation neu starten
	for character, playing in pairs(Poses.aiming) do
		if (character:IsValid()) then
			character:StopAnimation(playing)
			PlayAim(character)
		else
			Poses.aiming[character] = nil
		end
	end
	Console.Log("[DeathBox] Zielpose: %s, Rate %.3f, %s", Poses.aim_anim, Poses.aim_rate, Poses.aim_hold and "halten" or "Schleife")
end, "DeathBox: Oberkoerper-Pose beim Zielen mit dem Revolver", { "animation", "rate", "hold" })
