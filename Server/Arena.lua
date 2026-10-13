-- Server/Arena.lua
-- Baut eine leere Flaeche hoch ueber der Map: Boden, vier Waende, ein Tisch und Stuehle.
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
	BuildFloorAndWalls()
	BuildTableAndChairs()
	Arena.built = true
	Console.Log("[DeathBox] Arena gebaut: %d Objekte, %d Stuehle", #Arena.meshes, #Arena.chairs)
end

-- Zufaelliger Spawnpunkt im Raum, mit Abstand zu Waenden und Tisch
function Arena.GetSpawnLocation()
	local angle = math.random() * 360
	local max_radius = Cfg.FLOOR_SIZE / 2 - 150
	local radius = Cfg.PLAYER_RADIUS + 150 + math.random() * (max_radius - Cfg.PLAYER_RADIUS - 150)
	return PointOnCircle(angle, radius, 100), Rotator(0, angle + 180, 0)
end

-- Welcher Stuhl gehoert zu Platz seat_index, wenn nur seat_count Plaetze besetzt sind?
-- Verteilt die Spieler gleichmaessig um den Tisch, statt sie nebeneinander zu setzen.
function Arena.GetChairIndex(seat_index, seat_count)
	local count = #Arena.chairs
	return math.floor((seat_index - 1) * count / seat_count) + 1
end

-- Position und Blickrichtung fuer einen Spieler an seinem Platz (steht hinter dem Stuhl)
function Arena.GetSeatTransform(seat_index, seat_count)
	local chair = Arena.chairs[Arena.GetChairIndex(seat_index, seat_count)]
	local location = PointOnCircle(chair.angle, Cfg.PLAYER_RADIUS, 100)
	return location, Rotator(0, chair.yaw, 0)
end
