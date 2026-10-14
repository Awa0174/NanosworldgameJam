-- Client/World/Builder.lua
-- Bauhilfen fuer die LOKALE Welt. Alles hier existiert nur beim jeweiligen Spieler:
-- kein Netzwerk, keine Server-Last, Animationen laufen Bild fuer Bild fluessig.
-- Jeder Spieler baut nur den Ort, an dem er gerade ist (Friedhof oder Zelt).
--
-- Grundformen (cube, sphere, cylinder, cone, torus, plane) sind 100 x 100 x 100 cm gross und mittig.
-- Materialien: nanos-world::M_Default_Masked_Lit mit den Parametern
--   Tint (Farbe), Texture (Bild), Emissive (Leuchten, Werte > 1 = Bloom), Roughness, UTiling, VTiling

DeathBox.Builder = {
	tickers = {},   -- aktive Animationen: function(dt, time) -> false beendet sie
	time = 0,
}

local Builder = DeathBox.Builder
local SHAPE = 100
local MATERIAL = "nanos-world::M_Default_Masked_Lit"

-- Eine Bauliste: sammelt alles, was zu einem Ort gehoert, damit es gemeinsam abgerissen werden kann
function Builder.New()
	return { entities = {}, tickers = {} }
end

local function Track(list, entity)
	table.insert(list.entities, entity)
	return entity
end

-- Optionen fuer Materialien:
--   color      Tint (Color)
--   texture    Name einer Textur aus Client/textures (ohne .png)
--   tiling     { u, v } Kachelung der Textur
--   emissive   Color fuer Leuchten (z. B. Color(1, 0.3, 0) * 20)
--   roughness  0..1
function Builder.Paint(mesh, opts)
	if (not opts.color and not opts.texture and not opts.emissive and not opts.roughness) then return end
	mesh:SetMaterial(MATERIAL)
	if (opts.texture) then
		mesh:SetMaterialTextureParameter("Texture", DeathBox.TextureFile(opts.texture))
	end
	if (opts.tiling) then
		mesh:SetMaterialScalarParameter("UTiling", opts.tiling[1])
		mesh:SetMaterialScalarParameter("VTiling", opts.tiling[2])
	end
	mesh:SetMaterialColorParameter("Tint", opts.color or Color(1, 1, 1))
	if (opts.emissive) then
		mesh:SetMaterialColorParameter("Emissive", opts.emissive)
	end
	if (opts.roughness) then
		mesh:SetMaterialScalarParameter("Roughness", opts.roughness)
	end
end

-- Beliebiges Mesh. opts: scale, rotation, collision (true = fest, Standard: keine Kollision), + Material-Optionen
function Builder.Mesh(list, location, rotation, asset, opts)
	opts = opts or {}
	local collision = opts.collision and CollisionType.Normal or CollisionType.NoCollision
	local key = string.find(asset, "::", 1, true) and asset or DeathBox.Asset(asset)
	local mesh = StaticMesh(location, rotation or Rotator(), key, collision)
	if (opts.scale) then mesh:SetScale(opts.scale) end
	if (opts.shadow == false) then mesh:SetCastShadow(false) end
	Builder.Paint(mesh, opts)
	return Track(list, mesh)
end

local RotAxes   -- weiter unten definiert (Drehung -> lokale Achsen)

-- Der Torus der Engine ist 100 x 100 x 30 cm gross und hat seinen Drehpunkt an der Unterseite (In-Engine-Diagnose
-- 14.10., deathbox_diag.txt). Alle anderen Grundformen sind 100 cm und mittig.
local TORUS_THICKNESS = 30

-- Grundform mit Groesse in cm, "center" ist immer die Mitte der Form
function Builder.Shape(list, asset, center, size, opts)
	opts = opts or {}
	if (asset == "torus") then
		opts.scale = Vector(size.X / SHAPE, size.Y / SHAPE, size.Z / TORUS_THICKNESS)
		-- Drehpunkt unten: um die halbe Dicke entlang der lokalen Z-Achse absenken
		local _, _, z = RotAxes(opts.rotation or Rotator())
		center = center - Vector(z[1], z[2], z[3]) * (size.Z / 2)
	else
		opts.scale = Vector(size.X / SHAPE, size.Y / SHAPE, size.Z / SHAPE)
	end
	return Builder.Mesh(list, center, opts.rotation, asset, opts)
