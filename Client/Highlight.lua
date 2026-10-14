-- Client/Highlight.lua
-- Leuchtende Figuren: wer gewaehlt ist bzw. handelt (GOLD) und wer in Gefahr ist (ROT). Alles lokal beim Client.
--
--   DeathBox.Highlight.Set(seat, "actor" | "target")    ersetzt alle Plaetze dieser Art durch seat (0/nil = keiner)
--   DeathBox.Highlight.Set({ a, b }, "actor")           mehrere auf einmal (Duell, Split or Steal)
--   DeathBox.Highlight.Set(seat, "target", true)        zusaetzlich, die anderen bleiben
--   DeathBox.Highlight.Clear("target") / Clear()        eine Art / alles aus
--   DeathBox.Highlight.FindCharacter(seat)              Figur eines Platzes (oder nil)
--   DeathBox.Highlight.Has(seat, kind)                  ist der Platz gerade so markiert?
--
-- Technik: Engine-Highlight (Fuellung, Index 0 = GOLD, 1 = ROT, HighlightMode.Always: auch durch Jack hindurch sichtbar)
-- plus Umriss (SetOutlineEnabled, dieselben Indizes). Ist eine Figur beides, gewinnt ROT. Alles, was an der Figur haengt
-- (z. B. der Revolver in der Hand), leuchtet mit (Engine-Verhalten).
-- Die Figur eines Platzes findet sich ueber die synchronisierten Werte "DB_Seat"/"DB_Chair", die der Server beim Hinsetzen
-- setzt; Rueckfall: die naechste unmarkierte Figur am Sitzplatz (Layout.SitTransform). Solange etwas markiert ist, wird
-- zweimal pro Sekunde nachgesehen (spaet gespawnte Figuren, Platzwechsel, Abgaenge).
-- Konsole: db_hl <fuellung 0..1> [helligkeit] [umriss]   (z. B. "db_hl 0.3 4 2.5", "db_hl 0 4 3" = nur Umriss)

DeathBox.Highlight = {
	seats = { actor = {}, target = {} },   -- Art -> { [seat] = true }
	applied = {},                           -- Figur -> Index, der gerade an ist
	ticker = nil,
	fill = 0.28,                            -- Deckkraft der Fuellung (0 = aus)
	glow = 4,                               -- Helligkeit (> 1 = Bloom)
	outline = 2.5,                          -- Umrissdicke (0 = aus)
}

local Highlight = DeathBox.Highlight
local Layout = DeathBox.Layout
local Builder = DeathBox.Builder

local STYLE = {
	actor = { index = 0, rgb = { 1.0, 0.66, 0.12 } },    -- GOLD: gewaehlt / am Zug
	target = { index = 1, rgb = { 1.0, 0.05, 0.03 } },   -- ROT: Ziel / in Gefahr
}
local ORDER = { "actor", "target" }   -- spaeter gewinnt: ROT vor GOLD
local ALIAS = { gold = "actor", chosen = "actor", red = "target", danger = "target" }
local REFRESH_EVERY = 0.5
local FALLBACK_RADIUS = 140   -- cm um den Sitzpunkt fuer Figuren ohne Platz-Markierung

local function Kind(kind)
	kind = ALIAS[kind] or kind
	if (STYLE[kind]) then return kind end
	return nil
end

-- Farben an die Engine geben (global pro Index)
function Highlight.ApplyColors()
	for _, style in pairs(STYLE) do
		local r, g, b = style.rgb[1] * Highlight.glow, style.rgb[2] * Highlight.glow, style.rgb[3] * Highlight.glow
		Client.SetHighlightColor(Color(r, g, b, Highlight.fill), style.index, HighlightMode.Always)
		if (Highlight.outline > 0) then
			Client.SetOutlineColor(Color(r, g, b, 1), style.index, Highlight.outline)
		end
	end
end

-- ===================================================================
-- Figur eines Platzes finden
-- ===================================================================

local function SeatInfo(seat)
	local state = DeathBox.Presentation and DeathBox.Presentation.state
	if (state and state.seats) then
		for _, s in pairs(state.seats) do
			if (s.seat == seat) then return s end
		end
	end
	return nil
end

local function SeatCount()
	local tent = DeathBox.World and DeathBox.World.tent
	if (tent and tent.seat_count) then return tent.seat_count end
	local state = DeathBox.Presentation and DeathBox.Presentation.state
	return state and state.seat_count or nil
end

