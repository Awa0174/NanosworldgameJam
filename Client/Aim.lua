-- Client/Aim.lua
-- Zielmodus fuer den Revolver: Wer den Revolver haelt, zielt RICHTIG – mit der Kamera, die Maus bleibt gefangen, kein
-- Ring-Menue – und drueckt mit der linken Maustaste ab. Der Server entscheidet weiterhin alles.
--
-- Ablauf (Vertrag: docs/PROTOCOL.md):
--   Server -> "DeathBox:Choice" { ask, kind = "target", aim = true, options, seconds }  ->  HUD.lua ruft Aim.Begin
--   jedes Bild  anvisiert ist der erlaubte Platz (in options, lebt, nicht man selbst), dessen Kopf oder Brust dem
--               Kamerastrahl am naechsten liegt – hoechstens Aim.cone Grad daneben (Hysterese gegen Flackern)
--   Aenderung   sofort lokal: Arm/Revolver zeigt hin, ROT markiert (Presentation.ShowAiming), leises Ticken,
--               HUD-Zeile per HUD.ShowAim -> "Aim"(json); an den Server "DeathBox:Aim" (ask, Platz oder 0), hoechstens 5 pro
--               Sekunde (der letzte Stand kommt immer an) -> Server prueft, dreht die Figur und schickt allen
--               Show "revolver_aiming" { shooter, seat }
--   Linksklick  dieselbe gepruefte Wahl wie im Ring: HUD.SubmitChoice -> "DeathBox:Input" (ask, Platz)
--   Ende        Klick, "DeathBox:ChoiceEnd" oder Ortswechsel -> HUD.EndAim -> "AimEnd"(ask, grund)
--
-- HUD-Daten bei "Aim"(json):
--   { ask, seat (0 = niemand), chair, name, label ("AIMING AT NIBBLES – CLICK TO SHOOT"), hint, warn (true = Klick ohne
--     Ziel), seconds (Restzeit), total, crosshair = true }
-- Konsole: db_aimcone <grad>

DeathBox.Aim = {
	active = nil,        -- laufender Zielmodus (siehe Begin)
	ticker = nil,
	cone = 10,           -- Grad um den Kamerastrahl
	hysteresis = 2,      -- Grad: das bisherige Ziel bleibt, bis ein anderes klar naeher am Strahl liegt
	send_interval = 0.2, -- hoechstens 5 Zielmeldungen pro Sekunde
	arm_delay = 0.35,    -- so lange nach dem Start zaehlt kein Klick (versehentliche Klicks)
	chest_drop = 32,     -- Brustpunkt so viele cm unter dem Kopf (Zielen auf den Koerper zaehlt auch)
	last_sent_at = -1000,
	mouse_down = false,
	press_at = -1000,
}

local Aim = DeathBox.Aim
local Builder = DeathBox.Builder
local Tent = DeathBox.Tent
local Audio = DeathBox.Audio

Aim.TEXT = {
	AIMING = "AIMING AT %s – CLICK TO SHOOT",
	NO_TARGET = "AIM AT A PLAYER – CLICK TO SHOOT",
	HINT = "Move the mouse to aim · Left click to shoot",
	NEED_TARGET = "Aim at a player first!",
}

-- ===================================================================
-- Hilfen
-- ===================================================================

local function State()
	return DeathBox.Presentation and DeathBox.Presentation.state
end

local function SeatInfo(seat)
	local state = State()
	if (state and state.seats) then
		for _, s in pairs(state.seats) do
			if (s.seat == seat) then return s end
		end
	end
	return nil
end

-- Eigener Platz laut Tischzustand (nil = Zuschauer)
function Aim.MySeat()
	local player = Client.GetLocalPlayer()
	local state = State()
	if (not player or not state or not state.seats) then return nil end
	local id = player:GetID()
	for _, s in pairs(state.seats) do
		if (s.id == id) then return s.seat end
	end
	return nil
end

-- Blickrichtung einer Drehung (Einheitsvektor)
local function Forward(rot)
	local p, y = math.rad(rot.Pitch or 0), math.rad(rot.Yaw or 0)
	return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p))
end
Aim.Forward = Forward

local function AngleTo(origin, forward, point)
	local d = point - origin
	local len = math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
	if (len < 1) then return math.huge end
	local c = (d.X * forward.X + d.Y * forward.Y + d.Z * forward.Z) / len
	return math.deg(math.acos(math.max(-1, math.min(1, c))))
end

