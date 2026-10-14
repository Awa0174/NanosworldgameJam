-- Client/World/Hub.lua
-- Der Friedhof (Hub) – lokal gebaut, solange der Spieler auf die naechste Show wartet.
-- Offen nach oben: Nachthimmel mit Mond (Client/Atmosphere.lua).
--
-- Grundriss (von oben, +X = Norden):
--
--        +--------------- Zirkuszelt-Fassade ---------------+
--        |   Graeber      Kuerbisse      Graeber            |
--        |                                                  |
--        |               [ JACK-STATUE ]                    |
--        |                                                  |
--        |   Graeber      Kuerbisse      Graeber            |
--        +------------------+  Tor  +-----------------------+
--                           | GRUFT |   <- Spawn
--                           +-------+

DeathBox.Hub = {}

local Hub = DeathBox.Hub
local Builder = DeathBox.Builder
local Cfg = DeathBox.Config.WORLD

local ORANGE = Color(1.0, 0.45, 0.12)
local GREEN = Color(0.35, 1.0, 0.45)
local WARM_KEY = Color(1.0, 0.74, 0.46)
local BULB = Color(1.0, 0.72, 0.35)

-- Fester Zufall: jeder Spieler sieht denselben Friedhof
local function Random(seed)
	local state = seed
	return function(min, max)
		state = (state * 16807) % 2147483647
		local value = state / 2147483647
		if (min and max) then return min + value * (max - min) end
		return value
	end
end

-- ===================================================================
-- Anzeigetafel (Warteschlange)
-- ===================================================================

Hub.lobby = nil      -- letzter Hub-Zustand vom Server (DeathBox:Lobby, siehe docs/PROTOCOL.md)
Hub.lobby_at = 0     -- Empfangszeit (Builder.time)

function Hub.SetLobby(lobby)
	if (type(lobby) ~= "table") then return end
	Hub.lobby = lobby
	Hub.lobby_at = Builder.time
end

-- Restsekunden des laufenden Countdowns (lokal weitergezaehlt)
function Hub.SecondsLeft()
	local timer = Hub.lobby and Hub.lobby.timer
	if (type(timer) ~= "table" or type(timer.remaining) ~= "number") then return 0 end
	return math.max(0, timer.remaining - (Builder.time - Hub.lobby_at))
end

function Hub.BoardText()
	local lobby = Hub.lobby
	if (not lobby) then return "TONIGHT: JACK'S LAST SHOW" end
	local seats = tonumber(lobby.seats) or 16
	local left = Hub.SecondsLeft()
	if (lobby.timer and left > 0) then
		local humans = tonumber(lobby.humans)
		if (humans) then
			return string.format("NEXT SHOW IN 0:%02d   %d PLAYER%s", math.ceil(left), humans, humans == 1 and "" or "S")
		end
		return string.format("NEXT SHOW IN 0:%02d   %d/%d SEATS", math.ceil(left), math.min(tonumber(lobby.next_table) or 0, seats), seats)
	end
	if ((tonumber(lobby.tables) or 0) >= (tonumber(lobby.max_tables) or 1) and (tonumber(lobby.queued) or 0) > 0) then
		return "ALL TENTS ARE FULL - PLEASE WAIT"
	end
	local missing = (tonumber(lobby.needed) or 2) - (tonumber(lobby.next_table) or 0)
	if (missing > 0) then
		return string.format("WAITING FOR %d MORE SOUL%s", missing, missing == 1 and "" or "S")
	end
	return "THE SHOW IS ABOUT TO BEGIN"
end