end

function Builder.Box(list, center, size, opts)
	return Builder.Shape(list, "cube", center, size, opts)
end

-- Punktlicht. opts: flicker (0..1 Staerke), shadows, profile (LightProfile)
function Builder.Light(list, location, color, intensity, radius, opts)
	opts = opts or {}
	local light = Light(location, Rotator(), color, LightType.Point, intensity, radius, 44, 0, 6000, true, opts.shadows == true, true, 4)
	if (opts.profile) then light:SetTextureLightProfile(opts.profile) end
	Track(list, light)
	if (opts.flicker) then
		local base = intensity
		local seed = math.random() * 100
		Builder.AddTicker(list, function(dt, time)
			if (not light:IsValid()) then return false end
			local k = (DeathBox.World.light_scale or 1) * (DeathBox.World.light_dim or 1)
			local wobble = math.sin(time * 9 + seed) * 0.5 + math.sin(time * 23 + seed * 2) * 0.3 + (math.random() - 0.5) * 0.4
			light:SetIntensity(base * k * (1 + wobble * opts.flicker * 0.5))
		end)
	else
		light:SetValue("DB_BaseIntensity", intensity)
	end
	light:SetValue("DB_BaseIntensity", intensity)
	return light
end

-- Spot von oben. rotation zeigt die Richtung (Standard: senkrecht nach unten)
function Builder.Spot(list, location, color, intensity, radius, cone, opts)
	opts = opts or {}
	local light = Light(location, opts.rotation or Rotator(-90, 0, 0), color, LightType.Spot, intensity, radius,
		cone or 25, opts.inner or 0.5, 8000, true, opts.shadows ~= false, true, 4)
	if (opts.profile) then light:SetTextureLightProfile(opts.profile) end
	light:SetValue("DB_BaseIntensity", intensity)
	return Track(list, light)
end

function Builder.Particle(list, location, asset, scale, rotation)
	local key = string.find(asset, "::", 1, true) and asset or DeathBox.Asset(asset)
	local particle = Particle(location, rotation or Rotator(), key, false, true)
	if (scale) then particle:SetScale(scale) end
	return Track(list, particle)
end

-- Bild, das immer zur Kamera zeigt (z. B. Jacks Gesicht, Gluehbirnen-Schein)
function Builder.Billboard(list, location, texture, size, opts)
	opts = opts or {}
	local billboard = Billboard(location, MATERIAL, size, false)
	billboard:SetMaterialTextureParameter("Texture", DeathBox.TextureFile(texture))
	billboard:SetMaterialColorParameter("Tint", opts.color or Color(1, 1, 1))
	if (opts.emissive) then billboard:SetMaterialColorParameter("Emissive", opts.emissive) end
	billboard:SetMaterialScalarParameter("Opacity", 1)
	return Track(list, billboard)
end

-- Drehung -> lokale Achsen X/Y/Z in Weltkoordinaten (Engine-Konvention, im Spiel geprueft: Client/Diag.lua)
local ATAN2 = math.atan2 or math.atan
RotAxes = function(r)
	local p, y, rl = math.rad(r.Pitch or 0), math.rad(r.Yaw or 0), math.rad(r.Roll or 0)
	local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(rl), math.cos(rl)
	return { cp * cy, cp * sy, sp },
		{ sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp },
		{ -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp }
