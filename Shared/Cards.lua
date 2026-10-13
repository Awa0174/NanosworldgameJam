-- Shared/Cards.lua
-- Kartendefinitionen. Liegt in Shared, damit spaeter auch die Client-UI Name und Beschreibung kennt.
-- Die WIRKUNG einer Karte wird ausschliesslich auf dem Server ausgefuehrt.

DeathBox = DeathBox or {}

DeathBox.Cards = {
	shield = {
		name = "[KARTENNAME]",
		description = "[BESCHREIBUNG] Rettet dich einmal vor einem Schuss. Wird automatisch verbraucht.",
		-- Wann die Karte greift. MVP: nur "before_death" (kurz bevor ein Spieler ausscheiden wuerde).
		trigger = "before_death",
	},
}

-- Prueft, ob es eine Karte mit dieser ID gibt
function DeathBox.IsValidCard(card_id)
	return DeathBox.Cards[card_id] ~= nil
end
