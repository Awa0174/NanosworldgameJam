-- Server/Events/KnifeToss.lua
-- Event "Knife Toss": Jack wirft ein Messer auf den gewaehlten Spieler.
--
-- Regeln:
--   - Es erscheint eine Folge von Tasten (W/A/S/D), eine nach der anderen, mit kuerzer werdendem
--     Zeitfenster (Config.KNIFE.WINDOWS).
--   - Alle richtig = ausgewichen, das Messer fliegt vorbei.
--   - Falsche Taste oder zu langsam = getroffen, ausgeschieden.
--   - Safety hilft nicht (kein Schuss).
-- Die Tastenfolge erzeugt der Server, und der Server prueft jede Taste.
-- Das Messer selbst ist reine Darstellung beim Client (Show "knife_raise" / "knife_throw").

local Config = DeathBox.Config
local Text = DeathBox.Text

local KnifeToss = {
	id = "knife",
	min_alive = 2,
	kinds = { "qte" },
}

local function RandomKey()
	return Config.QTE_KEYS[math.random(#Config.QTE_KEYS)]
end

local function WrongKey(prompt)
	local key
	repeat key = RandomKey() until key ~= prompt
	return key
end

local Finish

local function Step(ctx)
	local step = ctx.data.step + 1
	ctx.data.step = step
	local prompt = RandomKey()
	ctx.data.prompt = prompt
	local window = Config.KNIFE.WINDOWS[step]
	-- Pro Taste so viel Erfolgschance, dass die ganze Folge BOT_SUCCESS ergibt
	local per_step = Config.KNIFE.BOT_SUCCESS ^ (1 / #Config.KNIFE.WINDOWS)

	ctx:Stage("dodge", { step = step, steps = #Config.KNIFE.WINDOWS }, { ctx.actor_index })
	ctx:Ask(ctx.actor_index, "qte", Config.QTE_KEYS, window, function()
		Finish(ctx, false)
	end, {
		prompt = prompt,
		step = step,
		steps = #Config.KNIFE.WINDOWS,
		label = "DODGE!",
		bot_delay = window * 0.5,
		bot_pick = function()
			return math.random() < per_step and prompt or WrongKey(prompt)
		end,
	})
end

Finish = function(ctx, dodged)
	if (ctx.data.over) then return end
	ctx.data.over = true
	local actor = ctx.actor_index
	local values = { name = ctx:Name(actor) }

	ctx:Show("knife_throw", { seat = actor, hit = not dodged })
	ctx:Stage(dodged and "dodged" or "hit")   -- vor dem Tod: dessen Zustand traegt schon das Ergebnis
	if (dodged) then
		ctx:Fx("dodge", actor)
		ctx:Show("survive", { seat = actor, name = ctx:Name(actor) })
		ctx:Say(Text.JACK.KNIFE_DODGED, values)
	else
		ctx:Fx("stab", actor)
		ctx:Kill(actor, "knife")
		ctx:Say(Text.JACK.KNIFE_HIT, values)
	end
	ctx:Conclude(Config.KNIFE.RESULT_TIME)
end

function KnifeToss.Start(ctx)
	ctx.data.step = 0
	ctx:Say(Text.JACK.KNIFE_START, { name = ctx:Name(ctx.actor_index) })
	ctx:Show("knife_raise", { seat = ctx.actor_index })
	ctx:Fx("knife_raise", ctx.actor_index)
	ctx:Stage("ready", nil, { ctx.actor_index }, Config.KNIFE.INTRO_TIME)   -- "GET READY": mind. INTRO_TIME vor der ersten Taste
	ctx:Push()
	ctx:After(Config.KNIFE.INTRO_TIME, function() Step(ctx) end)
end

function KnifeToss.OnInput(ctx, seat_index, choice)
	if (seat_index ~= ctx.actor_index or ctx.data.over) then return end
	if (choice ~= ctx.data.prompt) then
		Finish(ctx, false)
	elseif (ctx.data.step >= #Config.KNIFE.WINDOWS) then
		Finish(ctx, true)
	else
		ctx:Fx("qte_ok", seat_index)
		Step(ctx)
	end
end

DeathBox.Events.Register(KnifeToss)
