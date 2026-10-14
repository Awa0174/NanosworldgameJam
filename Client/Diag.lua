-- Client/Diag.lua
-- Selbstdiagnose im echten Spiel (nur mit DEBUG_COMMANDS). Misst, wie die Engine Grundformen, Drehungen und das
-- Anhaengen behandelt, und wo Jacks Teile tatsaechlich sitzen. Unser Test-Mock und der Vorschau-Renderer haben das
-- bisher nur angenommen. Das Ergebnis geht an den Server und landet dort in "deathbox_diag.txt" (Server-Ordner).
--
-- Automatisch: einmal ca. 6 s nach dem ersten Betreten des Friedhofs. Manuell: Konsole "db_diag".
-- Jeder Abschnitt laeuft in pcall: ein Fehler kostet nur seine eigenen Zeilen.

DeathBox.Diag = { ran = false }

local Diag = DeathBox.Diag
local Config = DeathBox.Config

local lines

local function L(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	table.insert(lines, ok and text or ("(format error) " .. tostring(fmt)))
end

local function V3(v)
	if (type(v) ~= "table" and type(v) ~= "userdata") then return tostring(v) end
	return string.format("(%.1f, %.1f, %.1f)", v.X or 0, v.Y or 0, v.Z or 0)
end

local function R3(r)
	if (type(r) ~= "table" and type(r) ~= "userdata") then return tostring(r) end
	return string.format("(P %.1f, Y %.1f, R %.1f)", r.Pitch or 0, r.Yaw or 0, r.Roll or 0)
end

-- Unsere Annahme (FRotationMatrix, Zeilen = lokale Achsen in Weltkoordinaten), siehe Revolver.lua / Renderer
local function Rows(p, y, r)
	local sp, cp = math.sin(math.rad(p)), math.cos(math.rad(p))
	local sy, cy = math.sin(math.rad(y)), math.cos(math.rad(y))
	local sr, cr = math.sin(math.rad(r)), math.cos(math.rad(r))
	return Vector(cp * cy, cp * sy, sp),
		Vector(sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp),
		Vector(-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp)
end

local function Section(name, fn)
	L("== %s", name)
	local ok, err = pcall(fn)
	if (not ok) then L("!! %s fehlgeschlagen: %s", name, tostring(err)) end
end

local spawned = {}
local function Spawn(location, rotation, asset)
	local mesh = StaticMesh(location, rotation or Rotator(), asset, CollisionType.NoCollision)
	table.insert(spawned, mesh)
	return mesh
end

local function Cleanup()
	for _, e in ipairs(spawned) do
		if (e and e:IsValid()) then e:Destroy() end
	end
	spawned = {}
end

local function Bounds(mesh)
	local b = mesh:GetBounds()
	return string.format("origin %s extent %s", V3(b.Origin), V3(b.BoxExtent))
end

-- Ergebnis in Stuecken an den Server (der schreibt die Datei)
local function Send()
	local text = table.concat(lines, "\n")
	local chunk = 1500
	local parts = math.ceil(#text / chunk)
	for i = 1, parts do
		Events.CallRemote("DeathBox:Diag", Reliability.Reliable, i, parts, string.sub(text, (i - 1) * chunk + 1, i * chunk))
	end
	Console.Log("[DeathBox] Diagnose gesendet (%d Zeilen, %d Teile)", #lines, parts)
end

function Diag.Run()
	lines = {}
	local base = Config.WORLD.HUB_CENTER + Vector(0, 0, 4000)   -- weit ueber dem Friedhof, niemand sieht es
	L("DeathBox %s Diagnose, Ort %s", tostring(DeathBox.VERSION), tostring(DeathBox.World.kind))

	-- 1) Grundformen: Groesse und Lage des Drehpunkts (Bounds-Mitte relativ zur Position)
	Section("Grundformen (Skalierung 1 und 1/2/3)", function()
		local assets = { "SM_Cube", "SM_Sphere", "SM_Cylinder", "SM_Cone", "SM_Plane", "SM_Torus", "SM_TopHat", "SM_None" }
		for i, name in ipairs(assets) do
			local at = base + Vector(i * 600, 0, 0)
			local ok, err = pcall(function()
				local mesh = Spawn(at, Rotator(), "nanos-world::" .. name)
				local b = mesh:GetBounds()
				L("%s: loc %s  origin-loc %s  extent %s", name, V3(mesh:GetLocation()), V3(b.Origin - at), V3(b.BoxExtent))
				mesh:SetScale(Vector(1, 2, 3))
				local b2 = mesh:GetBounds()
				L("%s scale(1,2,3): origin-loc %s  extent %s", name, V3(b2.Origin - at), V3(b2.BoxExtent))
			end)
			if (not ok) then L("%s: Fehler %s", name, tostring(err)) end
		end
	end)

	-- 2) Drehungen: Engine-Richtungen gegen unsere Annahme, plus eine gedrehte flache Box (Bounds zeigen die Achsen)
	Section("Drehungen", function()
		local tests = { { 0, 0, 0 }, { 30, 0, 0 }, { 0, 90, 0 }, { 0, 0, 90 }, { 0, -90, 90 }, { 10, 20, 30 }, { -40, 135, -60 } }
		for _, t in ipairs(tests) do
			local r = Rotator(t[1], t[2], t[3])
			local ex, ey, ez = Rows(t[1], t[2], t[3])
			L("Rotator%s engine fwd %s right %s up %s", R3(r), V3(r:GetForwardVector()), V3(r:GetRightVector()), V3(r:GetUpVector()))
			L("   annahme  X %s Y %s Z %s", V3(ex), V3(ey), V3(ez))
			L("   RotateVector(1,2,3) %s  annahme %s", V3(r:RotateVector(Vector(1, 2, 3))), V3(ex * 1 + ey * 2 + ez * 3))
			-- Flache Box: lokal X 10, Y 60, Z 120 (cm) -> Weltausdehnung zeigt, wohin die Achsen zeigen
			local at = base + Vector(0, 3000, 0)
			local box = Spawn(at, r, "nanos-world::SM_Cube")
			box:SetScale(Vector(0.1, 0.6, 1.2))
			L("   Box(10,60,120) %s", Bounds(box))
			box:Destroy()
		end
	end)

	-- 3) Anhaengen: KeepWorld, Elterndrehung, SetRelativeLocation, verschachtelt, skalierter Elternteil
	Section("Anhaengen", function()
		local at = base + Vector(0, 6000, 0)
		local parent = Spawn(at, Rotator(), "nanos-world::SM_None")
		local child = Spawn(at + Vector(100, 0, 50), Rotator(0, 0, 30), "nanos-world::SM_Cube")
		child:SetScale(Vector(0.1, 0.1, 0.1))
		child:AttachTo(parent, AttachmentRule.KeepWorld, "", -1, false)
		L("sofort: kind %s rel %s relrot %s attached %s", V3(child:GetLocation() - at), V3(child:GetRelativeLocation()),
			R3(child:GetRelativeRotation()), tostring(child:GetAttachedTo() == parent))
		parent:SetRotation(Rotator(0, 90, 0))
		L("eltern Gier 90: kind %s (annahme (0, 100, 50)) rot %s", V3(child:GetLocation() - at), R3(child:GetRotation()))
		parent:SetRotation(Rotator(30, 0, 0))
		local ex, ey, ez = Rows(30, 0, 0)
		L("eltern Nick 30: kind %s (annahme %s)", V3(child:GetLocation() - at), V3(ex * 100 + ez * 50))
		child:SetRelativeLocation(Vector(0, 0, 100))
		L("SetRelativeLocation(0,0,100) bei Nick 30: kind %s (annahme %s)", V3(child:GetLocation() - at), V3(ez * 100))
		child:SetRelativeRotation(Rotator(0, 0, 0))
		L("SetRelativeRotation(0): kind rot %s (annahme %s)", R3(child:GetRotation()), R3(Rotator(30, 0, 0)))
		-- verschachtelt
		local grand = Spawn(child:GetLocation() + Vector(0, 50, 0), Rotator(), "nanos-world::SM_Cube")
		grand:SetScale(Vector(0.1, 0.1, 0.1))
		grand:AttachTo(child, AttachmentRule.KeepWorld, "", -1, false)
		child:SetRelativeRotation(Rotator(0, 90, 0))
		L("enkel nach kind-Gier 90: enkel-kind %s", V3(grand:GetLocation() - child:GetLocation()))
		-- skalierter Elternteil (erbt das Kind die Skalierung in SetRelativeLocation?)
		local big = Spawn(at + Vector(0, 800, 0), Rotator(), "nanos-world::SM_Sphere")
		big:SetScale(Vector(2, 2, 2))
		local small = Spawn(at + Vector(0, 800, 0), Rotator(), "nanos-world::SM_Cube")
		small:SetScale(Vector(0.1, 0.1, 0.1))
		small:AttachTo(big, AttachmentRule.KeepWorld, "", -1, false)
		small:SetRelativeLocation(Vector(10, 0, 0))
		L("skalierter Eltern (2): SetRelativeLocation(10,0,0) -> %s, kind-skala %s", V3(small:GetLocation() - (at + Vector(0, 800, 0))), V3(small:GetScale()))
		-- spaeter nachmessen (falls Anhaengen erst im naechsten Bild wirkt)
		Diag.later = function()
			L("== Anhaengen (0,5 s spaeter)")
			if (child:IsValid()) then L("kind %s attached %s", V3(child:GetLocation() - at), tostring(child:GetAttachedTo() == parent)) end
			if (grand:IsValid()) then L("enkel-kind %s", V3(grand:GetLocation() - child:GetLocation())) end
		end
	end)

	-- 4) Jack, wie er gerade steht (Friedhof-Statue oder Zelt)
	Section("Jack", function()
		local holder = DeathBox.World.hub or DeathBox.World.tent
		local jack = holder and holder.jack
		if (not jack) then L("kein Jack gebaut") return end
		L("scale %s yaw %.1f center %s", tostring(jack.scale), jack.yaw or 0, V3(jack.center))
		local function Show(label, e)
			if (not e or not e.IsValid or not e:IsValid()) then L("%s: fehlt", label) return end
			local parent = e:GetAttachedTo()
			L("%s: loc-center %s rot %s rel %s relrot %s scale %s parent %s", label, V3(e:GetLocation() - jack.center), R3(e:GetRotation()),
				V3(e:GetRelativeLocation()), R3(e:GetRelativeRotation()), V3(e:GetScale()), parent and "ja" or "nein")
			local ok, b = pcall(function() return e:GetBounds() end)
			if (ok and b) then L("   bounds origin-center %s extent %s", V3(b.Origin - jack.center), V3(b.BoxExtent)) end
		end
		for _, key in ipairs({ "box_root", "lid_pivot", "root", "head", "jaw_pivot", "hat", "mask", "mouth", "neck_tube" }) do
			Show(key, jack[key])
		end
		for i, lid in ipairs(jack.eyelids or {}) do
			Show("lid" .. i, lid.mesh)
			-- Erwartung nach unserer Rechnung: Kopf-Weltlage + Kopf-Drehung * relative Lage
			local head = jack.head
			if (head and head:IsValid() and lid.mesh:IsValid()) then
				local rel = lid.mesh:GetRelativeLocation()
				local expect = head:GetLocation() + head:GetRotation():RotateVector(rel)
				L("   lid%d erwartet %s, ist %s", i, V3(expect - jack.center), V3(lid.mesh:GetLocation() - jack.center))
			end
		end
		for i, b in ipairs(jack.brows or {}) do Show("brow" .. i, b.mesh) end
		for i, e in ipairs(jack.eyes or {}) do Show("pupil" .. i, e.mesh) end
		if (jack.rings and jack.rings[1]) then
			Show("ring1", jack.rings[1])
			Show("ring" .. #jack.rings, jack.rings[#jack.rings])
		end
	end)

	-- Aufraeumen erst nach der zweiten Messung (die Anhaenge-Probe muss bis dahin stehen bleiben)
	Timer.SetTimeout(function()
		if (Diag.later) then pcall(Diag.later) end
		Diag.later = nil
		Cleanup()
		Send()
	end, 500)
end

-- Einmal automatisch nach dem ersten Betreten des Friedhofs
function Diag.OnEnter(kind)
	if (Diag.ran or kind ~= "hub" or not Config.DEBUG_COMMANDS) then return end
	Diag.ran = true
	Timer.SetTimeout(function() pcall(Diag.Run) end, 6000)
end

Console.RegisterCommand("db_diag", function()
	pcall(Diag.Run)
end, "DeathBox: Selbstdiagnose an den Server schicken")
