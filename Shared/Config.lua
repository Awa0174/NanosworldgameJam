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

	-- Arena: eigene Flaeche hoch ueber der Map, damit die Map selbst egal ist
	ARENA = {
		CENTER = Vector(0, 0, 20000),   -- Mittelpunkt der Bodenoberflaeche (Z = Hoehe in cm)
		FLOOR_SIZE = 2000,              -- Kantenlaenge des Bodens in cm (2000 = 20 m)
		FLOOR_THICKNESS = 20,
		WALL_HEIGHT = 400,              -- Waende als Absturzsicherung, 4 m hoch
		WALL_THICKNESS = 20,
		FLOOR_COLOR = Color(0.08, 0.08, 0.09),
		WALL_COLOR = Color(0.15, 0.12, 0.1),

		TABLE_MESH = "nanos-world::SM_WoodenTable",
		CHAIR_MESH = "nanos-world::SM_WoodenChair",
		CHAIR_RADIUS = 160,             -- Abstand Stuhl <-> Tischmitte in cm
		CHAIR_YAW_OFFSET = 0,           -- falls die Stuehle falsch herum stehen: 90, 180 oder 270 probieren
		PLAYER_RADIUS = 220,            -- wo Spieler waehrend der Partie stehen (hinter dem Stuhl)
	},

	-- Debug: Chat-Befehle /start, /bots, /status
	-- VOR DEM JAM AUF false STELLEN, sonst kann jeder Spieler Partien starten.
	DEBUG_COMMANDS = true,
	MAX_BOTS = 7,
}
