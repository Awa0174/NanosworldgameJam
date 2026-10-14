-- Client/World/Revolver.lua
-- Der Revolver der Show – eigenes Modell aus Grundformen (das Standard-Paket hat nur ein Skelett-Mesh, das der Client
-- nicht spawnen kann). Jacks Revolver ist 2,4-mal so gross wie echt (lesbar aus 3-6 m), der Revolver in der Hand eines
-- Spielers etwas kleiner (Revolver.HAND.scale), damit er wie eine echte Waffe in der Hand liegt.
--
-- Aufbau (Lauf zeigt nach +X): Lauf mit Schiene und Korn, Rahmen, Trommel mit sechs Kammern (geladene Kammern zeigen
-- Messing), Hahn, Abzug mit Buegel, Holzgriff. Die Trommel dreht sich bei jedem Abdruecken um 60 Grad weiter.
--
--   local gun = Revolver.Build(list, location [, scale])
--   Revolver.MoveTo(gun, point, look_at, seconds, arc)   schwebt zu point und zielt auf look_at
--   Revolver.Follow(gun, fn)                             folgt jedes Bild fn() -> point, look_at (z. B. Jacks Hand)
--   Revolver.Hold(gun, character, aim_fn)                in die rechte Hand einer Figur (Knochen "hand_r"); der Lauf zeigt
--                                                        jedes Bild auf aim_fn() -> Weltpunkt (nil = bleibt, wie er ist)
--   Revolver.Release(gun)                                aus der Hand loesen (danach wieder MoveTo/Follow/Drop)
--   Revolver.Cock(gun) / Click(gun) / Fire(gun)          Hahn spannen / Klick (Trommel weiter) / Schuss (Feuer, Rueckstoss)
--   Revolver.SetLoaded(gun, n)                           n Kammern mit Patronen
--   Revolver.SpinDrum(gun, seconds)                      Trommel wirbeln (Nachladen)
--   Revolver.SetFear(gun, k)                             Zittern (0 = ruhig, 1 = zitternde Hand)
--   Revolver.Drop(gun, floor_point)                      faellt zu Boden
-- Alles lokal beim Client, ein Ticker pro Revolver (in der Bauliste der Szene, wird mit ihr abgerissen).
--
-- Hand-Modus (Technik): ein unsichtbarer Drehpunkt sitzt per AttachTo(SnapToTarget, "hand_r") an der Hand und folgt so
-- jeder Animation ohne Verzoegerung. Seine Drehung ist absolut (Welt) und wird jedes Bild aufs Ziel gestellt – der Lauf
-- zeigt also immer genau aufs Ziel, egal wie der Handknochen ausgerichtet ist. Der Griff liegt im Drehpunkt (plus
-- HAND.palm cm Richtung Ziel = Handflaeche), der Rueckstoss kippt die Waffe um den Griff.
-- Konsole: db_gunhand <x> <y> <z> [palm] [scale] [bone]  (x/y/z = Versatz im Handknochen, gilt ab dem naechsten Halten)

DeathBox.Revolver = {}

local Revolver = DeathBox.Revolver
local Builder = DeathBox.Builder

local S = 2.4                           -- Vergroesserung gegenueber einem echten Revolver (lesbar aus 3-6 m)
local STEEL = Color(0.52, 0.52, 0.56)
local DARK = Color(0.035, 0.035, 0.04)
local BRASS = Color(0.95, 0.66, 0.24)
local WOOD = Color(0.42, 0.2, 0.1)
local FLASH = Color(1, 0.62, 0.25)

local DRUM_X, DRUM_Z = 0.8, 2.1         -- Trommelmitte (cm, unskaliert, relativ zur Wurzel)

-- Griff relativ zur Wurzel (skaliert): so weit hinter und unter der Wurzel liegt die Hand (fuer Jacks Revolver, S = 2,4)
Revolver.GRIP_BACK, Revolver.GRIP_DOWN = 6 * S, 4.2 * S
local CHAMBER_RADIUS = 1.45
local MUZZLE = { x = 20.5, z = 3.2 }

