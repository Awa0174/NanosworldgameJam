-- Server/Events/Revolver.lua
-- Event "Revolver": Russisch Roulette als Kette. Jack gibt dem Gewaehlten einen Revolver mit sechs Kammern
-- und einer Kugel (frisch geladen pro Event, Position geheim).
--
-- Regeln:
--   - Der Halter haelt den Revolver in der rechten Hand, zielt mit der Maus (Kamera) auf einen anderen lebenden Spieler
--     und drueckt mit der linken Maustaste ab (Abfrage "target" mit aim = true, docs/PROTOCOL.md).
--   - Waehlt er nicht rechtzeitig, zielt Jack mit dem Revolver auf den Halter selbst.
--   - Klick (leere Kammer): Das Ziel bekommt den Revolver und waehlt als Naechstes. Hat der Halter sich selbst
--     angeklickt, wandert der Revolver zum naechsten Lebenden im Uhrzeigersinn.
--   - Die Chance steigt mit jedem Klick. Config.REVOLVER.LOAD_EXTRA = true (Standard): Jack laedt nach jedem Klick eine
--     Kugel nach und dreht die Trommel, Chance pro Abzug 1/6, 2/6, 3/6 ... 6/6. Sonst klassisch: die eine Kugel liegt
--     gleichverteilt, Chance pro Abzug 1/6, 1/5, 1/4, 1/3, 1/2, 1/1.
--   - Der Knall beendet das Event. Karten: Ricochet lenkt ab, Safety rettet (Context:Shoot).
--
-- Ablauf pro Zug:
--   give   (GIVE_TIME, nur beim ersten Halter) Revolver fliegt in die Hand, "GET READY"
--   choose (CHOOSE_TIME) Halter zielt: Zwischenstaende per DeathBox:Aim -> Show "revolver_aiming" an alle (hoechstens
--          alle AIM_INTERVAL s, die neueste Wahl gewinnt), seine Figur dreht sich zum Ziel. Bots schwenken 2-3-mal.
--   aim    (AIM_TIME) Ziel steht fest, Hahn gespannt -> Klick oder Knall
--   pass   (PASS_TIME) nach einem Klick: "*click* - the gun passes to X", nach PASS_DELAY fliegt der Revolver in X' Hand
--          (revolver_pass), X liest "YOU get the gun next" -> choose ...
-- Jeder geplante Schritt traegt eine Nummer (data.step). Aendert sich die Lage (jemand geht), wird die Nummer
-- erhoeht und alte Timer verfallen. Nachgereichte Zielanzeigen tragen data.aim_gen.

local Config = DeathBox.Config
local Text = DeathBox.Text
local Net = DeathBox.Net

local CFG = Config.REVOLVER

local Revolver = {
	id = "revolver",
	min_alive = 2,
	kinds = { "target" },
}

function Revolver.GetPublic(ctx)
	local data = ctx.data
	return {
		chambers = CFG.CHAMBERS,
		spent = data.spent,
		bullets = data.bullets,          -- geladene Kugeln fuer den naechsten Abzug (klassisch immer 1)
		load_extra = CFG.LOAD_EXTRA,
		holder = data.holder,
		target = data.target,
	}
end

-- "4 chambers left, one bullet" / "3 of 6 chambers loaded" fuer Jacks Saetze
local function Odds(ctx)
	if (CFG.LOAD_EXTRA) then
		local bullets = ctx.data.bullets
		if (bullets >= CFG.CHAMBERS) then return Text.Format(Text.JACK.REVOLVER_ODDS_FULL) end
		return Text.Format(Text.JACK.REVOLVER_ODDS_LOADED, { bullets = bullets, chambers = CFG.CHAMBERS })
	end
	local left = CFG.CHAMBERS - ctx.data.spent
	if (left <= 1) then return Text.Format(Text.JACK.REVOLVER_ODDS_LAST) end
	return Text.Format(Text.JACK.REVOLVER_ODDS, { left = left })
end

-- "2 IN 6" fuer die Stage-Zeile (Chance des naechsten Abzugs)
local function ShortOdds(ctx)
	if (CFG.LOAD_EXTRA) then
		return Text.Format(Text.JACK.REVOLVER_ODDS_SHORT, { bullets = ctx.data.bullets, chambers = CFG.CHAMBERS })
	end
	return Text.Format(Text.JACK.REVOLVER_ODDS_SHORT_CLASSIC, { left = CFG.CHAMBERS - ctx.data.spent })
end

