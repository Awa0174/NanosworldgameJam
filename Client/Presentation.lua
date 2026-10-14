-- Client/Presentation.lua
-- Die Regie: setzt die Anweisungen des Servers ("DeathBox:Show", siehe docs/PROTOCOL.md) in Bild und Ton um.
-- Der Server entscheidet WAS passiert, hier wird entschieden, WIE es aussieht und klingt.
-- Alles ist lokal: Jack, Licht, Musik, Requisiten, Blut. Kein Netzwerk, kein Ruckeln.
--
-- Ablauf einer Auswahl (Zeiten aus Shared/Config.lua, passend zur Spieluhr-Musik):
--   spin   Jack lugt aus der offenen Kiste (Kopf und Schultern ueber dem Rand) und dreht sich langsam mit ihr, ein roter
--          Suchstrahl aus seinen Augen streicht ueber die Stuehle: jeder Stuhl flackert auf + Holz-Tick, am Ende kriecht er
--   (hold) Kiste steht vor dem Opfer: Starren (Kopf kippt, Lider halb zu), Strahl + ROT auf dem Opfer, Licht im Zelt fast
--          aus, Herzschlag (Audio.Music startet ihn am Ende der Melodie)
--   pop    "POP!" – Jack schiesst auf seiner Feder heraus, sein Gesicht schwebt ca. 1 m vor dem des Opfers, er lacht;
--          das Opfer wird GOLD markiert (gewaehlt)
--   card   Trommelwirbel und Event-Karte

DeathBox.Presentation = {
	state = nil,      -- letzter oeffentlicher Tischzustand (fuer Sitzplaetze/Namen)
	temp = nil,       -- Requisiten der aktuellen Runde (Messer, Feuer, Kuerbis ...)
	timers = {},
	tension = nil,    -- laufende Anspannungs-Animation
}

local P = DeathBox.Presentation
local Builder = DeathBox.Builder
local Layout = DeathBox.Layout
local Audio = DeathBox.Audio
local Atmosphere = DeathBox.Atmosphere
local Jack = DeathBox.Jack
local Tent = DeathBox.Tent
local Revolver = DeathBox.Revolver
local Config = DeathBox.Config

-- Markierung der Figuren (GOLD = gewaehlt/am Zug, ROT = in Gefahr), nur wenn Client/Highlight.lua geladen ist
local function Glow(fn, ...)
	local H = DeathBox.Highlight
	if (not H or not H[fn]) then return end
	local ok, err = pcall(H[fn], ...)
	if (not ok) then Console.Warn("[DeathBox] Highlight.%s: %s", fn, tostring(err)) end
end
local GOLD = Color(1, 0.75, 0.3)

-- Leuchtfarben der Karten (fuer die 3D-Karten ueber den Koepfen)
local CARD_COLORS = {
	safety = Color(0.3, 1, 0.5), skip = Color(0.4, 0.7, 1), ricochet = Color(1, 0.7, 0.2),
	guardian = Color(1, 0.95, 0.6), thief = Color(0.7, 0.3, 1),
}

-- ===================================================================
-- Hilfen
-- ===================================================================

local function After(seconds, fn)
	local id
	id = Timer.SetTimeout(function()
		P.timers[id] = nil
		fn()
	end, math.max(0, seconds) * 1000)
	P.timers[id] = true
	return id
end

local function Temp()
	if (not P.temp) then P.temp = Builder.New() end
	return P.temp
end

local function ClearTemp()
	if (P.temp) then Builder.Destroy(P.temp) end
	P.temp = nil
	P.knife, P.cleaver, P.fire, P.fire_light, P.pumpkin, P.bomb, P.fan = nil, nil, nil, nil, nil, nil, nil
	P.gun, P.jack_gun, P.duel = nil, nil, nil
end

-- Alle noch geplanten Effekte der letzten Szene verwerfen (z. B. wenn der Sieg mitten in einen Spin faellt)
local function CancelTimers()
	for id in pairs(P.timers) do
		if (Timer.IsValid(id)) then Timer.ClearTimeout(id) end
	end
	P.timers = {}
end

local LOOP_KEYS = { "heart", "fuse", "drone", "crank" }

local function StopLoops(fade)
	for _, key in ipairs(LOOP_KEYS) do Audio.StopLoop(key, fade or 0.2) end
end

function P.Reset()
	CancelTimers()
	ClearTemp()
	if (P.tension) then Builder.RemoveTicker(P.tension) end
	P.tension = nil
	Audio.StopMusic(0.3)
	StopLoops(0.2)
	Audio.DuckAmbience(1)
	Atmosphere.SetTension(0)
end

function P.SetState(state)
	P.state = state
	local tent = DeathBox.World.tent
	if (tent and state and state.seats and state.match == DeathBox.World.match_id) then
		local ok, err = pcall(Tent.UpdateSeats, tent, state.seats)
		if (not ok) then Console.Warn("[DeathBox] Platz-Markierungen: %s", tostring(err)) end
	end
end

local function CurrentTent() return DeathBox.World.tent end

local function ChairAngle(tent, chair)
	return Layout.ChairAngle(chair, tent.seat_count)
end

-- Kopfhoehe einer sitzenden Figur (Ziel fuer Jack und Requisiten). Konsole: db_head <cm>
P.head_height = Config.WORLD.HEAD_HEIGHT or 45
local function HeadPoint(tent, chair)
	return Tent.ChairPoint(tent, chair, P.head_height)
end

Console.RegisterCommand("db_head", function(cm)
	P.head_height = tonumber(cm) or Config.WORLD.HEAD_HEIGHT or 45
	Console.Log("[DeathBox] Kopfhoehe ueber dem Sitz: %s cm", tostring(P.head_height))
end, "DeathBox: Kopfhoehe sitzender Figuren fuer Effekte (cm)", { "cm" })

-- Richtung vom Platz zur Manegenmitte (waagerecht)
local function Inward(tent, chair)
	local rad = math.rad(ChairAngle(tent, chair))
	return Vector(-math.cos(rad), -math.sin(rad), 0)
end

-- Hier schwebt der Revolver eines Spielers: vor der Brust, etwas zur Mitte hin
local function HoldPoint(tent, chair)
	return HeadPoint(tent, chair) + Inward(tent, chair) * 50 - Vector(0, 0, 28)
end

local function IsMe(seat_index)
	local player = Client.GetLocalPlayer()
	if (not player or not P.state or not P.state.seats) then return false end
	for _, s in pairs(P.state.seats) do
		if (s.seat == seat_index) then return s.id == player:GetID() end
	end
	return false
end

-- Anspannung weich von a nach b ueber seconds
local function RampTension(to, seconds)
	if (P.tension) then Builder.RemoveTicker(P.tension) end
	local from = Atmosphere.tension
	local t0 = Builder.time
	P.tension = Builder.AddTicker(nil, function()
		local p = math.min(1, (Builder.time - t0) / math.max(0.01, seconds))
		Atmosphere.SetTension(from + (to - from) * p)
		if (p >= 1) then return false end
	end)
end

-- Objekt in seconds von a nach b bewegen, optional im Bogen (arc = Hoehe in cm) und drehend
local function Fly(mesh, from, to, seconds, arc, spin_per_second, on_done)
	local t0 = Builder.time
	local rot = mesh:GetRotation()
	mesh:SetValue("DB_Flying", true)
	Builder.AddTicker(P.temp, function()
		if (not mesh:IsValid()) then return false end
		local p = math.min(1, (Builder.time - t0) / seconds)
		local pos = from + (to - from) * p + Vector(0, 0, (arc or 0) * 4 * p * (1 - p))
		mesh:SetLocation(pos)
		if (spin_per_second) then
			mesh:SetRotation(Rotator(rot.Pitch + spin_per_second * (Builder.time - t0), rot.Yaw, rot.Roll))
		end
		if (p >= 1) then
			mesh:SetValue("DB_Flying", false)
			if (on_done) then on_done() end
			return false
		end
	end)
end