-- Reine Auswahl (testbar): candidates = { { seat, points = { Vector, ... } }, ... }
-- Gibt den anvisierten Platz (0 = keiner) und dessen Winkel zurueck.
function Aim.Pick(origin, forward, candidates, current, cone, hysteresis)
	local best, best_angle, current_angle = 0, math.huge, nil
	for _, c in ipairs(candidates) do
		local angle = math.huge
		for _, point in ipairs(c.points) do
			angle = math.min(angle, AngleTo(origin, forward, point))
		end
		if (angle < best_angle) then best, best_angle = c.seat, angle end
		if (c.seat == current) then current_angle = angle end
	end
	if (current_angle and current_angle <= cone + hysteresis and current_angle <= best_angle + hysteresis) then
		return current, current_angle
	end
	if (best_angle <= cone) then return best, best_angle end
	return 0, best_angle
end

-- Erlaubte Ziele mit Kopf- und Brustpunkt (wie die Regie: Tent.ChairPoint + Kopfhoehe). Die Punkte werden pro Abfrage
-- einmal berechnet, nur "lebt noch?" wird jedes Bild aus dem Tischzustand gelesen.
local function Candidates(a)
	local list = {}
	local tent = DeathBox.World and DeathBox.World.tent
	local state = State()
	if (not tent or not state or not state.seats) then return list end
	local head_z = (DeathBox.Presentation and DeathBox.Presentation.head_height) or 45
	a.cache = a.cache or {}
	for _, s in pairs(state.seats) do
		if (a.options[s.seat] and s.alive and s.seat ~= a.my_seat) then
			local entry = a.cache[s.seat]
			if (not entry or entry.head_z ~= head_z) then
				local head = Tent.ChairPoint(tent, s.chair or s.seat, head_z)
				entry = { seat = s.seat, head_z = head_z, points = { head, head - Vector(0, 0, Aim.chest_drop) } }
				a.cache[s.seat] = entry
			end
			table.insert(list, entry)
		end
	end
	return list
end

-- Alle Aufrufe an die WebUI laufen ueber Client/HUD.lua (ShowAim / EndAim)
local function ShowAimUI(json)
	local HUD = DeathBox.HUD
	if (HUD and HUD.ShowAim) then HUD.ShowAim(json) end
end

local function SendUI(a, warn)
	local info = a.seat > 0 and SeatInfo(a.seat) or nil
	local name = info and tostring(info.name or "") or ""
	ShowAimUI(JSON.stringify({
		ask = a.ask,
		seat = a.seat,
		chair = info and (info.chair or a.seat) or 0,
		name = name,
		label = a.seat > 0 and string.format(Aim.TEXT.AIMING, string.upper(name)) or Aim.TEXT.NO_TARGET,
		hint = warn and Aim.TEXT.NEED_TARGET or Aim.TEXT.HINT,
		warn = warn == true,
		seconds = math.max(0, a.ends_at - Builder.time),
		total = a.total,
		crosshair = true,
	}))
end

-- Lokales Bild (Arm, Revolver, Markierung) sofort – nicht erst, wenn das Echo des Servers da ist
local function ShowLocal(a, seat)
	local P = DeathBox.Presentation
	if (P and P.ShowAiming) then
		local ok, err = pcall(P.ShowAiming, a.my_seat, seat)
		if (not ok) then Console.Warn("[DeathBox] Zielen: %s", tostring(err)) end
	elseif (DeathBox.Highlight) then
		if (seat > 0) then DeathBox.Highlight.Set(seat, "target") else DeathBox.Highlight.Clear("target") end
	end
end

-- Zielmeldung an den Server, gedrosselt (hoechstens alle send_interval Sekunden)
local function Flush(a)
	if (a.sent_seat == a.seat) then return end
	if (Builder.time - Aim.last_sent_at < Aim.send_interval) then return end
	Events.CallRemote("DeathBox:Aim", Reliability.Reliable, a.ask, a.seat)
	Aim.last_sent_at = Builder.time
	a.sent_seat = a.seat
end

-- ===================================================================
-- Ablauf
-- ===================================================================

function Aim.IsActive()
	return Aim.active ~= nil
end

-- Startet den Zielmodus fuer eine Abfrage { ask, options, seconds, event }
function Aim.Begin(data)
	local restart = Aim.active ~= nil
	if (Aim.active) then Aim.End("restart") end
	local options = {}
	for _, value in ipairs(data.options or {}) do
		if (type(value) == "number") then options[value] = true end
	end
	local my_seat = Aim.MySeat()
	if (my_seat) then options[my_seat] = nil end
	local seconds = tonumber(data.seconds) or 10
	local a = {
		ask = data.ask, event = data.event, options = options, my_seat = my_seat,
		total = seconds, started = Builder.time, ends_at = Builder.time + seconds,
		-- der Server beginnt mit "niemand anvisiert"; neu gestellte Abfrage (jemand ist gegangen): dort zielt er evtl.
		-- noch auf den alten Platz -> den aktuellen Stand einmal neu melden (sent_seat = -1)
		seat = 0, sent_seat = restart and -1 or 0,
	}
	Aim.active = a
	Aim.mouse_down = false
	Aim.ticker = Builder.AddTicker(nil, function() return Aim.Update() end)
	ShowLocal(a, 0)
	SendUI(a)
	Aim.Update()
	return true