-- Revolver in der Hand eines Spielers: Knochen, Versatz im Knochen, Handflaeche (cm Richtung Ziel), Groesse
Revolver.HAND = { bone = "hand_r", offset = Vector(0, 0, 0), palm = 7, scale = 1.5 }

local atan2 = math.atan2 or math.atan

local function Clamp(x, a, b) return math.max(a, math.min(b, x)) end

local function AngleDelta(a, b)
	local d = (b - a) % 360
	if (d > 180) then d = d - 360 end
	return d
end

-- Vorwaerts-/Hochachse einer Drehung (Pitch/Yaw, ohne Roll), siehe FRotationMatrix
local function Axes(pitch, yaw)
	local p, y = math.rad(pitch), math.rad(yaw)
	local cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)
	return Vector(cp * cy, cp * sy, sp), Vector(-sp * cy, -sp * sy, cp)
end

local function Aim(from, to)
	local d = to - from
	local flat = math.sqrt(d.X * d.X + d.Y * d.Y)
	return math.deg(atan2(d.Z, math.max(flat, 0.001))), math.deg(atan2(d.Y, d.X))
end

-- ===================================================================
-- Aufbau
-- ===================================================================

function Revolver.Build(list, at, scale)
	local s = scale or S
	local gun = {
		list = list,
		s = s, grip_back = 6 * s, grip_down = 4.2 * s,
		pos = at, pitch = 0, yaw = 0,
		move = nil, follow = nil, held = nil,
		recoil = 0, fear = 0,
		hammer = 0, hammer_target = 0,
		drum = 0, drum_target = 0, drum_spin_until = 0,
		flash = 0, dropped = nil,
		parts = {},
	}
	-- Wurzel bei Drehung 0 bauen, Teile anhaengen, erst dann bewegen (relative Lagen stimmen so)
	gun.root = Builder.Mesh(list, at, Rotator(), "nanos-world::SM_None")
	table.insert(gun.parts, gun.root)
	local function V(x, y, z) return at + Vector(x * s, y * s, z * s) end
	local function Part(mesh, parent)
		Builder.Attach(mesh, parent or gun.root)
		table.insert(gun.parts, mesh)
		return mesh
	end
	local steel = { texture = "metal_rust", tiling = { 1, 1 }, color = STEEL, roughness = 0.28, shadow = false }
	local along_x = Rotator(90, 0, 0)       -- Zylinderachse (Z) auf X legen

	-- Lauf, Schiene, Korn, Muendung
	Part(Builder.Shape(list, "cylinder", V(12.5, 0, 3.2), Vector(2.4 * s, 2.4 * s, 16 * s),
		{ rotation = along_x, texture = "metal_rust", color = STEEL, roughness = 0.25, shadow = false }))
	Part(Builder.Box(list, V(12.5, 0, 4.7), Vector(16 * s, 1 * s, 0.9 * s), steel))
	Part(Builder.Box(list, V(19.8, 0, 5.4), Vector(1 * s, 0.5 * s, 1.3 * s), steel))
	Part(Builder.Shape(list, "cylinder", V(20.6, 0, 3.2), Vector(1.2 * s, 1.2 * s, 0.3 * s),
		{ rotation = along_x, color = DARK, roughness = 1, shadow = false }))
	-- Rahmen um die Trommel
	Part(Builder.Box(list, V(1, 0, 4.9), Vector(8.5 * s, 2.2 * s, 1 * s), steel))
	Part(Builder.Box(list, V(1, 0, -0.7), Vector(8.5 * s, 2.2 * s, 1.4 * s), steel))
	Part(Builder.Box(list, V(-3.6, 0, 2), Vector(2.6 * s, 2.4 * s, 6.8 * s), steel))
	Part(Builder.Box(list, V(4.6, 0, 2.1), Vector(1.2 * s, 2.2 * s, 5.4 * s), steel))

	-- Trommel: eigener Drehpunkt (rollt um X), sechs Kammern
	gun.drum_root = Part(Builder.Mesh(list, V(DRUM_X, 0, DRUM_Z), Rotator(), "nanos-world::SM_None"))
	Part(Builder.Shape(list, "cylinder", V(DRUM_X, 0, DRUM_Z), Vector(4.6 * s, 4.6 * s, 4.4 * s),
		{ rotation = along_x, texture = "metal_rust", color = Color(0.42, 0.42, 0.46), roughness = 0.3, shadow = false }), gun.drum_root)
	gun.chambers = {}
	for i = 1, 6 do
		local a = math.rad(30 + (i - 1) * 60)   -- Kammer 2 sitzt oben vor dem Lauf
		local y, z = math.cos(a) * CHAMBER_RADIUS, math.sin(a) * CHAMBER_RADIUS
		local chamber = Part(Builder.Shape(list, "cylinder", V(DRUM_X, y, DRUM_Z + z), Vector(1 * s, 1 * s, 5 * s),
			{ rotation = along_x, color = DARK, roughness = 0.6, shadow = false }), gun.drum_root)
		table.insert(gun.chambers, chamber)
	end

	-- Hahn (kippt beim Spannen nach hinten)
	gun.hammer_root = Part(Builder.Mesh(list, V(-4, 0, 4), Rotator(), "nanos-world::SM_None"))
	Part(Builder.Box(list, V(-4.6, 0, 5.4), Vector(1.3 * s, 0.9 * s, 2.6 * s), steel), gun.hammer_root)
	Part(Builder.Box(list, V(-5.6, 0, 6.5), Vector(1.6 * s, 1.1 * s, 0.6 * s), steel), gun.hammer_root)

	-- Abzug und Buegel
	Part(Builder.Box(list, V(0.4, 0, -2.4), Vector(0.6 * s, 0.6 * s, 2.4 * s), steel))
	Part(Builder.Box(list, V(0.6, 0, -4.1), Vector(5 * s, 0.7 * s, 0.5 * s), steel))
	Part(Builder.Box(list, V(3, 0, -2.6), Vector(0.5 * s, 0.7 * s, 3 * s), steel))

	-- Holzgriff, leicht nach hinten geneigt
	Part(Builder.Box(list, V(-6, 0, -4.2), Vector(3.4 * s, 2.8 * s, 9.5 * s),
		{ rotation = Rotator(-18, 0, 0), texture = "wood_crate", tiling = { 0.5, 1 }, color = WOOD, roughness = 0.7, shadow = false }))

	-- Muendungsblitz (unsichtbar, bis geschossen wird)
	gun.flash_mesh = Part(Builder.Shape(list, "sphere", V(MUZZLE.x + 2.5, 0, MUZZLE.z), Vector(9 * s, 6 * s, 6 * s),
		{ color = FLASH, emissive = FLASH * 0, shadow = false }))
	gun.flash_mesh:SetVisibility(false)

	-- Kleines warmes Licht am Revolver: macht ihn im dunklen Zelt sichtbar und leuchtet das Gesicht des Halters von unten an
	gun.glow = Part(Builder.Light(list, V(2, 0, 14), Color(1, 0.7, 0.4), 1.6, 160))

	Builder.AddTicker(list, function(dt, time) return Revolver.Update(gun, dt, time) end)
	return gun