-- Leichtes Zittern eines schwebenden Objekts (Messer, Hackbeil, Kuerbis)
local function Tremble(mesh, strength)
	local base = mesh:GetLocation()
	mesh:SetValue("DB_Base", base)
	Builder.AddTicker(P.temp, function(dt, time)
		if (not mesh:IsValid()) then return false end
		if (mesh:GetValue("DB_Flying")) then return end
		local b = mesh:GetValue("DB_Base") or base
		local k = strength or 1.5
		mesh:SetLocation(b + Vector(math.sin(time * 41) * k, math.cos(time * 37) * k, math.sin(time * 3) * 4))
	end)
end

-- Kleine leuchtende Karte (3D) ueber einem Platz, steigt auf und verschwindet
local function FloatingCard(tent, chair, color, then_fly_to_chair)
	local start = HeadPoint(tent, chair) + Vector(0, 0, 50)
	local card = Builder.Box(Temp(), start, Vector(3, 30, 44), { color = Color(0.9, 0.85, 0.7), emissive = (color or GOLD) * 6, shadow = false })
	card:SetRotation(Rotator(0, ChairAngle(tent, chair), 0))
	if (then_fly_to_chair) then
		Fly(card, start, HeadPoint(tent, then_fly_to_chair) + Vector(0, 0, 40), 0.6, 120, 360, function()
			if (card:IsValid()) then After(0.8, function() if (card:IsValid()) then card:Destroy() end end) end
		end)
	else
		Fly(card, start, start + Vector(0, 0, 90), 1.4, 0, 180, function()
			if (card:IsValid()) then card:Destroy() end
		end)
	end
	return card
end

-- Schriftzug ueber einem Kopf (zeigt immer zur Kamera), steigt leicht und verschwindet nach seconds
local function FloatLabel(tent, chair, text, color, seconds)
	local at = HeadPoint(tent, chair) + Vector(0, 0, 70)
	local label = TextRender(at, Rotator(), text, 34, color, TextRenderRenderingType.UnlitCameraAlignedDepth,
		TextRenderHorizontalAlignment.Center, TextRenderVerticalAlignment.Center, "nanos-world::Font_BoldPixels_DistanceField", false)
	table.insert(Temp().entities, label)
	local t0 = Builder.time
	Builder.AddTicker(P.temp, function()
		if (not label:IsValid()) then return false end
		local t = Builder.time - t0
		label:SetLocation(at + Vector(0, 0, math.min(t, 1) * 25))
		if (t > (seconds or 3)) then label:Destroy() return false end
	end)
	return label
end

-- ===================================================================
-- Regieanweisungen
-- ===================================================================

local Handlers = {}

-- Showbeginn: Jack versteckt in der Kiste (Augen zu), jemand kurbelt, Spieluhr "Pop Goes the Weasel", der Deckel
-- klappert, beim "POP!" am Ende der Melodie springt er mit Fanfare und Konfetti heraus (HUD zeigt solange "How to play")
function Handlers.intro(tent, data)
	local duration = data.duration or Config.INTRO_TIME or 12
	local pop_at = math.max(3, math.min(data.pop_at or Config.INTRO_POP_AT or (duration - 2), duration - 1.5))
	Glow("Clear")
	Jack.IntroPop(tent.jack, pop_at)
	Audio.Music(data.music or Config.INTRO_MUSIC or Config.SPIN_MUSIC, 0.9)
	-- Jemand kurbelt an der Kiste (die Kurbel dreht sich sichtbar mit, siehe Jack.Update)
	Audio.StartLoop("crank", "crank_turn", 0.3, 0.6, pop_at)
	Audio.DuckAmbience(0.25)
	Tent.SetMood(tent, "spin")
	RampTension(0.6, pop_at)
	After(math.max(0, pop_at - 1.5), function()
		Jack.Hold(tent.jack, true)
		Audio.StopLoop("crank", 0.15)
		Audio.Play3D("chain_rattle", tent.center + Vector(0, 0, 150), 0.45, 1, 3000)
	end)
	After(pop_at, function()
		Jack.Hold(tent.jack, false)
		Audio.Play3D("spring_boing", tent.center + Vector(0, 0, 200), 0.9, 1, 3500)
		Audio.Play("show_fanfare", 0.7)
		Audio.Play("laugh", 0.9, 0.85)
		Builder.Particle(Temp(), tent.center + Vector(0, 0, 420), "confetti", Vector(2, 2, 2))
		Atmosphere.Flash(Color(1, 0.9, 0.7), 0.35, 0.6)
		Tent.SetMood(tent, "normal")
		RampTension(0, 1.5)
		Audio.DuckAmbience(1)
	end)
end

