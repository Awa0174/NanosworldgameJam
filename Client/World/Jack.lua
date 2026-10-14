-- Client/World/Jack.lua
-- Jack 4 – der alte Jahrmarkts-Animatronic in der Kiste. Lokal beim Client gebaut und Bild fuer Bild animiert.
--
-- Aufbau (nur Grundformen + eigene Texturen. KEINE flachen Bildflaechen im Gesicht: die alte Masken-Ebene war im Spiel
-- unsichtbar. Jedes Gesichtsteil ist ein eigener Koerper und liest sich von vorne, schraeg und von der Seite):
--   Drehteller (Messing) -> Kiste ("box_root", dreht sich beim Auswaehlen), Klappdeckel mit rotem Samtfutter ("lid",
--   oeffnet hoechstens LID_STOP Grad und steht dann schraeg hinter der Kiste, liegt nie auf dem Boden), Kurbel
--   Rostige Feder aus Ringen zwischen Kistenboden und Rumpf (steckt in der Kiste, sichtbar erst beim Herausschiessen)
--   Rumpf ("root"): hagerer V-Oberkoerper im geflickten Streifenkostuem, Zackenkragen, Messing-Schultern, lange duenne
--   Arme mit schmutzig-weissen Handschuhen und vier Stahlkrallen. Die Haende greifen per IK den vorderen Kistenrand
--   (Krallen haengen ueber die Kante) oder das Gesicht des Opfers, egal wie hoch Jack gerade steht.
--   Teleskop-Hals: faehrt den Kopf ein (Gucken ueber den Rand, in der Kiste) und aus (POP)
--   Kopf ("head"): Porzellan-Ei mit Rissen, tiefe schwarze Augenhoehlen mit gluehend roten Pupillen und Lidern
--   (blinzeln, halb zu beim Starren), schwarze Brauen (Stimmung), rote Nase, Wangen, Schnauze mit rotem Grinsen und
--   zwei Reihen Zaehnen, Kinnlade ("jaw") klappt und klappert, Haarbueschel aus Kegeln, schiefer Zylinder
--
-- Choreografie (gesteuert von Client/Presentation.lua):
--   Spin()        Jack sinkt, bis nur Kopf, Krause und Schultern ueber den Rand gucken (Haende am Rand, gebeugt), und
--                 dreht sich langsam mit der Kiste. Searchlight(): roter Suchstrahl aus seinem Gesicht auf die Stuehle
--   Hold()        Starren: Kopf kippt langsam, Lider halb zu, Kiefer geht auf, rotes Licht von unten aus der Kiste
--                 (steckt er in der Kiste, z. B. im Intro, klappert stattdessen der Deckel)
--   Crouch()      kurzes Ducken direkt vor dem POP
--   PopOut(p)     Jack schiesst auf seiner Feder heraus und beugt sich ueber die Vorderkante: Stoss bis ca. 50 cm vor das
--                 Gesicht des Opfers, dann schwebt sein Gesicht ca. 1 m davor und lacht
--   Laugh / Disappointed / Aim / Throw / Retract / IntroPop / Present / PointTo / SetFace / SetEyeGlow
-- In Ruhe krallt er sich vorne an den Kistenrand, trommelt mit den Krallen und starrt JEDEN Spieler an
-- (der Kopf dreht sich wie bei einer Eule bis 150 Grad). Bewegungen sind bewusst "servo-artig": Gelenke springen in
-- kleinen Schritten (14 pro Sekunde) und zucken gelegentlich. Nichts faehrt je durch die Kistenwaende: vorbeugen und
-- nach vorne erst ueber dem Rand, zurueck in die Kiste erst nach dem Aufrichten.

DeathBox.Jack = {}

local Jack = DeathBox.Jack
local Builder = DeathBox.Builder

-- ------------------------------------------------------------------ Farben
local PORCELAIN = Color(0.96, 0.93, 0.88)       -- Tint auf der Porzellan-Textur
local LID_TINT = Color(0.9, 0.86, 0.82)         -- Augenlider: etwas dunkleres Porzellan
local CREAM = Color(0.86, 0.8, 0.66)
local RUFF_RED = Color(0.45, 0.03, 0.05)
local RED = Color(0.55, 0.03, 0.04)
local LIP = Color(0.62, 0.02, 0.05)
local ROUGE = Color(0.72, 0.1, 0.14)
local HAIR = { Color(0.55, 0.06, 0.03), Color(0.34, 0.02, 0.02), Color(0.72, 0.17, 0.04) }
local SOCKET = Color(0.012, 0.007, 0.009)
local BROW = Color(0.035, 0.02, 0.025)
local TOOTH = Color(0.88, 0.82, 0.64)
local HAT = Color(0.08, 0.045, 0.07)
local HAT_BAND = Color(0.5, 0.03, 0.05)
local EYE = Color(1, 0.06, 0.02)
local EYE_OFF = Color(0.06, 0.004, 0.002)        -- flackernde Pupille, kurz "aus"
local INNER = Color(1, 0.12, 0.05)
local CAVITY = Color(1, 0.08, 0.02)              -- Glimmen im Mund
local FACE_FILL = Color(1.0, 0.88, 0.76)         -- warmes Fuelllicht vor dem Gesicht (Porzellan bleibt im Dunkeln lesbar)
local SEARCH = Color(1, 0.08, 0.03)              -- Suchstrahl aus den Augen
local STEEL = Color(0.42, 0.4, 0.38)
local CLAW = Color(0.24, 0.24, 0.26)             -- Krallen: dunkler, angelaufener Stahl (glaenzt im Spot)
local GLOVE = Color(0.8, 0.76, 0.68)             -- schmutzig-weisse Clownshandschuhe

-- ------------------------------------------------------------------ Masse (cm bei Skalierung 1, alles * jack.scale)
local SERVO_STEP = 1 / 14      -- Gelenke aktualisieren sich in Schritten (ruckelt wie ein Animatronic)

-- Hoehen der Rumpfmitte ueber dem Drehteller-Boden. Vorfuehren: Huefte und Feder stecken in der Kiste, Oberkoerper,
-- Arme und Kopf sind draussen (kein Federturm, auch nicht bei der Statue im Hub). Gucken: nur Kopf, Krause und
-- Schultern ueber dem Rand (Kistenrand bei 165).
local PRESENT_U = 190
local PEEK_U = 128
local TRACK_MIN_U = 150        -- darueber verfolgt der Kopf in Ruhe die Kamera
local COLLAR = 64              -- Halsansatz ueber der Rumpfmitte
-- Teleskop-Hals: Kopf-Drehpunkt = COLLAR + neck ueber der Rumpfmitte
local NECK_PRESENT, NECK_PEEK, NECK_STARE, NECK_TUCK, NECK_POP = 16, 13, 22, 13, 56
local PLATE = 58               -- Federteller unter der Rumpfmitte (entlang der Koerperachse)
local HUNCH = 12               -- so weit beugt er sich beim Gucken nach vorne (Grad)
-- Gesichtsmitte (Nasenwurzel) im Kopf-Rahmen: Bezugspunkt fuer den POP (jack.mask)
local FACE_X, FACE_Z = 33, 47
-- POP in zwei Schlaegen: erst der Stoss (Gesicht LUNGE_GAP vor dem Auge des Opfers, knapp darueber), dann zieht er sich
-- zurueck und schwebt (Gesicht POP_GAP vor und POP_RISE ueber dem Auge: ca. 1 m). Gesicht POP_FACE Grad nach unten.
local POP_GAP, POP_RISE, POP_FACE = 92, 22, -13
local LUNGE_GAP, LUNGE_RISE = 50, 8
-- Federteller beim POP: hoechstens PLATE_IN_X vor der Mitte mind. PLATE_IN_Z hoch, sonst mind. PLATE_OUT_Z; die
-- Koerperachse kreuzt die Vorderkante (x = RIM_X) mind. RIM_CLEAR hoch (Rumpf ist 29 cm tief)
local PLATE_IN_X, PLATE_IN_Z, PLATE_OUT_Z = 55, 190, 212
local RIM_X, RIM_CLEAR = 92, 198
-- Rumpfhoehe, ab der Jack sich vorbeugen / nach vorne fahren darf (darunter steckt er noch im Kistenrand) und unter die
-- er erst sinkt, wenn er wieder aufrecht in der Mitte steht
local GATE_LO, GATE_HI = 160, 178
local ARMS_OUT_U = 150         -- POP aus der Kiste: die Arme bleiben angelegt, bis die Rumpfmitte so hoch ist
local HEAD_TILT = 6            -- Kopf haengt immer etwas schief (Roll, Grad)
local STARE_TILT = 22          -- beim Starren kippt er den Kopf langsam so weit
local TRACK_YAW = 150          -- so weit dreht er den Kopf zu dir (Eule)
local EYE_EMISSIVE = 13
local EYE_LIGHT_K = 0.012      -- SetEyeGlow-Wert -> rotes Licht unter dem Gesicht (Kiefer, Kragen, Krallen)
local FACE_LIGHT = 0.3         -- Fuelllicht 1 m vor und etwas ueber dem Gesicht
local SEARCH_LIGHT = 26        -- Suchstrahl (Spot, schmal), beim Starren heller
local SEARCH_CONE = 6.5

-- Eingefahren (Intro, Vorhang): Rumpfmitte so tief unter dem Drehteller-Boden, dass Kopf, Haare und Hut ganz unter
-- dem geschlossenen Deckel stecken; Rumpf und Arme verschwinden im Buehnenboden.
local RETRACT_U = -52
-- Deckel (Kistenrahmen): Scharnier hinten bei x = -86, Unterkante (Samtfutter) bei z = 161. Offen steht er schraeg
-- hinter der Kiste (hoechstens LID_STOP Grad, schlaegt dort an und federt zurueck)
local LID_HINGE_X, LID_UNDERSIDE = -86, 161
local LID_OPEN, LID_STOP = 106, 110
-- Hoechste Punkte der Figur (x = nach vorne, z = hoch) in der eingefahrenen Haltung (Arme angelegt, Kopf gerade,
-- Hals ganz drin), plus Reserve; head = true: Punkt sitzt am Kopf und faehrt mit dem Hals mit. Als Treppe vereinfacht
-- (jeder Punkt liegt hoeher und weiter hinten als die Huelle). Der Deckel bleibt immer ueber diesen Punkten.
-- Neu berechnen: work_jack/figure_top4.lua <pkg> (Huelle, Hut 201 cm ueber der Rumpfmitte -> RETRACT_U < -45)
local FIGURE_TOP = {
	{ x = -62, z = 145, head = true }, { x = -57, z = 182, head = true }, { x = -54, z = 189, head = true },
	{ x = -50, z = 193, head = true }, { x = -42, z = 198, head = true }, { x = -32, z = 202, head = true },
	{ x = -18, z = 205, head = true }, { x = 4, z = 205, head = true },
	{ x = -52, z = 59 }, { x = -14, z = 82 },
}

-- Arm (Rumpf-Rahmen): Schulter, Oberarm bis Ellbogen, Unterarm bis Handmitte, Knoechel 6 cm unter der Handmitte
local SH_Y, SH_Z = 50, 40
local UPPER, FORE = 74, 76
-- Haende am vorderen Kistenrand: Handmitte bei x = RIM_HAND_X (ueber der Vorderkante), z = RIM_HAND_Z (knapp ueber
-- dem Rahmen, Oberkante 165), Krallen haengen aussen an der Vorderwand herab
local RIM_HAND_X, RIM_HAND_Z = 94, 178.5
-- Krallen im Knoechel-Rahmen (zeigen nach unten, nebeneinander gespreizt; sy spiegelt): Spreizung (Grad), Laenge (cm)
local CLAW_SPREAD = { -22, -7, 7, 22 }
local CLAW_LEN = { 36, 44, 44, 38 }
local CLAW_HOOK = math.tan(math.rad(8))       -- leicht zur Handflaeche gekruemmt

local FINGERS_STRAIGHT = Rotator(0, 0, 0)
local FINGERS_FIST = Rotator(-150, 0, 0)       -- nach hinten unter den Griff geklappt (Revolver, Bewegung)

-- Drehprofil beim Auswaehlen (Anteil der Strecke ueber Anteil der Zeit): sanft anfahren (bis SPIN_A), gleichmaessig
-- drehen (bis SPIN_B), dann langes Auskriechen (Geschwindigkeit faellt mit Potenz SPIN_K). Passt zum Ritardando der
-- Spieluhr; die letzten Stuehle kriechen vorbei.
local SPIN_A, SPIN_B, SPIN_K = 0.12, 0.5, 2.0
local SPIN_V = 1 / (SPIN_A / 2 + (SPIN_B - SPIN_A) + (1 - SPIN_B) / (SPIN_K + 1))

-- Stimmungen: Lider (0 = offen, 1 = zu), Brauen (Neigung in Grad, + = aussen hoch/innen runter = boese; Hub in cm),
-- Kiefer offen (Grad)
local MOODS = {
	idle  = { lid = 0.12, brow = 8,   lift = 0,    jaw = 0 },
	laugh = { lid = 0.42, brow = -16, lift = 2.2,  jaw = 17 },
	angry = { lid = 0.3,  brow = 30,  lift = -1.4, jaw = 9 },
	stare = { lid = 0.4,  brow = 20,  lift = -0.6, jaw = 0 },
	sad   = { lid = 0.5,  brow = -24, lift = 1.2,  jaw = 7 },
}

