-- Server/Events/SplitSteal.lua
-- Event "Split or Steal": Jack waehlt zwei Spieler. Beide entscheiden geheim.
--
--   A \ B    Split                     Steal
--   Split    beide +1 Karte            B nimmt alle Karten von A, +1
--   Steal    A nimmt alle von B, +1    niemand bekommt etwas
--
-- Regeln:
--   - Keine Wahl im Zeitlimit gilt als Split. Aufgedeckt wird gleichzeitig, fuer alle sichtbar.
--   - Volle Hand: was nicht mehr passt, behaelt Jack.
--   - Niemand stirbt (Atempause). Bots stehlen mit Config.SPLITSTEAL.BOT_STEAL.

local Config = DeathBox.Config
local Text = DeathBox.Text
local Hand = DeathBox.Hand

local CFG = Config.SPLITSTEAL

local SplitSteal = {
	id = "splitsteal",
	min_alive = 2,
	actors = 2,
	kinds = { "splitsteal" },
}

function SplitSteal.GetPublic(ctx)
	local a, b = ctx.actors[1], ctx.actors[2]
	local choices = ctx.data.choices or {}
	return { a = a, b = b, locked_a = choices[a] ~= nil, locked_b = choices[b] ~= nil }
end

local function Reveal(ctx)
	if (ctx.data.over) then return end   -- einer ist im Aufdeck-Fenster gegangen: kein Deal
	ctx.data.over = true                  -- ab hier ist der Deal gemacht, Abgaenge aendern nichts mehr
	local match = ctx.match
	local a, b = ctx.actors[1], ctx.actors[2]
	local choice_a, choice_b = ctx.data.choices[a], ctx.data.choices[b]
	local gained = { [a] = 0, [b] = 0 }

	if (choice_a == "split" and choice_b == "split") then
		for _, index in ipairs({ a, b }) do
			if (Hand.GiveRandom(match, index)) then gained[index] = 1 end
		end
		ctx:Say(Text.JACK.SPLITSTEAL_SPLIT)
		ctx:Stage("split")
	elseif (choice_a == "steal" and choice_b == "steal") then
		ctx:Say(Text.JACK.SPLITSTEAL_BOTH)
		ctx:Stage("both")
	else
		local stealer = (choice_a == "steal") and a or b
		local victim = (stealer == a) and b or a
		local stolen = Hand.TakeAll(match, victim)
		local taken = Hand.AddAll(match, stealer, stolen)
		local bonus = Hand.GiveRandom(match, stealer) and 1 or 0
		gained[stealer] = taken + bonus
		gained[victim] = -#stolen
		ctx:Say(Text.JACK.SPLITSTEAL_STEAL, { stealer = ctx:Name(stealer), victim = ctx:Name(victim) })
		ctx:Stage("steal", { stealer = ctx:Name(stealer), victim = ctx:Name(victim) })
	end

	ctx:Show("splitsteal_result", {
		seat = a, seat2 = b, choice = choice_a, choice2 = choice_b, gained = gained[a], gained2 = gained[b],
	})
	ctx:Conclude(CFG.RESULT_TIME)
end

local function Lock(ctx, index, choice)
	local data = ctx.data
	if (data.over or data.revealing or data.choices[index]) then return end
	data.choices[index] = choice
	local a, b = ctx.actors[1], ctx.actors[2]
	local both = data.choices[a] and data.choices[b]
	if (both) then
		data.revealing = true
		ctx:Stage("reveal", nil, nil, CFG.REVEAL_TIME)
	end
	ctx:Push()
	if (both) then
		ctx:After(CFG.REVEAL_TIME, function() Reveal(ctx) end)
	end
end

function SplitSteal.Start(ctx)
	local a, b = ctx.actors[1], ctx.actors[2]
	ctx.data.choices = {}

	ctx:Show("splitsteal_start", { seat = a, seat2 = b, name = ctx:Name(a), name2 = ctx:Name(b) })
	ctx:Say(Text.JACK.SPLITSTEAL_START, { name = ctx:Name(a), name2 = ctx:Name(b) })
	ctx.match:PointAt(b)   -- Jack zeigt auf den zweiten Spieler
	ctx:Stage("ready", nil, { a, b }, CFG.INTRO_TIME)
	ctx:Push()

	ctx:After(CFG.INTRO_TIME, function()
		if (ctx.data.over) then return end   -- einer ist waehrend der Ansage gegangen
		ctx:Stage("choose")
		ctx:AskMany({ a, b }, "splitsteal", { "split", "steal" }, CFG.TIME, function(index)
			Lock(ctx, index, "split")   -- keine Wahl = Split
		end, function(index)
			local partner = (index == a) and b or a
			return {
				partner = partner,
				partner_name = ctx:Name(partner),
				bot_delay = ctx:Between(CFG.BOT_DELAY),
				bot_pick = function() return math.random() < CFG.BOT_STEAL and "steal" or "split" end,
			}
		end)
	end)
end

function SplitSteal.OnInput(ctx, seat_index, choice)
	Lock(ctx, seat_index, choice)
end

-- Einer der beiden geht vor dem Aufdecken (auch noch im Aufdeck-Fenster): kein Deal. Sonst bekaeme ein
-- Weggegangener die Karten des anderen, und die waeren einfach weg.
function SplitSteal.OnSeatLeft(ctx, index, was_alive)
	local data = ctx.data
	if (not was_alive or data.over) then return end
	if (index == ctx.actors[1] or index == ctx.actors[2]) then
		data.over = true
		ctx:CloseAllAsks()
		ctx:Say(Text.JACK.SPLITSTEAL_FLED, { name = ctx:Name(index) })
		ctx:Stage("fled", { name = ctx:Name(index) })
		ctx:Conclude(CFG.RESULT_TIME * 0.5)
	end
end

DeathBox.Events.Register(SplitSteal)
