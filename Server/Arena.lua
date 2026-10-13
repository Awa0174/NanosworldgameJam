-- Server/Arena.lua
-- Baut eine leere Flaeche hoch ueber der Map: Boden, vier Waende, ein Tisch und Stuehle,
-- und liefert die Sitzpositionen fuer die Spieler.
-- So ist es egal, welche Map der Server laedt. Alles wird beim Entladen des Packages
-- automatisch entfernt (auto_cleanup = true in der Package.toml).
--
-- Koordinaten in nanos world / Unreal: X = vorne, Y = rechts, Z = oben, Einheit = Zentimeter.
-- Yaw (Drehung um Z) waechst von oben gesehen im Uhrzeigersinn.

DeathBox.Arena = {
	built = false,
	meshes = {},
	chairs = {},   -- { location = Vector, yaw = Zahl } pro Stuhl, Index = Platznummer
}

local Arena = DeathBox.Arena
local Cfg = DeathBox.Config.ARENA

-- Prueft beim Laden, ob alle noetigen Einstellungen in Shared/Config.lua stehen.
-- Fehlt etwas (z. B. weil eine alte Config.lua behalten wurde), gibt es eine klare Meldung
-- statt eines Absturzes mitten im Aufbau.
local REQUIRED_SETTINGS = {
	"CENTER", "FLOOR_SIZE", "FLOOR_THICKNESS", "WALL_HEIGHT", "WALL_THICKNESS", "FLOOR_COLOR", "WALL_COLOR",
	"TABLE_MESH", "TABLE_SCALE", "CHAIR_MESH", "CHAIR_RADIUS", "CHAIR_YAW_OFFSET",
	"SIT_ANIMATION", "SIT_HEIGHT", "SIT_FORWARD",
}