-- Ticks fuer eine laufende Drehung: jedes Mal, wenn Jacks Blick (Kistenfront + Suchstrahl) einen lebenden Platz
-- passiert, flackert dessen Stuhl auf und es tickt. Der letzte Tick ist das Opfer. Liefert die Liste fuers HUD.
local function SpinTicks(tent, spin, loud_last)
	local ticks = {}
	if (P.state and P.state.seats) then
		for _, s in pairs(P.state.seats) do
			if (s.alive) then
				for _, t in ipairs(Jack.SpinCrossings(spin, ChairAngle(tent, s.chair or s.seat))) do
					table.insert(ticks, { t = t, seat = s.seat })
				end
			end
		end
	end
	table.sort(ticks, function(a, b) return a.t < b.t end)
	for i, tick in ipairs(ticks) do
		local last = loud_last and (i == #ticks)
		After(tick.t, function()
			Audio.Play("tick", last and 0.9 or 0.55, last and 0.75 or (0.92 + math.random() * 0.16))
			Tent.FlareSeat(tent, tick.seat)
		end)
	end
	return ticks
end

-- Suchstrahl auf die Koepfe der Sitzenden richten (Radius des Stuhlkreises, Kopfhoehe)
local function SearchOn(tent)
	local W = Config.WORLD
	Jack.Searchlight(tent.jack, true, Layout.ChairRadius(tent.seat_count) - (W.SIT_FORWARD or 15), (W.SIT_HEIGHT or 100) + P.head_height)
end

-- Auswahl: Jack lugt aus der Kiste und dreht sich langsam mit ihr, Suchstrahl + Ticks, dann Starren
function Handlers.spin(tent, data)
	CancelTimers()
	StopLoops(0.2)
	ClearTemp()
	Tent.SpotChair(tent, nil)
	Tent.SpotChair(tent, nil, true)
	Glow("Clear")
	Jack.Aim(tent.jack, false)
	Jack.SetFace(tent.jack, "idle")
	local duration = data.duration or Config.SPIN_TIME
	local hold = data.hold or Config.HOLD_TIME
	local spin = Jack.Spin(tent.jack, data.target_yaw or 0, data.turns or Config.SPIN_TURNS or 1, duration, data.start_yaw)
	SearchOn(tent)
	-- Spieluhr; am Ende der Melodie startet Audio selbst den Herzschlag fuer die Stille (hold)
	Audio.Music(data.music or Config.SPIN_MUSIC, 0.9, hold)
	Audio.DuckAmbience(0.2)
	Tent.SetMood(tent, "spin")
	Jack.SetEyeGlow(tent.jack, 6)
	RampTension(0.5, duration)
	Audio.Play3D("servo_whir", tent.center + Vector(0, 0, 200), 0.5, 0.8, 3000)   -- Jack sinkt bis zu den Schultern ein
	data.ticks = SpinTicks(tent, spin, true)

	-- Starren: Kiste steht vor dem Opfer, Licht im Zelt fast aus, Strahl heller, Opfer ROT (in Gefahr)
	After(duration, function()
		Tent.SetMood(tent, "hold")
		Jack.Hold(tent.jack, true)
		Jack.SetEyeGlow(tent.jack, 12)
		Glow("Set", data.seat, "target")
		RampTension(1, hold)
	end)
	-- Ausholen: kurz ducken, dann POP
	After(math.max(duration, duration + hold - 0.32), function() Jack.Crouch(tent.jack) end)
end

-- POP: Jack schiesst heraus, sein Gesicht schwebt ca. 1 m vor dem des Opfers, er lacht. Opfer GOLD (gewaehlt).
function Handlers.pop(tent, data)
	if (not data.seat_chair) then return end
	Audio.StopLoop("heart", 0.1)
	local reveal = Config.REVEAL_TIME or 1.8
	Jack.PopOut(tent.jack, HeadPoint(tent, data.seat_chair), math.max(1.4, reveal - 0.9))
	Jack.Laugh(tent.jack, 1.6)
	Audio.Play3D("spring_boing", tent.center + Vector(0, 0, 200), 0.9, 1, 3500)
	After(0.15, function() Audio.Play3D("laugh", Jack.MouthPoint(tent.jack), 0.95, 0.85 + math.random() * 0.1, 4500) end)
	Jack.SetEyeGlow(tent.jack, 3)
	Tent.SpotChair(tent, data.seat_chair)
	Tent.SetMood(tent, "normal")
	Glow("Clear", "target")
	-- alle Gewaehlten GOLD (Duell, Split or Steal: beide), aeltere Server ohne actors: nur seat
	Glow("Set", (type(data.actors) == "table" and #data.actors > 0) and data.actors or data.seat, "actor")
	RampTension(0.25, 1.2)
	Audio.DuckAmbience(0.6)
	data.me = IsMe(data.seat)
	if (data.me) then
		Atmosphere.Flash(Color(0.7, 0, 0), 0.6, 0.9)
	else
		Atmosphere.Flash(Color(1, 1, 1), 0.2, 0.4)
	end
end

-- Skip-Karte: Jack starrte schon, die Karte zerbricht, sein Blick reisst herum zum naechsten Opfer, kurzes Starren,
-- SKIP_TIME nach dem Cue kommt der POP
function Handlers.skip(tent, data)
	Audio.Play("card_break", 0.8)
	if (data.seat_chair) then FloatingCard(tent, data.seat_chair, CARD_COLORS.skip) end
	Glow("Clear", "target")
	Jack.Hold(tent.jack, false)
	local skip_time = Config.SKIP_TIME or 2.2
	local turn = math.min(1.8, skip_time * 0.6)
	local target_yaw = data.target_yaw or (data.new_seat_chair and ChairAngle(tent, data.new_seat_chair)) or tent.jack.yaw
	local spin = Jack.Spin(tent.jack, target_yaw, 0, turn)
	SearchOn(tent)
	Audio.Play3D("crank_turn", tent.center + Vector(0, 0, 100), 0.6, 1.1, 3000)
	SpinTicks(tent, spin, false)
	After(turn, function()
		Jack.Hold(tent.jack, true)
		Glow("Set", data.new_seat, "target")
		Audio.Play("tick", 0.9, 0.75)
		if (Audio.HoldHeartbeat) then Audio.HoldHeartbeat(skip_time - turn) end
	end)
	After(math.max(turn, skip_time - 0.32), function() Jack.Crouch(tent.jack) end)
end

function Handlers.card(tent, data)
	if ((data.duration or 0) >= 2) then Audio.Play("drumroll", 0.5) end
	RampTension(0.35, 0.5)
	-- Choose a Card: Jack faechert drei Karten vor dem Gewaehlten auf (siehe card_gain)
	if (data.event == "choosecard" and data.seat_chair) then
		After(0.4, function() P.CardFan(tent, data.seat_chair) end)
	end
end

function Handlers.point(tent, data)
	if (data.seat_chair) then Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.5) end
end

-- ---------------------------------------------------------------- Revolver (Kette)
-- Der Revolver liegt in der RECHTEN HAND des Halters (Client/World/Revolver.lua, Hand-Modus) – bei jedem Client:
--   give      Jack wirft ihn in die Hand, Lauf gesenkt; Halter GOLD markiert, goldener Spot
--   aiming    der Halter zielt live (Client/Aim.lua bzw. Echo vom Server): Arm hebt sich (Client/Poses.lua), der Lauf
--             zeigt aufs anvisierte Ziel, das ROT leuchtet und den roten Spot bekommt
--   aim       Ziel steht fest: Hahn gespannt, Hand zittert; zoegert der Halter, reisst Jack ihm den Revolver aus der
--             Hand und haelt ihm den Lauf vors eigene Gesicht
--   shot      Klick (Trommel weiter, kleiner Ruck) oder Knall (Muendungsfeuer, Rueckstoss um die Hand, Revolver faellt)
--   pass      von Hand zu Hand zum naechsten Halter
-- Findet sich keine Figur zum Platz (Highlight.FindCharacter), schwebt der Revolver wie frueher vor der Brust.

-- Highlight nur, wenn das Modul geladen ist (Client/Highlight.lua)
local function Mark(fn, ...)
	local H = DeathBox.Highlight
	if (not H or not H[fn]) then return end
	local ok, err = pcall(H[fn], ...)
	if (not ok) then Console.Warn("[DeathBox] Highlight.%s: %s", fn, tostring(err)) end
end

local function SeatChair(seat)
	if (P.state and P.state.seats) then
		for _, s in pairs(P.state.seats) do
			if (s.seat == seat) then return s.chair or seat end
		end
	end
	return seat
end

local function SeatCharacter(seat)
	local H = DeathBox.Highlight
	if (not seat or not H or not H.FindCharacter) then return nil end
	return H.FindCharacter(seat)
end

local function AimPose(seat, on)
	local Poses = DeathBox.Poses
	local character = Poses and Poses.SetAiming and SeatCharacter(seat)
	if (character) then Poses.SetAiming(character, on) end
end

-- Worauf der Lauf in der Hand zeigt: anvisierter Kopf, sonst gesenkt schraeg vor den Halter auf den Boden
local function GunLook(tent)
	local g = P.gun_state
	if (not g) then return tent.center end
	if (g.aim_chair) then return HeadPoint(tent, g.aim_chair) end
	return Tent.ChairFloor(tent, g.chair) + Inward(tent, g.chair) * 140
end

-- Revolver fliegt in die rechte Hand des Halters (oder schwebend vor dessen Brust, wenn keine Figur da ist)
local function GunToHolder(tent, gun, seat, chair, seconds, arc)
	P.gun_state = { seat = seat, chair = chair }
	local character = SeatCharacter(seat)
	local hand = character and Revolver.BonePoint(character)
	local look = GunLook(tent)
	Revolver.MoveTo(gun, hand and Revolver.RootFor(gun, hand, look) or HoldPoint(tent, chair), look, seconds, arc)
	P.gun_token = (P.gun_token or 0) + 1   -- eine spaetere Anweisung (Knall, Zoegern) gewinnt gegen das Einhaken
	local token = P.gun_token
	After(seconds, function()
		if (gun.dead or P.gun ~= gun or P.gun_token ~= token) then return end
		local holder = SeatCharacter(seat)   -- neu suchen: die Figur kann inzwischen gewechselt haben
		if (not (holder and Revolver.Hold(gun, holder, function() return GunLook(tent) end))) then
			Revolver.Follow(gun, function() return HoldPoint(tent, chair), GunLook(tent) end)
		end
	end)
end

-- Der Halter zielt gerade auf seat (0/nil = auf niemanden). Kommt vom Server ("revolver_aiming") und – beim Halter
-- selbst sofort – aus Client/Aim.lua.
function P.ShowAiming(shooter, seat)
	local tent = CurrentTent()
	if (not tent) then return end
	seat = (type(seat) == "number" and seat > 0) and seat or nil
	if (type(shooter) == "number" and shooter > 0) then Mark("Set", shooter, "actor") end
	if (seat) then Mark("Set", seat, "target") else Mark("Clear", "target") end
	local g = P.gun_state
	if (g and (not shooter or g.seat == shooter)) then
		g.aim = seat
		g.aim_chair = seat and SeatChair(seat) or nil
	end
	AimPose(shooter, seat ~= nil)
	Tent.SpotChair(tent, seat and SeatChair(seat) or nil)
	if (P.gun and not P.gun.dead) then Revolver.SetFear(P.gun, seat and 0.45 or 0.25) end
end

function Handlers.revolver_give(tent, data)
	if (not data.seat_chair) then return end
	Tent.SpotChair(tent, nil)                             -- noch kein Ziel
	Tent.SpotChair(tent, data.seat_chair, true, GOLD)     -- Halter: goldener Spot
	Mark("Set", data.seat, "actor")
	Mark("Clear", "target")
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.5)
	Audio.Play("cylinder_spin", 1.0)
	-- Jack wirft dem Halter den Revolver in die rechte Hand; der Lauf zeigt erst gesenkt auf den Boden der Manege
	local gun = Revolver.Build(Temp(), Jack.HandPoint(tent.jack), Revolver.HAND.scale)
	P.gun = gun
	Revolver.SetLoaded(gun, data.bullets or 1)
	Revolver.SpinDrum(gun, 0.9)
	Revolver.SetFear(gun, 0.25)
	GunToHolder(tent, gun, data.seat, data.seat_chair, 0.7, 90)
end

-- Live-Zielen des Halters (gedrosselt vom Server weitergereicht, Bots taeuschen ein paar Schwenks vor)
function Handlers.revolver_aiming(tent, data)
	P.ShowAiming(data.shooter, data.seat)
	if ((tonumber(data.seat) or 0) > 0) then Audio.Play("tick", 0.25, 1.8) end
end

function Handlers.revolver_aim(tent, data)
	if (not data.seat_chair) then return end
	if (data.shooter_chair) then Tent.SpotChair(tent, data.shooter_chair, true, GOLD) end
	Tent.SpotChair(tent, data.seat_chair)
	if (data.shooter) then Mark("Set", data.shooter, "actor") end
	Mark("Set", data.seat, "target")
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	Jack.Aim(tent.jack, true)
	Audio.Play("gun_cock", 0.9)
	local gun = P.gun
	if (gun and not gun.dead and data.shooter_chair) then
		if (P.gun_state) then P.gun_state.aim, P.gun_state.aim_chair = data.seat, data.seat_chair end
		if (data.seat == data.shooter) then
			-- Zu langsam gewaehlt: Jack reisst ihm den Revolver aus der Hand und haelt ihm den Lauf vors eigene Gesicht
			P.gun_token = (P.gun_token or 0) + 1
			AimPose(data.shooter, false)
			local head = HeadPoint(tent, data.shooter_chair)
			Revolver.MoveTo(gun, head + Inward(tent, data.shooter_chair) * 55 + Vector(0, 0, 4), head, 0.6, 25)
		else
			AimPose(data.shooter, true)
			if (not Revolver.IsHeld(gun)) then
				-- nicht in einer Hand (keine Figur gefunden): schwebend aufs Ziel wie frueher
				Revolver.MoveTo(gun, HoldPoint(tent, data.shooter_chair), HeadPoint(tent, data.seat_chair), 0.45, 8)
			end
		end
		Revolver.Cock(gun)
		Revolver.SetFear(gun, 0.7)
	end
	-- Herzschlag deutlich unter dem Hahn (Pegel siehe synth.py: gun_cock -21, heartbeat -18 LUFS M-max)
	Audio.StartLoop("heart", "heartbeat_loop", 0.45, 0.2, (data.aim_time or 1.5) + 4)
	RampTension(0.8, data.aim_time or 1.5)
end

function Handlers.revolver_shot(tent, data)
	Audio.StopLoop("heart", 0.1)
	Jack.Aim(tent.jack, false)
	-- Mit Schuetze: der Revolver der Kette (in dessen Hand). Ohne: Jack schiesst selbst (Angry Clown, Shooting Gallery)
	local gun = data.shooter and P.gun or P.jack_gun
	if (gun and not gun.dead) then
		if (data.result == "click") then
			Revolver.Click(gun)
			Revolver.SetFear(gun, 0.2)
		else
			Revolver.Fire(gun)
			Revolver.SetFear(gun, 0)
			if (data.shooter and data.shooter_chair) then
				-- Nach dem Knall senkt der Schuetze den Arm und laesst den Revolver fallen
				P.gun_token = (P.gun_token or 0) + 1
				local chair, shooter = data.shooter_chair, data.shooter
				After(1.4, function()
					AimPose(shooter, false)
					if (not gun.dead) then Revolver.Drop(gun, Tent.ChairFloor(tent, chair)) end
				end)
			end
		end
	end
	if (data.result ~= "click" and data.seat_chair) then
		Builder.Particle(Temp(), HeadPoint(tent, data.seat_chair) - Vector(0, 0, 25), "nanos-world::P_Sparks", Vector(0.6, 0.6, 0.6))
		Atmosphere.Flash(Color(1, 0.9, 0.7), 0.4, 0.25)
	end
	RampTension(0.25, 1.0)
end

-- Klick: der Revolver fliegt von Hand zu Hand zum neuen Halter
function Handlers.revolver_pass(tent, data)
	if (not data.seat_chair) then return end
	Tent.SpotChair(tent, nil)
	Tent.SpotChair(tent, data.seat_chair, true, GOLD)
	if (data.from) then AimPose(data.from, false) end
	Mark("Set", data.seat, "actor")
	Mark("Clear", "target")
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.45)
	Audio.Play("whoosh", 0.7, 1.2)
	Audio.Play("cylinder_spin", 0.6, 1.1)
	local gun = P.gun
	if (not gun or gun.dead or not gun.root:IsValid()) then
		-- Revolver ist weg (z. B. mit der Figur eines gegangenen Halters verschwunden): Jack holt einen neuen aus der Kiste
		gun = Revolver.Build(Temp(), Jack.HandPoint(tent.jack), Revolver.HAND.scale)
		P.gun = gun
	end
	if (gun and not gun.dead) then
		Revolver.SpinDrum(gun, 0.8)
		Revolver.SetFear(gun, 0.3)
		GunToHolder(tent, gun, data.seat, data.seat_chair, 0.55, 110)
		After(0.6, function() if (not gun.dead) then Revolver.SetLoaded(gun, data.bullets or 1) end end)
	end
	-- Jack laedt nach (Config.REVOLVER.LOAD_EXTRA): eine glaenzende Patrone fliegt in die Trommel, der Hahn rastet ein
	if ((data.bullets or 1) > 1) then
		local from = Jack.HandPoint(tent.jack)
		local holder = SeatCharacter(data.seat)
		local to = (holder and Revolver.BonePoint(holder)) or HoldPoint(tent, data.seat_chair)
		local bullet = Builder.Shape(Temp(), "cylinder", from, Vector(4, 4, 10),
			{ color = Color(0.85, 0.6, 0.2), roughness = 0.25, emissive = GOLD * 3, shadow = false })
		Fly(bullet, from, to, 0.45, 80, 900, function()
			if (bullet:IsValid()) then bullet:Destroy() end
		end)
		After(0.5, function() Audio.Play("gun_cock", 0.8, 1.05) end)
	end