function Highlight.FindCharacter(seat)
	if (type(seat) ~= "number" or seat <= 0) then return nil end
	local seat_count = SeatCount()
	if (not seat_count) then return nil end
	local info = SeatInfo(seat)
	local chair = (info and info.chair) or seat
	local point = Layout.SitTransform(chair, seat_count)

	local marked, marked_d = nil, math.huge
	local near, near_d = nil, FALLBACK_RADIUS * FALLBACK_RADIUS
	for _, character in pairs(Character.GetPairs()) do
		if (character:IsValid()) then
			local loc = character:GetLocation()
			local dx, dy, dz = loc.X - point.X, loc.Y - point.Y, loc.Z - point.Z
			local d = dx * dx + dy * dy + dz * dz
			local s, c = character:GetValue("DB_Seat"), character:GetValue("DB_Chair")
			if (s == seat or (s == nil and c ~= nil and c == chair)) then
				if (d < marked_d) then marked, marked_d = character, d end
			elseif (s == nil and c == nil and d < near_d) then
				near, near_d = character, d
			end
		end
	end
	return marked or near
end

-- ===================================================================
-- An/aus
-- ===================================================================

local function Enable(character, on, index)
	character:SetHighlightEnabled(on, index)
	if (Highlight.outline > 0 or not on) then character:SetOutlineEnabled(on and Highlight.outline > 0, index) end
end

-- Gleicht die gewuenschten Markierungen mit den Figuren ab
function Highlight.Refresh()
	local want = {}
	for _, kind in ipairs(ORDER) do
		for seat in pairs(Highlight.seats[kind]) do
			local character = Highlight.FindCharacter(seat)
			if (character) then want[character] = STYLE[kind].index end
		end
	end
	for character, index in pairs(Highlight.applied) do
		if (want[character] ~= index) then
			if (character:IsValid()) then Enable(character, false, index) end
			Highlight.applied[character] = nil
		end
	end
	for character, index in pairs(want) do
		if (Highlight.applied[character] ~= index) then
			Enable(character, true, index)
			Highlight.applied[character] = index
		end
	end
end

local function Active()
	return next(Highlight.seats.actor) ~= nil or next(Highlight.seats.target) ~= nil or next(Highlight.applied) ~= nil
end

local function EnsureTicker()
	if (Highlight.ticker or not Active()) then return end
	local wait = 0
	Highlight.ticker = Builder.AddTicker(nil, function(dt)
		wait = wait + dt
		if (wait < REFRESH_EVERY) then return end
		wait = 0
		local ok, err = pcall(Highlight.Refresh)
		if (not ok) then Console.Warn("[DeathBox] Highlight: %s", tostring(err)) end
		if (not Active()) then
			Highlight.ticker = nil
			return false
		end
	end)
end

local function Update()
	local ok, err = pcall(Highlight.Refresh)
	if (not ok) then Console.Warn("[DeathBox] Highlight: %s", tostring(err)) end
	EnsureTicker()
end

-- seats: Platznummer, Liste von Platznummern oder 0/nil (= keiner). keep = true: zusaetzlich markieren.
function Highlight.Set(seats, kind, keep)
	kind = Kind(kind)
	if (not kind) then return end
	if (not keep) then Highlight.seats[kind] = {} end
	local list = type(seats) == "table" and seats or { seats }
	for _, seat in ipairs(list) do
		if (type(seat) == "number" and seat > 0) then Highlight.seats[kind][seat] = true end
	end
	Update()
end

-- Eine Art (oder ohne Angabe alles) ausschalten
function Highlight.Clear(kind)
	if (kind == nil) then
		Highlight.seats = { actor = {}, target = {} }
	else
		kind = Kind(kind)
		if (not kind) then return end
		Highlight.seats[kind] = {}
	end
	Update()
end

function Highlight.Has(seat, kind)
	kind = Kind(kind)
	return kind ~= nil and Highlight.seats[kind][seat] == true
end

-- Index, der an einer Figur gerade leuchtet (nil = keiner), z. B. fuer Tests
function Highlight.IndexOf(character)
	return Highlight.applied[character]
end

Console.RegisterCommand("db_hl", function(fill, glow, outline)
	Highlight.fill = math.max(0, math.min(1, tonumber(fill) or 0.28))
	Highlight.glow = math.max(0.1, tonumber(glow) or Highlight.glow)
	local old_outline = Highlight.outline
	Highlight.outline = math.max(0, tonumber(outline) or Highlight.outline)
	Highlight.ApplyColors()
	-- Umriss neu setzen (an/aus) fuer alle markierten Figuren
	if ((old_outline > 0) ~= (Highlight.outline > 0)) then
		for character, index in pairs(Highlight.applied) do
			if (character:IsValid()) then character:SetOutlineEnabled(Highlight.outline > 0, index) end
		end
	end
	Console.Log("[DeathBox] Highlight: Fuellung %.2f, Helligkeit %.1f, Umriss %.1f", Highlight.fill, Highlight.glow, Highlight.outline)
end, "DeathBox: Figuren-Markierung (GOLD/ROT) einstellen", { "fill 0..1", "glow", "outline" })

Highlight.ApplyColors()