local function ValidateConfig()
	local missing = {}
	for _, key in ipairs(REQUIRED_SETTINGS) do
		if (Cfg[key] == nil) then
			table.insert(missing, key)
		end
	end
	if (#missing > 0) then
		Console.Error("[DeathBox] In Shared/Config.lua fehlen unter ARENA: %s – ist die Config.lua veraltet?", table.concat(missing, ", "))
		return false
	end
	return true
end

-- SM_Cube ist 100 x 100 x 100 cm gross. Mit SetScale wird daraus jede Quaderform.
local CUBE_SIZE = 100

local function SpawnBox(center, size, color)
	local mesh = StaticMesh(center, Rotator(), "nanos-world::SM_Cube")
	mesh:SetScale(Vector(size.X / CUBE_SIZE, size.Y / CUBE_SIZE, size.Z / CUBE_SIZE))
	mesh:SetMaterial("nanos-world::M_Default_Masked_Lit")
	mesh:SetMaterialColorParameter("Tint", color)
	table.insert(Arena.meshes, mesh)
	return mesh
end

-- Punkt auf einem Kreis um die Tischmitte. Winkel in Grad, 0 = in +X-Richtung.
local function PointOnCircle(angle_deg, radius, z_offset)
	local rad = math.rad(angle_deg)
	return Cfg.CENTER + Vector(math.cos(rad) * radius, math.sin(rad) * radius, z_offset or 0)
end

local function BuildFloorAndWalls()
	local c = Cfg.CENTER
	local size = Cfg.FLOOR_SIZE
	local half = size / 2
	local wall_z = c.Z + Cfg.WALL_HEIGHT / 2
	local t = Cfg.WALL_THICKNESS

	-- Boden: Oberkante liegt genau auf CENTER.Z
	SpawnBox(c - Vector(0, 0, Cfg.FLOOR_THICKNESS / 2), Vector(size, size, Cfg.FLOOR_THICKNESS), Cfg.FLOOR_COLOR)

	-- Waende: Nord, Sued, Ost, West
	SpawnBox(Vector(c.X + half, c.Y, wall_z), Vector(t, size, Cfg.WALL_HEIGHT), Cfg.WALL_COLOR)
	SpawnBox(Vector(c.X - half, c.Y, wall_z), Vector(t, size, Cfg.WALL_HEIGHT), Cfg.WALL_COLOR)
	SpawnBox(Vector(c.X, c.Y + half, wall_z), Vector(size, t, Cfg.WALL_HEIGHT), Cfg.WALL_COLOR)
	SpawnBox(Vector(c.X, c.Y - half, wall_z), Vector(size, t, Cfg.WALL_HEIGHT), Cfg.WALL_COLOR)
end

local function BuildTableAndChairs()
	local table_mesh = StaticMesh(Cfg.CENTER, Rotator(), Cfg.TABLE_MESH)
	table_mesh:SetScale(Cfg.TABLE_SCALE)
	table.insert(Arena.meshes, table_mesh)

	local count = DeathBox.Config.MAX_PLAYERS
	for i = 1, count do
		-- Platz 1 bei 0 Grad, danach im Uhrzeigersinn
		local angle = (i - 1) * 360 / count
		local location = PointOnCircle(angle, Cfg.CHAIR_RADIUS)
		local face_table_yaw = (angle + 180) % 360   -- vom Stuhl aus zur Tischmitte schauen

		local chair = StaticMesh(location, Rotator(0, face_table_yaw + Cfg.CHAIR_YAW_OFFSET, 0), Cfg.CHAIR_MESH)
		table.insert(Arena.meshes, chair)
		Arena.chairs[i] = { angle = angle, yaw = face_table_yaw }
	end
end

function Arena.Build()
	if (Arena.built) then return end
	if (not ValidateConfig()) then return end
	BuildFloorAndWalls()
	BuildTableAndChairs()
	Arena.built = true
	Console.Log("[DeathBox] Arena gebaut: %d Objekte, %d Stuehle", #Arena.meshes, #Arena.chairs)
end

-- Zufaelliger Spawnpunkt im Raum, mit Abstand zu Waenden und Tisch
function Arena.GetSpawnLocation()
	local angle = math.random() * 360
	local max_radius = Cfg.FLOOR_SIZE / 2 - 150
	local min_radius = Cfg.CHAIR_RADIUS + 150
	local radius = min_radius + math.random() * (max_radius - min_radius)
	return PointOnCircle(angle, radius, 100), Rotator(0, angle + 180, 0)
end

-- Welcher Stuhl gehoert zu Platz seat_index, wenn nur seat_count Plaetze besetzt sind?
-- Verteilt die Spieler gleichmaessig um den Tisch, statt sie nebeneinander zu setzen.
function Arena.GetChairIndex(seat_index, seat_count)
	local count = #Arena.chairs
	return math.floor((seat_index - 1) * count / seat_count) + 1
end

-- Sitzposition und Blickrichtung fuer einen bestimmten Stuhl (1 bis MAX_PLAYERS).
-- Wird bei jedem Aufruf neu berechnet, damit /sitpos live wirkt.
function Arena.GetChairSitTransform(chair_index)
	local chair = Arena.chairs[chair_index]
	local radius = Cfg.CHAIR_RADIUS - Cfg.SIT_FORWARD
	local location = PointOnCircle(chair.angle, radius, Cfg.SIT_HEIGHT)
	return location, Rotator(0, chair.yaw, 0)
end

-- Naechster Stuhl zu einer Position (fuer /sit im Testmodus)
function Arena.GetNearestChairIndex(location)
	local best_index, best_dist = 1, math.huge
	for index, chair in ipairs(Arena.chairs) do
		local chair_location = PointOnCircle(chair.angle, Cfg.CHAIR_RADIUS)
		local dx, dy = chair_location.X - location.X, chair_location.Y - location.Y
		local dist = dx * dx + dy * dy
		if (dist < best_dist) then
			best_index, best_dist = index, dist
		end
	end
	return best_index
end