-- Lichter an Jack im Spiel nachstellen (Faktoren, Konsole: db_jacklight <suchstrahl> <kiste> <gesicht>)
Jack.light_k = { search = 1, inner = 1, face = 1 }

local atan2 = math.atan2 or math.atan
local function Clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function Now() return Builder.time end

local function AngleDelta(a, b)
	local d = (b - a) % 360
	if (d > 180) then d = d - 360 end
	return d
end

-- Achsen (Zeilen X', Y', Z') einer UE-Drehung: Welt = lokal * M
local function Rows(p, y, r)
	local P, Y, R = math.rad(p), math.rad(y), math.rad(r)
	local SP, CP, SY, CY, SR, CR = math.sin(P), math.cos(P), math.sin(Y), math.cos(Y), math.sin(R), math.cos(R)
	return CP * CY, CP * SY, SP,
		SR * SP * CY - CR * SY, SR * SP * SY + CR * CY, -SR * CP,
		-(CR * SP * CY + SR * SY), CY * SR - CR * SP * SY, CR * CP
end

-- Drehung aus drei Achsen (wie FMatrix::Rotator)
local function MatToRot(xx, xy, xz, yx, yy, yz, zx, zy, zz)
	local pitch = math.deg(atan2(xz, math.sqrt(xx * xx + xy * xy)))
	local yaw = math.deg(atan2(xy, xx))
	local ry = math.rad(yaw)
	local syx, syy = -math.sin(ry), math.cos(ry)
	local roll = math.deg(atan2(zx * syx + zy * syy, yx * syx + yy * syy))
	return pitch, yaw, roll
end

-- Drehung, deren lokale Z-Achse in Richtung (dx, dy, dz) zeigt (fuer Kegel/Zylinder entlang einer Richtung)
local function AxisRot(dx, dy, dz)
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	dx, dy, dz = dx / len, dy / len, dz / len
	local yaw = (math.abs(dx) + math.abs(dy) > 1e-6) and math.deg(atan2(-dy, -dx)) or 0
	return Rotator(math.deg(math.acos(Clamp(dz, -1, 1))), yaw, 0)
end

-- Drehung fuer einen flachen Koerper auf einer Oberflaeche: lokale Z-Achse = Normale n, lokale Y-Achse = Breite entlang
-- t (auf die Flaeche projiziert, dort um tilt Grad gedreht), lokale X-Achse = zweite Flaechenrichtung.
-- Liefert die Drehung und die "Hoch"-Richtung in der Flaeche (lokale -X-Achse).
local function SurfaceRot(nx, ny, nz, tx, ty, tz, tilt)
	local d = tx * nx + ty * ny + tz * nz
	tx, ty, tz = tx - d * nx, ty - d * ny, tz - d * nz
	local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
	tx, ty, tz = tx / tl, ty / tl, tz / tl
	local hx, hy, hz = ty * nz - tz * ny, tz * nx - tx * nz, tx * ny - ty * nx
	if (tilt and tilt ~= 0) then
		local c, sn = math.cos(math.rad(tilt)), math.sin(math.rad(tilt))
		tx, ty, tz, hx, hy, hz = tx * c + hx * sn, ty * c + hy * sn, tz * c + hz * sn, hx * c - tx * sn, hy * c - ty * sn, hz * c - tz * sn
	end
	return Rotator(MatToRot(hx, hy, hz, tx, ty, tz, nx, ny, nz)), hx, hy, hz
end

-- Feder-Daempfer: zieht value zu target. k = Steifigkeit, c = Daempfung
local function SpringStep(s, target, k, c, dt)
	local a = k * (target - s.v) - c * s.vel
	s.vel = s.vel + a * dt
	s.v = s.v + s.vel * dt
end

-- Servo-Gelenk: faehrt mit begrenzter Geschwindigkeit, zeigt sich nur in Schritten
local function Servo(speed, value)
	return { cur = value or 0, target = value or 0, shown = value or 0, speed = speed or 240 }
end

local function ServoStep(j, dt, stepping, jitter)
	local d = j.target - j.cur
	local max = j.speed * dt
	j.cur = j.cur + Clamp(d, -max, max)
	if (stepping) then j.shown = j.cur + (math.random() - 0.5) * (jitter or 1.2) end
end

local function Arm()
	return { sp = Servo(320), ya = Servo(280), sr = Servo(280), el = Servo(320) }
end

-- Fester Zufall (jeder Spieler sieht denselben Jack)
local function Random(seed)
	local state = seed
	return function(a, b)
		state = (state * 16807) % 2147483647
		local v = state / 2147483647
		if (a and b) then return a + v * (b - a) end
		return v
	end
end

local function SpinEase(p)
	if (p <= 0) then return 0 end
	if (p >= 1) then return 1 end
	if (p < SPIN_A) then
		local t = p / SPIN_A
		return SPIN_V * SPIN_A * (t * t * t - t * t * t * t / 2)
	elseif (p <= SPIN_B) then
		return SPIN_V * (SPIN_A / 2 + (p - SPIN_A))
	end
	local q = (1 - p) / (1 - SPIN_B)
	return SPIN_V * (SPIN_A / 2 + (SPIN_B - SPIN_A) + (1 - SPIN_B) / (SPIN_K + 1) * (1 - q ^ (SPIN_K + 1)))
end

-- Vorbeugen haengt fest am Vorfahren (cm bei Skalierung 1 -> Grad), damit Teller, Huefte und Feder nie vor die Kiste
-- unter den Rand geraten. Kurve = Stuetzpunkte { f1, l1, f2, l2, ... } (f aufsteigend): bis LEAN_DEAD aufrecht,
-- dazwischen linear, danach flach. Ohne POP: bis 35 Grad.
local LEAN_DEAD = 12
local LEAN_DEFAULT = { 105, 35 }
local function LeanOf(curve, f)
	if (f <= LEAN_DEAD) then return 0 end
	local pf, pl = LEAN_DEAD, 0
	for i = 1, #curve, 2 do
		local cf, cl = curve[i], curve[i + 1]
		if (f <= cf) then return pl + (cl - pl) * (f - pf) / math.max(0.001, cf - pf) end
		pf, pl = cf, cl
	end
	return pl
end

-- Ziel-Federn: neues Ziel, das die Vorbeuge-Kurve des alten Ziels uebernimmt (so richtet sich Jack beim Zurueckfahren
-- genau so auf, wie er sich beim POP vorgebeugt hat)
local function Target(jack, f, u, k, c)
	local old = jack.ext_target
	return { f = f, u = u, k = k, c = c, lean = old and old.lean }
end

-- POP-Haltung (cm bei Skalierung 1): Feder steigt aus der Kiste auf, der Rumpf beugt sich ueber die Vorderkante, das
-- Gesicht schaut mit POP_FACE aufs Opfer und endet gap vor / rise ueber seinem Auge. dist = waagerechter Abstand zum
-- Opfer, eye_z = seine Augenhoehe. Liefert Vorbeugen (Grad, > 90 = Kopf tiefer als der Teller) und das Ziel der
-- Rumpfmitte (f vor, u hoch). Die Koerperachse (Teller -> Kopf) kreuzt die Vorderkante hoch genug.
local function PopPose(dist, eye_z, gap, rise)
	local mx, mz = dist - gap, eye_z + rise
	local fr = math.rad(POP_FACE)
	local hx, hz = FACE_X * math.cos(fr) - FACE_Z * math.sin(fr), FACE_X * math.sin(fr) + FACE_Z * math.cos(fr)
	local reach = PLATE + COLLAR + NECK_POP
	local kx, kz = mx - hx, mz - hz                     -- Kopf-Drehpunkt
	local best_err, best_l, best_px, best_pz = math.huge, 110, 0, PLATE_IN_Z
	for l = 80, 142, 2 do
		local sl, cl = math.sin(math.rad(l)), math.cos(math.rad(l))
		local px, pz = kx - reach * sl, kz - reach * cl
		local min_z = (px <= PLATE_IN_X) and PLATE_IN_Z or PLATE_OUT_Z
		local err = math.max(0, min_z - pz)
		if (px < RIM_X and kx > RIM_X) then
			local zr = pz + (kz - pz) * (RIM_X - px) / (kx - px)
			err = err + math.max(0, RIM_CLEAR - zr)
		end
		if (err < best_err - 0.001) then best_err, best_l, best_px, best_pz = err, l, px, math.max(pz, min_z) end
	end
	local sl, cl = math.sin(math.rad(best_l)), math.cos(math.rad(best_l))
	return best_l, best_px + PLATE * sl, best_pz + PLATE * cl
end

-- ===================================================================
-- Kopf-Geometrie (Kopf-Rahmen: x = vorne, y = Jacks rechte Seite, z = hoch, Ursprung = Hals-Drehpunkt)
-- ===================================================================

-- Ellipsoid { Mitte x, y, z, Halbachsen x, y, z }
local function Ell(cx, cy, cz, sx, sy, sz) return { cx, cy, cz, sx / 2, sy / 2, sz / 2, size = { sx, sy, sz } } end
local DOME = Ell(-2, 0, 50, 64, 68, 74)        -- Porzellan-Ei
local MUZZLE = Ell(18, 0, 34, 36, 54, 22)      -- Schnauze (Oberlippe, Wangen)
local MOUTH = Ell(13, 0, 20, 30, 44, 22)       -- dunkle Mundhoehle hinter den Zaehnen
local JAW = Ell(13, 0, 11, 36, 48, 18)         -- Kinnlade (geschlossen)
local JAW_HINGE = { -6, 0, 20 }
local EYES = { { y = 12.5, z = 53, side = 1 }, { y = -12.5, z = 53, side = -1 } }

-- Vorderseite eines Ellipsoids bei (y, z): x und Normale (nil, wenn (y, z) ausserhalb liegt)
local function Front(e, y, z)
	local dy, dz = (y - e[2]) / e[5], (z - e[3]) / e[6]
	local q = 1 - dy * dy - dz * dz
	if (q <= 0) then return nil end
	local dx = math.sqrt(q)
	local nx, ny, nz = dx / e[4], dy / e[5], dz / e[6]
	local n = math.sqrt(nx * nx + ny * ny + nz * nz)
	return e[1] + e[4] * dx, nx / n, ny / n, nz / n
end

-- vorderster Oberflaechenpunkt mehrerer Koerper
local function FrontOf(bodies, y, z)
	local bx, bnx, bny, bnz
	for _, e in ipairs(bodies) do
		local x, nx, ny, nz = Front(e, y, z)
		if (x and (not bx or x > bx)) then bx, bnx, bny, bnz = x, nx, ny, nz end
	end
	return bx, bnx, bny, bnz
end

local FACE_BODIES = { DOME, MUZZLE }

-- ===================================================================
-- Aufbau
-- ===================================================================

function Jack.Build(list, center, scale, yaw)
	local s = scale or 1
	local V = function(x, y, z) return Vector(x * s, y * s, z * s) end
	local at = function(x, y, z) return center + V(x, y, z) end
	local rnd = Random(4242)

	local jack = {
		list = list, center = center, scale = s,
		yaw = yaw or 0,                       -- wohin die Kiste (und Jack) zeigt
		anims = {}, face = "idle", mood = MOODS.idle,
		lid = { v = LID_OPEN, vel = 0 }, lid_target = LID_OPEN,
		ext_f = { v = 0, vel = 0 }, ext_u = { v = PRESENT_U * s, vel = 0 },   -- Rumpf: vor (f) und hoch (u) relativ zur Kiste
		ext_target = { f = 0, u = PRESENT_U * s, k = 40, c = 12 },
		neck = Servo(150, NECK_PRESENT), neck_shown = -1,
		hunch = { v = 0, vel = 0 }, peek = false, stare = false, crouch_until = 0,
		head_yaw = Servo(260), head_pitch = Servo(200), head_roll = Servo(160), jaw = Servo(420),
		arm = { l = Arm(), r = Arm() },
		lean = { v = 0, vel = 0 }, pitch = 0, roll = 0,
		pose = nil,   -- Grundhaltung der Gelenke (siehe Jack.SetPose)
		next_step = 0, next_twitch = 2, rattle = false, inner_glow = 0, inner_shown = -1,
		jaw_mood = 0, tucked = false, servo_boost_until = 0,
		next_tap = 3, tap_t0 = -10, tap_side = 1, next_flicker = 4, flicker_until = 0,
		next_blink = 2.5, blink_until = 0, lids = Servo(9, 0.12), lids_shown = -1,
		brow = Servo(120, 8), brow_lift = Servo(14, 0), brow_shown = -999,
		eye_glow = 1.5, lid_shown = -999, yaw_shown = -999, spring = { 0, 0, -1e9 }, arm_err = 0,
		search = { on = false, k = 0, shown = -1, dist = 330 * s, z = 145 * s },
	}
	local l, r = jack.arm.l, jack.arm.r
	jack.servos = { jack.head_yaw, jack.head_pitch, jack.head_roll, jack.jaw,
		l.sp, l.ya, l.sr, l.el, r.sp, r.ya, r.sr, r.el }

	local brass = { texture = "metal_brass", roughness = 0.3 }
	local rust = { texture = "metal_rust", roughness = 0.55 }
	local costume = { texture = "jack_costume", tiling = { 2, 1 }, roughness = 0.85 }
	local porcelain = { texture = "jack_porcelain_cracked", tiling = { 2, 2 }, color = PORCELAIN, roughness = 0.32 }

	-- Drehteller
	Builder.Shape(list, "cylinder", at(0, 0, 5), V(240, 240, 10), { texture = "metal_brass", tiling = { 2, 2 }, roughness = 0.35, collision = true })

	-- Kiste: Drehpunkt + Waende (oben offen), Boden, Messingkanten, Kurbel, Deckel, rotes Innenlicht
	jack.box_root = Builder.Mesh(list, center, Rotator(), "nanos-world::SM_None")
	local function BoxPart(mesh) Builder.Attach(mesh, jack.box_root) return mesh end
	local wall = { texture = "box_harlequin", roughness = 0.75, collision = true }
	BoxPart(Builder.Box(list, at(80, 0, 85), V(10, 170, 150), wall))
	BoxPart(Builder.Box(list, at(-80, 0, 85), V(10, 170, 150), wall))
	BoxPart(Builder.Box(list, at(0, 80, 85), V(150, 10, 150), wall))     -- Seitenwaende zwischen Vorder- und Rueckwand
	BoxPart(Builder.Box(list, at(0, -80, 85), V(150, 10, 150), wall))    -- (keine deckungsgleichen Flaechen an den Ecken)
	BoxPart(Builder.Box(list, at(0, 0, 14), V(160, 160, 6), { color = Color(0.05, 0.01, 0.01), roughness = 1 }))
	local post = { texture = "metal_brass", tiling = { 1, 4 }, roughness = 0.3 }
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		BoxPart(Builder.Box(list, at(c[1] * 86, c[2] * 86, 85), V(12, 12, 152), post))
	end
	-- Rahmen: vorne/hinten durchgehend (enden in den Eckpfosten), seitlich nur dazwischen (keine doppelten Flaechen)
	BoxPart(Builder.Box(list, at(86, 0, 161), V(8, 182, 8), post))
	BoxPart(Builder.Box(list, at(-86, 0, 161), V(8, 182, 8), post))
	BoxPart(Builder.Box(list, at(0, 86, 161), V(164, 8, 8), post))
	BoxPart(Builder.Box(list, at(0, -86, 161), V(164, 8, 8), post))

	-- Kurbel an der Seite (+Y)
	jack.crank = BoxPart(Builder.Mesh(list, at(0, 94, 92), Rotator(0, 0, 90), "nanos-world::SM_None"))
	local axle = Builder.Shape(list, "cylinder", at(0, 100, 92), V(10, 10, 16), { rotation = Rotator(0, 0, 90), texture = "metal_brass" })
	local handle = Builder.Box(list, at(0, 108, 114), V(8, 8, 48), { texture = "metal_brass" })
	local knob = Builder.Shape(list, "sphere", at(0, 116, 138), V(17, 17, 17), { color = RED, roughness = 0.4 })
	for _, m in ipairs({ axle, handle, knob }) do Builder.Attach(m, jack.crank) end
	jack.crank_angle = 0

	-- Deckel: Scharnier an der Hinterkante (-X), steht offen schraeg hinter der Kiste; innen rotes Samtfutter
	jack.lid_pivot = BoxPart(Builder.Mesh(list, at(-86, 0, 164), Rotator(), "nanos-world::SM_None"))
	for _, m in ipairs({
		Builder.Box(list, at(2, 0, 172), V(178, 178, 14), { texture = "box_lid", roughness = 0.6 }),
		Builder.Box(list, at(2, 0, 164), V(182, 182, 3), post),
		Builder.Box(list, at(0, 0, 161.75), V(148, 148, 1.5), { texture = "velvet_red", roughness = 1 }),
	}) do Builder.Attach(m, jack.lid_pivot) end

	-- Rotes Licht in der Kiste: dringt im Intro durch den Spalt, beim Gucken/Starren beleuchtet es Jack von unten
	jack.inner_light = BoxPart(Builder.Light(list, at(34, 0, 142), INNER, 0, 165 * s))

	-- Rumpf-Drehpunkt (wird jedes Bild frei positioniert, haengt NICHT an der Kiste)
	jack.root = Builder.Mesh(list, at(0, 0, PRESENT_U), Rotator(), "nanos-world::SM_None")
	local function Part(mesh, parent) Builder.Attach(mesh, parent or jack.root) return mesh end
	local root_at = function(x, y, z) return at(x, y, PRESENT_U + z) end

	-- Rumpf: hagerer V-Oberkoerper (Kegel, Spitze nach unten) im geflickten Streifenkostuem, kleine Huefte,
	-- Federteller, zwei ungleiche Knoepfe
	Part(Builder.Shape(list, "cone", root_at(0, 0, 12), V(58, 86, 100), { rotation = Rotator(180, 0, 0), texture = "jack_costume", tiling = { 3, 1 }, roughness = 0.85 }))
	Part(Builder.Shape(list, "sphere", root_at(0, 0, -36), V(40, 46, 36), { texture = "jack_costume", tiling = { 2, 1 }, color = Color(0.55, 0.55, 0.55), roughness = 0.9 }))
	Part(Builder.Shape(list, "cylinder", root_at(0, 0, -54), V(34, 34, 8), brass))
	Part(Builder.Shape(list, "sphere", root_at(22, 3, 36), V(10, 10, 10), brass))
	Part(Builder.Shape(list, "sphere", root_at(14, -3, 20), V(10, 10, 10), { color = RED, roughness = 0.5 }))

	-- Zackenkragen auf den Schultern: zehn Stoffzacken (creme/rot), eine davon zerrissen und haengend
	for i = 0, 9 do
		local a = math.rad(i * 36 + 18)
		local droop = math.rad((i == 6) and 36 or 12)
		local len = (i == 6) and 30 or 42
		local dx, dy, dz = math.cos(a) * math.cos(droop), math.sin(a) * math.cos(droop), -math.sin(droop)
		Part(Builder.Shape(list, "cone", root_at(math.cos(a) * 9 + dx * len / 2, math.sin(a) * 9 + dy * len / 2, 64 + dz * len / 2),
			V(25, 25, len), { rotation = AxisRot(dx, dy, dz), color = (i % 2 == 0) and CREAM or RUFF_RED, roughness = 0.95 }))
	end
	-- Kabelbaeume vom Nacken zu den Schulter-Servos
	for _, sy in ipairs({ 1, -1 }) do
		Part(Builder.Shape(list, "cylinder", root_at(-8, sy * 28, 54), V(3.5, 3.5, 41), { rotation = AxisRot(8, sy * 36, -16),
			color = (sy > 0) and Color(0.3, 0.03, 0.03) or Color(0.03, 0.03, 0.04), roughness = 0.6 }))
	end
	-- Halsmanschette (der Teleskop-Hals faehrt hier hinein)
	Part(Builder.Shape(list, "cylinder", root_at(0, 0, 66), V(14, 14, 22), { texture = "metal_rust", color = STEEL, roughness = 0.4 }))
	Part(Builder.Shape(list, "cylinder", root_at(0, 0, 76), V(20, 20, 4), brass))

	-- Arme (sy = +1: Jacks rechte Seite = +Y): Schulter -> Aermel -> Ellbogen -> rostiger Unterarm -> Handgelenk-Servo
	-- -> Handschuh -> Knoechel-Gelenk mit vier langen Stahlkrallen. Haengen nach unten; Gelenke siehe SolveArm.
	for side, sy in pairs({ r = 1, l = -1 }) do
		local shoulder = Part(Builder.Mesh(list, root_at(0, sy * SH_Y, SH_Z), Rotator(), "nanos-world::SM_None"))
		Part(Builder.Shape(list, "sphere", root_at(0, sy * SH_Y, SH_Z), V(22, 22, 20), { texture = "metal_brass", color = Color(0.6, 0.52, 0.42), roughness = 0.35 }), shoulder)
		Part(Builder.Shape(list, "cylinder", root_at(0, sy * SH_Y, 3), V(15, 15, 74), costume), shoulder)
		local elbow = Part(Builder.Mesh(list, root_at(0, sy * SH_Y, SH_Z - UPPER), Rotator(), "nanos-world::SM_None"), shoulder)
		Part(Builder.Shape(list, "sphere", root_at(0, sy * SH_Y, -34), V(14, 14, 14), brass), elbow)
		Part(Builder.Shape(list, "cylinder", root_at(0, sy * SH_Y, -68), V(8, 8, 66), rust), elbow)
		Part(Builder.Shape(list, "cylinder", root_at(0, sy * SH_Y, -100), V(11, 11, 15), { rotation = Rotator(0, 0, 90), texture = "metal_brass", roughness = 0.3 }), elbow)
		local hand = Part(Builder.Shape(list, "sphere", root_at(0, sy * SH_Y, SH_Z - UPPER - FORE), V(11, 21, 19), { color = GLOVE, roughness = 0.85 }), elbow)
		local fingers = Part(Builder.Mesh(list, root_at(0, sy * SH_Y, SH_Z - UPPER - FORE - 6), Rotator(), "nanos-world::SM_None"), elbow)
		for k = 1, 4 do
			local dx, dy, dz = CLAW_HOOK, sy * math.tan(math.rad(CLAW_SPREAD[k])), -1
			local n = math.sqrt(dx * dx + dy * dy + 1)
			dx, dy, dz = dx / n, dy / n, dz / n
			local len = CLAW_LEN[k]
			Part(Builder.Shape(list, "cone", root_at(1 + dx * len / 2, sy * (SH_Y + (k - 2.5) * 4.4) + dy * len / 2, SH_Z - UPPER - FORE - 7 + dz * len / 2),
				V(3.6, 3.6, len), { rotation = AxisRot(dx, dy, dz), color = CLAW, roughness = 0.28 }), fingers)
		end
		jack["shoulder_" .. side] = shoulder
		jack["elbow_" .. side] = elbow
		jack["hand_" .. side] = hand
		jack["fingers_" .. side] = fingers
	end

	-- ------------------------------------------------------------------ Kopf
	-- Drehpunkt am oberen Halsende (faehrt mit dem Teleskop-Hals: SetRelativeLocation)
	local neck0 = COLLAR + NECK_PRESENT
	jack.head = Part(Builder.Mesh(list, root_at(0, 0, neck0), Rotator(), "nanos-world::SM_None"))
	local function head_at(x, y, z) return root_at(x, y, neck0 + z) end
	local function HeadPart(mesh) return Part(mesh, jack.head) end
	local function Shape(kind, x, y, z, size, opts) return HeadPart(Builder.Shape(list, kind, head_at(x, y, z), V(size[1], size[2], size[3]), opts)) end
	-- flacher Koerper auf einer Oberflaeche (size = { hoehe, breite, dicke }), lift = Mitte ueber der Oberflaeche
	local function Decal(parent, x, nx, ny, nz, y, z, lift, size, opts, tx, ty, tz, tilt)
		if (not x) then return nil end   -- (y, z) liegt nicht auf dem Koerper
		opts.rotation = SurfaceRot(nx, ny, nz, tx or 0, ty or 1, tz or 0, tilt)
		local mesh = Builder.Shape(list, "sphere", head_at(x + nx * lift, y + ny * lift, z + nz * lift), V(size[1], size[2], size[3]), opts)
		return Part(mesh, parent or jack.head)
	end

	-- Teleskop-Hals: das innere Rohr gleitet in der Manschette (haengt am Rumpf, dreht nicht mit dem Kopf, damit es nie
	-- aus dem Kragen schwenkt), zwei kurze Kolben und abgerissene Kabel haengen am Kopf
	jack.neck_tube = Part(Builder.Shape(list, "cylinder", root_at(0, 0, neck0 - 26), V(8, 8, 52), { texture = "metal_rust", color = STEEL, roughness = 0.4 }))
	for _, sy in ipairs({ 1, -1 }) do
		HeadPart(Builder.Shape(list, "cylinder", head_at(-3, sy * 9, -10), V(4, 4, 24), { rotation = Rotator(0, 0, -sy * 8), texture = "metal_brass", roughness = 0.3 }))
	end
	HeadPart(Builder.Shape(list, "cylinder", head_at(-17, 6, -10), V(3.5, 3.5, 34), { rotation = AxisRot(-4, 2, -38), color = Color(0.35, 0.04, 0.03), roughness = 0.6 }))
	HeadPart(Builder.Shape(list, "cylinder", head_at(-15, -7, -10), V(3, 3, 32), { rotation = AxisRot(-2, -3, -38), color = Color(0.05, 0.06, 0.16), roughness = 0.6 }))

	-- Porzellan: Ei + Schnauze (Risse-Textur: auf Kugeln in jeder Richtung gleich)
	Shape("sphere", DOME[1], DOME[2], DOME[3], DOME.size, porcelain)
	Shape("sphere", MUZZLE[1], MUZZLE[2], MUZZLE[3], MUZZLE.size, porcelain)
	-- Mundhoehle: dunkel, rot glimmend (sichtbar zwischen den Zaehnen und wenn der Kiefer aufgeht)
	jack.cavity = Shape("sphere", MOUTH[1], MOUTH[2], MOUTH[3], MOUTH.size, { color = Color(0.05, 0.008, 0.008), emissive = CAVITY * 0.03, roughness = 0.7, shadow = false })

	-- Augen: tiefe schwarze Hoehlen (flache Linsen knapp ueber dem Porzellan), gluehende Pupillen, Lider (wachsen von
	-- oben ueber die Hoehle: blinzeln, halb zu beim Starren), schwarze Brauen darueber (Stimmung)
	jack.eyes, jack.eyelids, jack.brows = {}, {}, {}
	for _, e in ipairs(EYES) do
		local x, nx, ny, nz = Front(DOME, e.y, e.z)
		Decal(nil, x, nx, ny, nz, e.y, e.z, -1.3, { 15, 16.5, 4.6 }, { color = SOCKET, roughness = 1, shadow = false })
		-- Pupille 1 cm unter der Hoehlenmitte (bleibt unter halb geschlossenen Lidern sichtbar)
		local px, pnx, pny, pnz = Front(DOME, e.y, e.z - 1)
		local glow = (e.side > 0) and 1 or 0.8
		local on = EYE * (EYE_EMISSIVE * glow)
		local pupil = Decal(nil, px, pnx, pny, pnz, e.y, e.z - 1, 1.5, { 4, 4, 4 }, { color = EYE, emissive = on, roughness = 0.3, shadow = false })
		table.insert(jack.eyes, { mesh = pupil, side = e.side, glow = glow, on = on, off = false })
		-- Lid: Oberkante unter der Braue, waechst nach unten (Dicke 4, Mitte 2,1 cm vor dem Porzellan, vor der Pupille)
		local rot, hx, hy, hz = SurfaceRot(nx, ny, nz, 0, 1, 0, 0)
		local up = { -hx, -hy, -hz }   -- -X der Linse = nach oben in der Flaeche
		local top = { x + nx * 2.1 + up[1] * 8.4, e.y + ny * 2.1 + up[2] * 8.4, e.z + nz * 2.1 + up[3] * 8.4 }
		local lid_mesh = HeadPart(Builder.Shape(list, "sphere", head_at(top[1], top[2], top[3]), V(0.6, 18.5, 4), { rotation = rot, texture = "jack_porcelain_cracked", tiling = { 0.5, 0.5 }, color = LID_TINT, roughness = 0.4 }))
		table.insert(jack.eyelids, { mesh = lid_mesh, top = top, up = up, height = 17.4, width = 18.5, depth = 4 })
		-- Braue: liegt vor dem oberen Lidrand; Neigung und Hub je Stimmung (Jack.SetFace)
		local by, bz = e.y + e.side * 1, e.z + 11.5
		local bx, bnx, bny, bnz = Front(DOME, by, bz)
		local brow = HeadPart(Builder.Shape(list, "sphere", head_at(bx, by, bz), V(5.5, 21, 5), { color = BROW, roughness = 0.6 }))
		table.insert(jack.brows, { mesh = brow, x = bx, y = by, z = bz, n = { bnx, bny, bnz }, side = e.side })
		-- Clownsschminke: dunkelrote Traenen-Striche unter den Augen
		local tx_, tnx, tny, tnz = FrontOf(FACE_BODIES, e.y + e.side * 0.5, e.z - 12.5)
		Decal(nil, tx_, tnx, tny, tnz, e.y + e.side * 0.5, e.z - 12.5, 0.4, { 8, 3, 2 }, { color = Color(0.32, 0.02, 0.04), roughness = 0.5 }, 0, 1, 0)
	end

	-- Rote Nase (matt glimmend), Wangen
	do
		local x, nx, ny, nz = FrontOf(FACE_BODIES, 0, 44)
		Decal(nil, x, nx, ny, nz, 0, 44, 4.5, { 13, 13, 12 }, { color = RED, emissive = Color(1, 0.05, 0.02) * 0.2, roughness = 0.22 })
		for _, sy in ipairs({ 1, -1 }) do
			local cx, cnx, cny, cnz = FrontOf(FACE_BODIES, sy * 23, 38)
			Decal(nil, cx, cnx, cny, cnz, sy * 23, 38, 0.3, { 11, 12.5, 2.4 }, { color = ROUGE, roughness = 0.55 })
		end
	end

	-- Grinsen: Oberlippe (rote Kette, Mundwinkel ziehen hoch in die Wangen), obere Zahnreihe
	for i = -5, 5 do
		local t = i / 5
		local y, z = 25 * t, 29 + 7 * t * t
		local x, nx, ny, nz = FrontOf(FACE_BODIES, y, z)
		Decal(nil, x, nx, ny, nz, y, z, 0.6, { 3.6, 6.2, 3 }, { color = LIP, roughness = 0.35 }, 0, 25, 14 * t)
	end
	for i = 0, 9 do
		local y = -17.1 + i * 3.8
		if (i ~= 6) then   -- eine Zahnluecke
			local z0 = 28.5 + 6 * (y / 25) ^ 2
			local x = FrontOf(FACE_BODIES, y, z0 + 0.5)
			local len = (i == 2) and 5.5 or (7 + rnd(0, 1.5))
			local dx, dy, dz = 0.12, rnd(-0.06, 0.06), -1
			local n = math.sqrt(dx * dx + dy * dy + dz * dz)
			dx, dy, dz = dx / n, dy / n, dz / n
			Shape("cone", x - 2.2 + dx * len / 2, y + dy * len / 2, z0 + dz * len / 2, { 3.7, 3.7, len }, { rotation = AxisRot(dx, dy, dz), color = TOOTH, roughness = 0.3 })
		end
	end

	-- Kinnlade (Bauchrednerpuppe): Drehpunkt hinten im Kopf, Porzellan-Kinn, Unterlippe, untere Zahnreihe
	jack.jaw_pivot = HeadPart(Builder.Mesh(list, head_at(JAW_HINGE[1], JAW_HINGE[2], JAW_HINGE[3]), Rotator(), "nanos-world::SM_None"))
	local function JawPart(mesh) return Part(mesh, jack.jaw_pivot) end
	JawPart(Builder.Shape(list, "sphere", head_at(JAW[1], JAW[2], JAW[3]), V(JAW.size[1], JAW.size[2], JAW.size[3]), porcelain))
	for i = -4, 4 do
		local t = i / 4
		local y, z = 17 * t, 15 + 1.5 * t * t
		local x, nx, ny, nz = Front(JAW, y, z)
		Decal(jack.jaw_pivot, x, nx, ny, nz, y, z, 0.6, { 3.4, 6, 3 }, { color = LIP, roughness = 0.35 }, 0, 17, 3 * t)
	end
	for i = 0, 8 do
		local y = -15.2 + i * 3.8
		local z0 = 16 + 2 * (y / 20) ^ 2
		local x = Front(JAW, y, z0)
		local len = 6 + rnd(0, 1.2)
		JawPart(Builder.Shape(list, "cone", head_at(x - 2.4, y, z0 + len / 2), V(3.4, 3.4, len), { rotation = AxisRot(-0.08, 0, 1), color = TOOTH, roughness = 0.3 }))
	end
	-- Kiefer-Bolzen quer durch den Kopf (steht links und rechts heraus) + Servo-Scheiben an den Schlaefen
	Shape("cylinder", JAW_HINGE[1], 0, JAW_HINGE[3], { 7, 7, 74 }, { rotation = Rotator(0, 0, 90), texture = "metal_brass", roughness = 0.3 })
	for _, sy in ipairs({ 1, -1 }) do
		Shape("cylinder", -6, sy * 33, 42, { 15, 15, 4 }, { rotation = Rotator(0, 0, 90), texture = "metal_brass", roughness = 0.3 })
	end
	-- Abgeplatzte Stelle auf der Stirn: dunkles Loch, rot glimmend (das Innenleben schimmert durch)
	do
		local x, nx, ny, nz = Front(DOME, -15, 73)
		Decal(nil, x, nx, ny, nz, -15, 73, -0.6, { 6.5, 9, 3 }, { color = Color(0.03, 0.01, 0.01), emissive = CAVITY * 0.05, roughness = 0.8, shadow = false }, 0, 1, 0, 25)
	end

	-- Haarbueschel aus Kegeln: seitlich ueber den Ohren und hinten (Clowns-Silhouette, ragt unter dem Hut heraus)
	local function Tuft(cx, cy, cz, n, dir_fn)
		for k = 1, n do
			local dx, dy, dz = dir_fn(k)
			local len = rnd(17, 30)
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			dx, dy, dz = dx / d, dy / d, dz / d
			local bx, by, bz = cx + rnd(-4, 4), cy, cz + rnd(-4, 4)
			Shape("cone", bx + dx * len / 2, by + dy * len / 2, bz + dz * len / 2, { rnd(9, 13), rnd(9, 13), len },
				{ rotation = AxisRot(dx, dy, dz), color = HAIR[(k % #HAIR) + 1], roughness = 1 })
		end
	end
	for _, sy in ipairs({ 1, -1 }) do
		Tuft(-7, sy * 27, 64, 7, function(k) return rnd(-0.55, 0.2), sy * 1, rnd(-0.3, 0.8) end)
	end
	Tuft(-25, 0, 70, 4, function(k) return -1, rnd(-0.5, 0.5), rnd(0.1, 0.7) end)

	-- Schiefer Zylinder aus Grundformen: Krempe, Krone, rote Hutschnur, eine Spielkarte steckt im Band
	jack.hat = HeadPart(Builder.Mesh(list, head_at(-5, 4, 83), Rotator(5, 0, 14), "nanos-world::SM_None"))
	do
		local hp, hy, hr = 5, 0, 14
		local X1, X2, X3, Y1, Y2, Y3, Z1, Z2, Z3 = Rows(hp, hy, hr)
		local function hat_at(x, y, z)
			return head_at(-5 + x * X1 + y * Y1 + z * Z1, 4 + x * X2 + y * Y2 + z * Z2, 83 + x * X3 + y * Y3 + z * Z3)
		end
		local hat_rot = Rotator(hp, hy, hr)
		for _, p in ipairs({
			{ hat_at(0, 0, 1.5), V(48, 48, 3), { color = HAT, roughness = 0.65 } },
			{ hat_at(0, 0, 21), V(29, 29, 36), { color = HAT, roughness = 0.65 } },
			{ hat_at(0, 0, 7), V(30, 30, 7), { color = HAT_BAND, roughness = 0.5 } },
		}) do
			p[3].rotation = hat_rot
			Part(Builder.Shape(list, "cylinder", p[1], p[2], p[3]), jack.hat)
		end
		Part(Builder.Box(list, hat_at(14.6, -5, 11), V(0.8, 7, 10), { rotation = Rotator(hp, hy - 18, hr + 8), color = Color(0.92, 0.88, 0.8), emissive = Color(1, 0.9, 0.7) * 0.02, roughness = 0.6 }), jack.hat)
	end

	-- Bezugspunkte: Gesichtsmitte (POP-Abstand, Suchstrahl), Mund (Feuer)
	jack.mask = HeadPart(Builder.Mesh(list, head_at(FACE_X, 0, FACE_Z), Rotator(), "nanos-world::SM_None"))
	jack.mouth = HeadPart(Builder.Mesh(list, head_at(32, 0, 22), Rotator(), "nanos-world::SM_None"))
	-- Rotes Licht unter dem Gesicht (Augenglut: Kiefer, Kragen, Krallen) + warmes Fuelllicht vor und ueber dem Gesicht
	jack.eye_light = HeadPart(Builder.Light(list, head_at(40, 0, 18), EYE, 1.5 * EYE_LIGHT_K, 90 * s))
	jack.face_light = HeadPart(Builder.Light(list, head_at(105, 0, 70), FACE_FILL, FACE_LIGHT * s * s, 180 * s))

	-- Suchstrahl aus den Augen (Spot, ohne Schatten, wird jedes Bild auf die Stuehle gerichtet)
	jack.search_light = Builder.Spot(list, at(0, 0, 260), SEARCH, 0, 1300 * s, SEARCH_CONE, { shadows = false, inner = 0.4 })

	-- Feder: Ringe, die zwischen Kistenboden und Rumpf neu verteilt werden
	jack.rings = {}
	for i = 1, 22 do
		table.insert(jack.rings, Builder.Shape(list, "torus", at(0, 0, 30 + i * 5), V(52, 52, 10), { texture = "metal_rust", roughness = 0.45 }))
	end

	-- Ausgangslage: Kiste zeigt in "yaw", Jack steht draussen
	jack.box_root:SetRotation(Rotator(0, jack.yaw, 0))
	Jack.SetPose(jack, "idle")
	Jack.ApplyFace(jack)

	Builder.AddTicker(list, function(dt, time) return Jack.Update(jack, dt, time) end)
	return jack
end

-- ===================================================================
-- Steuerung
-- ===================================================================

-- Grundhaltungen. Arme: entweder feste Gelenkwinkel (sp = Schulter vor/zurueck, ya = Schulter drehen, sr = Schulter
-- nach aussen, el = Ellbogen; gleiche Werte = spiegelgleiche Arme; fingers = Knoechel) oder ein Griff:
--   grip = "rim"    Hand auf dem vorderen Kistenrand (y = Abstand zur Mitte), Krallen haengen aussen an der Vorderwand
--   grip = "reach"  Hand seitlich vor dem Gesicht des Opfers (spread = seitlich, fwd = Richtung Jack, up = hoeher),
--                   die Krallen zeigen auf seine Schlaefen (rahmen sein Bild ein, ohne Jacks Gesicht zu verdecken)
-- Animationen kommen jedes Bild als Versatz dazu.
local STRAIGHT = { sp = -4, ya = 0, sr = 6, el = 8, fingers = FINGERS_STRAIGHT }
local TUCK = { sp = -6, ya = 0, sr = -4, el = 12, fingers = FINGERS_STRAIGHT }
local POSES = {
	idle  = { head_pitch = 0,   l = { grip = "rim", y = 47 }, r = { grip = "rim", y = 47 } },
	peek  = { head_pitch = 0,   l = { grip = "rim", y = 37 }, r = { grip = "rim", y = 37 } },
	lunge = { head_pitch = -24, l = { grip = "reach", spread = 64, fwd = 30, up = 24 }, r = { grip = "reach", spread = 64, fwd = 30, up = 24 } },
	reach = { head_pitch = -24, l = { grip = "reach", spread = 52, fwd = 40, up = 8 }, r = { grip = "reach", spread = 52, fwd = 40, up = 8 } },
	aim   = { head_pitch = -4,  l = { grip = "rim", y = 47 }, r = { sp = 92, ya = 0, sr = 6, el = 0, fingers = FINGERS_FIST } },
	slump = { head_pitch = -18, l = STRAIGHT, r = STRAIGHT },
	-- angelegt (in der Kiste): Arme haengen innerhalb der Kistenwaende
	tuck  = { head_pitch = -14, l = TUCK, r = TUCK },
}

function Jack.SetPose(jack, name)
	jack.pose = POSES[name] or POSES.idle
	jack.pose_name = name
end

-- Gucken: Jack sinkt, bis nur Kopf, Krause und Schultern ueber den Rand ragen, beugt sich vor, Haende am Rand
function Jack.Peek(jack)
	local s = jack.scale
	jack.peek = true
	jack.tucked = false
	jack.rattle = false
	jack.stare = false
	jack.anims.pop = nil      -- ein laufender POP darf ihn nicht wieder herausholen
	jack.lid_target = LID_OPEN
	jack.ext_target = Target(jack, 0, PEEK_U * s, 60, 14)
	jack.neck.target = NECK_PEEK
	jack.servo_boost_until = Now() + 0.4
	Jack.SetPose(jack, "peek")
	Jack.ApplyFace(jack)
end

-- Kiste dreht sich auf target_yaw (mind. "turns" Umdrehungen ab der aktuellen Richtung, langsam mit langem
-- Auskriechen). Jack guckt dabei ueber den Rand und dreht sich mit. start_yaw (vom Server) wird nur benutzt, wenn
-- die Kiste lokal noch keine Richtung hat.
function Jack.Spin(jack, target_yaw, turns, duration, start_yaw)
	local from = jack.yaw or start_yaw or 0
	local delta = (target_yaw - from) % 360 + 360 * (turns or 1)
	jack.anims.spin = { t0 = Now(), duration = math.max(0.1, duration or 10), from = from, delta = delta }
	jack.anims.point = nil
	jack.stare = false
	Jack.Peek(jack)
	return jack.anims.spin
end

-- Zeitpunkte (Sekunden nach Start), an denen die Kistenfront (und der Suchstrahl) den Winkel "angle" passiert
function Jack.SpinCrossings(spin, angle)
	local times = {}
	local first = (angle - spin.from) % 360
	if (first == 0) then first = 360 end
	local covered = first
	while (covered <= spin.delta + 0.001) do
		local goal = Clamp(covered / math.max(spin.delta, 0.001), 0, 1)
		local lo, hi = 0, 1
		for _ = 1, 40 do
			local mid = (lo + hi) / 2
			if (SpinEase(mid) < goal) then lo = mid else hi = mid end
		end
		table.insert(times, ((goal >= 1) and 1 or hi) * spin.duration)
		covered = covered + 360
	end
	return times
end

function Jack.PointTo(jack, yaw, seconds)
	if (jack.anims.spin) then return end
	local delta = AngleDelta(jack.yaw, yaw)
	jack.anims.point = { t0 = Now(), duration = seconds or 0.6, from = jack.yaw, delta = delta }
	-- Servo surrt (schnelle Drehungen klingen hoeher)
	if (math.abs(delta) > 12) then
		local pitch = Clamp(0.5 / (seconds or 0.6), 0.85, 1.25)
		DeathBox.Audio.Play3D("servo_whir", jack.center + Vector(0, 0, 250 * jack.scale), 0.5, pitch, 3000)
	end
end

function Jack.SetYaw(jack, yaw)
	jack.anims.spin, jack.anims.point = nil, nil
	jack.yaw = yaw
end

-- Ruckartig ganz in die Kiste zurueck: Arme schnellen an den Koerper, Hals faehrt ein, der Deckel folgt ihm und
-- schlaegt zu, sobald der Hut drin ist (Vorhang beim Sieg)
function Jack.Retract(jack)
	local et = Target(jack, 0, RETRACT_U * jack.scale, 260, 28)
	et.close_lid = true
	jack.ext_target = et
	jack.anims.pop = nil
	jack.tucked = true
	jack.peek = false
	jack.stare = false
	jack.neck.target = NECK_TUCK
	jack.servo_boost_until = Now() + 0.5
	Jack.Searchlight(jack, false)
end

-- Stille vor dem POP: Starren (oder, wenn er in der Kiste steckt, klappert der Deckel)
function Jack.Hold(jack, on)
	if (on and jack.tucked) then
		jack.rattle = true
		jack.stare = false
	else
		jack.rattle = false
		jack.stare = on and Now() or false
	end
	Jack.ApplyFace(jack)
end

-- Kurzes Ducken direkt vor dem POP (Ausholen)
function Jack.Crouch(jack)
	if (jack.peek) then jack.crouch_until = Now() + 0.32 end
end

-- Suchstrahl aus den Augen: dist = Radius des Stuhlkreises, z = Kopfhoehe der Sitzenden ueber dem Zeltboden (cm)
function Jack.Searchlight(jack, on, dist, z)
	jack.search.on = on and true or false
	if (dist) then jack.search.dist = dist end
	if (z) then jack.search.z = z end
end

-- Ziel der Rumpfmitte fuer eine POP-Haltung mit ihrer Vorbeuge-Kurve
local function PopTarget(s, f, u, k, c, curve)
	return { f = f * s, u = u * s, k = k, c = c, lean = curve }
end

-- Aus der Kiste schiessen: hoch, dann ueber die Vorderkante gebeugt mit dem Gesicht DICHT vor das Gesicht des Opfers
-- (Stoss, Arme weit auf), danach ein Stueck zurueck: Gesicht schwebt ca. 1 m vor seinen Augen, leicht darueber,
-- Kiefer auf, Krallen links und rechts. Nach "seconds" (Standard 1,8 s) zurueck in die Vorfuehr-Haltung.
-- target_point = Augen des Opfers (Presentation.lua: HeadPoint).
function Jack.PopOut(jack, target_point, seconds)
	local s = jack.scale
	local rel = target_point - jack.center
	local dist = math.sqrt(rel.X * rel.X + rel.Y * rel.Y) / s
	local eye_z = rel.Z / s
	local lean1, f1, u1 = PopPose(dist, eye_z, LUNGE_GAP, LUNGE_RISE)
	local lean2, f2, u2 = PopPose(dist, eye_z, POP_GAP, POP_RISE)
	local from_box = jack.tucked or (jack.ext_u.v < GATE_LO * s and not jack.peek)
	jack.rattle = false
	jack.stare = false
	jack.tucked = false
	jack.peek = false
	jack.lid_target = LID_OPEN
	if (jack.lid.v < 60) then jack.lid.vel = 700 end
	jack.neck.target = NECK_POP
	jack.reach_point = target_point
	Jack.Searchlight(jack, false)
	-- Volle Neigung spaetestens nach 110 cm (Teller und Huefte kommen erst hoch ueber dem Rand nach vorne). Schwebe:
	-- lean2 bis zur Schwebe-Stelle, dann bis lean1 an der Stoss-Stelle (der Wechsel ist stetig); zurueck anteilig weniger.
	jack.ext_target = PopTarget(s, f1, u1, 260, 24, { math.min(110, f1), lean1 })
	jack.anims.pop = { t0 = Now(), back_at = Now() + (seconds or 1.8), lunge_f = f1 * s, arms_hold = from_box,
		hover = PopTarget(s, f2, u2, 150, 17, { math.min(110, f2), lean2, f2, lean2, math.max(f1, f2), lean1 }) }
	jack.servo_boost_until = Now() + 0.7
	Jack.SetFace(jack, "laugh")
	Jack.SetPose(jack, "lunge")
end

-- Auftritt: versteckt in der Kiste (Arme angelegt, Augen zu), springt nach pop_at Sekunden heraus
function Jack.IntroPop(jack, pop_at)
	local u = RETRACT_U * jack.scale
	jack.ext_f.v, jack.ext_f.vel, jack.ext_u.v, jack.ext_u.vel = 0, 0, u, 0
	jack.lean.v, jack.lean.vel = 0, 0
	jack.hunch.v, jack.hunch.vel = 0, 0
	jack.lid.v, jack.lid.vel, jack.lid_target = 0, 0, 0
	jack.ext_target = { f = 0, u = u, k = 60, c = 14 }
	jack.anims.intro = { t0 = Now(), pop_at = pop_at }
	jack.anims.pop, jack.anims.spin = nil, nil
	jack.tucked = true
	jack.peek = false
	jack.stare = false
	jack.neck.cur, jack.neck.target, jack.neck.shown = NECK_TUCK, NECK_TUCK, NECK_TUCK
	for _, side in ipairs({ "l", "r" }) do
		for key, value in pairs(POSES.tuck[side]) do
			local j = jack.arm[side][key]
			if (j) then j.cur, j.target, j.shown = value, value, value end
		end
	end
	Jack.Searchlight(jack, false)
	jack.next_step = 0
end

-- Vorfuehr-Haltung ueber der Kiste
function Jack.Present(jack)
	jack.lid_target = LID_OPEN
	jack.tucked = false
	jack.peek = false
	jack.stare = false
	jack.rattle = false
	jack.neck.target = NECK_PRESENT
	jack.ext_target = Target(jack, 0, PRESENT_U * jack.scale, 40, 11)
	Jack.Searchlight(jack, false)
	if (jack.pose_name == "peek") then Jack.SetPose(jack, "idle") end
	Jack.ApplyFace(jack)
end

function Jack.Laugh(jack, seconds)
	jack.anims.laugh = { t0 = Now(), duration = seconds or 1.6 }
	Jack.SetFace(jack, "laugh")
end

function Jack.Disappointed(jack)
	jack.anims.sad = { t0 = Now(), duration = 1.6 }
	Jack.ApplyFace(jack)
end

-- Rechter Arm zeigt nach vorne (auf das Ziel, die Kiste dreht sich vorher hin)
function Jack.Aim(jack, on)
	Jack.SetPose(jack, on and "aim" or "idle")
end

-- Wurfbewegung mit dem rechten Arm (Messer)
function Jack.Throw(jack)
	jack.anims.throw = { t0 = Now() }
end

-- Mundhoehle glimmt wie Glut: dunkelrot in Ruhe, heller beim Starren und wenn er wuetend ist
local function UpdateCavity(jack)
	if (jack.cavity and jack.cavity:IsValid()) then
		local k = math.min(0.07, 0.025 + 0.003 * (jack.eye_glow or 1.5)) * ((jack.face == "laugh") and 1.3 or 1)
		jack.cavity:SetMaterialColorParameter("Emissive", CAVITY * k)
	end
end

-- Stimmung, die gerade gilt (Lider, Brauen, Kiefer): Starren > Enttaeuscht > Gesicht
local function CurrentMood(jack)
	if (jack.stare and jack.face == "idle") then return MOODS.stare end
	if (jack.anims.sad) then return MOODS.sad end
	return MOODS[jack.face] or MOODS.idle
end

function Jack.ApplyFace(jack)
	local m = CurrentMood(jack)
	jack.mood = m
	jack.jaw_mood = m.jaw
	jack.brow.target = m.brow
	jack.brow_lift.target = m.lift
	UpdateCavity(jack)
end

-- Gesicht: "idle" | "laugh" | "angry". Stellt Brauen, Lider und Kinnlade: lachen = Mund offen, Augen schmal,
-- wuetend = Brauen tief, Zaehne gefletscht.
function Jack.SetFace(jack, mood)
	jack.face = MOODS[mood] and mood or "idle"
	Jack.ApplyFace(jack)
end

-- Augenglut: Pupillen + rotes Licht unter dem Gesicht (Presentation: 1,5 Ruhe, 3 POP, 6 Drehen, 12 Starren, 14 wuetend)
function Jack.SetEyeGlow(jack, intensity)
	jack.eye_glow = intensity
	if (jack.eye_light and jack.eye_light:IsValid()) then jack.eye_light:SetIntensity(intensity * EYE_LIGHT_K) end
	local k = Clamp(0.7 + intensity / 10, 0.8, 2)
	for _, e in ipairs(jack.eyes or {}) do
		e.on = EYE * (EYE_EMISSIVE * e.glow * k)
		if (e.mesh:IsValid() and not e.off) then e.mesh:SetMaterialColorParameter("Emissive", e.on) end
	end
	UpdateCavity(jack)
end

-- Weltpunkte fuer Effekte
function Jack.HandPoint(jack)
	return (jack.hand_r and jack.hand_r:IsValid()) and jack.hand_r:GetLocation() or (jack.center + Vector(0, 0, 250 * jack.scale))
end

function Jack.MouthPoint(jack)
	return (jack.mouth and jack.mouth:IsValid()) and jack.mouth:GetLocation() or (jack.center + Vector(0, 0, 330 * jack.scale))
end

function Jack.FacePoint(jack)
	return (jack.mask and jack.mask:IsValid()) and jack.mask:GetLocation() or (jack.center + Vector(0, 0, 340 * jack.scale))
end

-- ===================================================================
-- Arme (IK)
-- ===================================================================

-- Zwei-Gelenk-IK im Rumpf-Rahmen (cm bei Skalierung 1, sy = +1 rechts, -1 links): Ziel der Handmitte (tx, ty, tz),
-- bevorzugte Ellbogen-Richtung (px, py, pz). Liefert die Schulter-Drehung (Pitch, Yaw, Roll) und den Ellbogen (Grad).
local function SolveArm(sy, tx, ty, tz, px, py, pz)
	local sx, sy_, sz = 0, sy * SH_Y, SH_Z
	local dx, dy, dz = tx - sx, ty - sy_, tz - sz
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if (d < 1) then dx, dy, dz, d = 0, 0, -1, 1 end
	local ux, uy, uz = dx / d, dy / d, dz / d
	d = Clamp(d, math.abs(UPPER - FORE) + 6, UPPER + FORE - 1)
	local pd = px * ux + py * uy + pz * uz
	local wx, wy, wz = px - pd * ux, py - pd * uy, pz - pd * uz
	local wl = math.sqrt(wx * wx + wy * wy + wz * wz)
	if (wl < 1e-4) then wx, wy, wz, wl = -uz, 0, ux, math.sqrt(uz * uz + ux * ux) end
	if (wl < 1e-4) then wx, wy, wz, wl = 0, 1, 0, 1 end
	wx, wy, wz = wx / wl, wy / wl, wz / wl
	local ca = Clamp((UPPER * UPPER + d * d - FORE * FORE) / (2 * UPPER * d), -1, 1)
	local sa = math.sqrt(1 - ca * ca)
	local ax, ay, az = ca * ux + sa * wx, ca * uy + sa * wy, ca * uz + sa * wz        -- Oberarm
	local ex, ey, ez = sx + UPPER * ax, sy_ + UPPER * ay, sz + UPPER * az
	local fx, fy, fz = (sx + d * ux - ex) / FORE, (sy_ + d * uy - ey) / FORE, (sz + d * uz - ez) / FORE   -- Unterarm
	local fa = fx * ax + fy * ay + fz * az
	local qx, qy, qz = fx - fa * ax, fy - fa * ay, fz - fa * az
	local ql = math.sqrt(qx * qx + qy * qy + qz * qz)
	local el = math.deg(atan2(ql, fa))
	if (ql < 1e-4) then qx, qy, qz, ql = -wx, -wy, -wz, 1 end
	local Xx, Xy, Xz = qx / ql, qy / ql, qz / ql
	local Zx, Zy, Zz = -ax, -ay, -az
	local Yx, Yy, Yz = Zy * Xz - Zz * Xy, Zz * Xx - Zx * Xz, Zx * Xy - Zy * Xx
	local p, y, r = MatToRot(Xx, Xy, Xz, Yx, Yy, Yz, Zx, Zy, Zz)
	return p, y, r, el
end

local function Near(v, ref) return v + 360 * math.floor((ref - v) / 360 + 0.5) end

-- Schulter-Drehung -> Servo-Werte (sp, ya, sr) der Seite, nahe an den aktuellen Werten (keine Umschwuenge um 360 Grad)
local function ArmAngles(sy, arm, p, y, r)
	local best, bsp, bya, bsr = math.huge, 0, 0, 0
	for form = 1, 2 do
		local pp, yy, rr = p, y, r
		if (form == 2) then pp, yy, rr = 180 - p, y + 180, r + 180 end
		local sp = Near(pp, arm.sp.cur)
		local ya = Near((sy > 0) and yy or -yy, arm.ya.cur)
		local sr = Near((sy > 0) and -rr or rr, arm.sr.cur)
		local cost = math.abs(sp - arm.sp.cur) + math.abs(ya - arm.ya.cur) + math.abs(sr - arm.sr.cur)
		if (cost < best) then best, bsp, bya, bsr = cost, sp, ya, sr end
	end
	return bsp, bya, bsr
end

-- Knoechel-Drehung (relativ zum Ellbogen), damit die Krallen in Richtung d zeigen und entlang w gefaechert sind
-- (beides im Rumpf-Rahmen). sp/ya/sr/el = gezeigte Gelenkwinkel des Arms.
local function FingerRot(sy, sp, ya, sr, el, dx, dy, dz, wx, wy, wz)
	local p, y, r = sp, (sy > 0) and ya or -ya, (sy > 0) and -sr or sr
	local X1, X2, X3, Y1, Y2, Y3, Z1, Z2, Z3 = Rows(p, y, r)
	local ce, se = math.cos(math.rad(el)), math.sin(math.rad(el))
	local E1, E2, E3 = ce * X1 + se * Z1, ce * X2 + se * Z2, ce * X3 + se * Z3      -- Ellbogen-Achsen im Rumpf-Rahmen
	local F1, F2, F3 = Y1, Y2, Y3
	local G1, G2, G3 = -se * X1 + ce * Z1, -se * X2 + ce * Z2, -se * X3 + ce * Z3
	local zx, zy, zz = -(dx * E1 + dy * E2 + dz * E3), -(dx * F1 + dy * F2 + dz * F3), -(dx * G1 + dy * G2 + dz * G3)
	local zl = math.sqrt(zx * zx + zy * zy + zz * zz)
	zx, zy, zz = zx / zl, zy / zl, zz / zl
	local vx, vy, vz = wx * E1 + wy * E2 + wz * E3, wx * F1 + wy * F2 + wz * F3, wx * G1 + wy * G2 + wz * G3
	local vd = vx * zx + vy * zy + vz * zz
	vx, vy, vz = vx - vd * zx, vy - vd * zy, vz - vd * zz
	local vl = math.sqrt(vx * vx + vy * vy + vz * vz)
	if (vl < 1e-4) then return FINGERS_STRAIGHT end
	vx, vy, vz = vx / vl, vy / vl, vz / vl
	local xx, xy, xz = vy * zz - vz * zy, vz * zx - vx * zz, vx * zy - vy * zx
	return Rotator(MatToRot(xx, xy, xz, vx, vy, vz, zx, zy, zz))
end

-- ===================================================================
-- Pro Bild
-- ===================================================================

-- Feder zwischen Kistenboden (b) und Federteller (t): quadratische Kurve mit Kontrollpunkt (bx, by, cz) senkrecht ueber
-- dem Boden – sie steigt senkrecht auf und biegt sich zum Teller. Leicht schraeg gestellte Ringe sehen aus wie Windungen.
local function LayoutRings(jack, bx, by, bz, tx, ty, tz, cz)
	local dx, dy, dz = tx - bx, ty - by, tz - bz
	local rings = jack.rings
	local n = #rings
	for i = 1, n do
		local t = i / (n + 1)
		local w = t * t
		local px, py = bx + dx * w, by + dy * w
		local pz = bz * (1 - t) * (1 - t) + cz * 2 * (1 - t) * t + tz * w
		local gx, gy = dx * 2 * t, dy * 2 * t
		local gz = (cz - bz) * 2 * (1 - t) + (tz - cz) * 2 * t
		local ring = rings[i]
		if (ring:IsValid()) then
			-- Torus-Drehpunkt liegt an der Unterseite (In-Engine-Diagnose): um die halbe Ringdicke (10 cm) entlang der
			-- Federachse zuruecksetzen, damit (px, py, pz) die Ringmitte ist
			local gl = math.max(math.sqrt(gx * gx + gy * gy + gz * gz), 0.0001)
			local half = 5 * jack.scale / gl
			ring:SetLocation(Vector(px - gx * half, py - gy * half, pz - gz * half))
			ring:SetRotation(Rotator(math.deg(atan2(gz, math.sqrt(gx * gx + gy * gy))) - 90, math.deg(atan2(gy, gx)), 7))
		end
	end
end

-- Kleinster Deckelwinkel (Grad), bei dem die Deckel-Unterkante noch ueber allen FIGURE_TOP-Punkten liegt (0 = Jack ist drin)
local function LidClearance(jack)
	local s = jack.scale
	local angle = 0
	local neck_up = math.max(0, jack.neck.cur - NECK_TUCK)
	for _, p in ipairs(FIGURE_TOP) do
		local over = jack.ext_u.v + (p.z + (p.head and neck_up or 0) - LID_UNDERSIDE) * s
		if (over > 0) then
			local dist = jack.ext_f.v + (p.x - LID_HINGE_X) * s   -- waagerechter Abstand Scharnier -> Punkt
			angle = math.max(angle, math.deg(atan2(over, math.max(dist, 1))))
		end
	end
	return angle
end

function Jack.Update(jack, dt, time)
	if (not jack.root:IsValid()) then return false end
	dt = math.min(dt, 0.05)
	local a = jack.anims
	local now = Now()
	local s = jack.scale

	-- Kiste drehen / zu jemandem drehen
	local crank_speed = 0
	if (a.spin) then
		local p = Clamp((now - a.spin.t0) / a.spin.duration, 0, 1)
		jack.yaw = (a.spin.from + a.spin.delta * SpinEase(p)) % 360
		local speed = (SpinEase(math.min(1, p + 0.01)) - SpinEase(p)) * 100 * a.spin.delta / a.spin.duration
		crank_speed = 90 + speed * 3
		if (p >= 1) then a.spin = nil end
	elseif (a.point) then
		local p = Clamp((now - a.point.t0) / a.point.duration, 0, 1)
		jack.yaw = (a.point.from + a.point.delta * (p * p * (3 - 2 * p))) % 360
		if (p >= 1) then a.point = nil end
	end

	-- Auftritt: nach pop_at senkrecht heraus, Augen auf
	if (a.intro and now - a.intro.t0 >= a.intro.pop_at) then
		a.intro = nil
		jack.lid_target = LID_OPEN
		jack.lid.vel = 600
		jack.tucked = false
		jack.rattle = false
		jack.neck.target = NECK_PRESENT
		jack.ext_target = { f = 0, u = PRESENT_U * s, k = 130, c = 9 }
		Jack.Laugh(jack, 2.2)
	elseif (a.intro) then
		crank_speed = 260
	end

	-- POP: nach dem Stoss (Rumpf vorne angekommen, spaetestens nach 0,5 s) ein Stueck zurueck in die Schwebe-Haltung
	if (a.pop and a.pop.hover and (jack.ext_f.v >= a.pop.lunge_f - 2 * s or now - a.pop.t0 > 0.5)) then
		jack.ext_target = a.pop.hover
		a.pop.hover = nil
		if (jack.pose_name == "lunge") then Jack.SetPose(jack, "reach") end
	end
	-- Nach dem Herausschiessen zurueck in die Vorfuehr-Haltung (richtet sich im selben Verhaeltnis auf, wie er zurueckfaehrt)
	if (a.pop and now >= a.pop.back_at) then
		a.pop = nil
		jack.ext_target = Target(jack, 0, PRESENT_U * s, 38, 12)
		jack.neck.target = NECK_PRESENT
		if (jack.pose_name == "reach" or jack.pose_name == "lunge") then Jack.SetPose(jack, "idle") end
		Jack.SetFace(jack, "idle")
	end

	-- Ausfahren (Feder-Physik mit Ueberschwingen). Die Kiste ist massiv: nach vorne fahren und vorbeugen erst, wenn die
	-- Rumpfmitte ueber GATE_LO..GATE_HI steigt; solange er vorgebeugt oder vorne ist, sinkt er nicht unter GATE_HI.
	local et = jack.ext_target
	local gate = Clamp((jack.ext_u.v - GATE_LO * s) / ((GATE_HI - GATE_LO) * s), 0, 1)
	SpringStep(jack.ext_f, et.f * gate, et.k, et.c, dt)
	local u_goal = et.u
	local out = Clamp((math.max(jack.ext_f.v / s, -jack.lean.v) - 6) / 24, 0, 1)   -- 0 = aufrecht in der Mitte, 1 = >= 30 cm vor / 30 Grad
	if (out > 0) then u_goal = math.max(u_goal, GATE_HI * s * out) end
	-- beim Einfahren erst die Arme anlegen (Ellbogen stehen sonst seitlich ueber die Waende), dann absinken
	if (jack.tucked and jack.arm_err > 15) then u_goal = math.max(u_goal, jack.ext_u.v) end
	-- kurz ducken vor dem POP
	if (jack.peek and now < jack.crouch_until) then u_goal = u_goal - 12 * s end
	SpringStep(jack.ext_u, u_goal, et.k, et.c, dt)
	-- (der Deckel wartet, solange die Arme noch weit ausholen, z. B. ueber den Kopf zurueck nach einem POP)
	if (et.close_lid) then jack.lid_target = (jack.arm_err > 45) and LID_OPEN or 0 end

	-- Deckel (klappert im Intro; offen schlaegt er bei LID_STOP an und federt zurueck)
	local lid = jack.lid
	local lid_goal = jack.lid_target
	if (jack.rattle and lid_goal < 5) then lid_goal = (math.sin(time * 37) > 0.2) and (6 + math.random() * 8) or 0 end
	SpringStep(lid, lid_goal, 220, 16, dt)
	if (lid.v > LID_STOP) then
		lid.v = LID_STOP
		if (lid.vel > 0) then lid.vel = -lid.vel * 0.3 end
	elseif (lid.v < -2) then
		lid.v = -2
		if (lid.vel < 0) then lid.vel = 0 end
	end
	-- Nie durch Jack hindurch: ragt er noch heraus, liegt der Deckel auf ihm auf und bewegt sich mit ihm
	local clear = LidClearance(jack)
	if (lid.v < clear) then
		local follow = (clear - (jack.lid_clear or clear)) / math.max(dt, 0.001)
		lid.v = clear
		lid.vel = math.max(lid.vel, follow)
	end
	jack.lid_clear = clear
	if (math.abs(lid.v - jack.lid_shown) > 0.05) then
		jack.lid_shown = lid.v
		jack.lid_pivot:SetRelativeRotation(Rotator(lid.v, 0, 0))
	end

	-- Rotes Licht in der Kiste: stark beim Klappern (durch den Spalt), beim Gucken/Starren von unten auf Jack
	local glow_goal = 0
	if (jack.rattle) then glow_goal = 12
	elseif (jack.stare) then glow_goal = 2.4
	elseif (jack.peek) then glow_goal = 0.5
	elseif (lid.v > 30 and not jack.tucked) then glow_goal = 0.25 end
	jack.inner_glow = jack.inner_glow + (glow_goal - jack.inner_glow) * math.min(1, dt * 5)
	if (jack.inner_light:IsValid() and (jack.inner_glow > 0.01 or jack.inner_shown ~= 0)) then
		local v = (jack.inner_glow > 0.01) and jack.inner_glow * (0.85 + math.random() * 0.3) * s * s * Jack.light_k.inner or 0
		jack.inner_shown = v
		jack.inner_light:SetIntensity(v)
	end

	if (jack.face_k ~= Jack.light_k.face and jack.face_light:IsValid()) then
		jack.face_k = Jack.light_k.face
		jack.face_light:SetIntensity(FACE_LIGHT * s * s * jack.face_k)
	end

	-- Kiste drehen + Kurbel
	if (jack.yaw ~= jack.yaw_shown) then
		jack.yaw_shown = jack.yaw
		jack.box_root:SetRotation(Rotator(0, jack.yaw, 0))
	end
	if (crank_speed > 0) then
		jack.crank_angle = (jack.crank_angle + crank_speed * dt) % 360
		jack.crank:SetRelativeRotation(Rotator(jack.crank_angle, 0, 90))
	end

	-- Vorbeugen haengt fest am Vorfahren (beim POP bis ueber 90 Grad: der Kopf kommt tiefer als der Federteller),
	-- dazu das Buckeln beim Gucken
	local f, u = jack.ext_f.v, jack.ext_u.v
	jack.lean.v = -LeanOf(et.lean or LEAN_DEFAULT, f / s)
	SpringStep(jack.hunch, (jack.peek and not jack.tucked) and HUNCH or 0, 70, 15, dt)
	local bob = math.sin(time * 1.8) * 3 * s
	local roll_w = math.sin(time * 0.9) * 2.5

	-- Servo-Gelenke: Grundhaltung + Animationen (jedes Bild frisch berechnet, nichts summiert sich auf)
	local stepping = now >= jack.next_step
	if (stepping) then jack.next_step = now + SERVO_STEP end
	-- POP aus der Kiste: Arme bleiben angelegt, bis er heraus ist (sonst fahren Ellbogen durch die Waende)
	local arms_in = jack.tucked or (a.pop and a.pop.arms_hold and u < ARMS_OUT_U * s)
	local pose = arms_in and POSES.tuck or jack.pose
	local head_yaw, head_pitch, head_roll = 0, jack.pose.head_pitch, HEAD_TILT + math.sin(time * 0.7) * 4
	local jaw = jack.jaw_mood

	-- Lachen: Kopf in den Nacken, Kiefer klappert (schnappt bei jedem Klack zu), Arme trommeln, Rumpf huepft
	local flap_l, flap_r = 0, 0
	if (a.laugh) then
		local t = now - a.laugh.t0
		local k = math.max(0, 1 - t / a.laugh.duration)
		head_pitch = head_pitch + 22 * k + math.sin(t * 26) * 7 * k
		head_roll = head_roll + math.sin(t * 19) * 9 * k
		flap_l = math.abs(math.sin(t * 17)) * 30 * k
		flap_r = math.abs(math.sin(t * 17 + 1.5)) * 30 * k
		bob = bob + math.abs(math.sin(t * 14)) * 14 * s * k
		if (k > 0.3 and t >= (a.laugh.next_clack or 0)) then
			a.laugh.next_clack = t + 0.22 + math.random() * 0.1
			a.laugh.clack_at = t
			-- Klack-Geraeusch nur in der Show, nicht bei der Statue im Hub
			if (DeathBox.World.kind == "match") then
				DeathBox.Audio.Play3D("jaw_clack", Jack.MouthPoint(jack), 0.4, 0.9 + math.random() * 0.2, 2500)
			end
		end
		jaw = (t - (a.laugh.clack_at or -1) < 0.07) and 0 or math.max(jaw, 6 + 20 * k)
		if (t > a.laugh.duration) then
			a.laugh = nil
			if (jack.face == "laugh") then Jack.SetFace(jack, "idle") end
		end
	end

	-- Enttaeuscht: Kopfschuetteln, Kiefer haengt, sacken
	if (a.sad) then
		local t = now - a.sad.t0
		local k = math.max(0, 1 - t / a.sad.duration)
		head_yaw = head_yaw + math.sin(t * 8) * 22 * k
		head_pitch = head_pitch - 18 * k
		jaw = math.max(jaw, 7 * k)
		flap_l, flap_r = flap_l - 14 * k, flap_r - 14 * k
		bob = bob - 18 * s * k
		if (t > a.sad.duration) then
			a.sad = nil
			Jack.ApplyFace(jack)
		end
	end

	-- Zufaelliges Zucken (Animatronic-Defekt): Kopf ruckt, Kiefer klappt kurz auf
	if (now >= jack.next_twitch) then
		jack.next_twitch = now + 1.8 + math.random() * 3.5
		jack.twitch = { t0 = now, yaw = (math.random() - 0.5) * ((jack.peek or jack.stare) and 16 or 50), roll = (math.random() - 0.5) * 30 }
		if (DeathBox.World.kind == "match" and not jack.tucked) then
			DeathBox.Audio.Play3D("servo_twitch", jack.center + Vector(0, 0, 300 * s), 0.35, 0.9 + math.random() * 0.3, 2500)
		end
	end
	if (jack.twitch) then
		local t = now - jack.twitch.t0
		if (t < 0.18) then
			head_yaw = head_yaw + jack.twitch.yaw
			head_roll = head_roll + jack.twitch.roll
			jaw = jaw + 6
		elseif (t > 0.5) then
			jack.twitch = nil
		end
	end

	-- Rumpf-Position (nur Zahlen): in Blickrichtung der Kiste vor (f) und hoch (u)
	local pitch_total = jack.lean.v - jack.hunch.v
	local rad = math.rad(jack.yaw)
	local cosy, siny = math.cos(rad), math.sin(rad)
	local c = jack.center
	local rx, ry, rz = c.X + cosy * f, c.Y + siny * f, c.Z + u + bob
	local neck = jack.neck.cur

	-- Gucken/Starren: Kopf nach vorne auf die Stuehle gerichtet (Augenhoehe der Sitzenden), beim Starren kippt er
	-- langsam zur Seite, schiebt den Kopf vor und oeffnet den Kiefer
	if (jack.peek and not a.pop) then
		local face_z = (u + bob) / s + (COLLAR + neck + FACE_Z)
		local goal = math.deg(atan2(jack.search.z / s - face_z, math.max(50, jack.search.dist / s - FACE_X)))
		head_pitch = goal - pitch_total
		if (jack.stare) then
			local k = Clamp((now - jack.stare) / 1.6, 0, 1)
			head_roll = head_roll + STARE_TILT * k
			jaw = math.max(jaw, 7 * k)
		end
	end

	-- Starrt DICH an: in Ruhe dreht Jack den Kopf zur Kamera des lokalen Spielers (jeder sieht sich selbst angestarrt)
	local busy = a.spin or a.pop or a.throw or a.laugh or a.sad or a.intro or jack.pose_name ~= "idle" or jack.tucked or jack.peek
	if (not busy and u > TRACK_MIN_U * s) then
		local player = Client.GetLocalPlayer()
		local cam = player and player:GetCameraLocation()
		if (cam) then
			local dx, dy, dz = cam.X - rx, cam.Y - ry, cam.Z - (rz + (COLLAR + neck + 50) * s)
			local flat = math.sqrt(dx * dx + dy * dy)
			if (flat < 6000 * s) then
				head_yaw = head_yaw + Clamp(AngleDelta(jack.yaw, math.deg(atan2(dy, dx))), -TRACK_YAW, TRACK_YAW)
				head_pitch = head_pitch + Clamp(math.deg(atan2(dz, math.max(flat, 1))), -42, 35)
			end
		end
	end

	-- POP: der Kopf bleibt aufs Opfer gerichtet, egal wie weit sich der Rumpf ueber die Kante beugt (wie ein Vogel)
	local pop_face = a.pop and (jack.pose_name == "reach" or jack.pose_name == "lunge")
	if (pop_face) then head_pitch = POP_FACE - pitch_total end

	-- In der Kiste: Kopf gerade, Arme angelegt (nichts ragt durch Waende oder Deckel, egal was gerade lief)
	if (jack.tucked) then
		head_yaw, head_pitch, head_roll = 0, POSES.tuck.head_pitch, HEAD_TILT
	end

	-- Hals: beim Starren schiebt er den Kopf langsam vor
	if (jack.peek and jack.stare and not jack.tucked) then
		jack.neck.target = NECK_PEEK + (NECK_STARE - NECK_PEEK) * Clamp((now - jack.stare) / 1.8, 0, 1)
	end
	jack.neck.speed = a.pop and 320 or 150
	ServoStep(jack.neck, (now < jack.servo_boost_until) and dt * 3 or dt, stepping, 0)

	-- Arme: Griffe per IK (Ziele im Rumpf-Rahmen dieses Bildes), sonst feste Winkel
	local R1, R2, R3, S1, S2, S3, T1, T2, T3 = Rows(pitch_total, 0, roll_w)   -- Rumpf relativ zur Kiste
	local fb, ub = f / s, (u + bob) / s
	local function ToRoot(bx, by, bz)
		local wx, wy, wz = bx - fb, by, bz - ub
		return wx * R1 + wy * R2 + wz * R3, wx * S1 + wy * S2 + wz * S3, wx * T1 + wy * T2 + wz * T3
	end
	local function DirToRoot(bx, by, bz)
		return bx * R1 + by * R2 + bz * R3, bx * S1 + by * S2 + bz * S3, bx * T1 + by * T2 + bz * T3
	end
	-- Kistenrahmen des Opfer-Auges (fuer "reach")
	local vx, vy, vz
	if (jack.reach_point) then
		local dx, dy = (jack.reach_point.X - c.X) / s, (jack.reach_point.Y - c.Y) / s
		vx, vy, vz = dx * cosy + dy * siny, -dx * siny + dy * cosy, (jack.reach_point.Z - c.Z) / s
	end
	-- In Ruhe trommelt er mit den Krallen auf die Kiste (abwechselnd links/rechts, zwei kurze Schlaege)
	local tap_r, tap_l = false, false
	if (jack.pose_name == "idle" and not arms_in and not a.laugh and not a.sad) then
		if (now >= jack.next_tap) then
			jack.next_tap = now + 2.2 + math.random() * 3.5
			jack.tap_t0, jack.tap_side = now, -jack.tap_side
		end
		local t = now - jack.tap_t0
		if (t < 0.45 and math.floor(t * 9) % 2 == 0) then
			if (jack.tap_side > 0) then tap_r = true else tap_l = true end
		end
	end
	local arm_targets = {}
	for _, side in ipairs({ "r", "l" }) do
		local sy = (side == "r") and 1 or -1
		local spec = pose[side]
		local arm = jack.arm[side]
		local sp, ya, sr, el, claw
		local flap = (side == "r") and flap_r or flap_l
		local lift = math.max(0, flap) * 0.45          -- Griffe: Lachen/Trommeln hebt die Hand an, nie in die Kiste
		if (spec.grip == "rim" or (spec.grip == "reach" and not vx)) then
			local tap = (side == "r") and tap_r or tap_l
			local hx, hy, hz = ToRoot(RIM_HAND_X + (tap and 2 or 0), sy * (spec.y or 47), RIM_HAND_Z + (tap and 7 or 0) + lift)
			local p, y, r, e = SolveArm(sy, hx, hy, hz, -0.35, sy * 1, 0.6)
			sp, ya, sr = ArmAngles(sy, arm, p, y, r)
			el = e
			local dx, dy, dz = DirToRoot(0.12, 0, -1)
			local wx, wy, wz = DirToRoot(0, 1, 0)
			claw = { dx, dy, dz, wx, wy, wz }
		elseif (spec.grip == "reach") then
			-- vom Opfer waagerecht Richtung Kistenmitte (ox, oy), seitlich dazu (oy, -ox) = Jacks rechte Seite
			local ol = math.max(1, math.sqrt(vx * vx + vy * vy))
			local ox, oy = -vx / ol, -vy / ol
			local fwd, side = spec.fwd or 35, sy * (spec.spread or 50)
			local bx, by, bz = vx + ox * fwd + oy * side, vy + oy * fwd - ox * side, vz + (spec.up or 8) + lift
			local hx, hy, hz = ToRoot(bx, by, bz)
			local p, y, r, e = SolveArm(sy, hx, hy, hz, -0.3, sy * 1, 0.7)
			sp, ya, sr = ArmAngles(sy, arm, p, y, r)
			el = e
			local cx, cy = vx + oy * sy * 14, vy - ox * sy * 14
			local dx, dy, dz = DirToRoot(cx - bx, cy - by, vz + 2 - bz)
			local wx, wy, wz = DirToRoot(0, 0, 1)
			claw = { dx, dy, dz, wx, wy, wz }
		else
			-- feste Winkel: jeweils die naechstgelegene volle Umdrehung (nach IK-Griffen nie eine 360-Grad-Pirouette)
			sp, ya, sr, el = Near(spec.sp + flap, arm.sp.cur), Near(spec.ya, arm.ya.cur), Near(spec.sr, arm.sr.cur), spec.el
		end
		arm_targets[side] = { sp = sp, ya = ya, sr = sr, el = el, claw = claw, fingers = spec.fingers }
	end
	-- Wurf mit dem rechten Arm: ausholen, dann nach vorne schnellen
	if (a.throw) then
		local t = now - a.throw.t0
		local at = arm_targets.r
		local ra = jack.arm.r
		if (t < 0.28) then at.sp, at.ya, at.sr, at.el, at.claw = Near(-70, ra.sp.cur), Near(0, ra.ya.cur), Near(10, ra.sr.cur), 60, nil
		elseif (t < 0.7) then at.sp, at.ya, at.sr, at.el, at.claw = Near(110, ra.sp.cur), Near(0, ra.ya.cur), Near(6, ra.sr.cur), 0, nil
		else a.throw = nil end
	end

	jack.head_yaw.target, jack.head_pitch.target, jack.head_roll.target = head_yaw, head_pitch, head_roll
	-- beim POP haelt der Nacken das Gesicht ohne Verzoegerung aufs Opfer (die Neigung folgt fest dem Vorfahren)
	if (pop_face) then jack.head_pitch.cur = head_pitch end
	jack.jaw.target = Clamp(jaw, 0, 26)
	for _, side in ipairs({ "l", "r" }) do
		local arm, t = jack.arm[side], arm_targets[side]
		arm.sp.target, arm.ya.target, arm.sr.target, arm.el.target = t.sp, t.ya, t.sr, t.el
	end
	local servo_dt = (now < jack.servo_boost_until) and dt * 3 or dt     -- beim Einfahren schnappen alle Gelenke an
	local servos = jack.servos
	local arm_err = 0
	for i = 1, #servos do
		local sv = servos[i]
		ServoStep(sv, servo_dt, stepping)
		if (i > 4) then arm_err = math.max(arm_err, math.abs(sv.target - sv.cur), math.abs(sv.target - sv.shown)) end
	end
	jack.arm_err = arm_err

	-- Lider (blinzeln, Stimmung, zu in der Kiste) und Brauen
	if (now >= jack.next_blink) then
		jack.next_blink = now + 2.5 + math.random() * 4
		jack.blink_until = now + 0.16
	end
	local lid_goal = jack.mood.lid
	if (jack.tucked) then lid_goal = 1
	elseif (now < jack.blink_until) then lid_goal = 1 end
	jack.lids.target = lid_goal
	jack.lids.speed = (now < jack.blink_until or lid_goal > 0.9) and 14 or 3
	ServoStep(jack.lids, dt, stepping, 0)
	ServoStep(jack.brow, dt, stepping, 0)
	ServoStep(jack.brow_lift, dt, stepping, 0)

	jack.root:SetLocation(Vector(rx, ry, rz))
	jack.root:SetRotation(Rotator(pitch_total, jack.yaw, roll_w))
	jack.pitch, jack.roll = pitch_total, roll_w

	-- Gelenke zeigen sich nur in Servo-Schritten (14 pro Sekunde): nur dann neue Drehungen setzen
	if (stepping) then
		if (math.abs(jack.neck.shown - jack.neck_shown) > 0.05) then
			jack.neck_shown = jack.neck.shown
			jack.head:SetRelativeLocation(Vector(0, 0, (COLLAR + jack.neck.shown) * s))
			if (jack.neck_tube:IsValid()) then jack.neck_tube:SetRelativeLocation(Vector(0, 0, (COLLAR + jack.neck.shown - 26) * s)) end
		end
		jack.head:SetRelativeRotation(Rotator(jack.head_pitch.shown, jack.head_yaw.shown, jack.head_roll.shown))
		jack.jaw_pivot:SetRelativeRotation(Rotator(-math.max(0, jack.jaw.shown), 0, 0))
		local l, r = jack.arm.l, jack.arm.r
		jack.shoulder_r:SetRelativeRotation(Rotator(r.sp.shown, r.ya.shown, -r.sr.shown))
		jack.shoulder_l:SetRelativeRotation(Rotator(l.sp.shown, -l.ya.shown, l.sr.shown))
		jack.elbow_r:SetRelativeRotation(Rotator(r.el.shown, 0, 0))
		jack.elbow_l:SetRelativeRotation(Rotator(l.el.shown, 0, 0))
		-- Knoechel: bei jedem Haltungswechsel und angelegt klappen die Krallen ein und erst wieder auf, wenn die Arme
		-- angekommen sind (nichts schrammt am Kistenrand). Griffe: Krallen nach der gezeigten Armhaltung ausrichten.
		if (pose ~= jack.arm_pose) then
			jack.arm_pose = pose
			jack.fingers_folded = true
		elseif (jack.fingers_folded and not arms_in and arm_err < 10) then
			jack.fingers_folded = false
		end
		for _, side in ipairs({ "r", "l" }) do
			local sy = (side == "r") and 1 or -1
			local arm, t = jack.arm[side], arm_targets[side]
			local rot
			if (jack.fingers_folded) then rot = FINGERS_FIST
			elseif (t.claw) then
				local cw = t.claw
				rot = FingerRot(sy, arm.sp.shown, arm.ya.shown, arm.sr.shown, arm.el.shown, cw[1], cw[2], cw[3], cw[4], cw[5], cw[6])
			else rot = t.fingers or FINGERS_STRAIGHT end
			local key = "fingers_shown_" .. side
			if (rot ~= jack[key]) then
				jack[key] = rot
				jack["fingers_" .. side]:SetRelativeRotation(rot)
			end
		end

		-- Lider wachsen von oben ueber die Augenhoehle
		if (math.abs(jack.lids.shown - jack.lids_shown) > 0.004) then
			jack.lids_shown = jack.lids.shown
			local v = Clamp(jack.lids.shown, 0, 1)
			for _, lid_e in ipairs(jack.eyelids) do
				if (lid_e.mesh:IsValid()) then
					local h = math.max(0.6, lid_e.height * v)
					local tp, up = lid_e.top, lid_e.up
					lid_e.mesh:SetRelativeLocation(Vector((tp[1] - up[1] * h / 2) * s, (tp[2] - up[2] * h / 2) * s, (tp[3] - up[3] * h / 2) * s))
					lid_e.mesh:SetScale(Vector(h * s / 100, lid_e.width * s / 100, lid_e.depth * s / 100))
				end
			end
		end
		-- Brauen: Neigung (+ = aussen hoch) und Hub je Stimmung
		local bk = jack.brow.shown * 100 + jack.brow_lift.shown
		if (math.abs(bk - jack.brow_shown) > 0.05) then
			jack.brow_shown = bk
			for _, b in ipairs(jack.brows) do
				if (b.mesh:IsValid()) then
					local n = b.n
					local tilt = (b.side > 0) and -jack.brow.shown or jack.brow.shown
					local rot, hx, hy, hz = SurfaceRot(n[1], n[2], n[3], 0, b.side, 0, tilt)
					local lift = jack.brow_lift.shown
					-- Hoch-Richtung in der Flaeche (ohne Neigung)
					local _, ux, uy, uz = SurfaceRot(n[1], n[2], n[3], 0, b.side, 0, 0)
					local sgn = (b.side > 0) and -1 or 1
					local px, py, pz = b.x + n[1] * 2.4 + sgn * ux * lift, b.y + n[2] * 2.4 + sgn * uy * lift, b.z + n[3] * 2.4 + sgn * uz * lift
					b.mesh:SetRelativeLocation(Vector(px * s, py * s, pz * s))
					b.mesh:SetRelativeRotation(rot)
				end
			end
		end

		-- Die linke Pupille hat einen Wackelkontakt
		if (now >= jack.next_flicker) then
			jack.next_flicker = now + 3 + math.random() * 5
			jack.flicker_until = now + 0.3 + math.random() * 0.4
		end
		local e = jack.eyes[2]
		if (e and e.mesh:IsValid()) then
			local off = now < jack.flicker_until and math.random() < 0.6
			if (off ~= e.off) then
				e.off = off
				e.mesh:SetMaterialColorParameter("Emissive", off and EYE_OFF or e.on)
			end
		end
	end

	-- Suchstrahl: aus dem Gesicht auf die Kopfhoehe der Sitzenden in Blickrichtung (beim Starren heller)
	local sk_goal = jack.search.on and (SEARCH_LIGHT * (jack.stare and 1.7 or 1)) or 0
	jack.search.k = jack.search.k + (sk_goal - jack.search.k) * math.min(1, dt * (jack.search.on and 4 or 10))
	local beam = jack.search_light
	if (beam and beam:IsValid() and (jack.search.k > 0.05 or jack.search.shown ~= 0)) then
		if (jack.search.k > 0.05) then
			-- Gesichtspunkt in der Welt: Rumpf -> Hals -> Kopf (gezeigte Winkel)
			local A1, A2, A3, B1, B2, B3, C1, C2, C3 = Rows(pitch_total, jack.yaw, roll_w)
			local H1, H2, H3, I1, I2, I3, J1, J2, J3 = Rows(jack.head_pitch.shown, jack.head_yaw.shown, jack.head_roll.shown)
			local fx, fz = FACE_X + 6, FACE_Z + 4
			-- Kopf-Rahmen -> Rumpf-Rahmen
			local qx, qy, qz = fx * H1 + fz * J1, fx * H2 + fz * J2, (COLLAR + jack.neck.shown) + fx * H3 + fz * J3
			local wx = rx + (qx * A1 + qy * B1 + qz * C1) * s
			local wy = ry + (qx * A2 + qy * B2 + qz * C2) * s
			local wz = rz + (qx * A3 + qy * B3 + qz * C3) * s
			local yaw = jack.yaw + jack.head_yaw.shown
			local yr = math.rad(yaw)
			local tx, ty = c.X + math.cos(yr) * jack.search.dist, c.Y + math.sin(yr) * jack.search.dist
			local flat = math.sqrt((tx - wx) ^ 2 + (ty - wy) ^ 2)
			local pitch = math.deg(atan2(c.Z + jack.search.z - wz, math.max(flat, 30 * s)))
			beam:SetLocation(Vector(wx, wy, wz))
			beam:SetRotation(Rotator(pitch, yaw, 0))
			local v = jack.search.k * (0.9 + math.random() * 0.2) * (DeathBox.World.light_scale or 1) * s * s * Jack.light_k.search
			jack.search.shown = v
			beam:SetIntensity(v)
		else
			jack.search.shown = 0
			beam:SetIntensity(0)
		end
	end

	-- Feder vom Kistenboden bis unter den Federteller (folgt der Rumpfneigung; gestaucht, wenn Jack in der Kiste steckt).
	-- Steht sie still (nur leichtes Wippen), wird sie nur in Servo-Schritten nachgezogen.
	local lr = math.rad(pitch_total)
	local sn, cs = math.sin(lr), math.cos(lr)
	local tx, ty, tz = rx + PLATE * s * sn * cosy, ry + PLATE * s * sn * siny, rz - PLATE * s * cs
	local bz = c.Z + 30 * s
	if (tz < bz + 20 * s) then tz = bz + 20 * s end
	local last = jack.spring
	if (stepping or math.abs(tx - last[1]) + math.abs(ty - last[2]) + math.abs(tz - last[3]) > 0.4 * s) then
		last[1], last[2], last[3] = tx, ty, tz
		-- Kontrollpunkt: senkrecht ueber dem Boden, auf der Koerperachse hinter dem Teller (die Feder laeuft gerade in
		-- den Teller, beim POP von oben ueber die Kante gebogen); aufrecht oder fast aufrecht: Mitte (gerade Feder)
		local hx, hy = tx - c.X, ty - c.Y
		local dh, uh = math.sqrt(hx * hx + hy * hy), -sn
		local cz = (bz + tz) * 0.5
		if (dh > s and uh > 0.17) then cz = Clamp(tz - dh * cs / uh, bz + (tz - bz) * 0.45, math.max(tz, bz) + 90 * s) end
		LayoutRings(jack, c.X, c.Y, bz, tx, ty, tz, cz)
	end
end

-- Konsole: Jacks Lichter skalieren (Suchstrahl, rotes Licht aus der Kiste, Fuelllicht vor dem Gesicht), Standard 1 1 1
Console.RegisterCommand("db_jacklight", function(search, inner, face)
	local k = Jack.light_k
	k.search = tonumber(search) or k.search
	k.inner = tonumber(inner) or k.inner
	k.face = tonumber(face) or k.face
	Console.Log("[DeathBox] Jacks Lichter: Suchstrahl %s, Kiste %s, Gesicht %s", tostring(k.search), tostring(k.inner), tostring(k.face))
end, "DeathBox: Jacks Lichter skalieren (Suchstrahl, Kiste, Gesicht)", { "suchstrahl", "kiste", "gesicht" })
