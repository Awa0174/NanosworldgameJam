-- Server/Cards.lua
-- Kartenhand der Spieler: geben, nehmen, verbrauchen, verfallen lassen, ausspielen.
-- Was die Karten koennen, steht in Shared/Cards.lua. Wo die automatischen Karten greifen:
--   skip      Server/Match.lua    (bei der Auswahl, vor dem POP)
--   ricochet  Server/Events.lua   (Context:Kill, mit Flugzeit in Context:Shoot)
--   safety    Server/Events.lua   (Context:Kill)
--
-- Eine Karte auf der Hand ist eine Instanz { uid, id, rounds_left? }:
--   uid          eindeutige Nummer. Der Client nennt beim Ausspielen nur die uid, nie den Typ.
--   id           Kartentyp aus Shared/Cards.lua
--   rounds_left  nur bei verfallenden Karten (Safety aus Guardian): Runden bis zum Verfall
--
-- Die Hand ist privat: Nur der Besitzer bekommt sie ("DeathBox:Hand", nach jeder Aenderung),
-- alle anderen sehen nur die Anzahl (State.seats[].cards). Den Zustand-Push machen die Aufrufer.
--
-- Ausspielen (Net: "DeathBox:PlayCard", uid, target_seat) wird streng geprueft:
--   Show laeuft, Spieler sitzt und lebt, besitzt die Karte, Karte ist ausspielbar, Ziel passt zur Zielregel,
--   hoechstens eine Karte pro Config.CARDS.PLAY_COOLDOWN Sekunden.
-- Bots spielen ihre Karten selbst, zu Beginn einer Runde (Hand.BotTurn), ueber denselben Weg.

DeathBox.Hand = {
	next_uid = 0,
	last_play = {},    -- Player-ID -> Zeitpunkt (ms) der letzten ausgespielten Karte
}

local Hand = DeathBox.Hand
local Config = DeathBox.Config
local Net = DeathBox.Net

-- Schickt dem Besitzer seine Hand (nur echte, verbundene Spieler)
function Hand.Sync(match, index)
	local seat = match.seats[index]
	if (not seat or not seat.player) then return end
	local cards = {}
	for _, card in ipairs(seat.cards) do
		table.insert(cards, { uid = card.uid, id = card.id, rounds_left = card.rounds_left })
	end
	Net.SendHand(seat.player, { cards = cards })
end

function Hand.HasRoom(match, index)
	local seat = match.seats[index]
	return seat ~= nil and seat.alive and #seat.cards < Config.CARDS.MAX_HAND
end

-- Legt eine fertige Instanz auf die Hand (z. B. gestohlene Karte). true, wenn Platz war.
local function Add(match, index, card)
	if (not Hand.HasRoom(match, index)) then return false end
	table.insert(match.seats[index].cards, card)
	Hand.Sync(match, index)
	return true
end

-- Gibt einem lebenden Platz eine neue Karte. Gibt die Instanz zurueck oder nil (Hand voll, Platz tot).
function Hand.Give(match, index, card_id, rounds_left)
	if (not DeathBox.IsValidCard(card_id)) then return nil end
	Hand.next_uid = Hand.next_uid + 1
	local card = { uid = Hand.next_uid, id = card_id, rounds_left = rounds_left }
	return Add(match, index, card) and card or nil
end

-- Gibt einem Platz eine zufaellige Karte (nach Gewicht). Instanz oder nil.
function Hand.GiveRandom(match, index)
	return Hand.Give(match, index, DeathBox.RandomCard())
end

-- Nimmt die Karte mit dieser uid von der Hand. Gibt die Instanz zurueck oder nil.
function Hand.Remove(match, index, uid)
	local seat = match.seats[index]
	if (not seat) then return nil end
	for i, card in ipairs(seat.cards) do
		if (card.uid == uid) then
			table.remove(seat.cards, i)
			Hand.Sync(match, index)
			return card
		end
	end
	return nil
end

-- Karte mit dieser uid auf der Hand (oder nil)
function Hand.Find(match, index, uid)
	local seat = match.seats[index]
	if (not seat) then return nil end
	for _, card in ipairs(seat.cards) do
		if (card.uid == uid) then return card end
	end
	return nil
end

function Hand.Has(match, index, card_id)
	local seat = match.seats[index]
	if (not seat) then return false end
	for _, card in ipairs(seat.cards) do
		if (card.id == card_id) then return true end
	end
	return false
end

-- Verbraucht eine Karte dieses Typs. Die zuerst verfallende zuerst (die dauerhafte ist mehr wert).
-- true, wenn eine da war.
function Hand.Consume(match, index, card_id)
	local seat = match.seats[index]
	if (not seat) then return false end
	local best
	for i, card in ipairs(seat.cards) do
		if (card.id == card_id) then
			local best_card = best and seat.cards[best]
			if (not best_card or (card.rounds_left and (not best_card.rounds_left or card.rounds_left < best_card.rounds_left))) then
				best = i
			end
		end
	end
	if (not best) then return false end
	table.remove(seat.cards, best)
	Hand.Sync(match, index)
	return true
end

