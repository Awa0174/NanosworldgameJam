-- Shared/Config.lua
-- Alle Einstellungen an einer Stelle. Zum Balancing nur hier etwas aendern.

DeathBox = DeathBox or {}

DeathBox.Config = {
	-- Spieler
	MIN_PLAYERS = 2,            -- ab so vielen Spielern startet automatisch eine Partie
	MAX_PLAYERS = 8,            -- Plaetze am Tisch, weitere Spieler schauen zu

	-- Zeiten in Sekunden
	START_COUNTDOWN = 10,       -- Countdown bis zum Partiestart
	TURN_SUSPENSE = 3,          -- Spannungspause: Spieler hat die Pistole, bevor abgedrueckt wird
	BETWEEN_TURNS = 2,          -- Pause nach dem Abdruecken, bevor der naechste dran ist
	GAME_END_DELAY = 10,        -- Pause nach dem Sieg bis zur Rueckkehr in die Lobby

	-- Pistole
	SHOT_CHANCE = 1 / 6,        -- Wahrscheinlichkeit, dass die Pistole zuendet (1/6 = ~17 %)

	-- Karten
	START_CARDS = { "shield" }, -- Karten, mit denen jeder Spieler in die Partie startet

	-- Debug: Chat-Befehle /start, /bots, /status
	-- VOR DEM JAM AUF false STELLEN, sonst kann jeder Spieler Partien starten.
	DEBUG_COMMANDS = true,
	MAX_BOTS = 7,
}