end

-- ===================================================================
-- Hand-Modus
-- ===================================================================

-- Weltpunkt eines Knochens einer Figur (nil, wenn es ihn nicht gibt)
function Revolver.BonePoint(character, bone)
	if (not character or not character:IsValid()) then return nil end
	local ok, t = pcall(character.GetSocketTransform, character, bone or Revolver.HAND.bone)
	if (ok and type(t) == "table" and t.Location) then return t.Location end
	return nil
end

-- Wurzel-Position, bei der der Griff in grip liegt und der Lauf auf look_at zeigt (Ziel fuer den Flug in die Hand)
function Revolver.RootFor(gun, grip, look_at)
	local forward, up = Axes(Aim(grip, look_at))
	return grip + forward * (gun.grip_back + Revolver.HAND.palm) + up * gun.grip_down
end

function Revolver.IsHeld(gun)
	return gun.held ~= nil
end

-- In die Hand einer Figur. aim_fn() -> Weltpunkt, auf den der Lauf zeigt (nil = Richtung bleibt)
function Revolver.Hold(gun, character, aim_fn, bone)
	if (gun.dead or not character or not character:IsValid() or not gun.root:IsValid()) then return false end
	Revolver.Release(gun)
	gun.move, gun.follow, gun.dropped = nil, nil, nil
	if (not gun.pivot or not gun.pivot:IsValid()) then
		gun.pivot = Builder.Mesh(gun.list, gun.root:GetLocation(), Rotator(), "nanos-world::SM_None")
		table.insert(gun.parts, gun.pivot)
	end
	local pivot = gun.pivot
	-- Ort folgt der Hand (Animation), Drehung bleibt in Weltkoordinaten (use_absolute_rotation)
	pivot:AttachTo(character, AttachmentRule.SnapToTarget, bone or Revolver.HAND.bone, -1, true)
	pivot:SetRelativeLocation(Revolver.HAND.offset)
	pivot:SetRotation(Rotator(gun.pitch, gun.yaw, 0))
	-- Wurzel vor/ueber den Griff: der Griff liegt in der Handflaeche (palm cm Richtung Ziel vor dem Handgelenk)
	gun.root:AttachTo(pivot, AttachmentRule.SnapToTarget, "", -1, false)
	gun.root:SetRelativeLocation(Vector(gun.grip_back + Revolver.HAND.palm, 0, gun.grip_down))
	gun.root:SetRelativeRotation(Rotator(0, 0, 0))
	gun.held = { character = character, aim = aim_fn }
	if (gun.glow and gun.glow:IsValid()) then gun.glow:SetIntensity(1.6) end
	return true
