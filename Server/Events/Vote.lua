-- Server/Events/Vote.lua
-- Event "Spare or Eliminate": Der ganze Tisch stimmt ueber den Gewaehlten ab, auch die Ausgeschiedenen.
--
-- Regeln:
--   - Waehler: jeder Platz mit verbundenem Spieler (lebend oder ausgeschieden) und jeder LEBENDE Bot, ausser dem Opfer.
--     Bots stimmen mit Config.VOTE.BOT_KILL fuer ELIMINATE.
--   - Die Stimmen werden live gezaehlt (State event.data). Haben alle gewaehlt, endet die Abstimmung sofort.
--   - Mehrheit entscheidet. Gleichstand (auch 0:0) = Jack wirft eine Muenze.
--   - Keine Karte rettet (kein Schuss).
-- Wer nicht rechtzeitig abstimmt, wird nicht gezaehlt.

local Config = DeathBox.Config
local Text = DeathBox.Text

local CFG = Config.VOTE
local PUSH_DELAY = 0.2   -- Live-Zaehlung: viele Stimmen kurz hintereinander = ein Zustand-Push

local Vote = {
	id = "vote",
	min_alive = 2,
	kinds = { "vote" },
}

function Vote.GetPublic(ctx)
	local data = ctx.data
	local hidden = data.secret and not data.result
	return {
		target = ctx.actor_index,
		spare = not hidden and data.spare or nil,
		kill = not hidden and data.kill or nil,
		voted = data.spare + data.kill,
		voters = #data.voters,
		secret = data.secret,
	}
end

-- Alle Plaetze, die abstimmen duerfen
local function Voters(ctx)
	local result = {}
	for index, seat in ipairs(ctx.match.seats) do
		-- Menschen stimmen immer mit (auch ausgeschiedene), Bots nur, solange sie leben: sonst entscheiden an einem
		-- Tisch mit vielen Bots die toten Bots, und die Stimmen der Menschen gehen unter.
		if (index ~= ctx.actor_index and (seat.player or (seat.is_bot and seat.alive))) then table.insert(result, index) end
	end
	return result
end

-- Urteil vollstrecken
local function Execute(ctx)
	local victim = ctx.actor_index
	local data = ctx.data
	if (not ctx:IsAlive(victim)) then   -- Opfer ist waehrend der Auszaehlung gegangen
		ctx:Conclude(CFG.END_TIME)
		return
	end
	local values = { name = ctx:Name(victim), spare = data.spare, kill = data.kill }
	ctx:Stage(data.result, values)   -- "spare" / "kill" (nach Gleichstand: Ergebnis der Muenze)
	if (data.result == "kill") then
		ctx:Say(data.tie and Text.JACK.VOTE_COIN_KILL or Text.JACK.VOTE_KILL, values)
		ctx:Kill(victim, "vote")
	else
		ctx:Say(data.tie and Text.JACK.VOTE_COIN_SPARE or Text.JACK.VOTE_SPARE, values)
		ctx:Show("survive", { seat = victim, name = ctx:Name(victim) })
	end
	ctx:Conclude(CFG.END_TIME)
end

-- Auszaehlen und Ergebnis zeigen, nach RESULT_TIME vollstrecken
local function Resolve(ctx)
	local data = ctx.data
	if (data.result) then return end
	ctx:CloseAllAsks()

	if (data.kill > data.spare) then
		data.result = "kill"
	elseif (data.spare > data.kill) then
		data.result = "spare"
	else
		data.tie = true
		data.result = math.random() < 0.5 and "kill" or "spare"
	end

	local victim = ctx.actor_index
	ctx:Show("vote_result", { seat = victim, spare = data.spare, kill = data.kill, result = data.result, tie = data.tie or false })
	ctx:Stage(data.tie and "tie" or data.result, { spare = data.spare, kill = data.kill })
	if (data.tie) then
		ctx:Say(Text.JACK.VOTE_TIE, { spare = data.spare, kill = data.kill })
	end
	ctx.match:SetTimer(nil)
	ctx:Push()
	ctx:After(CFG.RESULT_TIME, function() Execute(ctx) end)