end

-- Ricochet: Kugel prallt ab und trifft jemand anderen
function Handlers.ricochet(tent, data)
	if (data.from_chair) then
		Builder.Particle(Temp(), HeadPoint(tent, data.from_chair), "nanos-world::P_Sparks", Vector(0.8, 0.8, 0.8))
		FloatingCard(tent, data.from_chair, CARD_COLORS.ricochet, data.seat_chair)
	end
	Audio.Play("card_break", 0.7)
	Audio.Play("whoosh", 0.9, 1.8)
	if (data.seat_chair) then
		Tent.SpotChair(tent, data.seat_chair)
		Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.3)
	end
	if (data.seat) then Mark("Set", data.seat, "target") end
end

-- ---------------------------------------------------------------- Knife Toss

function Handlers.knife_raise(tent, data)
	if (not data.seat_chair) then return end
	ClearTemp()
	Glow("Set", data.seat, "target")   -- in Gefahr: ROT (bis round_end)
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	Tent.SpotChair(tent, data.seat_chair)
	After(0.45, function()
		local hand = Jack.HandPoint(tent.jack)
		local target = HeadPoint(tent, data.seat_chair) - Vector(0, 0, 20)
		local knife = Builder.Mesh(Temp(), hand, Builder.LookAt(hand, target), "knife_throw", { scale = Vector(3, 3, 3) })
		P.knife = knife
		Tremble(knife)
	end)
end