end

-- Aus der Hand loesen: der Revolver bleibt, wo er gerade ist (schwebend), bis MoveTo/Follow/Drop ihn bewegt
function Revolver.Release(gun)
	local held = gun.held
	if (not held) then return end
	gun.held = nil
	if (not gun.root:IsValid()) then return end
	local loc, rot = gun.root:GetLocation(), gun.root:GetRotation()
	gun.root:Detach()
	if (gun.pivot and gun.pivot:IsValid()) then gun.pivot:Detach() end
	gun.pos = loc
	gun.pitch, gun.yaw = rot.Pitch, rot.Yaw
	gun.root:SetLocation(loc)
	gun.root:SetRotation(Rotator(rot.Pitch, rot.Yaw, 0))
end

-- Neues Ziel fuer den Lauf, waehrend der Revolver in der Hand liegt
function Revolver.SetAim(gun, aim_fn)
	if (gun.held) then gun.held.aim = aim_fn end
end

-- ===================================================================
-- Steuerung
-- ===================================================================

function Revolver.MoveTo(gun, point, look_at, seconds, arc)
	Revolver.Release(gun)
	local pitch, yaw = Aim(point, look_at)
	gun.follow = nil
	gun.move = {
		t0 = Builder.time, dur = math.max(0.01, seconds or 0.5), arc = arc or 0,
		from = gun.pos, to = point,
		pitch0 = gun.pitch, yaw0 = gun.yaw, pitch1 = pitch, dyaw = AngleDelta(gun.yaw, yaw),
	}
end

-- fn() liefert jedes Bild Ort und Zielpunkt (z. B. Jacks Hand und das Opfer)
function Revolver.Follow(gun, fn)
	Revolver.Release(gun)
	gun.move = nil
	gun.follow = fn
end

function Revolver.Cock(gun)
	gun.hammer_target = 1
end

local function AdvanceDrum(gun)
	gun.drum_target = gun.drum_target + 60
end

function Revolver.Click(gun)
	gun.hammer_target = 0
	gun.hammer = 0.15
	AdvanceDrum(gun)
	gun.recoil = math.max(gun.recoil, 0.12)
end

