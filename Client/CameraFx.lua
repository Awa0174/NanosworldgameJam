-- Client/CameraFx.lua
-- Kurzer Kamera-Ruck in Schluesselmomenten (POP, Tod): die Kamera schnellt fuer einen Augenblick naeher an die eigene
-- Figur heran (Spring-Arm kuerzer) und gleitet zurueck. Nur lokal, kein Netzwerk.
--
-- Warum Spring-Arm statt Sichtfeld: Player:SetCameraFOV wirkt laut API nur OHNE gesteuerte Figur, Character:SetFOVMultiplier
-- nur auf dem Server. Player:SetCameraArmLength geht auf dem Client (authority "both").
-- Lesbarkeit geht vor: Wer gerade eine Eingabe machen muss (Abfrage offen, Revolver-Zielmodus), bekommt KEINEN Ruck.
-- Im Spiel pruefen und einstellen:  db_punch <staerke 0..1>   (0 = aus, Standard 1)

DeathBox.CameraFx = {
	scale = 1,      -- Gesamtstaerke (db_punch)
	base = nil,     -- urspruengliche Arm-Laenge, solange ein Ruck laeuft
	timer = nil,
}

local CameraFx = DeathBox.CameraFx

local function Busy()
	local HUD = DeathBox.HUD
	return (HUD and HUD.choice_ask ~= nil) or (DeathBox.Aim ~= nil and DeathBox.Aim.active ~= nil)
end

-- Arm-Laenge sofort zuruecksetzen (Ortswechsel, Entladen, neuer Ruck)
function CameraFx.Reset()
	if (CameraFx.timer and Timer.IsValid(CameraFx.timer)) then Timer.ClearTimeout(CameraFx.timer) end
	CameraFx.timer = nil
	local player = Client.GetLocalPlayer()
	if (player and CameraFx.base) then player:SetCameraArmLength(CameraFx.base) end
	CameraFx.base = nil
end

-- strength 0..1: Anteil, um den die Kamera naeher rueckt (0.15 = leicht, 0.35 = stark). hold: Sekunden bis zurueck.
function CameraFx.Punch(strength, hold)
	if (CameraFx.scale <= 0 or Busy()) then return end
	local player = Client.GetLocalPlayer()
	if (not player) then return end
	local base = CameraFx.base or player:GetCameraArmLength(true)
	if (type(base) ~= "number" or base < 50) then return end   -- Ego-Perspektive: kein Arm, nichts zu tun
	CameraFx.base = base
	if (CameraFx.timer and Timer.IsValid(CameraFx.timer)) then Timer.ClearTimeout(CameraFx.timer) end
	player:SetCameraArmLength(base * (1 - math.min(0.6, strength * CameraFx.scale)))
	CameraFx.timer = Timer.SetTimeout(function()
		CameraFx.timer = nil
		CameraFx.Reset()
	end, math.floor((hold or 0.25) * 1000))
end

Console.RegisterCommand("db_punch", function(value)
	CameraFx.scale = math.max(0, math.min(2, tonumber(value) or 1))
	Console.Log("[DeathBox] Kamera-Ruck: %s", tostring(CameraFx.scale))
end, "DeathBox: Staerke des Kamera-Rucks (0 = aus)", { "staerke" })