function Hub.Build()
	local list = Builder.New()
	local c = Cfg.HUB_CENTER
	local size = Cfg.HUB_SIZE
	local half = size / 2
	local h = Cfg.HUB_WALL_HEIGHT
	local rnd = Random(1337)
	local hub = { list = list }

	-- Boden und Friedhofsmauer (Tor im Sueden zur Gruft)
	Builder.Box(list, c - Vector(0, 0, 10), Vector(size + 600, size + 600, 20),
		{ texture = "graveyard_ground", tiling = { 12, 12 }, roughness = 1, collision = true })
	local wall = { texture = "stone_wall", tiling = { 12, 1.2 }, roughness = 0.95, collision = true }
	Builder.Box(list, c + Vector(0, half, h / 2), Vector(size, 60, h), wall)
	Builder.Box(list, c + Vector(0, -half, h / 2), Vector(size, 60, h), wall)
	Builder.Box(list, c + Vector(half, 0, h / 2), Vector(60, size + 60, h), { texture = "stone_wall", tiling = { 12, 1.2 }, roughness = 0.95, collision = true })
	local gate = 500
	local side = (size - gate) / 2
	local side_wall = { texture = "stone_wall", tiling = { 6, 1.2 }, roughness = 0.95, collision = true }
	Builder.Box(list, c + Vector(-half, -(gate / 2 + side / 2), h / 2), Vector(60, side, h), side_wall)
	Builder.Box(list, c + Vector(-half, (gate / 2 + side / 2), h / 2), Vector(60, side, h), side_wall)
	Builder.Box(list, c + Vector(-half, 0, h + 60), Vector(80, gate + 120, 120), side_wall)

	-- Gruft (Spawn) hinter dem Tor: Steinkammer, Saerge, Kerzen, gruenes Licht
	local cs = Cfg.CRYPT_SIZE
	local cc = c + Vector(-half - cs / 2, 0, 0)
	local ch = 450
	local stone = { texture = "stone_wall", tiling = { 3, 1.5 }, roughness = 0.95, collision = true }
	Builder.Box(list, cc - Vector(0, 0, 8), Vector(cs + 40, cs + 40, 20), stone)    -- Boden der Gruft (Spawn!), 2 cm hoeher gegen Flackern
	Builder.Box(list, cc + Vector(0, 0, ch + 10), Vector(cs, cs, 20), stone)
	Builder.Box(list, cc + Vector(-cs / 2, 0, ch / 2), Vector(40, cs, ch), stone)
	Builder.Box(list, cc + Vector(0, cs / 2, ch / 2), Vector(cs, 40, ch), stone)
	Builder.Box(list, cc + Vector(0, -cs / 2, ch / 2), Vector(cs, 40, ch), stone)
	for i = -1, 1 do
		for _, sy in ipairs({ -1, 1 }) do
			Builder.Box(list, cc + Vector(i * 230, sy * (cs / 2 - 90), 40), Vector(190, 70, 80),
				{ texture = "floor_planks", tiling = { 1, 1 }, color = Color(0.5, 0.4, 0.35), collision = true })
		end
	end
	for i = 1, 6 do
		local p = cc + Vector(-cs / 2 + 70, -cs / 2 + 120 + i * 110, 0)
		Builder.Shape(list, "cylinder", p + Vector(0, 0, 20), Vector(10, 10, 40), { color = Color(0.9, 0.85, 0.7) })
		Builder.Shape(list, "sphere", p + Vector(0, 0, 46), Vector(5, 5, 9), { color = ORANGE, emissive = ORANGE * 30, shadow = false })
	end
	Builder.Light(list, cc + Vector(0, 0, ch - 80), GREEN, 4, 900, { flicker = 0.4 })
	Builder.Light(list, cc + Vector(-cs / 2 + 80, 0, 70), ORANGE, 2, 500, { flicker = 0.8 })

	-- Graeber in Reihen, schief und versetzt, mit Weg in der Mitte
	local graves = { "grave_1", "grave_2", "grave_3", "grave_4" }
	for gx = -3, 3 do
		for gy = -3, 3 do
			local near_center = math.abs(gx) <= 1 and math.abs(gy) <= 1
			if (not near_center and gy ~= 0) then
				local p = c + Vector(gx * 560 + rnd(-120, 120), gy * 560 + rnd(-120, 120), 0)
				local asset = graves[math.floor(rnd(1, #graves + 0.999))]
				Builder.Mesh(list, p, Rotator(0, 180 + rnd(-15, 15), rnd(-7, 7)), asset, { collision = true })
			end
		end
	end

	-- Kuerbisse mit Kerzenschein entlang des Mittelwegs
	for i = -3, 3 do
		if (i ~= 0) then
			for _, sy in ipairs({ -260, 260 }) do
				local p = c + Vector(i * 560, sy, 0)
				Builder.Mesh(list, p, Rotator(0, rnd(0, 360), 0), "pumpkin", { scale = Vector(2.4, 2.4, 2.4), collision = true })
				Builder.Light(list, p + Vector(0, 0, 70), ORANGE, 2.5, 550, { flicker = 0.7 })
			end
		end
	end

	-- Tote Baeume und Felsen in den Ecken
	for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local base = c + Vector(corner[1] * (half - 400), corner[2] * (half - 400), 0)
		Builder.Mesh(list, base, Rotator(0, rnd(0, 360), 0), "tree", { scale = Vector(1.5, 1.5, 1.5) })   -- Originalmaterial behalten (Blaetter brauchen ihre Maske)
		Builder.Mesh(list, base + Vector(-corner[1] * 260, 0, 0), Rotator(0, rnd(0, 360), 0), "rock", { collision = true })
	end

	-- Fackeln an der Mauer
	for i = -2, 2 do
		for _, sy in ipairs({ 1, -1 }) do
			local p = c + Vector(i * 900, sy * (half - 50), 250)
			Builder.Mesh(list, p, Rotator(0, sy * -90, 0), "torch")
			Builder.Particle(list, p + Vector(0, 0, 70), "fire", Vector(0.4, 0.4, 0.4))
			Builder.Light(list, p + Vector(0, -sy * 60, 80), ORANGE, 3, 800, { flicker = 0.6 })
		end
	end

	-- Plakate an der Mauer: aufrechte Flaechen, die zur Friedhofsmitte zeigen
	for i, x in ipairs({ -1400, -500, 500, 1400 }) do
		for _, sy in ipairs({ 1, -1 }) do
			local facing = -90 * sy
			-- Mauer-Innenseite bei half - 30: Plakat 3 cm davor
			Builder.Mesh(list, c + Vector(x, sy * (half - 33), 240), Rotator(0, facing - 90, 90), "nanos-world::SM_Plane",
				{ scale = Vector(1.5, 2.0, 1), texture = (i % 2 == 0) and "poster_seats" or "poster_show", roughness = 0.9 })
		end
	end

	-- Zirkuszelt-Fassade im Norden mit Lichterkette: das Versprechen der Show
	local tent_c = c + Vector(half + 700, 0, 0)
	Builder.Shape(list, "cylinder", tent_c + Vector(0, 0, 450), Vector(1600, 1600, 900),
		{ texture = "tent_canvas", tiling = { 8, 1 }, roughness = 1 })
	Builder.Shape(list, "cone", tent_c + Vector(0, 0, 1250), Vector(1700, 1700, 700),
		{ texture = "tent_canvas_dark", tiling = { 10, 2 }, roughness = 1 })
	Builder.Box(list, tent_c + Vector(-805, 0, 260), Vector(20, 380, 520), { color = Color(0.02, 0.0, 0.0) })   -- dunkler Eingang
	for k = 0, 24 do
		local angle = 140 + k * (80 / 24)
		local p = Builder.OnCircle(tent_c, angle, 812, 900 - math.abs(k - 12) * 6)
		Builder.Shape(list, "sphere", p, Vector(14, 14, 18), { color = BULB, emissive = BULB * 10, shadow = false })
	end
	Builder.Light(list, tent_c + Vector(-900, 0, 700), BULB, 6, 1500, { flicker = 0.2 })

	-- Leuchtschrift ueber dem Zelteingang + Gluehbirnen-Rahmen. TextRender zeigt nach lokal +X (im Spiel bestaetigt: die
	-- Anzeigetafel darunter mit Gier 180 ist vom Friedhof aus lesbar). Darum fest Gier 180, mittig im Rahmen, mit dunkler Tafel
	-- dahinter. (Vorher Text3D mit FaceCamera: schwebte versetzt neben dem Rahmen und drehte sich beim Herumlaufen mit.)
	local sign_at = tent_c + Vector(-830, 0, 720)
	Builder.Box(list, sign_at + Vector(8, 0, 0), Vector(8, 800, 150), { color = Color(0.12, 0.02, 0.02), roughness = 0.7 })
	local sign = TextRender(sign_at + Vector(-8, 0, -4), Rotator(0, 180, 0), "JACK'S LAST SHOW", 84, BULB,
		TextRenderRenderingType.Unlit, TextRenderHorizontalAlignment.Center, TextRenderVerticalAlignment.Center,
		"nanos-world::Font_LondrinaSolid_DistanceField", false)
	table.insert(list.entities, sign)
	local frame_bulbs = {}
	for k = -10, 10 do
		for _, dz in ipairs({ -70, 70 }) do
			local b = Builder.Shape(list, "sphere", sign_at + Vector(-6, k * 38, dz), Vector(10, 10, 12),
				{ color = BULB, emissive = BULB * 8, shadow = false })
			table.insert(frame_bulbs, { mesh = b, i = k })
		end
	end
	-- Lauflicht im Rahmen wie auf dem Rummel; die Schrift setzt alle paar Sekunden kurz aus (Wackelkontakt)
	-- Nur bei Aenderung setzen (8 Schritte pro Sekunde), nicht in jedem Frame: 42 Birnen x 60 fps waeren sonst
	-- ueber 2500 Material-Aufrufe pro Sekunde.
	local last_step, last_glitch = nil, nil
	Builder.AddTicker(list, function(dt, time)
		local step = math.floor(time * 8)
		if (sign:IsValid()) then
			local glitch = (math.floor(time * 10) % 67) < 2
			if (glitch ~= last_glitch) then
				last_glitch = glitch
				sign:SetColor(glitch and BULB * 0.12 or BULB)
			end
		end
		if (step == last_step) then return end
		last_step = step
		for _, fb in ipairs(frame_bulbs) do
			if (fb.mesh:IsValid()) then
				local on = ((fb.i + step) % 4) ~= 0
				fb.mesh:SetMaterialColorParameter("Emissive", BULB * (on and 8 or 0.4))
			end
		end
	end)

	-- Anzeigetafel unter der Leuchtschrift: wann die naechste Show beginnt (Daten vom Server, siehe Hub.SetLobby)
	local board_at = sign_at + Vector(-4, 0, -150)
	Builder.Box(list, board_at + Vector(12, 0, 0), Vector(6, 820, 100), { color = Color(0.03, 0.015, 0.015), roughness = 0.8 })
	for _, dz in ipairs({ -54, 54 }) do
		Builder.Box(list, board_at + Vector(10, 0, dz), Vector(8, 830, 6), { texture = "metal_brass", tiling = { 8, 1 }, roughness = 0.35 })
	end
	hub.board = TextRender(board_at, Rotator(0, 180, 0), Hub.BoardText(), 56, BULB,
		TextRenderRenderingType.Unlit, TextRenderHorizontalAlignment.Center, TextRenderVerticalAlignment.Center,
		"nanos-world::Font_BoldPixels_DistanceField", false)
	table.insert(list.entities, hub.board)
	hub.board_text = nil
	Builder.AddTicker(list, function(dt, time)
		if (not hub.board:IsValid()) then return false end
		local text = Hub.BoardText()
		if (text ~= hub.board_text) then
			hub.board_text = text
			hub.board:SetText(text)
		end
		-- im Countdown blinkt die Tafel in den letzten Sekunden
		local urgent = Hub.lobby and Hub.lobby.timer and Hub.SecondsLeft() <= 5
		local blink = (urgent and math.floor(time * 4) % 2 == 0) and true or false
		if (blink ~= hub.board_blink) then
			hub.board_blink = blink
			hub.board:SetColor(blink and Color(1, 0.25, 0.1) or BULB)
		end
	end)

	-- Jack als Statue in der Mitte auf einem Sockel: kompakt (Oberkoerper ragt aus der offenen Kiste, die Haende am Rand,
	-- kein Federturm), warm angestrahlt wie ein Denkmal bei Nacht: Schluessellicht schraeg von vorne oben (Richtung
	-- Gruft, von dort kommen die Spieler), zwei flackernde Fusslichter am Sockel, schwaches kaltes Mondlicht von oben
	local scale = 2.0
	Builder.Shape(list, "cylinder", c + Vector(0, 0, 40), Vector(520, 520, 80), { texture = "stone_wall", tiling = { 4, 0.5 }, collision = true })
	hub.jack = DeathBox.Jack.Build(list, c + Vector(0, 0, 80), scale, 180)
	local head = c + Vector(0, 0, 80 + 320 * scale)
	local key_at = c + Vector(-1100, -420, 1250)
	Builder.Spot(list, key_at, WARM_KEY, 140, 2800, 15, { rotation = Builder.LookAt(key_at, head) })
	for _, sy in ipairs({ 1, -1 }) do
		Builder.Light(list, c + Vector(-300, sy * 170, 110), ORANGE, 2.5, 800, { flicker = 0.3 })
	end
	Builder.Spot(list, c + Vector(-200, 0, 1400), Color(0.75, 0.8, 1.0), 22, 2000, 18, { rotation = Rotator(-80, 0, 0), shadows = false })   -- nur Fuelllicht: ohne Schatten

	-- Jack dreht sich langsam und schaut sich um; ab und zu lacht er
	hub.next_turn = 0
	Builder.AddTicker(list, function(dt, time)
		if (time > hub.next_turn) then
			hub.next_turn = time + 5 + math.random() * 4
			local yaw = (hub.jack.yaw + 60 + math.random() * 120) % 360
			DeathBox.Jack.PointTo(hub.jack, yaw, 2.5)
			if (math.random() < 0.3) then
				DeathBox.Jack.Laugh(hub.jack, 1.4)
				DeathBox.Audio.Play3D("laugh", head, 0.6, 0.8 + math.random() * 0.2, 6000)
			end
		end
	end)

	-- Geister schweben auf und ab und kreisen langsam
	local ghosts = {}
	for i = 1, 6 do
		local angle = i * 60
		local ghost = Builder.Mesh(list, Builder.OnCircle(c, angle, 1400, 260), Rotator(0, angle + 90, 0), "ghost",
			{ scale = Vector(1.9, 1.9, 1.9), color = Color(0.7, 0.85, 1.0), emissive = Color(0.2, 0.4, 0.6) * 0.35 })   -- sonst weisse Kleckse (Belichtung x4,7)
		table.insert(ghosts, { mesh = ghost, angle = angle, seed = i * 1.7 })
	end
	Builder.AddTicker(list, function(dt, time)
		for _, g in ipairs(ghosts) do
			if (g.mesh:IsValid()) then
				local angle = g.angle + time * 4
				g.mesh:SetLocation(Builder.OnCircle(c, angle, 1400 + math.sin(time * 0.3 + g.seed) * 150,
					240 + math.sin(time * 1.1 + g.seed) * 80))
				g.mesh:SetRotation(Rotator(0, angle + 90, math.sin(time * 0.9 + g.seed) * 8))
			end
		end
	end)

	-- Bodennebel
	for i = 1, 4 do
		Builder.Particle(list, Builder.OnCircle(c, i * 90 + 45, 900, 20), "smoke", Vector(3, 3, 1))   -- Skalierung 4 kostete viel transparente Ueberzeichnung
	end

	return hub
end
