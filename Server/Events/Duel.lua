-- Server/Events/Duel.lua
-- Event "Quick Draw": Jack waehlt zwei Spieler fuer ein Duell.
--
-- Regeln:
--   - Beide warten eine zufaellige Zeit (Spannung), dann erscheint "DRAW!" mit einer Taste (W/A/S/D) – bei beiden dieselbe.
--   - Wer zuerst die richtige Taste drueckt, schiesst und gewinnt; der andere wird getroffen (Safety/Ricochet greifen wie bei Schuessen).
--   - Falsche Taste = man schiesst sich ins eigene Bein: man selbst scheidet aus.
--   - Drueckt keiner rechtzeitig, verliert Jack die Geduld: beide scheiden aus (wie im Original).
-- Die Taste und die Reihenfolge der Eingaben bestimmt der Server.

local Config = DeathBox.Config
local Text = DeathBox.Text

local CFG = Config.DUEL

local Duel = {
	id = "duel",
	actors = 2,
	min_alive = 3,       -- mit nur 2 Lebenden waere das Spiel sofort zu Ende (beide koennten sterben)
	kinds = { "qte" },
}

local function RandomKey()
	return Config.QTE_KEYS[math.random(#Config.QTE_KEYS)]
end

local function Other(ctx, seat_index)
	return (seat_index == ctx.actors[1]) and ctx.actors[2] or ctx.actors[1]
end

-- Schuss auf einen Duellanten (Ricochet und Safety greifen, Context:Strike). Ein Querschlaeger fliegt RICOCHET_TIME
-- lang (wie beim Revolver), dann trifft er sein neues Opfer. Rettet eine Safety, folgt "survive" wie bei jedem Schuss.
-- on_landed() sobald die Kugel getroffen hat.
local function Hit(ctx, index, on_landed)
	ctx:Strike(index, function(result, hit)
		if (result == "safety") then
			ctx:Show("survive", { seat = hit, name = ctx:Name(hit) })
			ctx:Say(Text.JACK.SAFETY_SAVE, { target = ctx:Name(hit) })
		end
		on_landed()
	end)
end

local function Resolve(ctx, winner, loser, how)
	if (ctx.data.over) then return end
	ctx.data.over = true
	ctx:CloseAllAsks()
	local a, b = ctx.actors[1], ctx.actors[2]
	-- Ergebnis-Pause erst, wenn jede Kugel getroffen hat (Querschlaeger: RICOCHET_TIME spaeter)
	local flying = (how == "both") and 2 or 1
	local function Landed()
		flying = flying - 1
		if (flying == 0) then ctx:Conclude(CFG.RESULT_TIME) end
	end

	if (how == "both") then
		ctx:Show("duel_result", { seat = a, seat2 = b, result = "both" })
		ctx:Stage("both")
		ctx:Say(Text.JACK.DUEL_BOTH)
		ctx:Fx("bang", a)
		Hit(ctx, a, Landed)
		Hit(ctx, b, Landed)
	elseif (how == "misfire") then
		ctx:Show("duel_result", { seat = loser, seat2 = winner, result = "misfire" })
		ctx:Stage("misfire", { loser = ctx:Name(loser) })
		ctx:Say(Text.JACK.DUEL_MISFIRE, { name = ctx:Name(loser) })
		ctx:Fx("bang", loser)
		Hit(ctx, loser, Landed)
	else
		ctx:Show("duel_result", { seat = winner, seat2 = loser, result = "win" })
		-- "X wins - Y is hit" nur, wenn die Kugel Y wirklich trifft. Ricochet und Safety setzen ihre eigene Zeile
		-- ("RICOCHET! ...", danach "BANG! Z is OUT" bzw. "A SAFETY card saves ...").
		if (ctx:HitOutcome(loser, "shot") == "dead") then
			ctx:Stage("win", { winner = ctx:Name(winner), loser = ctx:Name(loser) })
			ctx:Say(Text.JACK.DUEL_WIN, { name = ctx:Name(winner), target = ctx:Name(loser) })
		end
		ctx:Fx("bang", loser)
		Hit(ctx, loser, Landed)
	end
end

local function Draw(ctx)
	local prompt = RandomKey()
	ctx.data.prompt = prompt
	ctx.data.drawn = true
	ctx:Show("duel_draw", { seat = ctx.actors[1], seat2 = ctx.actors[2] })
	ctx:Stage("draw", nil, ctx.actors)

	for _, index in ipairs(ctx.actors) do
		ctx:Ask(index, "qte", Config.QTE_KEYS, CFG.WINDOW, function()
			-- Zeitlimit fuer diesen Spieler; wenn beide nichts gedrueckt haben, sterben beide
			if (not ctx.data.over and not ctx:IsAsking(Other(ctx, index))) then
				Resolve(ctx, nil, nil, "both")
			end
		end, {
			prompt = prompt,
			label = "DRAW!",
			step = 1,
			steps = 1,
			bot_delay = ctx:Between(CFG.BOT_REACTION),
			bot_pick = function(options)
				if (math.random() < CFG.BOT_ACCURACY) then return prompt end
				for _, key in ipairs(options) do if (key ~= prompt) then return key end end
			end,
		})
	end
end

function Duel.Start(ctx)
	local a, b = ctx.actors[1], ctx.actors[2]
	ctx.data.focus = a
	ctx:Say(Text.JACK.DUEL_START, { name = ctx:Name(a), target = ctx:Name(b) })
	ctx:Show("duel_start", { seat = a, seat2 = b, name = ctx:Name(a), name2 = ctx:Name(b) })
	ctx:Stage("wait", nil, { a, b })   -- "WAIT FOR IT": mind. WAIT[1] Sekunden vor "DRAW!"
	ctx:Push()
	ctx:After(ctx:Between(CFG.WAIT), function() Draw(ctx) end)
end

function Duel.OnInput(ctx, seat_index, choice)
	if (ctx.data.over or not ctx.data.drawn) then return end
	if (seat_index ~= ctx.actors[1] and seat_index ~= ctx.actors[2]) then return end
	local opponent = Other(ctx, seat_index)
	if (choice == ctx.data.prompt) then
		Resolve(ctx, seat_index, opponent, "win")
	else
		Resolve(ctx, opponent, seat_index, "misfire")
	end
end

-- Einer der beiden verlaesst die Show: der andere gewinnt kampflos
function Duel.OnSeatLeft(ctx, index, was_alive)
	if (ctx.data.over or not was_alive) then return end
	if (index ~= ctx.actors[1] and index ~= ctx.actors[2]) then return end
	ctx.data.over = true
	local winner = Other(ctx, index)
	ctx:Say(Text.JACK.DUEL_FLED, { name = ctx:Name(index), target = ctx:Name(winner) })
	ctx:Stage("fled", { winner = ctx:Name(winner), loser = ctx:Name(index) })
	ctx:Show("survive", { seat = winner, name = ctx:Name(winner) })
	ctx:Finish()
end

DeathBox.Events.Register(Duel)