-- Plant einen Schritt, der verfaellt, sobald sich die Lage aendert (siehe Kopf)
local function Later(ctx, seconds, callback)
	local data = ctx.data
	data.step = data.step + 1
	local step = data.step
	ctx:After(seconds, function()
		if (data.step == step) then callback() end
	end)
end

-- Die sitzende Figur des Halters dreht sich zum Ziel (nil oder er selbst: zur Mitte). Alle sehen, wohin er zielt.
local function TurnHolder(ctx, target)
	ctx.match:TurnSeatToward(ctx.data.holder, target)
end

-- ===================================================================
-- Zielen (Zwischenstaende waehrend der Wahl)
-- ===================================================================

local function SendAim(ctx)
	local data = ctx.data
	if (data.phase ~= "choose" or data.aim_seat == data.aim_sent) then return end
	data.aim_sent = data.aim_seat
	data.aim_last = Net.Now()
	ctx:Show("revolver_aiming", { shooter = data.holder, seat = data.aim_seat })
	TurnHolder(ctx, data.aim_seat ~= 0 and data.aim_seat or nil)
end

-- Hoechstens alle AIM_INTERVAL Sekunden an den Tisch; was dazwischen kommt, wird nachgereicht (neueste Wahl gewinnt)
local function QueueAim(ctx)
	local data = ctx.data
	if (data.aim_pending) then return end
	local wait = (data.aim_last or -math.huge) + CFG.AIM_INTERVAL * 1000 - Net.Now()
	if (wait <= 0) then
		SendAim(ctx)
		return
	end
	data.aim_pending = true
	local gen = data.aim_gen
	ctx:After(wait / 1000, function()
		if (data.aim_gen ~= gen) then return end
		data.aim_pending = false
		SendAim(ctx)
	end)
end

-- Neuer Zwischenstand (Mensch per DeathBox:Aim, Bot per Schwenk). target = 0: zielt auf niemanden.
local function SetAim(ctx, target)
	local data = ctx.data
	if (data.phase ~= "choose" or data.aim_seat == target) then return end
	data.aim_seat = target
	QueueAim(ctx)
end

