-- Server/Events/Bomb.lua
-- Event "Defuse or Die": Jack stellt dem gewaehlten Spieler eine Bombe vor die Fuesse.
--
-- Regeln:
--   - Drei Draehte (rot, gruen, blau), jeder mit einer Nummer. Dazu eine Zeile aus Jacks "Defusal Manual",
--     z. B. "Cut the wire with the HIGHEST number." Genau ein Draht ist richtig.
--   - Richtigen Draht rechtzeitig kappen = entschaerft. Falscher Draht oder zu langsam = BOOM.
--   - Keine Karte rettet (kein Schuss).
-- Draehte, Nummern, Regel und Loesung erzeugt der Server; der Client bekommt nur die Anzeige, nicht die Loesung.

local Config = DeathBox.Config
local Text = DeathBox.Text

local CFG = Config.BOMB

local COLORS = { "red", "green", "blue" }

local Bomb = {
	id = "bomb",
	min_alive = 2,
	kinds = { "wire" },
}

-- ===================================================================
-- Raetsel: drei Draehte + eine Regel mit genau einer Loesung
-- ===================================================================

local function Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function DistinctNumbers(count, min, max)
	local used, out = {}, {}
	while (#out < count) do
		local n = math.random(min, max)
		if (not used[n]) then
			used[n] = true
			table.insert(out, n)
		end
	end
	return out
end

local function DigitSum(n) return math.floor(n / 10) + n % 10 end

local RULES = {
	function(w)
		local best = w[1]
		for _, x in ipairs(w) do if (x.number > best.number) then best = x end end
		return "Cut the wire with the HIGHEST number.", best.color
	end,
	function(w)
		local best = w[1]
		for _, x in ipairs(w) do if (x.number < best.number) then best = x end end
		return "Cut the wire with the LOWEST number.", best.color
	end,
	function(w)
		-- Genau eine gerade Zahl erzwingen
		local even_index = math.random(3)
		for i, x in ipairs(w) do
			if (i == even_index and x.number % 2 == 1) then x.number = x.number + 1 end
			if (i ~= even_index and x.number % 2 == 0) then x.number = x.number + 1 end
			if (x.number > 99) then x.number = x.number - 2 end
		end
		return "Cut the only EVEN-numbered wire.", w[even_index].color
	end,
	function(w)
		local keep = w[math.random(3)].color
		local others = {}
		for _, x in ipairs(w) do if (x.color ~= keep) then table.insert(others, string.upper(x.color)) end end
		return "Do NOT cut the " .. others[1] .. " or the " .. others[2] .. " wire.", keep
	end,
	function(w)
		local best, best_d, tie = nil, math.huge, false
		for _, x in ipairs(w) do
			local d = math.abs(x.number - 50)
			if (d < best_d) then best, best_d, tie = x, d, false elseif (d == best_d) then tie = true end
		end
		if (tie) then return nil end
		return "Cut the wire whose number is CLOSEST to 50.", best.color
	end,
	function(w)
		local best, best_s, tie = nil, -1, false
		for _, x in ipairs(w) do
			local s = DigitSum(x.number)
			if (s > best_s) then best, best_s, tie = x, s, false elseif (s == best_s) then tie = true end
		end
		if (tie) then return nil end
		return "Cut the wire whose digits ADD UP to the most.", best.color
	end,
}

local function MakePuzzle()
	for _ = 1, 20 do
		local numbers = DistinctNumbers(3, 11, 98)
		local colors = { COLORS[1], COLORS[2], COLORS[3] }
		Shuffle(colors)
		local wires = {}
		for i = 1, 3 do wires[i] = { color = colors[i], number = numbers[i] } end
		local rule, answer = RULES[math.random(#RULES)](wires)
		if (rule) then
			-- Nummern muessen nach Anpassungen (gerade/ungerade) eindeutig bleiben
			local seen, ok = {}, true
			for _, x in ipairs(wires) do
				if (seen[x.number]) then ok = false end
				seen[x.number] = true
			end
			if (ok) then return wires, rule, answer end
		end
	end
	local wires = { { color = "red", number = 13 }, { color = "green", number = 77 }, { color = "blue", number = 42 } }
	return wires, "Cut the wire with the HIGHEST number.", "green"
end

-- ===================================================================
-- Ablauf
-- ===================================================================

local function Finish(ctx, defused, wire)
	if (ctx.data.over) then return end
	ctx.data.over = true
	local victim = ctx.actor_index
	local values = { name = ctx:Name(victim) }
	ctx:Show("bomb_result", { seat = victim, defused = defused, wire = wire or "" })
	ctx:Stage(defused and "defused" or "boom")
	if (defused) then
		ctx:Show("survive", { seat = victim, name = ctx:Name(victim) })
		ctx:Say(Text.JACK.BOMB_DEFUSED, values)
	else
		ctx:Fx("burn", victim)
		ctx:Kill(victim, "explosion")
		ctx:Say(Text.JACK.BOMB_BOOM, values)
	end
	ctx:Conclude(CFG.RESULT_TIME)
end

function Bomb.Start(ctx)
	local victim = ctx.actor_index
	local wires, rule, answer = MakePuzzle()
	ctx.data.answer = answer

	ctx:Say(Text.JACK.BOMB_START, { name = ctx:Name(victim) })
	ctx:Show("bomb_start", { seat = victim, seconds = CFG.TIME, intro = CFG.INTRO_TIME })
	ctx:Stage("ready", nil, { victim }, CFG.INTRO_TIME)   -- "GET READY": INTRO_TIME vor dem Schneiden
	ctx:Push()

	ctx:After(CFG.INTRO_TIME, function()
		ctx:Stage("cut", nil, { victim })
		ctx:Ask(victim, "wire", COLORS, CFG.TIME, function()
			Finish(ctx, false, nil)
		end, {
			wires = wires,
			rule = rule,
			bot_delay = ctx:Between(CFG.BOT_DELAY),
			bot_pick = function()
				if (math.random() < CFG.BOT_SUCCESS) then return answer end
				local wrong = {}
				for _, c in ipairs(COLORS) do if (c ~= answer) then table.insert(wrong, c) end end
				return wrong[math.random(#wrong)]
			end,
		})
	end)
end

function Bomb.OnInput(ctx, seat_index, choice)
	if (seat_index ~= ctx.actor_index or ctx.data.over) then return end
	Finish(ctx, choice == ctx.data.answer, choice)
end

DeathBox.Events.Register(Bomb)
