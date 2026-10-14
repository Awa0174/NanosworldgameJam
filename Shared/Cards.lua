-- Shared/Cards.lua
-- Karten: Name, Beschreibung, Typ, Zielregel, Bild, Haeufigkeit. Liegt in Shared, damit HUD und Server
-- dieselben Daten haben. Die WIRKUNG einer Karte wird ausschliesslich auf dem Server ausgefuehrt:
--   Server/Cards.lua    Hand (geben, nehmen, verfallen), Ausspielen (guardian, thief)
--   Server/Match.lua    skip (bei der Auswahl, vor dem POP)
--   Server/Events.lua   ricochet und safety (beim Treffer)
--
-- Felder:
--   name, description   Text fuer das HUD (Englisch)
--   type                "auto"      greift von selbst, wenn die Bedingung eintritt
--                       "playable"  der Spieler spielt sie per Klick aus (DeathBox:PlayCard)
--   target              nur bei "playable": wen man waehlen darf
--                         "alive"             einen lebenden Spieler, auch sich selbst
--                         "other_with_cards"  einen anderen lebenden Spieler mit mindestens einer Karte
--   events              nur bei "auto": in welchen Events die Karte greift. Ausserhalb davon wirkt sie nie.
--   art                 Bild im HUD: Client/UI/img/cards/<art>.png (gleich der id)
--   weight              Haeufigkeit beim zufaelligen Ziehen (Startkarte, Deal, Split or Steal, Choose a Card)
--
-- Reihenfolge, wenn mehrere greifen: skip (bei der Auswahl) -> ricochet -> safety (beim Treffer).

DeathBox = DeathBox or {}

DeathBox.Cards = {
	safety = {
		name = "Safety",
		description = "Survive one gunshot. Breaks after use.",
		type = "auto",
		events = { revolver = true, angry = true, gallery = true, duel = true },
		art = "safety",
		weight = 2.5,
	},
	skip = {
		name = "Skip",
		description = "When Jack picks you for a deadly game, someone else takes your place.",
		type = "auto",
		-- nur Events, in denen der Gewaehlte selbst in Gefahr ist (beim Revolver und beim Messer
		-- an den Nachbarn ist der Gewaehlte zuerst der Taeter, nicht das Opfer)
		events = { angry = true, gallery = true, knife = true, fire = true, vote = true, pumpkin = true, bomb = true, duel = true },
		art = "skip",
		weight = 2,
	},
	ricochet = {
		name = "Ricochet",
		description = "A bullet meant for you bounces off and hits a random other player.",
		type = "auto",
		events = { revolver = true, angry = true, gallery = true, duel = true },
		art = "ricochet",
		weight = 2,
	},
	guardian = {
		name = "Guardian",
		description = "Give a living player (or yourself) a Safety that breaks after 3 rounds.",
		type = "playable",
		target = "alive",
		art = "guardian",
		weight = 1.5,
	},
	thief = {
		name = "Thief",
		description = "Steal a random card from another player.",
		type = "playable",
		target = "other_with_cards",
		art = "thief",
		weight = 2,
	},
}

-- Feste Reihenfolge (HUD-Sortierung und reproduzierbares Ziehen)
DeathBox.CARD_IDS = { "safety", "skip", "ricochet", "guardian", "thief" }

function DeathBox.IsValidCard(card_id)
	return type(card_id) == "string" and DeathBox.Cards[card_id] ~= nil
end

-- Wirkt die (automatische) Karte im angegebenen Event?
function DeathBox.CardWorksIn(card_id, event_id)
	local card = DeathBox.Cards[card_id]
	return card ~= nil and card.events ~= nil and card.events[event_id] == true
end

-- Zufaellige Karte nach Gewicht. exclude = { [card_id] = true } wird uebersprungen (z. B. fuer 3 verschiedene).
function DeathBox.RandomCard(exclude)
	local total = 0
	for _, id in ipairs(DeathBox.CARD_IDS) do
		if (not (exclude and exclude[id])) then total = total + DeathBox.Cards[id].weight end
	end
	if (total <= 0) then return nil end

	local roll = math.random() * total
	local last
	for _, id in ipairs(DeathBox.CARD_IDS) do
		if (not (exclude and exclude[id])) then
			roll = roll - DeathBox.Cards[id].weight
			last = id
			if (roll <= 0) then return id end
		end
	end
	return last
end
