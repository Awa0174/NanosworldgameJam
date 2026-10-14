-- Server/Events/Deal.lua
-- Event "Card Deal": Jack ist grosszuegig und verteilt Karten. Niemand stirbt (Atempause zwischen den Toden).
--
-- Regeln:
--   - Jeder Config.DEAL.SHARE-te Lebende bekommt eine zufaellige Karte (aufgerundet, mindestens einer).
--   - Der Gewaehlte ist immer dabei, die anderen sind zufaellig. Wer eine volle Hand hat, wird uebersprungen.
--   - Jack sagt an wie im Original: "N PLAYERS WILL NOW BE GIVEN CARDS".

local Config = DeathBox.Config
local Text = DeathBox.Text
local Hand = DeathBox.Hand

local Deal = {
	id = "deal",
	min_alive = 2,
}

local function Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

function Deal.Start(ctx)
	local match = ctx.match
	local wanted = math.ceil(#ctx:AliveSeats() / Config.DEAL.SHARE)

	local receivers = {}
	if (Hand.HasRoom(match, ctx.actor_index)) then table.insert(receivers, ctx.actor_index) end
	local others = {}
	for _, index in ipairs(ctx:AliveSeats(ctx.actor_index)) do
		if (Hand.HasRoom(match, index)) then table.insert(others, index) end
	end
	Shuffle(others)
	for _, index in ipairs(others) do
		if (#receivers >= wanted) then break end
		table.insert(receivers, index)
	end
	table.sort(receivers)

	for _, index in ipairs(receivers) do Hand.GiveRandom(match, index) end

	local count = #receivers
	if (count == 0) then
		ctx:Say(Text.JACK.DEAL_NONE)
	else
		ctx:Say(count == 1 and Text.JACK.DEAL_ONE or Text.JACK.DEAL_MANY, { count = count })
	end
	ctx:Stage(count == 0 and "none" or (count == 1 and "one" or "many"), { count = count })
	ctx:Show("deal", { seats = receivers, count = count })
	ctx:Conclude(Config.DEAL.TIME)
end

function Deal.OnInput()
	-- Keine Eingaben: Jack verteilt
end

DeathBox.Events.Register(Deal)