function Handlers.knife_throw(tent, data)
	if (not data.seat_chair) then return end
	Jack.Throw(tent.jack)
	After(0.3, function()
		local knife = P.knife
		if (not knife or not knife:IsValid()) then return end
		local from = knife:GetLocation()
		local target = HeadPoint(tent, data.seat_chair) - Vector(0, 0, 20)
		Audio.Play3D("whoosh", from, 1, 1.1, 2500)
		if (data.hit) then
			Fly(knife, from, target, 0.16)
		else
			Fly(knife, from, target + (target - from) * 1.2 + Vector(0, 0, 70), 0.4, 0, 1200)
		end
	end)
end

-- ---------------------------------------------------------------- Fire Breath

function Handlers.fire_breath(tent, data)
	if (not data.seat_chair) then return end
	ClearTemp()
	Glow("Set", data.seat, "target")
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.35)
	Jack.SetFace(tent.jack, "angry")
	Tent.SpotChair(tent, data.seat_chair)
	After(0.4, function()
		local mouth = Jack.MouthPoint(tent.jack)
		local target = HeadPoint(tent, data.seat_chair)
		Builder.Particle(Temp(), mouth, "fire_breath", Vector(1.6, 1.6, 1.6), Builder.LookAt(mouth, target))
		Audio.Play3D("fire_whoosh", mouth, 1, 0.9, 4000)
	end)
	After(math.max(0.5, (data.delay or 1) * 0.85), function()
		Jack.SetFace(tent.jack, "laugh")
		local at = Tent.ChairPoint(tent, data.seat_chair, -10)
		P.fire = Builder.Particle(Temp(), at, "fire_big", Vector(1.1, 1.1, 1.5))
		P.fire_light = Builder.Light(Temp(), at + Vector(0, 0, 60), Color(1, 0.45, 0.1), 8, 450, { flicker = 1 })
		Audio.Play3D("fire_whoosh", at, 0.8, 1.2, 3000)
	end)
end

function Handlers.fire_off(tent, data)
	local function Extinguish()
		for _, e in ipairs({ P.fire, P.fire_light }) do
			if (e and e:IsValid()) then e:Destroy() end
		end
		P.fire, P.fire_light = nil, nil
	end
	Jack.SetFace(tent.jack, "idle")
	if (data.survived) then
		Extinguish()
		if (data.seat_chair) then
			local at = Tent.ChairPoint(tent, data.seat_chair, 0)
			Builder.Particle(Temp(), at, "smoke", Vector(0.8, 0.8, 0.8))
			Audio.Play3D("hiss", at, 1, 1, 2500)
		end
	else
		After(2.5, Extinguish)
	end
end

-- ---------------------------------------------------------------- Stab Your Neighbour

function Handlers.stab_raise(tent, data)
	if (not data.seat_chair) then return end
	ClearTemp()
	if (data.holder) then Glow("Set", data.holder, "actor") end   -- wer zusticht: GOLD, das Opfer: ROT
	Glow("Set", data.seat, "target")
	if (data.holder_chair) then Tent.SpotChair(tent, data.holder_chair, true, GOLD) end
	local above = HeadPoint(tent, data.seat_chair) + Vector(0, 0, 90)
	local cleaver = Builder.Mesh(Temp(), above, Rotator(0, ChairAngle(tent, data.seat_chair), 90), "knife_stab", { scale = Vector(2.2, 2.2, 2.2) })
	P.cleaver = cleaver
	Tremble(cleaver, 2.5)
	Tent.SpotChair(tent, data.seat_chair)
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	Audio.StartLoop("heart", "heartbeat_loop", 0.8, 0.15, 6)
end

function Handlers.stab_strike(tent, data)
	Audio.StopLoop("heart", 0.1)
	local cleaver = P.cleaver
	if (not cleaver or not cleaver:IsValid() or not data.seat_chair) then return end
	local from = cleaver:GetLocation()
	if (data.blocked) then
		Fly(cleaver, from, from + Vector(0, 0, 420), 0.6, 0, 900)
	else
		Fly(cleaver, from, HeadPoint(tent, data.seat_chair) - Vector(0, 0, 30), 0.09)
	end
end

-- ---------------------------------------------------------------- Angry Clown

function Handlers.angry_aim(tent, data)
	if (not data.seat_chair) then return end
	-- Jack zieht seinen eigenen Revolver (bleibt bei der Shooting Gallery fuer alle drei Schuesse in der Hand)
	local gun = P.jack_gun
	if (not gun or gun.dead) then
		gun = Revolver.Build(Temp(), Jack.HandPoint(tent.jack))
		Revolver.SetLoaded(gun, 6)
		P.jack_gun = gun
	end
	local target = HeadPoint(tent, data.seat_chair)
	Revolver.Follow(gun, function()
		local hand = Jack.HandPoint(tent.jack)
		local d = target - hand
		local len = math.max(1, math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z))
		return hand + d * (Revolver.GRIP_BACK / len) + Vector(0, 0, Revolver.GRIP_DOWN), target    -- Griff in der Hand, Lauf aufs Opfer
	end)
	Revolver.Cock(gun)
	Glow("Set", data.seat, "target")   -- Jack legt auf diesen Platz an (Shooting Gallery: wandert mit)
	P.jack_gun_token = (P.jack_gun_token or 0) + 1
	local token = P.jack_gun_token
	After((data.aim_time or 2) + 1.6, function()
		if (P.jack_gun == gun and P.jack_gun_token == token) then
			Revolver.Destroy(gun)
			P.jack_gun = nil
		end
	end)
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	Jack.SetFace(tent.jack, "angry")
	Jack.Aim(tent.jack, true)
	Tent.SpotChair(tent, data.seat_chair)
	Jack.SetEyeGlow(tent.jack, 14)
	Tent.SetMood(tent, "hold")
	Audio.Play("drumroll", 0.7)
	RampTension(0.9, data.aim_time or 2)
	After(data.aim_time or 2, function()
		Jack.SetEyeGlow(tent.jack, 3)
		Jack.SetFace(tent.jack, "idle")
		Jack.Aim(tent.jack, false)
		Tent.SetMood(tent, "normal")
	end)
end

-- ---------------------------------------------------------------- Spare or Eliminate

function Handlers.vote_start(tent, data)
	Glow("Set", data.seat, "target")
	if (data.seat_chair) then
		Tent.SpotChair(tent, data.seat_chair)
		Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.5)
	end
	Audio.StartLoop("drone", "vote_drone_loop", 0.6, 1.0, (data.duration or 12) + 5)
	Audio.DuckAmbience(0.3)
	RampTension(0.6, 2)
end

function Handlers.vote_result(tent, data)
	Audio.StopLoop("drone", 0.4)
	Audio.Play("vote_bell", 0.9)
	Audio.DuckAmbience(1)
	if (data.result == "kill") then
		Jack.SetFace(tent.jack, "laugh")
	end
	RampTension(0.2, 1.5)
end

-- ---------------------------------------------------------------- Kuerbisbombe (heisse Kartoffel)

local function PumpkinTarget(tent, chair)
	return HeadPoint(tent, chair) + Vector(0, 0, 25)
end

function Handlers.pumpkin_start(tent, data)
	if (not data.seat_chair) then return end
	ClearTemp()
	Glow("Clear", "actor")
	Glow("Set", data.seat, "target")   -- ROT wandert mit dem Kuerbis
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	Jack.SetFace(tent.jack, "laugh")
	Tent.SpotChair(tent, data.seat_chair, false, Color(1, 0.5, 0.1))
	Jack.Throw(tent.jack)
	After(0.3, function()
		local from = Jack.HandPoint(tent.jack)
		local pumpkin = Builder.Mesh(Temp(), from, Rotator(), "pumpkin", { scale = Vector(1.6, 1.6, 1.6) })
		local spark = Builder.Particle(Temp(), from + Vector(0, 0, 30), "nanos-world::P_Sparks", Vector(0.25, 0.25, 0.25))
		local glow = Builder.Light(Temp(), from + Vector(0, 0, 20), Color(1, 0.45, 0.1), 4, 260, { flicker = 1 })
		Builder.Attach(spark, pumpkin)
		Builder.Attach(glow, pumpkin)
		P.pumpkin = pumpkin
		Fly(pumpkin, from, PumpkinTarget(tent, data.seat_chair), 0.5, 140, 400, function()
			pumpkin:SetValue("DB_Base", PumpkinTarget(tent, data.seat_chair))
		end)
		Tremble(pumpkin, 1)
		Audio.StartLoop("fuse", "fuse_hiss_loop", 0.7, 0.2, 25)
	end)
