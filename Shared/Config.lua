-- Shared/Config.lua
-- Alle Einstellungen an einer Stelle. Zum Balancing nur hier etwas aendern.

DeathBox = DeathBox or {}

DeathBox.Config = {
	-- ===============================================================
	-- Server und Instanzen
	-- ===============================================================
	-- Jeder Tisch (Match) und jeder Hub-Bereich laeuft in einer eigenen nanos-"Dimension".
	-- Spieler sehen nur die Figuren und Objekte ihrer Dimension. So laufen beliebig viele
	-- identische Raeume an derselben Stelle der Welt, ohne sich gegenseitig zu stoeren.
	HUB_CAPACITY = 64,          -- Spieler pro Hub-Bereich (danach wird ein weiterer identischer Hub geoeffnet)
	MAX_MATCHES = 64,           -- so viele Tische duerfen gleichzeitig laufen (64 x 16 = 1024 Plaetze)
	DIMENSION_HUB_FIRST = 2,    -- Dimensionen ab hier fuer Hubs (1 = Standard von nanos, bleibt leer)
	DIMENSION_MATCH_FIRST = 1000, -- Dimensionen ab hier fuer Tische

	-- ===============================================================
	-- Matchmaking
	-- ===============================================================
	MIN_PLAYERS = 2,            -- ab so vielen wartenden Spielern wird ein Tisch eroeffnet
	TABLE_SEATS = 16,           -- Plaetze pro Tisch (16 = wie im Original, maximal 32)
	QUEUE_COUNTDOWN = 15,       -- Countdown, bis ein neuer Tisch startet
	QUEUE_COUNTDOWN_FULL = 5,   -- ... verkuerzt, sobald genug Spieler fuer einen vollen Tisch warten
	GAME_END_DELAY = 10,        -- Pause nach dem Sieg bis zur Rueckkehr in den Hub
	DEAD_RESPAWN_DELAY = 3,     -- so lange liegt ein Ausgeschiedener, bevor er als Zuschauer aufsteht
	CHAT_INTERVAL = 0.75,       -- Chat: hoechstens eine Zeile pro Spieler in dieser Zeit (Flutschutz)
	CHAT_MAX_LENGTH = 200,      -- Chat: laengere Zeilen werden gekuerzt

	-- ===============================================================
	-- Ablauf einer Runde (Sekunden). Leitlinie (Spielertest v0.8: "VIEL zu schnell, man weiss nie, was dran ist"):
	-- LESBARKEIT vor Tempo. Jeder sieht jederzeit Phase, Beteiligte, eigene Aufgabe und Restzeit (docs/PROTOCOL.md, "Klarheit").
	-- Die Auswahl ist auf die Spieluhr abgestimmt (je Spin eine zufaellige Melodie aus SPIN_TUNES, jede genau SPIN_TIME lang):
	--    0.0 s  Melodie startet, Jack lugt aus der Kiste und dreht sich langsam (1-2 Umdrehungen), Suchscheinwerfer
	--   10.0 s  Melodie endet mit Ritardando, Jack steht still vor dem Opfer: Stille + Herzschlag (HOLD_TIME)
	--   12.0 s  "POP!" – Jack schnellt bis vor das Gesicht des Opfers, Name gross im Bild (REVEAL_TIME)
	-- SPIN_TIME nur zusammen mit der Musik aendern (scratchpad audio/synth.py). Es gibt bewusst KEINEN schnellen Spin mehr.
	-- Dauert eine 16er-Partie im Median laenger als ca. 18 min: toedlicher machen (EVENT_WEIGHTS), NIE die Show kuerzen.
	-- ===============================================================
	INTRO_TIME = 12,            -- Showbeginn: Spieluhr, Jack springt aus der Box, Begruessung, "How to play" im HUD
	INTRO_POP_AT = 10.0,        -- ... POP im Intro (Ende der Intro-Melodie, "Pop! goes the weasel")
	INTRO_MUSIC = "spin_weasel",
	SPIN_TIME = 10.0,           -- Jack dreht sich (Melodie mit Ritardando, endet auf dem Stopp)
	HOLD_TIME = 2.0,            -- Stille + Herzschlag, Licht auf dem Opfer, dann POP
	SPIN_TURNS = 1,             -- volle Umdrehungen vor dem Rest bis zum Opfer: Weg = 1-2 Umdrehungen ab Jacks Blickrichtung
	SPIN_TUNES = { "spin_rosie", "spin_weasel", "spin_bridge", "spin_lullaby" },   -- zufaellig je Spin, nie zweimal dieselbe
	SPIN_MUSIC = "spin_weasel", -- Ersatz, falls ein Cue keine Melodie nennt
	REVEAL_TIME = 3.0,          -- POP: Jack vor dem Gesicht des Opfers, Name gross im Bild
	CARD_TIME = 5.0,            -- Event-Karte (Name, wer, so geht's, YOU: ...), beim ersten Mal pro Show
	CARD_TIME_REPEAT = 3.5,     -- ... wenn das Event in dieser Show schon dran war
	RESULT_PAUSE = 4.0,         -- Rundenergebnis ("ROUND 7 - Bonzo is OUT - 12 left"), durchatmen
	BOT_THINK_TIME = 2.0,       -- so lange "ueberlegt" ein Bot
	SKIP_TIME = 3.0,            -- Karte Skip: Jack dreht weiter zum naechsten Opfer, danach erst der POP
	RICOCHET_TIME = 1.2,        -- Karte Ricochet: Flugzeit der abgelenkten Kugel bis zum neuen Opfer

	-- ===============================================================
	-- Haeufigkeit der Events je nach Zahl der Lebenden (Server/Events.lua, EventSystem.Pick).
	-- Vier Phasen: riesig (>= HUGE Lebende, nur an Tischen mit mehr als 16 Plaetzen), viele (>= MANY),
	-- mittel (>= MID), wenige (Rest). 0 = kommt in der Phase nicht vor.
	-- Leitlinie: Solange viele leben, ist Jack toedlicher (Tempo). Im Finale mehr Duelle und Nerven.
	-- Atempausen (deal, splitsteal, choosecard) kommen regelmaessig, aber selten genug, um nicht zu bremsen.
	-- Grosse Tische: Die Spannung jeder Runde (Spieluhr 10 s, Stille 2 s, POP 3 s, Karte 3,5-5 s, Rundenergebnis 4 s) kostet
	-- seit v0.10 ca. 23 s. Damit 32 Plaetze nicht doppelt so lange dauern wie 16, raeumt die Schiessbude (gallery, drei Ziele)
	-- auf, solange 17+ leben; Atempausen sind dort seltener. Die Spalte "riesig" gibt es nur an Tischen mit mehr als 16 Plaetzen.
	-- Tempo-Simulation v0.10 (scratchpad sim/run.lua pace, 40-80 Partien): 16 Spieler Median ca. 16-17 min (mit Bedenkzeit
	-- ca. 15 min), 32 Spieler ca. 25-26 min. Grenze laut Vorgabe: 16er-Median ueber ca. 18 min -> toedlicher machen.
	-- ===============================================================
	EVENT_PHASES = { HUGE = 17, MANY = 9, MID = 5 },
	EVENT_WEIGHTS = {
		--             riesig  viele  mittel  wenige
		revolver   = { 2,      2.5,   3,      3 },
		angry      = { 4,      4,     1.5,    0.5 },   -- braucht 3 Lebende
		gallery    = { 7,      0,     0,      0 },     -- nur an grossen Tischen (drei Ziele pro Runde)
		knife      = { 3,      3,     3,      3 },
		fire       = { 2,      2,     2,      2 },
		stab       = { 0.6,    1.2,   2,      2 },
		vote       = { 2.5,    2.5,   2,      1 },
		pumpkin    = { 2,      2.5,   2,      1.5 },
		bomb       = { 0.7,    1.2,   2,      1 },
		duel       = { 2,      2,     1,      1 },     -- braucht 3 Lebende (beide Duellanten koennen sterben)
		deal       = { 0.4,    0.6,   0.8,    0.3 },
		splitsteal = { 0.5,    0.8,   1,      0.5 },
		choosecard = { 0.4,    0.6,   0.8,    0.5 },
	},

	-- Abfrage-Arten, die das HUD (Client/UI/hud.js) schon anzeigen kann (docs/PROTOCOL.md, "Abfragen").
	-- Ein Event, das eine andere Art braucht (def.kinds in Server/Events/*.lua), wird nicht ausgewuerfelt:
	-- Wer eine Frage nicht sieht, darf an ihr nicht sterben. /event erzwingt es trotzdem (zum Testen der Panels).
	-- Sobald das HUD ein Panel hat, die Art hier eintragen. Seit HUD v0.9 alle: vote (Spare or Eliminate),
	-- pass (Kuerbis), splitsteal (Split or Steal), pickcard (Choose a Card), wire (Bombe).
	HUD_CHOICE_KINDS = {
		target = true, qte = true, click = true,
		vote = true, pass = true, splitsteal = true, pickcard = true, wire = true,
	},

	-- ===============================================================
	-- Events
	-- ===============================================================
	-- Revolver: sechs Kammern, eine Kugel. Wer angeklickt wird (Fehlschuss), bekommt den Revolver und schiesst als
	-- Naechster. Mit LOAD_EXTRA laedt Jack nach jedem Klick nach (1/6, 2/6, 3/6 ...), sonst klassisch (1/6, 1/5, 1/4 ...).
	-- Der Knall beendet das Event.
	REVOLVER = {
		CHAMBERS = 6,
		-- true: Nach jedem Klick laedt Jack eine Kugel nach und dreht die Trommel. Chance pro Abzug 1/6, 2/6, 3/6 ... 6/6.
		-- false: klassisch, die eine Kugel bleibt, wo sie ist. Chance pro Abzug 1/6, 1/5, 1/4 ... (kumuliert 1/6, 2/6, 3/6).
		LOAD_EXTRA = true,
		GIVE_TIME = 2.5,        -- Jack wirft dem Halter den Revolver in die Hand ("GET READY"), dann erst die Zielwahl
		CHOOSE_TIME = 12,       -- so lange darf der Halter zielen (Maus) und abdruecken (sonst zielt Jack auf den Halter)
		AIM_TIME = 2.5,         -- Spannungspause zwischen Zielen und Abdruecken
		PASS_TIME = 3.0,        -- nach einem Klick: Revolver fliegt weiter, dann darf der naechste Halter zielen
		PASS_DELAY = 0.8,       -- ... davon haelt der alte Halter ihn noch so lange (Klick wirken lassen), dann fliegt er
		                        -- (revolver_pass): der neue Halter hat ihn PASS_TIME - PASS_DELAY vor der Zielwahl in der Hand
		RESULT_TIME = 3.5,      -- Pause nach dem Knall
		AIM_INTERVAL = 0.2,     -- Zielanzeige ("revolver_aiming") hoechstens 5x pro Sekunde an den Tisch
		AIM_RATE = 6,           -- DeathBox:Aim: hoechstens so viele Nachrichten pro Sekunde und Spieler (Rest verworfen)
		BOT_AIM = { 2.5, 4.5 }, -- Bots schwenken so lange ueber 2-3 Ziele, bevor sie abdruecken
	},

	-- Knife Toss: Jack wirft ein Messer. Tastenfolge (WASD) richtig druecken = ausgewichen.
	KNIFE = {
		INTRO_TIME = 2.6,       -- Jack holt aus, der Gewaehlte liest "GET READY" (mind. 2,5 s vor der ersten Taste)
		WINDOWS = { 1.6, 1.25, 1.0 },  -- Zeitfenster pro Taste (Anzahl = Laenge der Folge)
		RESULT_TIME = 3,
		BOT_SUCCESS = 0.55,     -- Chance, dass ein Bot die ganze Folge schafft
	},

	-- Fire Breath: Jack zuendet den Spieler an. Springende Flamme X-mal anklicken.
	FIRE = {
		INTRO_TIME = 2.6,
		CLICKS = 10,
		TIME = 6.25,            -- Gesamtzeit fuer alle Klicks
		RESULT_TIME = 3,
		BOT_SUCCESS = 0.45,
	},

	-- Stab Your Neighbour: Messer an den linken oder rechten Nachbarn. Das Opfer darf blocken.
	STAB = {
		INTRO_TIME = 2.5,       -- Jack gibt dem Gewaehlten das Messer ("GET READY"), dann erst die Wahl
		CHOOSE_TIME = 8,
		AIM_TIME = 2.5,         -- Hackbeil schwebt ueber dem Opfer: "GET READY TO BLOCK", dann die Block-Taste
		BLOCK_WINDOW = 1.15,    -- Zeit fuer die Block-Taste
		RESULT_TIME = 3,
		BOT_BLOCK = 0.35,       -- Chance, dass ein Bot blockt
	},

	-- Angry Clown: Jack verliert die Geduld und schiesst selbst. Nur Safety (und Ricochet) helfen.
	-- Kommt haeufiger, solange viele leben (haelt die Show bei 16-32 Spielern im Tempo).
	ANGRY = {
		AIM_TIME = 3.0,         -- Jack zielt (Trommelwirbel), Spannung
		RESULT_TIME = 3,
	},

	-- Shooting Gallery (nur an grossen Tischen): Jack schiesst nacheinander auf den Gewaehlten und seine beiden
	-- lebenden Nachbarn, wie auf die Enten einer Schiessbude. Nur Safety und Ricochet helfen.
	GALLERY = {
		FIRST_AIM = 2.6,        -- Jack legt an (Trommelwirbel)
		AIM_TIME = 1.6,         -- jedes weitere Ziel
		GAP = 0.9,              -- nach einem Schuss, bevor Jack zum naechsten Ziel schwenkt
		RESULT_TIME = 3,
	},

	-- Spare or Eliminate: alle am Tisch (auch Ausgeschiedene) stimmen ueber den Gewaehlten ab. Keine Karte rettet.
	VOTE = {
		INTRO_TIME = 2.5,       -- Licht auf das Opfer, "GET READY TO VOTE", dann oeffnet die Abstimmung
		TIME = 15,              -- Abstimmungszeit (endet frueher, sobald alle abgestimmt haben)
		CLOSE_TIME = 1.5,       -- alle haben gewaehlt: kurz Luft holen bis zur Auszaehlung
		RESULT_TIME = 3.5,      -- Ergebnis zeigen, dann das Urteil
		END_TIME = 1.8,         -- nach dem Urteil, bevor die Runde endet
		SECRET = false,         -- true = Zaehlung erst im Ergebnis sichtbar
		BOT_KILL = 0.6,         -- so oft stimmen Bots fuer ELIMINATE
		BOT_DELAY = { 1.5, 9.0 },   -- Bots stimmen verteilt ab, damit die Zaehlung lebt
	},

	-- Pass the Pumpkin: heisse Kartoffel. Der Halter wirft den Kuerbis an den linken oder rechten Nachbarn,
	-- bis die geheime Zuendschnur abgebrannt ist. Wer ihn dann haelt, fliegt in die Luft. Keine Karte rettet.
	PUMPKIN = {
		THROW_TIME = 2.6,       -- Jack zuendet und wirft den Kuerbis zum ersten Halter ("CATCH! GET READY")
		FUSE = { 8, 15 },       -- Zuendschnur in Sekunden ab der Landung (geheim, zufaellig)
		PASS_TIME = 3,          -- Zeit pro Wurf-Abfrage (laeuft sie ab, kommt eine neue, solange die Schnur brennt)
		CATCH_TIME = 0.6,       -- Flugzeit: so lange kann der Faenger noch nicht weiterwerfen
		BOT_DELAY = { 0.8, 2.4 },   -- Bots werfen nach so vielen Sekunden weiter
		RESULT_TIME = 3.3,
	},

	-- Defuse or Die: Bombe vor den Fuessen, drei Draehte mit Nummern und eine Regel aus Jacks Handbuch.
	-- Richtiger Draht = entschaerft, falscher oder zu langsam = BOOM. Keine Karte rettet.
	BOMB = {
		INTRO_TIME = 2.6,       -- Bombe wird abgestellt, Zuender piept ("GET READY")
		TIME = 12.5,            -- Zeit zum Lesen und Schneiden
		RESULT_TIME = 3.3,
		BOT_SUCCESS = 0.65,     -- so oft kappt ein Bot den richtigen Draht
		BOT_DELAY = { 3.0, 7.0 },   -- Bots "lesen" so lange im Handbuch
	},

	-- Quick Draw: Duell zweier Spieler. Wer nach "DRAW!" zuerst die richtige Taste drueckt, gewinnt.
	-- Safety und Ricochet gelten wie bei jedem Schuss.
	DUEL = {
		WAIT = { 3.0, 6.0 },    -- zufaellige Wartezeit bis "DRAW!" ("WAIT FOR IT", mind. 2,5 s lesbar)
		WINDOW = 2.0,           -- Zeit fuer die Taste nach "DRAW!" (drueckt keiner, schiesst Jack auf beide)
		RESULT_TIME = 3.6,
		BOT_REACTION = { 0.4, 1.5 },
		BOT_ACCURACY = 0.85,    -- so oft trifft ein Bot die richtige Taste
	},

	-- Split or Steal: zwei Spieler waehlen geheim. Beide Split: je eine Karte. Einer Steal: er bekommt alle Karten
	-- des anderen plus eine. Beide Steal: nichts. Niemand stirbt (Atempause).
	SPLITSTEAL = {
		INTRO_TIME = 2.6,       -- Jack zeigt auf den zweiten Spieler
		TIME = 15,              -- Rede- und Bedenkzeit (Zeitlimit = Split)
		REVEAL_TIME = 2.2,      -- Trommelwirbel vor dem Aufdecken
		RESULT_TIME = 4.5,
		BOT_STEAL = 0.4,        -- so oft waehlen Bots Steal
		BOT_DELAY = { 2.5, 10.0 },  -- Bots "ueberlegen" verschieden lange
	},

	-- Deal: Jack verteilt Karten an einen Teil der Lebenden (der Gewaehlte ist immer dabei). Niemand stirbt.
	DEAL = {
		SHARE = 3,              -- jeder SHARE-te Lebende bekommt eine Karte (aufgerundet)
		TIME = 4.8,             -- Karten fliegen, Ansage
	},

	-- Choose a Card: der Gewaehlte nimmt eine von mehreren Karten. Niemand stirbt.
	CHOOSECARD = {
		OPTIONS = 3,
		TIME = 12,              -- Zeitlimit = Jack zieht zufaellig
		RESULT_TIME = 2.7,
	},

	QTE_KEYS = { "W", "A", "S", "D" },

	-- ===============================================================
	-- Karten (Shared/Cards.lua: was sie tun, Server/Cards.lua: Hand und Ausspielen)
	-- ===============================================================
	CARDS = {
		START = 1,              -- so viele zufaellige Karten bekommt jeder zum Start
		MAX_HAND = 5,           -- volle Hand: weitere Karten verfallen
		GUARDIAN_ROUNDS = 3,    -- so viele Runden haelt die Safety aus einer Guardian-Karte
		PLAY_COOLDOWN = 2,      -- Sekunden zwischen zwei ausgespielten Karten (pro Spieler)
		BOT_PLAY = 0.35,        -- Chance pro Runde, dass ein Bot eine Guardian- oder Thief-Karte ausspielt
	},

	-- ===============================================================
	-- Welt (Hub und Show-Raum). Koordinaten in cm, X = vorne, Y = rechts, Z = oben.
	-- Beide liegen hoch ueber der Map, damit die geladene Map egal ist.
	-- Wenn spaeter eine Custom Map die Raeume enthaelt: BUILD_GEOMETRY = false
	-- und die Mittelpunkte auf die Positionen in der Map setzen.
	-- ===============================================================
	-- Die Welt wird KOMPLETT auf dem Client gebaut (Client/World/*.lua): jeder Spieler baut nur den Ort,
	-- an dem er gerade ist. Der Server kennt nur diese Koordinaten (fuer Sitz- und Spawnpunkte).
	-- Hoch ueber dem Boden, damit es mit JEDER Map funktioniert (Pterodactyl startet z. B. default-testing-map,
	-- deren Strand auf Hoehe 0 liegt -> Boden-Flackern). Am besten trotzdem default-empty-map starten.
	-- Wer herunterfaellt, wird zurueckgeholt (Server/Rescue.lua).
	WORLD = {
		HUB_CENTER = Vector(0, 0, 20000),
		HUB_SIZE = 4400,            -- Kantenlaenge des Friedhofs in cm
		HUB_WALL_HEIGHT = 420,      -- Friedhofsmauer (offen nach oben: Nachthimmel)
		CRYPT_SIZE = 900,           -- Spawn-Gruft vor dem Friedhof

		SHOW_CENTER = Vector(0, 30000, 20000),
		SHOW_RADIUS = 1300,         -- Radius des runden Zirkuszelts
		SHOW_WALL_HEIGHT = 1000,
		SHOW_WALL_SEGMENTS = 28,

		RESCUE_DEPTH = 700,         -- so tief unter dem Boden wird man zurueckgeholt

		-- Stuhlkreis: der Radius waechst mit der Zahl der Plaetze (ca. 1 m Platz pro Stuhl)
		CHAIR_SPACING = 105,
		CHAIR_MIN_RADIUS = 330,
		CHAIR_YAW_OFFSET = 270,     -- Drehung des Stuhl-Modells, damit die Sitzflaeche zur Mitte zeigt

		-- Sitzen: Position der Figur relativ zum Stuhl. Im Spiel mit /sitpos <hoehe> <vor> [drehung] feinjustieren.
		-- Werte aus dem Ingame-Test von v0.5.3: 90 war zu tief, 0 war zu weit hinten.
		SIT_HEIGHT = 100,
		SIT_FORWARD = 15,
		SIT_YAW_OFFSET = 0,
		SIT_CAMERA_PITCH = 12,      -- Kamera beim Hinsetzen leicht nach oben, damit Jacks Gesicht im Bild ist

		-- Kopfhoehe einer sitzenden Figur ueber der Sitzposition (Ziel fuer Jacks POP, Messer, Revolver, Karten ...).
		-- Geschaetzt (Sitz-Animation: Augen ca. 30 cm ueber der Kapselmitte). Im Spiel mit "db_head <cm>" (Konsole) pruefen.
		HEAD_HEIGHT = 45,
	},

	-- ===============================================================
	-- Debug: Chat-Befehle /start, /bots, /status, /event, Cheats
	-- VOR DEM JAM AUF false STELLEN, sonst kann jeder Spieler Tische starten.
	-- ===============================================================
	DEBUG_COMMANDS = true,
}

-- Sicherheitsnetz: Plaetze im erlaubten Bereich halten
DeathBox.Config.TABLE_SEATS = math.max(2, math.min(32, DeathBox.Config.TABLE_SEATS))
