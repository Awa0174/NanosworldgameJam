-- Shared/Config.lua
-- Alle Einstellungen an einer Stelle. Zum Balancing nur hier etwas aendern.

DeathBox = DeathBox or {}

DeathBox.Config = {
	-- Spieler
	MIN_PLAYERS = 2,            -- ab so vielen Spielern startet automatisch eine Partie
	MAX_PLAYERS = 8,            -- Plaetze am Tisch, weitere Spieler schauen zu

	-- Zeiten in Sekunden. Leitlinie: kurz und knackig, kein Leerlauf.
	START_COUNTDOWN = 8,        -- Countdown bis zum Partiestart
	BETWEEN_TURNS = 1.5,        -- Pause zwischen zwei Ritualen
	ANNOUNCE_TIME = 1.5,        -- Madame verkuendet, wer gewaehlt ist, bevor es losgeht
	GAME_END_DELAY = 8,         -- Pause nach dem Sieg bis zur Rueckkehr in die Lobby
	BOT_THINK_TIME = 1.5,       -- so lange "ueberlegt" ein Test-Bot, bevor er waehlt

	-- Ritual: The Chamber (Revolver mit gemeinsamer Trommel)
	CHAMBER = {
		CHAMBERS = 6,           -- Kammern in der Trommel, eine davon geladen
		CHOOSE_TIME = 8,        -- so lange darf der Schuetze sein Ziel waehlen
		AIM_TIME = 1.5,         -- Spannungspause zwischen Zielen und Abdruecken
		RESULT_TIME = 2,        -- Pause nach Klick/Schuss
	},

	-- Karten
	START_CARDS = { "ward" },   -- Karten, mit denen jeder Spieler in die Partie startet
	MAX_HAND = 3,               -- maximal so viele Karten auf der Hand

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
		TABLE_SCALE = Vector(2, 2, 1),  -- Tisch breiter machen (X/Y), Hoehe (Z) bleibt
		CHAIR_MESH = "nanos-world::SM_WoodenChair",
		CHAIR_RADIUS = 240,             -- Abstand Stuhl <-> Tischmitte in cm (mit dem Tisch mitwachsen lassen)
		CHAIR_YAW_OFFSET = 270,         -- Drehung des Stuhl-Modells, damit die Sitzflaeche zum Tisch zeigt (im Spiel getestet)

		-- Sitzen: Position der Figur relativ zum Stuhl. Im Spiel mit /sitpos <hoehe> <vor> feinjustieren.
		SIT_ANIMATION = "nanos-world::A_Mannequin_Sit_Bench",
		SIT_HEIGHT = 90,                -- cm ueber dem Boden (Mittelpunkt der Figur)
		SIT_FORWARD = 0,                -- cm Richtung Tisch (negativ = nach hinten)
	},

	-- Debug: Chat-Befehle /start, /bots, /status, /ritual, Cheats
	-- VOR DEM JAM AUF false STELLEN, sonst kann jeder Spieler Partien starten.
	DEBUG_COMMANDS = true,
	MAX_BOTS = 7,
}