end

function Handlers.pumpkin_pass(tent, data)
	Glow("Set", data.seat, "target")   -- ROT wandert mit, auch wenn der Kuerbis (noch) nicht zu sehen ist
	local pumpkin = P.pumpkin
	if (not pumpkin or not pumpkin:IsValid() or not data.seat_chair) then return end
	local to = PumpkinTarget(tent, data.seat_chair)
	Fly(pumpkin, pumpkin:GetLocation(), to, 0.35, 90, 600, function() pumpkin:SetValue("DB_Base", to) end)
	Tent.SpotChair(tent, data.seat_chair, false, Color(1, 0.5, 0.1))
	Audio.Play("whoosh", 0.7, 1.4)
end

function Handlers.pumpkin_boom(tent, data)
	Audio.StopLoop("fuse", 0)
	local at = (P.pumpkin and P.pumpkin:IsValid()) and P.pumpkin:GetLocation() or (data.seat_chair and PumpkinTarget(tent, data.seat_chair))
	if (P.pumpkin and P.pumpkin:IsValid()) then P.pumpkin:Destroy() end
	P.pumpkin = nil
	if (at) then
		Builder.Particle(Temp(), at, "nanos-world::P_Explosion", Vector(0.8, 0.8, 0.8))
		Audio.Play3D("explosion", at, 1, 1, 5000)
	end
	Atmosphere.Flash(Color(1, 0.6, 0.2), 0.7, 0.8)
end

-- ---------------------------------------------------------------- Defuse or Die (Bombe)

-- Bombe vor den Fuessen des Opfers: Dynamit, Draehte, LED-Zeitzuender, blinkendes Licht
function Handlers.bomb_start(tent, data)
	if (not data.seat_chair) then return end
	ClearTemp()
	Glow("Set", data.seat, "target")
	local angle = ChairAngle(tent, data.seat_chair)
	local radius = Layout.ChairRadius(tent.seat_count) - 75
	local base = Builder.OnCircle(tent.center, angle, radius, 0)
	local face = Rotator(0, angle, 0)                 -- Front zeigt nach aussen, zum Opfer
	local list = Temp()
	local rad = math.rad(angle)
	local out = Vector(math.cos(rad), math.sin(rad), 0)
	local side = Vector(-math.sin(rad), math.cos(rad), 0)

	for i = -1, 1 do
		Builder.Shape(list, "cylinder", base + side * (i * 13) + Vector(0, 0, 14), Vector(12, 12, 26),
			{ rotation = Rotator(90, angle + 90, 0), color = Color(0.6, 0.05, 0.03), roughness = 0.7 })
	end
	Builder.Box(list, base + Vector(0, 0, 14), Vector(14, 46, 8), { color = Color(0.03, 0.03, 0.03), roughness = 0.9, rotation = face })
	Builder.Box(list, base + out * 9 + Vector(0, 0, 30), Vector(10, 30, 16), { color = Color(0.05, 0.05, 0.06), roughness = 0.5, rotation = face })
	local led = TextRender(base + out * 15 + Vector(0, 0, 30), Rotator(0, angle, 0), "0:" .. string.format("%02d", math.ceil(data.seconds or 10)), 14,   -- ceil: %d mit 12.5 bricht in Lua 5.4
		Color(1, 0.08, 0.04), TextRenderRenderingType.Unlit, TextRenderHorizontalAlignment.Center, TextRenderVerticalAlignment.Center,
		"nanos-world::Font_BoldPixels_DistanceField", false)
	table.insert(list.entities, led)
	for i, col in ipairs({ Color(0.8, 0.05, 0.05), Color(0.05, 0.6, 0.1), Color(0.05, 0.15, 0.8) }) do
		Builder.Shape(list, "cylinder", base + out * 6 + side * ((i - 2) * 10) + Vector(0, 0, 24), Vector(2.5, 2.5, 22),
			{ rotation = Rotator(30 * (i - 2), angle, 50), color = col, emissive = col * 0.6 })
	end
	local blink = Builder.Light(list, base + out * 18 + Vector(0, 0, 42), Color(1, 0.05, 0.02), 0, 240)
	local dot = Builder.Shape(list, "sphere", base + out * 14 + Vector(0, 0, 40), Vector(4, 4, 4), { color = Color(1, 0, 0), emissive = Color(1, 0, 0) * 1 })

	-- Countdown + Blinken (wird schneller), lokal ungefaehr synchron zum Server
	local t0 = Builder.time + (data.intro or 1.4)
	local total = data.seconds or 10
	local bomb = { led = led, blink = blink, dot = dot, done = false }
	P.bomb = bomb
	local last_beep = -1
	Builder.AddTicker(list, function(dt, time)
		if (bomb.done or not led:IsValid()) then return false end
		local left = math.max(0, total - math.max(0, Builder.time - t0))
		led:SetText(string.format("0:%02d", math.ceil(left)))
		local rate = (left < 3) and 6 or ((left < 6) and 3 or 1.5)
		local on = (math.floor(time * rate * 2) % 2 == 0)
		blink:SetIntensity(on and 6 or 0)
		dot:SetMaterialColorParameter("Emissive", Color(1, 0, 0) * (on and 30 or 0.5))
		local beep = math.floor(time * rate)
		if (on and beep ~= last_beep and Builder.time >= t0) then
			last_beep = beep
			Audio.Play3D("bomb_tick", base, 1.0, left < 3 and 1.3 or 1.0, 5000)   -- auch die gegenueber sollen es ticken hoeren
		end
	end)
	Tent.SpotChair(tent, data.seat_chair)
	Jack.PointTo(tent.jack, angle, 0.4)
	Jack.SetFace(tent.jack, "laugh")
	Audio.StartLoop("heart", "heartbeat_loop", 0.35, 0.5, total + 6)   -- leise: das Ticken ist der Taktgeber
end

function Handlers.bomb_result(tent, data)
	Audio.StopLoop("heart", 0.2)
	local bomb = P.bomb
	if (not bomb) then return end
	bomb.done = true
	if (data.defused) then
		if (bomb.led:IsValid()) then
			bomb.led:SetText("--:--")
			bomb.led:SetColor(Color(0.1, 1, 0.2))
		end
		if (bomb.blink:IsValid()) then bomb.blink:SetIntensity(0) end
		Audio.Play("hiss", 0.7, 1.3)
		Jack.SetFace(tent.jack, "idle")
	else
		local at = bomb.led:IsValid() and bomb.led:GetLocation() or (data.seat_chair and Tent.ChairFloor(tent, data.seat_chair))
		Builder.Particle(Temp(), at, "nanos-world::P_Explosion", Vector(1, 1, 1))
		Audio.Play3D("explosion", at, 1, 0.95, 5000)
		Atmosphere.Flash(Color(1, 0.6, 0.2), 0.75, 0.9)
		for _, e in ipairs({ bomb.led, bomb.blink, bomb.dot }) do
			if (e and e:IsValid()) then e:Destroy() end
		end
	end
	P.bomb = nil
end

-- ---------------------------------------------------------------- Quick Draw (Duell)