function Revolver.Fire(gun)
	gun.hammer_target = 0
	gun.hammer = 0
	AdvanceDrum(gun)
	gun.recoil = 1
	gun.flash = 1
	if (gun.flash_mesh:IsValid()) then gun.flash_mesh:SetVisibility(true) end
	local forward, up = Axes(gun.pitch, gun.yaw)
	local muzzle
	if (gun.held and gun.root:IsValid()) then
		muzzle = gun.root:GetLocation() + forward * (MUZZLE.x * gun.s) + up * (MUZZLE.z * gun.s)
	else
		muzzle = gun.pos + forward * (MUZZLE.x * gun.s)
	end
	Builder.Particle(gun.list, muzzle, "nanos-world::P_Weapon_BarrelSmoke", Vector(2, 2, 2) * (gun.s / S), Rotator(gun.pitch, gun.yaw, 0))
	gun.light = Builder.Light(gun.list, muzzle + forward * 20, FLASH, 40, 900)
	-- die gefeuerte Kammer (oben vor dem Lauf) ist leer. Rollen um R zeigt Kammerwinkel a bei a - R, oben = 90 Grad.
	local fired = gun.chambers[((1 + math.floor(gun.drum_target / 60 + 0.5)) % 6) + 1]
	if (fired and fired:IsValid()) then
		fired:SetMaterialColorParameter("Tint", DARK)
		fired:SetMaterialColorParameter("Emissive", Color(0, 0, 0))
	end
end

-- n Kammern geladen (Messing), Rest leer
function Revolver.SetLoaded(gun, n)
	for i, chamber in ipairs(gun.chambers) do
		if (chamber:IsValid()) then
			local loaded = i <= (n or 0)
			chamber:SetMaterialColorParameter("Tint", loaded and BRASS or DARK)
			chamber:SetMaterialColorParameter("Emissive", loaded and BRASS * 0.6 or Color(0, 0, 0))
		end
	end
end

function Revolver.SpinDrum(gun, seconds)
	gun.drum_spin_until = Builder.time + (seconds or 0.6)
end

function Revolver.SetFear(gun, k)
	gun.fear = Clamp(k or 0, 0, 1)
end

-- Faellt zu Boden und bleibt liegen
function Revolver.Drop(gun, floor_point)
	Revolver.Release(gun)
	gun.follow = nil
	gun.move = nil
	gun.dropped = { t0 = Builder.time, from = gun.pos, to = floor_point + Vector(0, 0, 6), pitch0 = gun.pitch, yaw0 = gun.yaw }
	if (gun.glow and gun.glow:IsValid()) then gun.glow:SetIntensity(0.3) end
end

function Revolver.Destroy(gun)
	gun.dead = true
	gun.held = nil
	for _, e in ipairs(gun.parts) do
		if (e:IsValid()) then e:Destroy() end
	end
	if (gun.light and gun.light:IsValid()) then gun.light:Destroy() end
	gun.parts, gun.light = {}, nil
end

-- ===================================================================
-- Pro Bild
-- ===================================================================

