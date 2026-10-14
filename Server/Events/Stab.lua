-- Server/Events/Stab.lua
-- Event "Stab Your Neighbour": Jack gibt dem gewaehlten Spieler ein Messer.
--
-- Regeln:
--   - Jack gibt dem Gewaehlten das Messer ("GET READY", INTRO_TIME), dann waehlt er.
--   - Der Halter waehlt seinen linken oder rechten (lebenden) Sitznachbarn.
--   - Waehlt er nicht rechtzeitig, sticht Jack den Halter selbst.
--   - Das Opfer bekommt eine Taste (W/A/S/D) und ein kurzes Zeitfenster zum Blocken.
--     Richtig = geblockt. Falsch oder zu langsam = ausgeschieden.
--   - Safety hilft nicht (kein Schuss).
-- Das Hackbeil ist reine Darstellung beim Client (Show "stab_raise" / "stab_strike").

local Config = DeathBox.Config
local Text = DeathBox.Text

local Stab = {
	id = "stab",
	min_alive = 2,
	kinds = { "target", "qte" },
}

local function Resolve(ctx, blocked)
	if (ctx.data.over) then return end
	ctx.data.over = true
	local victim = ctx.data.victim
	local values = { target = ctx:Name(victim) }

	ctx:Show("stab_strike", { seat = victim, blocked = blocked })
	ctx:Stage(blocked and "blocked" or "hit", values)
	if (blocked) then
		ctx:Fx("block", victim)
		ctx:Show("survive", { seat = victim, name = ctx:Name(victim) })
		ctx:Say(Text.JACK.STAB_BLOCKED, values)
	else
		ctx:Fx("stab", victim)
		ctx:Kill(victim, "knife")
		ctx:Say(Text.JACK.STAB_HIT, values)
	end
	ctx.data.focus = nil
	ctx:Conclude(Config.STAB.RESULT_TIME)
end

-- Opfer steht fest: Hackbeil schwebt ueber ihm, Opfer darf blocken
local function Strike(ctx, victim)
	ctx.data.victim = victim
	ctx.data.focus = victim
	-- Das Opfer liest "GET READY TO BLOCK" (AIM_TIME), dann kommt die Taste
	ctx:Stage(victim == ctx.actor_index and "hesitate" or "strike", { target = ctx:Name(victim) }, { victim },
		Config.STAB.AIM_TIME)

	ctx:Show("stab_raise", { seat = victim, holder = ctx.actor_index })
	ctx.match:PointAt(victim)
	ctx:Fx("knife_raise", victim)
	ctx:Push()

	ctx:After(Config.STAB.AIM_TIME, function()
		local prompt = Config.QTE_KEYS[math.random(#Config.QTE_KEYS)]
		ctx.data.prompt = prompt
		ctx:Stage("block", { target = ctx:Name(victim) }, { victim })
		ctx:Ask(victim, "qte", Config.QTE_KEYS, Config.STAB.BLOCK_WINDOW, function()
			Resolve(ctx, false)
		end, {
			prompt = prompt,
			step = 1,
			steps = 1,
			label = "BLOCK!",
			bot_delay = Config.STAB.BLOCK_WINDOW * 0.5,
			bot_pick = function(options)
				if (math.random() < Config.STAB.BOT_BLOCK) then return prompt end
				for _, key in ipairs(options) do
					if (key ~= prompt) then return key end
				end
			end,
		})
	end)
end

-- Der Halter waehlt einen Nachbarn. Die Nachbarn erst jetzt bestimmen: im Intro kann jemand gegangen sein.
local function AskNeighbour(ctx)
	local actor = ctx.actor_index
	local options = ctx:Neighbours(actor)
	if (#options == 0) then
		ctx:Finish()
		return
	end
	ctx:Stage("choose", nil, { actor })
	ctx:Ask(actor, "target", options, Config.STAB.CHOOSE_TIME, function()
		ctx:Say(Text.JACK.STAB_HESITATE, { name = ctx:Name(actor) })
		Strike(ctx, actor)
	end)
end

function Stab.Start(ctx)
	local actor = ctx.actor_index
	if (#ctx:Neighbours(actor) == 0) then
		ctx:Finish()
		return
	end
	ctx:Say(Text.JACK.STAB_HAND, { name = ctx:Name(actor) })
	ctx:Stage("ready", nil, { actor }, Config.STAB.INTRO_TIME)   -- "GET READY": INTRO_TIME vor der Wahl
	ctx:Push()
	ctx:After(Config.STAB.INTRO_TIME, function() AskNeighbour(ctx) end)
end

function Stab.OnInput(ctx, seat_index, choice)
	if (seat_index == ctx.actor_index and not ctx.data.victim) then
		ctx:Say(Text.JACK.STAB_CHOSE, { name = ctx:Name(seat_index), target = ctx:Name(choice) })
		Strike(ctx, choice)
	elseif (seat_index == ctx.data.victim) then
		Resolve(ctx, choice == ctx.data.prompt)
	end
end

-- Halter geht vor der Wahl oder das Opfer geht: Event endet ohne Ergebnis.
-- Geht ein angebotener Nachbar, ist der naechste Lebende der neue Nachbar (Ring wird neu geschickt).
function Stab.OnSeatLeft(ctx, index, was_alive)
	if (not was_alive or ctx.data.over) then return end
	if ((index == ctx.actor_index and not ctx.data.victim) or index == ctx.data.victim) then
		ctx:Finish()
	elseif (not ctx.data.victim and ctx:Offers(ctx.actor_index, index)) then
		ctx:UpdateAsk(ctx.actor_index, ctx:Neighbours(ctx.actor_index))
	end
end

DeathBox.Events.Register(Stab)