end

-- Jedes Bild: Kamerastrahl -> anvisierter Platz
function Aim.Update()
	local a = Aim.active
	if (not a) then return false end
	-- Sicherheitsnetz: der Server schliesst die Abfrage selbst (ChoiceEnd); kommt das nicht, endet der Modus trotzdem
	if (Builder.time > a.ends_at + 2) then
		Aim.End("timeout")
		return false
	end
	local player = Client.GetLocalPlayer()
	local origin = player and player:GetCameraLocation()
	local rot = player and player:GetCameraRotation()
	if (origin and rot) then
		local seat = Aim.Pick(origin, Forward(rot), Candidates(a), a.seat, Aim.cone, Aim.hysteresis)
		if (seat ~= a.seat) then
			a.seat = seat
			ShowLocal(a, seat)
			if (seat > 0) then Audio.Play("tick", 0.3, 1.7) end
			SendUI(a)
		end
	end
	Flush(a)
end

-- Abdruecken: dieselbe gepruefte Wahl wie im Ring (HUD.SubmitChoice). Ohne Ziel: kurzer Hinweis.
function Aim.Confirm()
	local a = Aim.active
	if (not a) then return false end
	if (a.seat <= 0 or not a.options[a.seat]) then
		Audio.Play("tick", 0.45, 0.6)
		SendUI(a, true)
		return false
	end
	a.confirmed = true
	local HUD = DeathBox.HUD
	local ok = HUD and HUD.SubmitChoice and HUD.SubmitChoice(a.ask, a.seat)
	if (not ok) then
		a.confirmed = nil
		return false
	end
	if (Aim.active == a) then Aim.End("confirm") end
	return true
end

-- Beendet den Zielmodus. Ohne Schuss wird das Ziel wieder freigegeben (die Regie setzt es mit dem naechsten Cue neu).
function Aim.End(reason)
	local a = Aim.active
	if (not a) then return end
	Aim.active = nil
	if (Aim.ticker) then
		Builder.RemoveTicker(Aim.ticker)
		Aim.ticker = nil
	end
	if (a.confirmed) then
		reason = "confirm"
	elseif (a.seat > 0 and reason ~= "place") then
		ShowLocal(a, 0)
	end
	if (DeathBox.HUD and DeathBox.HUD.EndAim) then DeathBox.HUD.EndAim(a.ask, reason or "end") end
	-- Zeit abgelaufen, aber kein ChoiceEnd vom Server: Abfrage auch im HUD schliessen (sonst bliebe z. B. die Kartenhand gesperrt)
	if (reason == "timeout" and DeathBox.HUD and DeathBox.HUD.CloseChoice) then DeathBox.HUD.CloseChoice(a.ask) end
end

-- Echo des Servers ("revolver_aiming") auf dem eigenen Client:
--   nil    nicht der eigene Zielmodus -> normal verarbeiten
--   "ui"   passt zum lokalen Stand -> nur ans HUD (das Bild steht schon)
--   "drop" veraltet (lokal laengst ein anderes Ziel) -> verwerfen
function Aim.FilterEcho(data)
	local a = Aim.active
	if (not a or not a.my_seat or data.shooter ~= a.my_seat) then return nil end
	if ((tonumber(data.seat) or 0) == a.seat) then return "ui" end
	return "drop"
end

-- ===================================================================
-- Maus
-- ===================================================================

-- Chat offen: Klicks gehoeren dem Chat, nicht dem Abzug
Chat.Subscribe("Open", function() Aim.chat_open = true end)
Chat.Subscribe("Close", function() Aim.chat_open = false end)

-- Linke Maustaste = abdruecken. Gehaltene Taste (Wiederholungen) zaehlt nur einmal.
Input.Subscribe("MouseDown", function(key_name)
	local a = Aim.active
	if (not a or key_name ~= "LeftMouseButton" or Aim.chat_open) then return end
	local now = Builder.time
	local held = Aim.mouse_down and (now - Aim.press_at) < 0.3
	Aim.mouse_down = true
	Aim.press_at = now
	if (held or now - a.started < Aim.arm_delay) then return false end
	Aim.Confirm()
	return false
end)

Input.Subscribe("MouseUp", function(key_name)
	if (key_name == "LeftMouseButton") then Aim.mouse_down = false end
end)

Console.RegisterCommand("db_aimcone", function(deg)
	Aim.cone = math.max(2, math.min(45, tonumber(deg) or 10))
	Console.Log("[DeathBox] Zielkegel: %.1f Grad", Aim.cone)
end, "DeathBox: Zielkegel beim Revolver (Grad um die Bildmitte)", { "grad" })