function Handlers.duel_start(tent, data)
	ClearTemp()
	Glow("Clear", "target")
	Glow("Set", { data.seat, data.seat2 }, "actor")   -- beide Duellanten GOLD
	if (data.seat_chair) then Tent.SpotChair(tent, data.seat_chair, false, GOLD) end
	if (data.seat2_chair) then Tent.SpotChair(tent, data.seat2_chair, true, GOLD) end
	-- Jack schaut zwischen die beiden
	if (data.seat_chair and data.seat2_chair) then
		local a1, a2 = ChairAngle(tent, data.seat_chair), ChairAngle(tent, data.seat2_chair)
		local mid = a1 + ((a2 - a1 + 540) % 360 - 180) / 2
		Jack.PointTo(tent.jack, mid, 0.6)
	end
	Tent.SetMood(tent, "hold")
	Audio.StartLoop("heart", "heartbeat_loop", 0.8, 0.4, 10)
	Audio.Play("whisper_swell", 0.6)
	RampTension(0.9, 3)
	-- Zwei Revolver fliegen aus der Kiste zu den Duellanten, Lauf gesenkt
	P.duel = {}
	for _, pair in ipairs({ { data.seat_chair, data.seat2_chair }, { data.seat2_chair, data.seat_chair } }) do
		local mine, other = pair[1], pair[2]
		if (mine and other) then
			local gun = Revolver.Build(Temp(), tent.center + Vector(0, 0, 230))
			Revolver.SetLoaded(gun, 6)
			Revolver.MoveTo(gun, HoldPoint(tent, mine), Tent.ChairFloor(tent, mine) + Inward(tent, mine) * 120, 0.7, 120)
			Revolver.SetFear(gun, 0.35)
			P.duel[mine] = { gun = gun, other = other }
		end
	end
end

function Handlers.duel_draw(tent, data)
	Audio.StopLoop("heart", 0)
	-- DRAW! Beide reissen den Revolver hoch
	for mine, d in pairs(P.duel or {}) do
		if (not d.gun.dead) then
			Revolver.MoveTo(d.gun, HoldPoint(tent, mine), HeadPoint(tent, d.other), 0.16, 0)
			Revolver.Cock(d.gun)
			Revolver.SetFear(d.gun, 0.15)
		end
	end
	Audio.Play("vote_bell", 1.0, 1.4)
	Atmosphere.Flash(Color(1, 1, 1), 0.35, 0.25)
	Tent.SetMood(tent, "normal")
end

function Handlers.duel_result(tent, data)
	local function Spark(chair)
		if (chair) then
			Builder.Particle(Temp(), HeadPoint(tent, chair) - Vector(0, 0, 20), "nanos-world::P_Sparks", Vector(0.6, 0.6, 0.6))
		end
	end
	local duel = P.duel or {}
	local function Gun(chair) return chair and duel[chair] and not duel[chair].gun.dead and duel[chair].gun end
	local function DropLater(chair, seconds)
		local gun = Gun(chair)
		if (gun) then After(seconds, function() if (not gun.dead) then Revolver.Drop(gun, Tent.ChairFloor(tent, chair)) end end) end
	end
	if (data.result == "both") then
		-- keiner war schnell genug: Jack schiesst auf beide, die Revolver fallen
		Spark(data.seat_chair)
		Spark(data.seat2_chair)
		Audio.PlayAsset("snd_shot", 1, 0.8)
		DropLater(data.seat_chair, 0.3)
		DropLater(data.seat2_chair, 0.35)
	elseif (data.result == "misfire") then
		-- falsche Taste: Schuss ins eigene Bein
		local gun = Gun(data.seat_chair)
		if (gun) then
			Revolver.MoveTo(gun, HoldPoint(tent, data.seat_chair), Tent.ChairFloor(tent, data.seat_chair) - Inward(tent, data.seat_chair) * 30, 0.1, 0)
			After(0.12, function() if (not gun.dead) then Revolver.Fire(gun) end end)
		end
		Spark(data.seat_chair)
		Jack.Laugh(tent.jack, 1.6)
		DropLater(data.seat_chair, 1.2)
	else
		local gun = Gun(data.seat_chair)
		if (gun) then Revolver.Fire(gun) end
		Spark(data.seat2_chair)
		DropLater(data.seat2_chair, 0.4)
	end
	RampTension(0.2, 1.2)
	After(2, function()
		Tent.SpotChair(tent, nil)
		Tent.SpotChair(tent, nil, true)
	end)
end

-- ---------------------------------------------------------------- Split or Steal

function Handlers.splitsteal_start(tent, data)
	Glow("Set", { data.seat, data.seat2 }, "actor")
	if (data.seat_chair) then Tent.SpotChair(tent, data.seat_chair, false, GOLD) end
	if (data.seat2_chair) then Tent.SpotChair(tent, data.seat2_chair, true, GOLD) end
	Audio.StartLoop("drone", "vote_drone_loop", 0.45, 1.0, 20)
	RampTension(0.5, 2)
end

function Handlers.splitsteal_result(tent, data)
	Audio.StopLoop("drone", 0.3)
	local a, b = data.choice, data.choice2
	if (a == "split" and b == "split") then
		Audio.Play("card_deal", 0.9)
		Jack.Disappointed(tent.jack)
	elseif (a == "steal" and b == "steal") then
		Audio.Play("survive_wahwah", 0.6)
		Jack.Laugh(tent.jack, 1.6)
		Audio.Play("laugh", 0.7, 0.9)
	else
		Audio.Play("card_break", 0.8)
		Jack.Laugh(tent.jack, 1.2)
	end
	for _, field in ipairs({ "seat_chair", "seat2_chair" }) do
		if (data[field]) then FloatingCard(tent, data[field], GOLD) end
	end
	-- Aufdecken fuer alle sichtbar: SPLIT (gruen) / STEAL (rot) ueber den Koepfen
	local labels = { split = { "SPLIT", Color(0.3, 1, 0.4) }, steal = { "STEAL", Color(1, 0.15, 0.1) } }
	for _, pair in ipairs({ { data.seat_chair, a }, { data.seat2_chair, b } }) do
		local look = labels[pair[2]]
		if (pair[1] and look) then FloatLabel(tent, pair[1], look[1], look[2], 3.5) end
	end
	After(2, function()
		Tent.SpotChair(tent, nil)
		Tent.SpotChair(tent, nil, true)
	end)
	RampTension(0.2, 1)
end

-- ---------------------------------------------------------------- Karten

-- Eine leuchtende Karte fliegt aus der Kiste zu einem Platz
local function CardFromBox(tent, chair, volume)
	local from = tent.center + Vector(0, 0, 230)
	local to = HeadPoint(tent, chair)
	local card = Builder.Box(Temp(), from, Vector(3, 26, 38), { color = Color(0.9, 0.85, 0.7), emissive = GOLD * 4, shadow = false })
	Fly(card, from, to, 0.55, 160, 720, function()
		Builder.Particle(Temp(), to + Vector(0, 0, 25), "nanos-world::P_Sparks", Vector(0.25, 0.25, 0.25))
		After(0.6, function() if (card:IsValid()) then card:Destroy() end end)
	end)
	-- card_deal landet bei 0.55 s (= Flugzeit oben); Tonhoehe nur leicht variieren, sonst verrutscht die Landung
	Audio.Play("card_deal", volume or 0.6, 0.96 + math.random() * 0.08)
end

-- Jack verteilt Karten: sie fliegen aus der Kiste zu den Gluecklichen
function Handlers.deal(tent, data)
	Jack.Laugh(tent.jack, 1.2)
	local chairs = {}
	if (P.state and P.state.seats and data.seats) then
		for _, seat_index in pairs(data.seats) do
			for _, s in pairs(P.state.seats) do
				if (s.seat == seat_index) then table.insert(chairs, s.chair or s.seat) end
			end
		end
	end
	for i, chair in ipairs(chairs) do
		After(0.15 * i, function() CardFromBox(tent, chair) end)
	end
end

