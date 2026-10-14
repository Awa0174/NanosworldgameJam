-- Client/World/Tent.lua
-- Das Zirkuszelt – lokal gebaut, sobald der Spieler an einem Tisch sitzt.
-- Alle Zelte sehen gleich aus (jedes Match ist eine eigene Dimension auf dem Server, aber der Client
-- baut einfach "sein" Zelt an derselben Stelle). Stuehle kommen aus Shared/Layout.lua, damit sie exakt
-- dort stehen, wo der Server die Figuren hinsetzt.

DeathBox.Tent = {}

local Tent = DeathBox.Tent
local Builder = DeathBox.Builder
local Layout = DeathBox.Layout
local Cfg = DeathBox.Config.WORLD

local WARM = Color(1.0, 0.55, 0.22)
local BULB = Color(1.0, 0.72, 0.35)
local SPOT = Color(1.0, 0.9, 0.75)
local BLOOD_SPOT = Color(1.0, 0.18, 0.1)

-- Grundhelligkeiten (lassen sich im Spiel mit "db_light <faktor>" in der Konsole skalieren)
local LAMP_INTENSITY = 6
local BULB_LIGHT_INTENSITY = 3
local JACK_SPOT_INTENSITY = 60
local ROOF_HEIGHT = 700          -- Dachspitze ueber der Wandoberkante (cm)
local TARGET_SPOT_INTENSITY = 90