function Revolver.Update(gun, dt, time)
	if (gun.dead or not gun.root:IsValid()) then return false end
	dt = math.min(dt, 0.05)

	-- In der Hand: Figur weg (Spieler hat die Show verlassen) -> Revolver bleibt schwebend, wo er war
	local held = gun.held
	if (held and (not held.character:IsValid() or not gun.pivot:IsValid())) then
		Revolver.Release(gun)
		held = nil
	end

	-- Bewegung: in der Hand, geplanter Flug, Folgen oder Fallen
	local m = gun.move
	if (held) then
		local grip = gun.pivot:GetLocation()
		gun.pos = grip
		local ok, look = pcall(held.aim or function() return nil end)
		if (ok and look) then
			local pitch, yaw = Aim(grip, look)
			local k = math.min(1, dt * 10)          -- Hand schwenkt weich zum neuen Ziel
			gun.pitch = gun.pitch + (pitch - gun.pitch) * k
			gun.yaw = gun.yaw + AngleDelta(gun.yaw, yaw) * k
		end
	elseif (m) then
		local p = Clamp((Builder.time - m.t0) / m.dur, 0, 1)
		local e = p * p * (3 - 2 * p)
		gun.pos = m.from + (m.to - m.from) * e + Vector(0, 0, m.arc * 4 * p * (1 - p))
		gun.pitch = m.pitch0 + (m.pitch1 - m.pitch0) * e
		gun.yaw = m.yaw0 + m.dyaw * e
		if (p >= 1) then gun.move = nil end
	elseif (gun.follow) then
		local ok, point, look_at = pcall(gun.follow)
		if (ok and point) then
			gun.pos = point
			if (look_at) then gun.pitch, gun.yaw = Aim(point, look_at) end
		end
	elseif (gun.dropped) then
		local d = gun.dropped
		local p = Clamp((Builder.time - d.t0) / 0.45, 0, 1)
		gun.pos = d.from + (d.to - d.from) * (p * p)
		gun.pitch = d.pitch0 * (1 - p)
		gun.yaw = d.yaw0 + 140 * p
	end

	-- Hahn, Trommel, Rueckstoss, Muendungsblitz
	gun.hammer = gun.hammer + (gun.hammer_target - gun.hammer) * math.min(1, dt * (gun.hammer_target > gun.hammer and 9 or 30))
	if (Builder.time < gun.drum_spin_until) then
		gun.drum = gun.drum + 1400 * dt
		gun.drum_target = math.ceil(gun.drum / 60) * 60
	else
		local d = gun.drum_target - gun.drum
		gun.drum = gun.drum + Clamp(d, -720 * dt, 720 * dt)
	end
	gun.recoil = math.max(0, gun.recoil - dt * 3.2)
	if (gun.flash > 0) then
		gun.flash = math.max(0, gun.flash - dt * 9)
		if (gun.flash_mesh:IsValid()) then
			gun.flash_mesh:SetMaterialColorParameter("Emissive", FLASH * (60 * gun.flash))
			gun.flash_mesh:SetScale(Vector(0.09 * gun.s, 0.06 * gun.s, 0.06 * gun.s) * (0.6 + gun.flash))
			if (gun.flash <= 0) then gun.flash_mesh:SetVisibility(false) end
		end
		if (gun.light and gun.light:IsValid()) then
			gun.light:SetIntensity(40 * gun.flash)
			if (gun.flash <= 0) then gun.light:Destroy() gun.light = nil end
		end
	end

	-- Zittern (Angst des Halters) und leichtes Schweben
	local k = gun.fear
	local shake_p = (math.sin(time * 37) * 1.6 + math.sin(time * 23) * 0.9) * k
	local shake_y = (math.cos(time * 41) * 1.4 + math.sin(time * 29) * 0.8) * k

	local pitch = gun.pitch + gun.recoil * 28 + shake_p
	local yaw = gun.yaw + shake_y
	if (held) then
		-- Drehpunkt = Griff: Ziel, Rueckstoss und Zittern drehen die Waffe um die Hand
		gun.pivot:SetRotation(Rotator(pitch, yaw, 0))
	else
		local bob = gun.dropped and 0 or math.sin(time * 2.1) * 1.2
		local forward, up = Axes(pitch, yaw)
		gun.root:SetLocation(gun.pos - forward * (gun.recoil * 9) + up * bob)
		gun.root:SetRotation(Rotator(pitch, yaw, gun.dropped and 90 * Clamp((Builder.time - gun.dropped.t0) / 0.45, 0, 1) or 0))
	end
	gun.drum_root:SetRelativeRotation(Rotator(0, 0, gun.drum))
	gun.hammer_root:SetRelativeRotation(Rotator(38 * gun.hammer, 0, 0))   -- positives Pitch kippt den Hahn nach hinten
end

-- ===================================================================
-- Konsole
-- ===================================================================

Console.RegisterCommand("db_gunhand", function(x, y, z, palm, scale, bone)
	local H = Revolver.HAND
	H.offset = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
	H.palm = tonumber(palm) or H.palm
	H.scale = Clamp(tonumber(scale) or H.scale, 0.5, 4)
	if (bone and bone ~= "") then H.bone = bone end
	Console.Log("[DeathBox] Revolver in der Hand: Knochen %s, Versatz %.1f %.1f %.1f, Handflaeche %.1f cm, Groesse %.2f (ab dem naechsten Halten)",
		H.bone, H.offset.X, H.offset.Y, H.offset.Z, H.palm, H.scale)
end, "DeathBox: Revolver in der Hand ausrichten", { "x", "y", "z", "palm", "scale", "bone" })
