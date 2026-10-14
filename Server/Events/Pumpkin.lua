-- Server/Events/Pumpkin.lua
-- Event "Pass the Pumpkin": heisse Kartoffel mit einer Kuerbisbombe.
--
-- Regeln:
--   - Jack zuendet einen Kuerbis und wirft ihn dem Gewaehlten zu. Die Zuendschnur brennt eine geheime,
--     zufaellige Zeit (Config.PUMPKIN.FUSE).
--   - Wer den Kuerbis haelt, wirft ihn an seinen linken oder rechten lebenden Nachbarn (Abfrage "pass").
--     Laeuft die Abfrage ab, kommt sofort eine neue, solange die Schnur brennt.
--   - Ist die Schnur abgebrannt, explodiert der Kuerbis beim Halter. Keine Karte rettet.
--   - Nach einem Wurf ist der Kuerbis kurz in der Luft (CATCH_TIME): so lange kann der Faenger nicht weiterwerfen.
--     Explodiert er im Flug, trifft es den Faenger.

local Config = DeathBox.Config
local Text = DeathBox.Text

local CFG = Config.PUMPKIN

local Pumpkin = {
	id = "pumpkin",
	min_alive = 2,
	kinds = { "pass" },
}

function Pumpkin.GetPublic(ctx)
	return { holder = ctx.data.holder }
end

local function AskPass(ctx)
	local data = ctx.data
	if (data.over) then return end
	local holder = data.holder
	ctx:Stage("hold", { name = ctx:Name(holder) }, { holder })
	ctx:Ask(holder, "pass", ctx:Neighbours(holder), CFG.PASS_TIME, function()
		AskPass(ctx)   -- nicht geworfen: Schnur brennt weiter, neue Abfrage
	end, {
		bot_delay = ctx:Between(CFG.BOT_DELAY),
		no_timer = true,   -- kein Zeitbalken: er wuerde eine Explosion nach PASS_TIME vortaeuschen
	})
end

local function Throw(ctx, from, to)
	local data = ctx.data
	data.holder = to
	data.focus = to
	data.flight = data.flight + 1
	local flight = data.flight
	ctx:Show("pumpkin_pass", { from = from, seat = to })
	ctx:Stage("hold", { name = ctx:Name(to) }, { to })
	ctx:Push()
	ctx:After(CFG.CATCH_TIME, function()
		if (data.flight == flight) then AskPass(ctx) end
	end)
end

local function Boom(ctx)
	local data = ctx.data
	if (data.over) then return end
	data.over = true
	ctx:CloseAllAsks()
	local holder = data.holder
	ctx:Show("pumpkin_boom", { seat = holder })
	ctx:Say(Text.JACK.PUMPKIN_BOOM, { name = ctx:Name(holder) })
	ctx:Stage("boom", { name = ctx:Name(holder) })
	ctx:Kill(holder, "explosion")
	ctx:Conclude(CFG.RESULT_TIME)
end

function Pumpkin.Start(ctx)
	local data = ctx.data
	data.holder = ctx.actor_index
	data.focus = data.holder
	data.flight = 0

	ctx:Say(Text.JACK.PUMPKIN_START, { name = ctx:Name(data.holder) })
	-- duration_hint = laengste moegliche Schnur. Die echte bleibt geheim.
	ctx:Show("pumpkin_start", { seat = data.holder, duration_hint = CFG.FUSE[2] })
	ctx:Stage("catch", nil, { data.holder }, CFG.THROW_TIME)   -- "CATCH!": THROW_TIME vor der ersten Wurf-Abfrage
	ctx:Push()

	local fuse = ctx:Between(CFG.FUSE)
	ctx:After(CFG.THROW_TIME, function()
		AskPass(ctx)
		ctx:After(fuse, function() Boom(ctx) end)
	end)
end

function Pumpkin.OnInput(ctx, seat_index, choice)
	local data = ctx.data
	if (data.over or seat_index ~= data.holder) then return end
	Throw(ctx, seat_index, choice)
end

-- Halter geht: der Kuerbis explodiert auf dem leeren Stuhl, niemand sonst stirbt.
-- Geht ein Nachbar des Halters, ist der naechste Lebende der neue Nachbar (Ring wird neu geschickt).
function Pumpkin.OnSeatLeft(ctx, index, was_alive)
	local data = ctx.data
	if (not was_alive or data.over) then return end
	if (index == data.holder) then
		data.over = true
		ctx:CloseAllAsks()
		ctx:Show("pumpkin_boom", { seat = index })
		ctx:Say(Text.JACK.PUMPKIN_FLED, { name = ctx:Name(index) })
		ctx:Stage("fled", { name = ctx:Name(index) })
		ctx:Conclude(CFG.RESULT_TIME)
	elseif (ctx:Offers(data.holder, index)) then
		ctx:UpdateAsk(data.holder, ctx:Neighbours(data.holder))
	end
end

DeathBox.Events.Register(Pumpkin)