-- Nimmt alle Karten eines Platzes (Split or Steal, Ausscheiden). Gibt die Liste der Instanzen zurueck.
function Hand.TakeAll(match, index)
	local seat = match.seats[index]
	if (not seat or #seat.cards == 0) then return {} end
	local cards = seat.cards
	seat.cards = {}
	Hand.Sync(match, index)
	return cards
end

-- Legt mehrere Instanzen auf die Hand, solange Platz ist. Gibt die Zahl der aufgenommenen zurueck.
function Hand.AddAll(match, index, cards)
	local added = 0
	for _, card in ipairs(cards) do
		if (not Add(match, index, card)) then break end
		added = added + 1
	end
	return added
end

-- Neue Runde: verfallende Karten zaehlen herunter, abgelaufene verschwinden.
function Hand.Tick(match)
	for index, seat in ipairs(match.seats) do
		local changed = false
		for i = #seat.cards, 1, -1 do
			local card = seat.cards[i]
			if (card.rounds_left) then
				card.rounds_left = card.rounds_left - 1
				changed = true
				if (card.rounds_left <= 0) then table.remove(seat.cards, i) end
			end
		end
		if (changed) then Hand.Sync(match, index) end
	end
end

-- Karten am Tisch verteilen: jeder Lebende bekommt count zufaellige Karten (Showbeginn)
function Hand.DealStart(match, count)
	for index in ipairs(match.seats) do
		for _ = 1, count do Hand.GiveRandom(match, index) end
	end
end

-- ===================================================================
-- Ausspielen
-- ===================================================================

-- Darf target fuer diese Karte gewaehlt werden? (Regeln aus Shared/Cards.lua)
function Hand.IsValidTarget(match, actor, def, target)
	local seat = match.seats[target]
	if (not seat or not seat.alive) then return false end
	if (def.target == "alive") then return true end
	if (def.target == "other_with_cards") then return target ~= actor and #seat.cards > 0 end
	return false
end

-- Wirkung der ausspielbaren Karten. Die gespielte Karte ist schon von der Hand genommen.
-- Gibt false zurueck, wenn die Wirkung nicht moeglich war (dann bekommt der Spieler die Karte zurueck).
local EFFECTS = {
	-- Ziel bekommt eine Safety, die nach GUARDIAN_ROUNDS Runden verfaellt
	guardian = function(match, actor, target)
		return Hand.Give(match, target, "safety", Config.CARDS.GUARDIAN_ROUNDS) ~= nil
	end,
	-- Eine zufaellige Karte des Ziels wandert zum Dieb (behaelt uid und Restlaufzeit)
	thief = function(match, actor, target)
		local cards = match.seats[target].cards
		if (#cards == 0 or not Hand.HasRoom(match, actor)) then return false end
		local card = Hand.Remove(match, target, cards[math.random(#cards)].uid)
		return Add(match, actor, card)
	end,
}

-- Darf index diese (ausspielbare) Karte auf target spielen? Zielregel und Platz auf der Hand.
local function CanTarget(match, index, card, target)
	local def = DeathBox.Cards[card.id]
	if (not def or def.type ~= "playable" or not EFFECTS[card.id]) then return false end
	if (not Hand.IsValidTarget(match, index, def, target)) then return false end
	-- Guardian braucht Platz auf der Hand des Ziels (die eigene wird durch das Ausspielen frei)
	if (card.id == "guardian" and target ~= index and not Hand.HasRoom(match, target)) then return false end
	return true
end

-- Spielt eine gepruefte Karte aus. Gibt true zurueck, wenn sie gewirkt hat.
local function Use(match, index, card, target)
	Hand.Remove(match, index, card.uid)
	if (not EFFECTS[card.id](match, index, target)) then
		Add(match, index, card)   -- Wirkung nicht moeglich: Karte zurueck, nichts passiert
		return false
	end
	match:Show("card_play", { seat = index, card = card.id, target = target })
	match:PushState()
	return true
end

-- Gepruefte Anfrage eines Spielers. Gibt true zurueck, wenn die Karte gespielt wurde.
function Hand.Play(player, uid, target)
	local match = DeathBox.Lobby.GetMatchOf(player)
	if (not match or match.state ~= DeathBox.Match.STATE.PLAYING) then return false end
	local seat, index = match:FindSeatByPlayer(player)
	if (not seat or not seat.alive) then return false end

	local now = Net.Now()
	local id = player:GetID()
	local last = Hand.last_play[id]
	if (last and now - last < Config.CARDS.PLAY_COOLDOWN * 1000) then return false end

	local card = Hand.Find(match, index, uid)
	if (not card or not CanTarget(match, index, card, target)) then return false end
	if (not Use(match, index, card, target)) then return false end
	Hand.last_play[id] = now
	return true
end

-- Neue Runde: Mit Config.CARDS.BOT_PLAY spielt EIN Bot eine seiner ausspielbaren Karten (nie mehrere auf einmal,
-- damit der Beginn der Runde ruhig bleibt). Guardian bevorzugt auf sich selbst, solange er keine Safety hat,
-- sonst auf einen zufaelligen Lebenden; Thief auf einen zufaelligen anderen Lebenden mit Karten.
function Hand.BotTurn(match)
	local plays = {}
	for index, seat in ipairs(match.seats) do
		if (seat.alive and seat.is_bot) then
			for _, card in ipairs(seat.cards) do
				if (EFFECTS[card.id]) then table.insert(plays, { index = index, card = card }) end
			end
		end
	end
	if (#plays == 0 or math.random() >= Config.CARDS.BOT_PLAY) then return end

	local play = plays[math.random(#plays)]
	local index, card = play.index, play.card
	local target
	if (card.id == "guardian" and not Hand.Has(match, index, "safety")) then
		target = index
	else
		local targets = {}
		for other in ipairs(match.seats) do
			if (CanTarget(match, index, card, other)) then table.insert(targets, other) end
		end
		if (#targets > 0) then target = targets[math.random(#targets)] end
	end
	if (target) then Use(match, index, card, target) end
end

Player.Subscribe("Destroy", function(player)
	Hand.last_play[player:GetID()] = nil
end)