end

-- Alle Stimmen da (oder Zeit um): kurz Luft holen, dann auszaehlen
local function CheckDone(ctx)
	local data = ctx.data
	if (not data.open or data.result or data.closing) then return end   -- im Intro ist noch niemand gefragt
	for _, index in ipairs(data.voters) do
		if (ctx:IsAsking(index)) then return end
	end
	data.closing = true
	ctx:After(CFG.CLOSE_TIME, function() Resolve(ctx) end)
end

-- Live-Zaehlung gesammelt verschicken
local function PushSoon(ctx)
	local data = ctx.data
	if (data.push_pending) then return end
	data.push_pending = true
	ctx:After(PUSH_DELAY, function()
		data.push_pending = false
		ctx:Push()
	end)
end

-- Nach dem Intro: Abstimmung oeffnen (Waehler, die im Intro gegangen sind, hat OnSeatLeft schon gestrichen)
local function OpenVote(ctx)
	local data = ctx.data
	if (data.result) then return end   -- Opfer ist im Intro gegangen
	data.open = true
	local victim = ctx.actor_index
	if (#data.voters == 0) then   -- niemand da, der abstimmen kann: die Muenze entscheidet
		Resolve(ctx)
		return
	end

	ctx:Stage("voting")
	ctx:AskMany(data.voters, "vote", { "spare", "kill" }, CFG.TIME, function()
		CheckDone(ctx)
	end, function()
		return {
			target = victim,
			target_name = ctx:Name(victim),
			bot_delay = ctx:Between(CFG.BOT_DELAY),
			bot_pick = function() return math.random() < CFG.BOT_KILL and "kill" or "spare" end,
		}
	end)
end

function Vote.Start(ctx)
	local victim = ctx.actor_index
	local data = ctx.data
	data.spare, data.kill = 0, 0
	data.secret = CFG.SECRET
	data.voters = Voters(ctx)
	data.has_voted = {}   -- seat_index -> true, sobald die Stimme zaehlt
	data.focus = victim

	ctx:Say(Text.JACK.VOTE_START, { name = ctx:Name(victim) })
	ctx:Show("vote_start", { seat = victim, name = ctx:Name(victim), duration = CFG.TIME, secret = data.secret,
		intro = CFG.INTRO_TIME })
	ctx:Stage("ready", nil, data.voters, CFG.INTRO_TIME)   -- alle Waehler lesen "GET READY TO VOTE", dann oeffnet die Abstimmung
	ctx:Push()
	ctx:After(CFG.INTRO_TIME, function() OpenVote(ctx) end)
end

function Vote.OnInput(ctx, seat_index, choice)
	local data = ctx.data
	if (data.result) then return end
	data[choice] = data[choice] + 1   -- choice ist "spare" oder "kill" (gepruefte Option)
	data.has_voted[seat_index] = true
	PushSoon(ctx)
	CheckDone(ctx)
end

-- Opfer geht: es ist ohnehin raus. Waehler geht: seine Stimme zaehlt, wenn sie schon abgegeben war; sonst
-- zaehlt er nicht mehr zu den moeglichen Stimmen (die Anzeige "voted / voters" geht trotzdem auf).
function Vote.OnSeatLeft(ctx, index, was_alive)
	local data = ctx.data
	if (data.result) then return end
	if (index == ctx.actor_index and was_alive) then
		data.result = "fled"
		ctx:CloseAllAsks()
		ctx:Say(Text.JACK.VOTE_FLED, { name = ctx:Name(index) })
		ctx:Stage("fled")
		ctx:Conclude(CFG.END_TIME)
		return
	end
	if (not data.has_voted[index]) then
		for i = #data.voters, 1, -1 do
			if (data.voters[i] == index) then table.remove(data.voters, i) end
		end
		PushSoon(ctx)
	end
	CheckDone(ctx)
end

DeathBox.Events.Register(Vote)