end
local function Dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Haengt ein Objekt an ein anderes (Position in Weltkoordinaten bleibt erhalten).
-- nanos 1.159 haelt KeepWorld bei unseren lokalen Objekten NICHT ein (In-Engine-Diagnose 14.10., deathbox_diag.txt): das
-- Kind landet mit relativer Lage 0 im Drehpunkt des Elternteils. Daran lag v0.8 "Maske unsichtbar, Kiste kaputt".
-- Darum wird die relative Lage/Drehung hier selbst gesetzt (wo KeepWorld funktioniert, z. B. im Mock, ergibt das
-- dieselbe Lage). Relative Orte skaliert die Engine mit dem Elternteil, deshalb / Elterngroesse.
function Builder.Attach(child, parent)
	local loc, rot = child:GetLocation(), child:GetRotation()
	child:AttachTo(parent, AttachmentRule.KeepWorld, "", -1, false)
	local p_loc, p_rot = parent:GetLocation(), parent:GetRotation()
	if (not (loc and rot and p_loc and p_rot)) then return child end
	local s = parent:GetScale()
	local sx = (s and s.X and s.X ~= 0) and s.X or 1
	local sy = (s and s.Y and s.Y ~= 0) and s.Y or 1
	local sz = (s and s.Z and s.Z ~= 0) and s.Z or 1
	local PX, PY, PZ = RotAxes(p_rot)
	local CX, CY, CZ = RotAxes(rot)
	local d = { loc.X - p_loc.X, loc.Y - p_loc.Y, loc.Z - p_loc.Z }
	child:SetRelativeLocation(Vector(Dot(d, PX) / sx, Dot(d, PY) / sy, Dot(d, PZ) / sz))
	-- Drehung des Kindes im Rahmen des Elternteils -> Rotator
	local X = { Dot(CX, PX), Dot(CX, PY), Dot(CX, PZ) }
	local Y = { Dot(CY, PX), Dot(CY, PY), Dot(CY, PZ) }
	local Z = { Dot(CZ, PX), Dot(CZ, PY), Dot(CZ, PZ) }
	local pitch = math.deg(math.asin(math.max(-1, math.min(1, X[3]))))
	local yaw, roll
	if (math.abs(X[3]) < 0.99999) then
		yaw, roll = math.deg(ATAN2(X[2], X[1])), math.deg(ATAN2(-Y[3], Z[3]))
	else   -- senkrecht: Gieren und Rollen fallen zusammen
		yaw, roll = math.deg(ATAN2(-Y[1], Y[2])), 0
	end
	child:SetRelativeRotation(Rotator(pitch, yaw, roll))
	return child
end

-- Animation, die jedes Bild aufgerufen wird. Gibt die Funktion false zurueck, endet sie.
function Builder.AddTicker(list, fn)
	local entry = { fn = fn, list = list }
	table.insert(Builder.tickers, entry)
	if (list) then table.insert(list.tickers, entry) end
	return entry
end

function Builder.RemoveTicker(entry)
	if (entry) then entry.dead = true end
end

function Builder.Destroy(list)
	for _, entry in ipairs(list.tickers) do entry.dead = true end
	list.tickers = {}
	for _, entity in ipairs(list.entities) do
		if (entity and entity:IsValid()) then entity:Destroy() end
	end
	list.entities = {}
end

-- Punkt auf einem Kreis. Winkel in Grad, 0 = +X.
function Builder.OnCircle(center, angle_deg, radius, z_offset)
	local rad = math.rad(angle_deg)
	return center + Vector(math.cos(rad) * radius, math.sin(rad) * radius, z_offset or 0)
end

-- Drehung, damit etwas von "from" nach "to" zeigt
local atan2 = math.atan2 or math.atan
function Builder.LookAt(from, to)
	local d = to - from
	local flat = math.sqrt(d.X * d.X + d.Y * d.Y)
	return Rotator(math.deg(atan2(d.Z, flat)), math.deg(atan2(d.Y, d.X)), 0)
end

-- Ein einziger Tick fuer alle lokalen Animationen
Client.Subscribe("Tick", function(delta_time)
	Builder.time = Builder.time + delta_time
	local time = Builder.time
	local alive = {}
	for _, entry in ipairs(Builder.tickers) do
		if (not entry.dead) then
			local ok, result = pcall(entry.fn, delta_time, time)
			if (not ok) then
				Console.Warn("[DeathBox] Animationsfehler: %s", tostring(result))
				entry.dead = true
			elseif (result == false) then
				entry.dead = true
			end
		end
		if (not entry.dead) then table.insert(alive, entry) end
	end
	Builder.tickers = alive
end)