-- Drei Karten schweben gefaechert zwischen Jack und dem Gewaehlten (Choose a Card)
function P.CardFan(tent, chair)
	local angle = ChairAngle(tent, chair)
	local rad = math.rad(angle)
	local inward = Vector(-math.cos(rad), -math.sin(rad), 0)   -- vom Platz Richtung Mitte
	local side = Vector(-math.sin(rad), math.cos(rad), 0)
	local head = HeadPoint(tent, chair)
	local from = tent.center + Vector(0, 0, 230)
	local fan = { chair = chair, cards = {} }
	for i = -1, 1 do
		local at = head + inward * 75 + side * (i * 34) + Vector(0, 0, 12 - math.abs(i) * 7)
		local card = Builder.Box(Temp(), from, Vector(3, 26, 38), { color = Color(0.9, 0.85, 0.7), emissive = GOLD * 4, shadow = false })
		card:SetRotation(Rotator(0, angle, i * 14))
		After(0.12 * (i + 1), function()
			if (not card:IsValid()) then return end
			Fly(card, from, at, 0.5, 120, nil, function() card:SetValue("DB_Base", at) end)
			Audio.Play("card_deal", 0.45, 0.96 + math.random() * 0.08)
		end)
		Tremble(card, 0.6)
		table.insert(fan.cards, card)
	end
	P.fan = fan
	-- Keine Wahl (z. B. volle Hand): Karten verschwinden nach Ablauf wieder in der Kiste
	local timeout = (Config.CHOOSECARD and Config.CHOOSECARD.TIME or 10) + 4
	After(timeout, function()
		if (P.fan ~= fan) then return end
		P.fan = nil
		for _, card in ipairs(fan.cards) do
			if (card:IsValid()) then
				Fly(card, card:GetLocation(), from, 0.5, 80, 540, function() if (card:IsValid()) then card:Destroy() end end)
			end
		end
	end)
	return fan
end

-- Jemand bekommt eine Karte (Choose a Card, /card)
function Handlers.card_gain(tent, data)
	if (not data.seat_chair) then return end
	Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.4)
	local fan = P.fan
	P.fan = nil
	if (fan and fan.chair == data.seat_chair) then
		-- Die mittlere Karte geht an den Spieler, die anderen fliegen zurueck in die Kiste
		local box = tent.center + Vector(0, 0, 230)
		for i, card in ipairs(fan.cards) do
			if (card:IsValid()) then
				local to = (i == 2) and HeadPoint(tent, data.seat_chair) or box
				Fly(card, card:GetLocation(), to, (i == 2) and 0.35 or 0.55, (i == 2) and 30 or 110, (i == 2) and nil or 540, function()
					if (card:IsValid()) then card:Destroy() end
				end)
			end
		end
		Audio.Play("card_flip", IsMe(data.seat) and 0.9 or 0.6)
		Builder.Particle(Temp(), HeadPoint(tent, data.seat_chair) + Vector(0, 0, 25), "nanos-world::P_Sparks", Vector(0.25, 0.25, 0.25))
	else
		CardFromBox(tent, data.seat_chair, IsMe(data.seat) and 0.9 or 0.6)
	end
end

-- Jemand spielt eine Karte aus (Guardian, Thief)
function Handlers.card_play(tent, data)
	if (not data.seat_chair) then return end
	Audio.Play("card_flip", 0.9)
	local target_chair = nil
	if (data.target and P.state and P.state.seats) then
		for _, s in pairs(P.state.seats) do
			if (s.seat == data.target) then target_chair = s.chair or s.seat end
		end
	end
	FloatingCard(tent, data.seat_chair, CARD_COLORS[data.card], target_chair)
end

-- Eine automatische Karte greift (Safety rettet, Ricochet ...)
function Handlers.card_trigger(tent, data)
	if (not data.seat_chair) then return end
	Audio.Play("card_break", 0.9)
	FloatingCard(tent, data.seat_chair, CARD_COLORS[data.card])
	Builder.Particle(Temp(), HeadPoint(tent, data.seat_chair) + Vector(0, 0, 40), "nanos-world::P_Sparks", Vector(0.5, 0.5, 0.5))
end

-- ---------------------------------------------------------------- Nachruecker

-- Ein Spieler uebernimmt den Platz eines Bots (zu Beginn einer Runde): kurzes Funkeln, Namensschild steigt auf
function Handlers.seat_taken(tent, data)
	if (not data.seat_chair) then return end
	Builder.Particle(Temp(), HeadPoint(tent, data.seat_chair) + Vector(0, 0, 30), "nanos-world::P_Sparks", Vector(0.4, 0.4, 0.4))
	FloatLabel(tent, data.seat_chair, "NEW: " .. tostring(data.name or "?"), Color(1, 0.82, 0.3), 3.5)
	Audio.Play("card_deal", 0.7)
end

-- Nur an den Nachruecker selbst: "Du bist drin" (das HUD zeigt die grosse Zeile)
function Handlers.you_joined(tent, data)
	Atmosphere.Flash(Color(1, 0.8, 0.3), 0.35, 0.8)
	Audio.Play("your_turn", 0.8)
end

-- ---------------------------------------------------------------- Tod, Ueberleben, Sieg

function Handlers.death(tent, data)
	if (data.left) then return end   -- jemand hat die Show verlassen: nur das HUD zeigt es, Licht/Jack laufen weiter
	Tent.SetMood(tent, "death")
	After(1.6, function() Tent.SetMood(tent, "normal") end)
	After(2.2, function() Tent.SpotChair(tent, nil) end)
	Audio.Play("sting", 0.65)
	Atmosphere.Flash(Color(0.55, 0, 0), 0.5, 1.0)
	-- Totenglocke nur fuers Opfer, kurz NACH dem Schock-Akkord, damit sich beide nicht gegenseitig verdecken
	if (IsMe(data.seat)) then After(0.3, function() Audio.Play("death_toll", 1.0) end) end
	After(0.6, function()
		Jack.Laugh(tent.jack, 1.8)
		Audio.Play("laugh", 0.85, 0.8 + math.random() * 0.15)
	end)
	if (data.seat_chair) then
		-- Blut bleibt bis zum Ende der Show liegen
		local floor = Tent.ChairFloor(tent, data.seat_chair)
		local decal = Decal(floor + Vector(0, 0, 20), Rotator(-90, math.random(0, 359), 0),
			string.format("nanos-world::MI_Blood_Decal_%02d", math.random(1, 10)), Vector(40, 110, 110), 900, 0.002)
		table.insert(tent.list.entities, decal)
	end
end

function Handlers.survive(tent, data)
	After(0.5, function()
		Audio.Play("survive_wahwah", 0.55)
		Jack.Disappointed(tent.jack)
	end)
	After(1.8, function() Tent.SpotChair(tent, nil) end)
end

function Handlers.winner(tent, data)
	CancelTimers()
	StopLoops(0.2)
	Audio.StopMusic(0.4)
	Jack.Hold(tent.jack, false)
	Jack.SetYaw(tent.jack, tent.jack.yaw)   -- laufende Drehung beenden, damit er sich zum Sieger drehen kann
	Jack.Present(tent.jack)                 -- raus aus der Kiste, Suchstrahl aus
	Glow("Clear")
	Tent.SetMood(tent, "normal")
	Tent.SpotChair(tent, nil, true)
	RampTension(0, 1)
	Audio.Play("winner_fanfare", 0.8)
	if (data.seat_chair) then
		Glow("Set", data.seat, "actor")
		Jack.PointTo(tent.jack, ChairAngle(tent, data.seat_chair), 0.8)
		Jack.Aim(tent.jack, true)
		Tent.SpotChair(tent, data.seat_chair, false, Color(1, 0.9, 0.7))
		for i = 1, 3 do
			After(i * 0.35, function()
				Builder.Particle(Temp(), HeadPoint(tent, data.seat_chair) + Vector(0, 0, 140), "confetti", Vector(1.5, 1.5, 1.5))
			end)
		end
	end
	After(0.8, function()
		Jack.Aim(tent.jack, false)
		Jack.Laugh(tent.jack, 2.6)
		Audio.Play("laugh", 0.9, 0.75)
	end)
	-- Vorhang: Jack verschwindet in der Kiste, Deckel zu
	After(4.5, function()
		Jack.Retract(tent.jack)
		Audio.Play3D("lid_slam", tent.center + Vector(0, 0, 170), 0.9, 0.9, 3000)
	end)
end

-- ===================================================================
-- Eingang
-- ===================================================================

-- Verarbeitet eine Regieanweisung. Gibt die (ggf. ergaenzten) Daten fuer das HUD zurueck.
function P.Handle(data)
	local tent = CurrentTent()
	local handler = Handlers[data.action]
	if (tent and handler) then
		local ok, err = pcall(handler, tent, data)
		if (not ok) then
			Console.Warn("[DeathBox] Regiefehler bei '%s': %s", tostring(data.action), tostring(err))
		end
	end
	return data
end