function Tent.Build(seat_count, jack_yaw)
	local list = Builder.New()
	local c = Cfg.SHOW_CENTER
	local r = Cfg.SHOW_RADIUS
	local h = Cfg.SHOW_WALL_HEIGHT
	local tent = { list = list, center = c, seat_count = seat_count, lights = {}, bulbs = {}, mood = "normal" }
	local chair_radius = Layout.ChairRadius(seat_count)

	-- Boden: alte Buehnenbretter, in der Mitte die Manege mit Saegemehl und rot-weissem Rand
	Builder.Shape(list, "cylinder", c - Vector(0, 0, 10), Vector(r * 2 + 200, r * 2 + 200, 20),
		{ texture = "floor_planks", tiling = { 10, 10 }, roughness = 0.85, collision = true })
	Builder.Shape(list, "cylinder", c + Vector(0, 0, 1), Vector(chair_radius * 2 - 140, chair_radius * 2 - 140, 2),
		{ texture = "sawdust_ring", tiling = { 4, 4 }, roughness = 1 })
	-- Manegenrand: rot-weisse Holzsegmente (ein skalierter Torus wuerde zum flachen Donut, Renderer-Befund 14)
	local curb_r = chair_radius - 60
	local curb_n = 36
	local curb_len = 2 * math.pi * curb_r / curb_n + 3
	for i = 1, curb_n do
		local angle = (i - 0.5) * 360 / curb_n
		Builder.Box(list, Builder.OnCircle(c, angle, curb_r, 8), Vector(18, curb_len, 16),
			{ rotation = Rotator(0, angle, 0), color = (i % 2 == 0) and Color(0.55, 0.04, 0.03) or Color(0.82, 0.76, 0.64),
			  roughness = 0.45, collision = true })
	end

	-- Zeltwand aus gestreiftem Segeltuch
	local segments = Cfg.SHOW_WALL_SEGMENTS
	local width = 2 * math.pi * r / segments + 24
	for i = 1, segments do
		local angle = (i - 0.5) * 360 / segments
		Builder.Box(list, Builder.OnCircle(c, angle, r, h / 2), Vector(40, width, h),
			{ rotation = Rotator(0, angle, 0), texture = (i % 2 == 0) and "tent_canvas" or "tent_canvas_dark",
			  tiling = { 1, 2 }, roughness = 0.95, collision = true })
	end

	-- Dach: nach innen gewandte Planen bis zur Spitze (SM_Plane ist einseitig). Ein geschlossener Kegel waere von innen
	-- nur eine flache Decke auf Wandhoehe, die die Lichterketten verdeckt (Renderer-Befund 6).
	-- Jede Plane liegt quer zur Dachschraege (lokal X = quer, Y = die Schraege hinab, Z = nach innen-unten), damit die
	-- senkrechten Streifen der Textur strahlenfoermig von der Spitze zur Wand laufen: Rotator(0, Winkel + 90, 180 - Neigung).
	local roof_h = ROOF_HEIGHT
	local slope_len = math.sqrt(r * r + roof_h * roof_h)
	local roof_pitch = math.deg(math.atan(roof_h / r))
	local panels = 16
	local panel_w = 2 * math.pi * r / panels + 40
	for i = 1, panels do
		local angle = (i - 0.5) * 360 / panels
		Builder.Mesh(list, Builder.OnCircle(c, angle, r / 2, h + roof_h / 2), Rotator(0, angle + 90, 180 - roof_pitch), "nanos-world::SM_Plane",
			{ scale = Vector(panel_w / 100, slope_len / 100, 1), texture = (i % 2 == 0) and "tent_canvas" or "tent_canvas_dark",
			  tiling = { 1, 2 }, color = Color(0.75, 0.7, 0.68), roughness = 1, shadow = false })
	end
	-- Mittelmast haengt von der Dachspitze herab
	Builder.Shape(list, "cylinder", c + Vector(0, 0, h + roof_h - 400), Vector(34, 34, 800), { texture = "floor_planks", tiling = { 1, 4 } })

	-- Lichterketten vom Mast zur Wand, mit Gluehbirnen (einige flackern, manche sind kaputt)
	local strands = 10
	for i = 1, strands do
		local angle = i * 360 / strands
		local top = c + Vector(0, 0, h + 380)
		local wall = Builder.OnCircle(c, angle, r - 60, h - 40)
		for k = 1, 9 do
			local t = k / 10
			local sag = math.sin(t * math.pi) * 90
			local p = top + (wall - top) * t - Vector(0, 0, sag)
			local broken = math.random() < 0.12
			local bulb = Builder.Shape(list, "sphere", p, Vector(9, 9, 12),
				{ color = BULB, emissive = broken and Color(0, 0, 0) or BULB * 8, roughness = 0.2, shadow = false })
			if (not broken) then table.insert(tent.bulbs, { mesh = bulb, phase = math.random() * 10, flicker = math.random() < 0.2 }) end
		end
		-- ein schwaches Licht pro Kette, damit sie den Raum leicht faerben
		local mid = top + (wall - top) * 0.55 - Vector(0, 0, 80)
		table.insert(tent.lights, Builder.Light(list, mid, BULB, BULB_LIGHT_INTENSITY, 900, { flicker = 0.3 }))
	end

	-- Haengende Oellampen ueber dem Stuhlkreis (warmes, flackerndes Hauptlicht)
	for i = 1, 6 do
		local angle = i * 60 + 30
		local p = Builder.OnCircle(c, angle, chair_radius + 40, 520)
		Builder.Mesh(list, p, Rotator(), "oil_lamp", { scale = Vector(1.6, 1.6, 1.6) })
		Builder.Shape(list, "sphere", p + Vector(0, 0, 18), Vector(10, 10, 16), { color = WARM, emissive = WARM * 25, shadow = false })
		table.insert(tent.lights, Builder.Light(list, p - Vector(0, 0, 20), WARM, LAMP_INTENSITY, 750, { flicker = 0.6 }))
	end

	-- Stuehle genau dort, wo der Server die Figuren hinsetzt
	for i = 1, seat_count do
		local location, rotation = Layout.ChairTransform(i, seat_count)
		Builder.Mesh(list, location, rotation, "chair")
	end

	-- Deko am Zeltrand: Faesser, Kisten, Kuerbisse (mit Kerzenschein), Ballons, Grammophon, Plakate
	local deco = { "barrel", "crate", "pumpkin", "kids_box", "barrel", "crate" }
	for i = 1, 18 do
		local angle = i * 20 + math.random(-5, 5)
		local p = Builder.OnCircle(c, angle, r - 130, 0)
		local asset = deco[(i % #deco) + 1]
		Builder.Mesh(list, p, Rotator(0, math.random(0, 359), 0), asset,
			{ scale = asset == "pumpkin" and Vector(2.2, 2.2, 2.2) or nil, collision = true })
		if (asset == "pumpkin") then
			Builder.Light(list, p + Vector(0, 0, 60), WARM, 2, 300, { flicker = 0.8 })
		end
		if (i % 3 == 0) then
			local balloon = ({ "balloon_1", "balloon_2", "balloon_3" })[(i % 3) + 1]
			local b = Builder.Mesh(list, Builder.OnCircle(c, angle + 6, r - 150, 260 + math.random(0, 120)), Rotator(), balloon)
			local base = b:GetLocation()
			local seed = math.random() * 10
			Builder.AddTicker(list, function(dt, time)
				if (not b:IsValid()) then return false end
				b:SetLocation(base + Vector(0, 0, math.sin(time * 0.8 + seed) * 12))
			end)
		end
	end
	Builder.Mesh(list, Builder.OnCircle(c, 0, r - 220, 0), Rotator(0, 180, 0), "gramophone", { scale = Vector(1.6, 1.6, 1.6) })

	-- Plakate an der Zeltwand: aufrechte Flaechen (SM_Plane), die zur Zeltmitte zeigen
	-- (Plane liegt in XY mit U entlang X und V entlang Y -> Rotator(0, Blickrichtung - 90, 90) stellt sie aufrecht hin)
	for i, angle in ipairs({ 45, 135, 225, 315 }) do
		local p = Builder.OnCircle(c, angle, r - 24, 270)
		local facing = (angle + 180) % 360
		Builder.Mesh(list, p, Rotator(0, facing - 90, 90), "nanos-world::SM_Plane",
			{ scale = Vector(1.5, 2.0, 1), texture = (i % 2 == 0) and "poster_seats" or "poster_show", roughness = 0.9 })
	end

	-- Rostige Ketten haengen von der Kuppel (wie im Original ueber dem Tisch)
	for i = 1, 8 do
		local angle = i * 45 + 10
		local p = Builder.OnCircle(c, angle, chair_radius * 0.55, 0)
		local top_z = h + ROOF_HEIGHT * (1 - chair_radius * 0.55 / r)     -- haengen vom Dach
		local length = (top_z - h) + 380 + math.random(0, 160)
		Builder.Shape(list, "cylinder", p + Vector(0, 0, top_z - length / 2), Vector(5, 5, length),
			{ texture = "metal_rust", tiling = { 1, 8 }, roughness = 0.6, shadow = false })
		Builder.Shape(list, "torus", p + Vector(0, 0, top_z - length), Vector(16, 16, 5),
			{ texture = "metal_rust", rotation = Rotator(0, 0, 90), shadow = false })
	end

	-- Alte Blutflecken frueherer Shows
	for i = 1, 5 do
		local angle = math.random(0, 359)
		local p = Builder.OnCircle(c, angle, math.random(120, math.floor(chair_radius - 60)), 20)
		local decal = Decal(p, Rotator(-90, math.random(0, 359), 0), string.format("nanos-world::MI_Blood_Decal_%02d", math.random(1, 10)),
			Vector(30, 70 + math.random(0, 60), 70 + math.random(0, 60)), 3600, 0.002)
		table.insert(list.entities, decal)
	end

	-- Jack in der Mitte mit hartem Spot von oben
	tent.jack = DeathBox.Jack.Build(list, c, 1, jack_yaw or 0)
	tent.jack_spot = Builder.Spot(list, c + Vector(0, 0, h - 60), SPOT, JACK_SPOT_INTENSITY, h + 300, 20,
		{ profile = LightProfile.SpotLight_02 })
	-- Feiner Staub, nur im Lichtkegel ueber Jack sichtbar
	Builder.Particle(list, c + Vector(0, 0, 420), "dust", Vector(0.5, 0.5, 1.2))

	-- Spots auf das Opfer (werden bewegt, normalerweise aus). Zwei, z. B. fuer Split or Steal.
	tent.target_spot = Builder.Spot(list, c + Vector(0, 0, h - 60), BLOOD_SPOT, 0, h + 400, 11,
		{ profile = LightProfile.SpotLight_01 })
	tent.target_spot2 = Builder.Spot(list, c + Vector(0, 0, h - 60), BLOOD_SPOT, 0, h + 400, 11,
		{ profile = LightProfile.SpotLight_01, shadows = false })   -- selten an (zwei Gewaehlte): Schatten wirft der erste

	-- Gluehbirnen flackern lassen + Stimmung (Lichter dimmen) weich nachfuehren
	tent.dim = 1
	tent.dim_target = 1
	-- Leistung: Flackernde Birnen 20x pro Sekunde, alle anderen nur, wenn sich die Stimmung merklich aendert
	-- (vorher ~80 Material-Aufrufe in JEDEM Frame, gerade in den spannenden Momenten).
	local last_dim, next_flicker = 1, 0
	Builder.AddTicker(list, function(dt, time)
		tent.dim = tent.dim + (tent.dim_target - tent.dim) * math.min(1, dt * 3)
		if (math.abs(tent.dim - tent.dim_target) < 0.002) then tent.dim = tent.dim_target end
		local dim_changed = math.abs(tent.dim - last_dim) > 0.01 or (tent.dim == tent.dim_target and tent.dim ~= last_dim)
		local flicker_now = time >= next_flicker
		if (flicker_now) then next_flicker = time + Builder.FLICKER_STEP end
		if (dim_changed) then last_dim = tent.dim end
		if (dim_changed or flicker_now) then
			for _, b in ipairs(tent.bulbs) do
				if (b.mesh:IsValid() and ((b.flicker and flicker_now) or (not b.flicker and dim_changed))) then
					local f = b.flicker and (0.55 + 0.45 * math.abs(math.sin(time * 7 + b.phase) * math.sin(time * 13 + b.phase))) or 1
					b.mesh:SetMaterialColorParameter("Emissive", BULB * (8 * f * tent.dim))
				end
			end
		end
		DeathBox.World.light_dim = tent.dim
	end)

	return tent
end

-- ===================================================================
-- Platz-Markierungen: Kerze vor jedem besetzten Stuhl + Name ueber dem Kopf
-- (werden aus dem Tischzustand gebaut; Kerze erlischt beim Tod, flammt auf, wenn Jacks Suchstrahl vorbeistreicht)
-- Namensschilder: gross, zeigen immer zur Kamera; GOLD = gewaehlt / am Zug (event.actors, Revolver-Halter),
-- GRAU = ausgeschieden, sonst warmes Weiss. Beim Vorbeistreichen des Strahls blitzen sie kurz hell auf.
-- ===================================================================

local FLAME = Color(1.0, 0.55, 0.15)
local LABEL_SIZE = 24
local LABEL_HEIGHT = 128          -- ueber dem Sitzpunkt (ca. 65 cm ueber dem Kopf einer sitzenden Figur)
local LABEL_COLORS = {
	alive = Color(0.95, 0.9, 0.8),
	actor = Color(1.0, 0.72, 0.16),
	dead = Color(0.4, 0.4, 0.42),
}
local LABEL_FLASH = Color(1.0, 0.95, 0.8)

local function ShortName(name)
	name = tostring(name or "")
	if (#name > 14) then name = name:sub(1, 13) .. "." end
	return name
end

-- Wer ist gerade "dran" (GOLD)? Aus dem letzten Tischzustand (Client/Presentation.lua setzt ihn vor UpdateSeats)
local function ActorSet()
	local set = {}
	local state = DeathBox.Presentation and DeathBox.Presentation.state
	local event = state and state.event
	if (type(event) == "table") then
		for _, seat in pairs(event.actors or {}) do set[seat] = true end
		local data = event.data
		if (type(data) == "table" and type(data.holder) == "number") then set[data.holder] = true end
	end
	return set
end

local function LabelColor(m)
	return LABEL_COLORS[(not m.alive) and "dead" or (m.actor and "actor" or "alive")]
end

function Tent.UpdateSeats(tent, seats)
	tent.markers = tent.markers or {}
	local actors = ActorSet()
	for _, s in pairs(seats) do
		local chair = s.chair or s.seat
		local m = tent.markers[s.seat]
		if (not m) then
			local angle = Layout.ChairAngle(chair, tent.seat_count)
			local base = Builder.OnCircle(tent.center, angle, Layout.ChairRadius(tent.seat_count) - 72, 0)
			m = { chair = chair, alive = true, base = base, flare = 0, actor = false }
			m.candle = Builder.Shape(tent.list, "cylinder", base + Vector(0, 0, 14), Vector(7, 7, 28), { color = Color(0.85, 0.8, 0.68), roughness = 0.8, shadow = false })
			m.flame = Builder.Shape(tent.list, "sphere", base + Vector(0, 0, 33), Vector(5, 5, 9), { color = FLAME, emissive = FLAME * 20, shadow = false })
			local head = Layout.SitTransform(chair, tent.seat_count) + Vector(0, 0, LABEL_HEIGHT)
			m.label = TextRender(head, Rotator(), ShortName(s.name), LABEL_SIZE, LABEL_COLORS.alive,
				TextRenderRenderingType.UnlitCameraAligned, TextRenderHorizontalAlignment.Center, TextRenderVerticalAlignment.Center,
				"nanos-world::Font_Roboto_DistanceField", false)
			table.insert(tent.list.entities, m.label)
			m.color = LABEL_COLORS.alive
			m.name = s.name
			tent.markers[s.seat] = m
		end
		-- Platz hat den Besitzer gewechselt (Nachruecker uebernimmt einen Bot): neues Namensschild
		if (m.name ~= s.name and m.label:IsValid()) then
			m.name = s.name
			m.label:SetText(ShortName(s.name))
		end
		if (m.alive and not s.alive) then
			-- Kerze erlischt
			m.alive = false
			if (m.flame:IsValid()) then m.flame:SetVisibility(false) end
			Builder.Particle(tent.list, m.base + Vector(0, 0, 36), "smoke", Vector(0.15, 0.15, 0.3))
		end
		m.actor = actors[s.seat] and true or false
		local color = LabelColor(m)
		if (color ~= m.color) then
			m.color = color
			if (m.label:IsValid() and m.flare <= 0) then m.label:SetColor(color) end
		end
	end

	-- Kerzen flackern; "Flare" (Suchstrahl/Spin-Tick) laesst Kerze und Namensschild kurz hell aufflammen
	if (not tent.marker_ticker) then
		tent.marker_ticker = Builder.AddTicker(tent.list, function(dt, time)
			for _, m in pairs(tent.markers) do
				local flaring = m.flare > 0
				m.flare = math.max(0, m.flare - dt * 3)
				if (m.alive and m.flame:IsValid()) then
					local f = 0.75 + 0.25 * math.sin(time * 11 + m.chair) + m.flare * 4
					m.flame:SetMaterialColorParameter("Emissive", FLAME * (20 * f * (0.4 + 0.6 * (DeathBox.World.light_dim or 1)) + m.flare * 60))
					local k = 1 + m.flare * 0.8
					m.flame:SetScale(Vector(0.05 * k, 0.05 * k, 0.09 * k))
				end
				if (flaring and m.label:IsValid()) then
					local base, k = m.color or LABEL_COLORS.alive, m.flare
					m.label:SetColor(Color(base.R + (LABEL_FLASH.R - base.R) * k, base.G + (LABEL_FLASH.G - base.G) * k, base.B + (LABEL_FLASH.B - base.B) * k))
				end
			end
		end)
	end
end

-- Platz kurz aufflammen lassen (Jacks Suchstrahl streicht vorbei): Kerze + Namensschild
function Tent.FlareSeat(tent, seat_index)
	local m = tent.markers and tent.markers[seat_index]
	if (m and m.alive) then m.flare = 1 end
end

-- Stimmungen: "normal", "spin" (gedimmt), "hold" (fast dunkel), "reveal", "death" (Flackern)
function Tent.SetMood(tent, mood)
	tent.mood = mood
	local base
	if (mood == "spin") then base = 0.55
	elseif (mood == "hold") then base = 0.25
	elseif (mood == "death") then base = 0.15
	else base = 1 end
	-- Je weiter die Show, desto dunkler das Zelt (Tent.SetDoom): im Finale nur noch ~45 % Grundlicht
	tent.dim_target = base * (1 - 0.55 * (tent.doom or 0))
end

-- Fortschritt der Show 0..1 (Client/Presentation.lua aus dem Tischzustand)
function Tent.SetDoom(tent, doom)
	if (tent.doom == doom) then return end
	tent.doom = doom
	Tent.SetMood(tent, tent.mood or "normal")
end

-- Roter Spot auf einen Stuhl (nil = aus). second = true nutzt den zweiten Spot.
function Tent.SpotChair(tent, chair_index, second, color)
	local spot = second and tent.target_spot2 or tent.target_spot
	if (not spot or not spot:IsValid()) then return end
	spot:SetColor(color or BLOOD_SPOT)
	if (not chair_index) then
		spot:SetIntensity(0)
		return
	end
	local angle = Layout.ChairAngle(chair_index, tent.seat_count)
	spot:SetLocation(Builder.OnCircle(tent.center, angle, Layout.ChairRadius(tent.seat_count), Cfg.SHOW_WALL_HEIGHT - 60))
	spot:SetIntensity(TARGET_SPOT_INTENSITY * (DeathBox.World.light_scale or 1))
end

-- Brustpunkt einer sitzenden Figur auf einem Stuhl (fuer Messer, Feuer ...)
function Tent.ChairPoint(tent, chair_index, z)
	local location = Layout.SitTransform(chair_index, tent.seat_count)
	return location + Vector(0, 0, z or 20)
end

-- Boden vor einem Stuhl (fuer Blut)
function Tent.ChairFloor(tent, chair_index)
	local angle = Layout.ChairAngle(chair_index, tent.seat_count)
	return Builder.OnCircle(tent.center, angle, Layout.ChairRadius(tent.seat_count) - 40, 2)
end
