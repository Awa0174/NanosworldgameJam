-- Server/Events/FireBreath.lua
-- Event "Fire Breath": Jack spuckt Feuer, der gewaehlte Spieler brennt.
--
-- Regeln:
--   - Eine Flamme springt ueber den Bildschirm. Sie muss Config.FIRE.CLICKS-mal angeklickt werden,
--     bevor Config.FIRE.TIME abgelaufen ist.
--   - Geschafft = Feuer aus. Nicht geschafft = verbrannt, ausgeschieden.
--   - Safety hilft nicht (kein Schuss).
--
-- Fairness/Sicherheit: Jede Position und jedes Klick-Token erzeugt der Server. Ein Klick zaehlt nur,
-- wenn er das aktuelle Token zur aktuellen Abfrage traegt. Die Zeit misst der Server.
-- Feuer und Rauch sind reine Darstellung beim Client (Show "fire_breath" / "fire_off").

local Config = DeathBox.Config
local Text = DeathBox.Text
local Net = DeathBox.Net

local FireBreath = {
	id = "fire",
	min_alive = 2,
	kinds = { "click" },
}

local Burn, Extinguish

local function NextClick(ctx)
	local remaining = (ctx.data.deadline - Net.Now()) / 1000
	if (remaining <= 0.05) then
		Burn(ctx)
		return
	end

	local token = math.random(100000, 999999)
	local done = Config.FIRE.CLICKS - ctx.data.left
	ctx:Stage("click", { left = ctx.data.left, done = done, clicks = Config.FIRE.CLICKS }, { ctx.actor_index })
	ctx:Ask(ctx.actor_index, "click", { token }, remaining, function()
		Burn(ctx)
	end, {
		x = math.random(15, 85),
		y = math.random(20, 75),
		progress = done,
		total = Config.FIRE.CLICKS,
		bot_delay = Config.FIRE.TIME * 0.8 / Config.FIRE.CLICKS,
		bot_pick = function(options)
			return ctx.data.bot_wins and options[1] or nil
		end,
	})
end

Burn = function(ctx)
	if (ctx.data.over) then return end
	ctx.data.over = true
	local actor = ctx.actor_index
	ctx:Show("fire_off", { seat = actor, survived = false })
	ctx:Fx("burn", actor)
	ctx:Stage("burn")
	ctx:Kill(actor, "fire")
	ctx:Say(Text.JACK.FIRE_BURN, { name = ctx:Name(actor) })
	ctx:Conclude(Config.FIRE.RESULT_TIME)
end

Extinguish = function(ctx)
	if (ctx.data.over) then return end
	ctx.data.over = true
	local actor = ctx.actor_index
	ctx:Show("fire_off", { seat = actor, survived = true })
	ctx:Show("survive", { seat = actor, name = ctx:Name(actor) })
	ctx:Fx("extinguish", actor)
	ctx:Say(Text.JACK.FIRE_OUT, { name = ctx:Name(actor) })
	ctx:Stage("out")
	ctx:Conclude(Config.FIRE.RESULT_TIME)
end

function FireBreath.Start(ctx)
	local actor = ctx.actor_index
	ctx.data.left = Config.FIRE.CLICKS
	ctx.data.bot_wins = math.random() < Config.FIRE.BOT_SUCCESS

	ctx:Say(Text.JACK.FIRE_START, { name = ctx:Name(actor) })
	ctx:Show("fire_breath", { seat = actor, delay = Config.FIRE.INTRO_TIME })
	ctx:Fx("fire", actor)
	ctx:Stage("ready", nil, { actor }, Config.FIRE.INTRO_TIME)   -- "GET READY": mind. INTRO_TIME vor der ersten Flamme
	ctx:Push()

	ctx:After(Config.FIRE.INTRO_TIME, function()
		ctx.data.deadline = Net.Now() + Config.FIRE.TIME * 1000
		NextClick(ctx)
	end)
end

function FireBreath.OnInput(ctx, seat_index)
	if (seat_index ~= ctx.actor_index or ctx.data.over) then return end
	ctx.data.left = ctx.data.left - 1
	if (ctx.data.left <= 0) then
		Extinguish(ctx)
	else
		NextClick(ctx)
	end
end

DeathBox.Events.Register(FireBreath)
