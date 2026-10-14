-- Server/Events/ChooseCard.lua
-- Event "Choose a Card": Jack faechert Karten auf, der Gewaehlte behaelt eine. Niemand stirbt.
--
-- Regeln:
--   - Config.CHOOSECARD.OPTIONS verschiedene, zufaellige Karten (nach Gewicht) zur Wahl (Abfrage "pickcard").
--   - Zeitlimit: Jack zieht eine davon zufaellig.
--   - Volle Hand: Jack lacht, es gibt nichts.

local Config = DeathBox.Config
local Text = DeathBox.Text
local Hand = DeathBox.Hand

local CFG = Config.CHOOSECARD

local ChooseCard = {
	id = "choosecard",
	min_alive = 2,
	kinds = { "pickcard" },
}

local function Take(ctx, card_id)
	local data = ctx.data
	if (data.over) then return end
	data.over = true
	local actor = ctx.actor_index
	if (Hand.Give(ctx.match, actor, card_id)) then
		ctx:Show("card_gain", { seat = actor, count = 1 })
	end
	ctx:Stage("done")
	ctx:Conclude(CFG.RESULT_TIME)
end

function ChooseCard.Start(ctx)
	local actor = ctx.actor_index
	local values = { name = ctx:Name(actor) }
	if (not Hand.HasRoom(ctx.match, actor)) then
		ctx.data.over = true
		ctx:Say(Text.JACK.CHOOSECARD_FULL, values)
		ctx:Stage("full")
		ctx:Conclude(CFG.RESULT_TIME)
		return
	end

	-- verschiedene Karten, nach Gewicht gezogen (shown = eigene Liste fuers HUD, options bleibt beim Server)
	local cards, shown, taken = {}, {}, {}
	for _ = 1, CFG.OPTIONS do
		local id = DeathBox.RandomCard(taken)
		if (not id) then break end
		taken[id] = true
		table.insert(cards, id)
		table.insert(shown, id)
	end

	ctx:Say(Text.JACK.CHOOSECARD_START, values)
	ctx:Stage("pick", nil, { actor })
	ctx:Ask(actor, "pickcard", cards, CFG.TIME, function()
		ctx:Say(Text.JACK.CHOOSECARD_TIMEOUT, values)
		Take(ctx, cards[math.random(#cards)])
	end, { cards = shown })
end

function ChooseCard.OnInput(ctx, seat_index, choice)
	if (seat_index ~= ctx.actor_index) then return end
	ctx:Say(Text.JACK.CHOOSECARD_DONE, { name = ctx:Name(seat_index) })
	Take(ctx, choice)
end

DeathBox.Events.Register(ChooseCard)