-- Bots tun so, als wuerden sie zielen: 1-2 andere Plaetze, zuletzt das echte Ziel, dann der Schuss (bot_delay)
local function BotSweep(ctx, final, delay)
	local data = ctx.data
	local token = data.step
	local others = {}
	for _, index in ipairs(ctx:AliveSeats(data.holder)) do
		if (index ~= final) then table.insert(others, index) end
	end
	local plan = {}
	for _ = 1, math.min(math.random(1, 2), #others) do
		table.insert(plan, table.remove(others, math.random(#others)))
	end
	table.insert(plan, final)
	for i, target in ipairs(plan) do
		ctx:After(delay * i / (#plan + 1), function()
			if (data.step ~= token or data.phase ~= "choose" or not ctx:IsAlive(target)) then return end
			SetAim(ctx, target)
		end)
	end
end

-- ===================================================================
-- Ablauf
-- ===================================================================

local AskTarget, Aim, Pull, HandOver, SayPass, PassTo

-- Der Halter zielt und drueckt ab. Zu langsam: Jack richtet den Revolver auf den Halter selbst.
AskTarget = function(ctx)
	local data = ctx.data
	local holder = data.holder
	local targets = ctx:AliveSeats(holder)
	if (#targets == 0) then
		ctx:Finish()
		return
	end
	data.phase = "choose"
	data.target = nil
	data.focus = holder
	data.step = data.step + 1   -- nichts Geplantes mehr offen
	data.aim_gen = data.aim_gen + 1
	data.aim_seat, data.aim_sent, data.aim_pending = 0, 0, false
	TurnHolder(ctx, nil)
	ctx:Stage("choose", { name = ctx:Name(holder) }, { holder })

	local extra = { aim = true }   -- HUD: Zielmodus statt Ring (Revolver in der Hand, Maus zielt)
	local seat = ctx:Seat(holder)
	if (seat.is_bot or not seat.player) then
		local final = targets[math.random(#targets)]
		local delay = ctx:Between(CFG.BOT_AIM)
		extra.bot_delay = delay
		extra.bot_pick = function(options)
			for _, option in ipairs(options) do
				if (option == final) then return final end
			end
			return options[math.random(#options)]   -- das geplante Ziel ist gegangen
		end
		BotSweep(ctx, final, delay)
	end
	ctx:Ask(holder, "target", targets, CFG.CHOOSE_TIME, function()
		ctx:Say(Text.JACK.REVOLVER_HESITATE, { name = ctx:Name(holder) })
		Aim(ctx, holder)
	end, extra)
end

Aim = function(ctx, target)
	local data = ctx.data
	data.phase = "aim"
	data.target = target
	data.aim_gen = data.aim_gen + 1   -- nachgereichte Zielanzeigen verfallen
	data.aim_pending = false
	TurnHolder(ctx, target)
	ctx:Stage(target == data.holder and "aim_self" or "aim",
		{ name = ctx:Name(data.holder), target = ctx:Name(target), odds = ShortOdds(ctx) })
	ctx:Fx("aim", target)
	ctx:Show("revolver_aim", {
		shooter = data.holder,
		seat = target,
		aim_time = CFG.AIM_TIME,
		chamber = data.spent + 1,
		chambers = CFG.CHAMBERS,
		bullets = data.bullets,
	})
	ctx.match:PointAt(target)
	ctx:Push()
	Later(ctx, CFG.AIM_TIME, function() Pull(ctx) end)
end

Pull = function(ctx)
	local data = ctx.data
	local holder, target = data.holder, data.target
	data.spent = data.spent + 1
	local shot = { shooter = holder, chamber = data.spent, chambers = CFG.CHAMBERS, bullets = data.bullets }
	local fires
	if (CFG.LOAD_EXTRA) then
		fires = math.random(CFG.CHAMBERS) <= data.bullets    -- Trommel frisch gedreht: bullets von 6 Kammern geladen
	else
		fires = data.spent >= data.bullet
	end

	if (not fires) then
		-- Klick: leere Kammer
		shot.seat = target
		shot.result = "click"
		ctx:Fx("click", target)
		ctx:Show("revolver_shot", shot)

		local next_holder = target
		if (target == holder) then
			next_holder = ctx:NextAlive(holder, 1)
			ctx:Say(Text.JACK.REVOLVER_SELF_CLICK, { name = ctx:Name(holder), next = ctx:Name(next_holder) })
		else
			ctx:Say(Text.JACK.REVOLVER_CLICK, { target = ctx:Name(target) })
		end
		if (CFG.LOAD_EXTRA) then data.bullets = math.min(CFG.CHAMBERS, data.bullets + 1) end
		data.phase = "pass"
		data.target = nil
		data.next_holder = next_holder
		local key = CFG.LOAD_EXTRA and "click_reload" or "click"
		ctx:Stage(key, { name = ctx:Name(holder), target = ctx:Name(target), next = ctx:Name(next_holder) }, { next_holder },
			CFG.PASS_TIME)
		ctx:Push()
		-- Der Klick wirkt kurz (PASS_DELAY, der alte Halter haelt den Revolver noch), dann fliegt er in die Hand des
		-- neuen Halters. Der liest "YOU get the gun next" und zielt PASS_TIME nach dem Klick (Text und 3D passen zusammen).
		local delay = math.min(CFG.PASS_DELAY or 0, CFG.PASS_TIME)
		Later(ctx, delay, function()
			local planned = data.next_holder
			if (not HandOver(ctx, planned)) then return end
			if (data.holder ~= planned) then   -- der geplante Empfaenger ist gegangen: die Zeile nennt den neuen
				ctx:Stage(key, { name = ctx:Name(holder), next = ctx:Name(data.holder) }, { data.holder })
			end
			ctx:Push()
			Later(ctx, CFG.PASS_TIME - delay, function()
				if (ctx:IsAlive(data.holder)) then
					SayPass(ctx)   -- erst jetzt: Jacks Klick-Satz bleibt lesbar stehen
					AskTarget(ctx)
				else
					PassTo(ctx, data.holder)   -- der neue Halter ist waehrend der Weitergabe gegangen: einen Platz weiter
				end
			end)
		end)
		return
	end

	-- Knall: das Event endet, egal ob jemand stirbt oder eine Karte rettet
	data.phase = "over"
	ctx:Shoot(target, shot, function(result, victim)
		if (result == "safety") then
			ctx:Show("survive", { seat = victim, name = ctx:Name(victim) })
			ctx:Say(Text.JACK.SAFETY_SAVE, { target = ctx:Name(victim) })
		elseif (result == "dead") then
			ctx:Say(victim == target and Text.JACK.REVOLVER_BANG or Text.JACK.RICOCHET_HIT, { target = ctx:Name(victim) })
			ctx:Stage("bang", { target = ctx:Name(victim) })
		end
		data.target = nil
		ctx:Conclude(CFG.RESULT_TIME)
	end)
end

-- Revolver fliegt zum naechsten Halter (revolver_pass). Ist der inzwischen weg, zum naechsten Lebenden im
-- Uhrzeigersinn. Gibt false zurueck, wenn das Event damit endet (niemand mehr da).
HandOver = function(ctx, next_holder)
	local data = ctx.data
	if (not next_holder or not ctx:IsAlive(next_holder)) then
		next_holder = next_holder and ctx:NextAlive(next_holder, 1)
	end
	if (not next_holder or #ctx:AliveSeats() < 2) then
		ctx:Finish()
		return false
	end
	local from = data.holder
	TurnHolder(ctx, nil)   -- der alte Halter schaut wieder zur Mitte
	data.holder = next_holder
	data.focus = next_holder
	data.next_holder = nil
	ctx:Show("revolver_pass", { from = from, seat = next_holder, bullets = data.bullets, chambers = CFG.CHAMBERS })
	return true
end

-- Jack zum neuen Halter ("One more bullet for luck! Bonzo, your turn. 2 of 6 ...")
SayPass = function(ctx)
	ctx:Say(CFG.LOAD_EXTRA and Text.JACK.REVOLVER_RELOAD or Text.JACK.REVOLVER_PASS, { name = ctx:Name(ctx.data.holder), odds = Odds(ctx) })
end

-- Sofort weitergeben und zielen lassen (der Halter ist gegangen)
PassTo = function(ctx, next_holder)
	if (HandOver(ctx, next_holder)) then
		SayPass(ctx)
		AskTarget(ctx)
	end
end

function Revolver.Start(ctx)
	local data = ctx.data
	data.spent = 0
	data.bullet = math.random(CFG.CHAMBERS)   -- nur klassisch: Kammer mit der Kugel
	data.bullets = 1
	data.holder = ctx.actor_index
	data.step = 0
	data.aim_gen = 0
	data.phase = "give"
	data.focus = data.holder

	ctx:Say(Text.JACK.REVOLVER_HAND, { name = ctx:Name(data.holder), blanks = CFG.CHAMBERS - 1 })
	ctx:Show("revolver_give", { seat = data.holder })
	ctx:Stage("give", { name = ctx:Name(data.holder) }, { data.holder }, CFG.GIVE_TIME)
	ctx:Push()
	-- Erst fliegt der Revolver in die Hand und der Halter liest, was er tun muss, dann wird gezielt
	Later(ctx, CFG.GIVE_TIME, function() AskTarget(ctx) end)
end

function Revolver.OnInput(ctx, seat_index, choice)
	local data = ctx.data
	if (data.phase ~= "choose" or seat_index ~= data.holder) then return end
	ctx:Say(Text.JACK.REVOLVER_AIM, { name = ctx:Name(seat_index), target = ctx:Name(choice), odds = Odds(ctx) })
	Aim(ctx, choice)
end

-- Zwischenstand der Zielwahl (schon geprueft: offene Abfrage des Halters mit aim = true, Ziel 0 oder erlaubt)
function Revolver.OnAim(ctx, seat_index, target)
	local data = ctx.data
	if (data.phase ~= "choose" or seat_index ~= data.holder) then return end
	SetAim(ctx, target)
end

-- Jemand verlaesst die Show. Die Kammer, auf die gezielt wurde, bleibt geladen.
function Revolver.OnSeatLeft(ctx, index, was_alive)
	local data = ctx.data
	if (not was_alive or data.phase == "over") then return end

	if (data.phase == "pass") then
		-- Revolver ist unterwegs: war der Empfaenger der Gehende, geht er einen Platz weiter (PassTo)
		return
	end

	if (index == data.holder) then
		local next_holder = ctx:NextAlive(index, 1)
		if (not next_holder or #ctx:AliveSeats() < 2) then
			ctx:Finish()
			return
		end
		ctx:Say(Text.JACK.REVOLVER_HOLDER_FLED, { name = ctx:Name(index), next = ctx:Name(next_holder) })
		PassTo(ctx, next_holder)
	elseif (data.phase == "aim" and index == data.target) then
		ctx:Say(Text.JACK.TARGET_FLED, { target = ctx:Name(index) })
		AskTarget(ctx)
	else
		if (data.phase == "choose" and index == data.aim_seat) then SetAim(ctx, 0) end   -- angezieltes Ziel ist weg
		ctx:DropOption(index)   -- aus der offenen Zielwahl nehmen (neue Abfrage-ID, Zielmodus bleibt)
	end
end

DeathBox.Events.Register(Revolver)
