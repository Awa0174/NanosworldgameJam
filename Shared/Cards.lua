-- Shared/Cards.lua
-- Tarotkarten. Liegt in Shared, damit auch die Client-UI Name und Beschreibung kennt.
-- Die WIRKUNG einer Karte wird ausschliesslich auf dem Server ausgefuehrt.
--
-- type:
--   "auto"     greift von selbst, wenn die Bedingung eintritt
--   "playable" der Spieler entscheidet per Klick, wann (kommt an Tag 4)

DeathBox = DeathBox or {}

DeathBox.Cards = {
	ward = {
		name = "The Ward",
		type = "auto",
		description = "Prevents your death once.",
	},
	-- Geplant (Tag 4): mirror, moon, hermit
}

-- Prueft, ob es eine Karte mit dieser ID gibt
function DeathBox.IsValidCard(card_id)
	return DeathBox.Cards[card_id] ~= nil
end
