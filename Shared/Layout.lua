-- Shared/Layout.lua
-- Geometrie, die Server UND Client exakt gleich berechnen muessen:
-- wo die Stuehle stehen, wo eine Figur sitzt, wo Zuschauer stehen, wo der Hub-Spawn ist.
--
-- Der Server setzt die Figuren an diese Punkte, der Client baut die Stuehle an dieselben Punkte.
-- Weil beide dieselbe Funktion benutzen, passt beides immer zusammen.

DeathBox.Layout = {}

local Layout = DeathBox.Layout
local Cfg = DeathBox.Config.WORLD

local function OnCircle(center, angle_deg, radius, z_offset)
	local rad = math.rad(angle_deg)
	return center + Vector(math.cos(rad) * radius, math.sin(rad) * radius, z_offset or 0)
end
Layout.OnCircle = OnCircle

-- Radius des Stuhlkreises: waechst mit der Zahl der Plaetze (ca. 1 m Platz pro Stuhl)
function Layout.ChairRadius(seat_count)
	return math.max(Cfg.CHAIR_MIN_RADIUS, seat_count * Cfg.CHAIR_SPACING / (2 * math.pi))
end

-- Winkel eines Stuhls (Grad). Stuhl 1 bei 0 Grad, danach gegen den Uhrzeigersinn (von oben gesehen).
function Layout.ChairAngle(chair_index, seat_count)
	return (chair_index - 1) * 360 / seat_count
end

-- Blickrichtung vom Stuhl zur Mitte
function Layout.FaceCenterYaw(chair_index, seat_count)
	return (Layout.ChairAngle(chair_index, seat_count) + 180) % 360
end

-- Position und Drehung des Stuhl-Modells
function Layout.ChairTransform(chair_index, seat_count)
	local angle = Layout.ChairAngle(chair_index, seat_count)
	local location = OnCircle(Cfg.SHOW_CENTER, angle, Layout.ChairRadius(seat_count))
	return location, Rotator(0, Layout.FaceCenterYaw(chair_index, seat_count) + Cfg.CHAIR_YAW_OFFSET, 0)
end

-- Sitzposition einer Figur: Position, Drehung der Figur, Blickrichtung der Kamera (zur Mitte, leicht nach oben zu Jack).
-- Werte SIT_HEIGHT / SIT_FORWARD / SIT_YAW_OFFSET stammen aus dem Ingame-Test (v0.5.3).
function Layout.SitTransform(chair_index, seat_count)
	local angle = Layout.ChairAngle(chair_index, seat_count)
	local face = Layout.FaceCenterYaw(chair_index, seat_count)
	local location = OnCircle(Cfg.SHOW_CENTER, angle, Layout.ChairRadius(seat_count) - Cfg.SIT_FORWARD, Cfg.SIT_HEIGHT)
	-- Kamera leicht nach oben: Jacks Gesicht liegt von einem Sitz aus 25-36 Grad ueber Augenhoehe (Renderer-Befund 3)
	return location, Rotator(0, (face + Cfg.SIT_YAW_OFFSET) % 360, 0), Rotator(Cfg.SIT_CAMERA_PITCH or 12, face, 0)
end

-- Zuschauerplatz hinter dem eigenen Stuhl
function Layout.SpectatorTransform(chair_index, seat_count)
	local angle = Layout.ChairAngle(chair_index, seat_count)
	local location = OnCircle(Cfg.SHOW_CENTER, angle, Layout.ChairRadius(seat_count) + 260, 100)
	return location, Rotator(0, Layout.FaceCenterYaw(chair_index, seat_count), 0)
end

-- Spawn in der Gruft des Hubs (zufaellig verteilt, damit niemand ineinander spawnt)
function Layout.HubSpawn()
	local crypt = Cfg.HUB_CENTER + Vector(-(Cfg.HUB_SIZE / 2) - Cfg.CRYPT_SIZE / 2, 0, 0)
	local x = (math.random() - 0.5) * (Cfg.CRYPT_SIZE - 300)
	local y = (math.random() - 0.5) * (Cfg.CRYPT_SIZE - 400)
	return crypt + Vector(x, y, 100), Rotator(0, 0, 0)
end
