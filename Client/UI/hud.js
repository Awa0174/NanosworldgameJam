// Jack's Last Show – HUD
// Zeigt nur an, was der Server schickt. Entscheidungen trifft ausschliesslich der Server.
// Vertrag (einzige Quelle der Wahrheit): docs/PROTOCOL.md
//
// Von Lua (Client/HUD.lua):
//   Init(local_player_id, version)
//   Place(kind)            "hub" oder "match": wo der Spieler gerade ist
//   Lobby(json)            Hub-Zustand: online, queued, needed, next_table, seats, tables, max_tables, timer
//   State(json)            oeffentlicher Zustand des eigenen Tisches: round, stage (intro spin skip pop card event result ended),
//                          event { id, name, actors, awaiting, involved, focus, instruction_actor, instruction_others, data }.
//                          event.data je Event:
//                            revolver { chambers, spent, holder, target }   vote { target, spare, kill, voted, voters, secret }
//                            pumpkin { holder }   splitsteal { a, b, locked_a, locked_b }   gallery { targets, aim }
//   Say(text)              Jacks Untertitel (erscheint wie auf der Schreibmaschine)
//   Fx(kind, seat)         kleiner Effekt: aim click bang safety qte_ok dodge stab block burn extinguish knife_raise fire
//                          chosen death winner (spin/start nur als Ersatz fuer Server ohne Show-Cues)
//   Show(json)             Inszenierung (Cue), immer { action, ... }. Alle Cues aus PROTOCOL.md, u. a.:
//                            intro spin pop card death survive winner          Vorhang (+ How to play), Gluecksrad, Name,
//                                                                              Event-Karte (who, how, YOU), Stempel, Plakat
//                            round_end                                         Rundenergebnis-Karte (wer ist raus, wie viele leben)
//                            skip ricochet revolver_give/aiming/aim/shot/pass angry_aim  Regie-Zeile + grosse Woerter
//                            vote_* pumpkin_* splitsteal_* bomb_* duel_* deal   Regie-Zeile, Aufdecken, Woerter
//                            card_gain card_play card_trigger                  kleine Meldungen unten links
//   Choice(json)           Abfrage oeffnen: { ask, event, kind, options:[...], seconds, ... } -> YOUR TURN (+ Sting)
//                            target      Ring mit Plaetzen                      -> Platznummer
//                                        aim = true (Revolver): KEIN Ring – Zielmodus (Client/Aim.lua), Fadenkreuz
//                            pass        Ring, nur Nachbarn (Kuerbis)           -> Platznummer
//                            qte         grosse Taste, Eingabe liest Lua        -> (Lua)
//                            click       springende Flamme (x, y, progress, total) -> das eine Token
//                            vote        SPARE / ELIMINATE (target, target_name)   -> "spare" / "kill"
//                            splitsteal  SPLIT / STEAL (partner, partner_name)      -> "split" / "steal"
//                            pickcard    3 Karten (cards)                           -> card_id
//                            wire        3 Draehte (wires [{color, number}], rule)  -> "red" / "green" / "blue"
//   ChoiceEnd(ask)         Abfrage schliessen (0 = alle)
//   QtePressed(key)        Lua hat eine Taste an den Server geschickt (nur Anzeige)
//   Hand(json)             eigene Karten { cards: [ { uid, id, rounds_left? } ] } (privat)
//   CardDefs(json)         { <id>: { name, description, type, target, art } } aus Shared/Cards.lua
//   CardMode(open)         Kartenhand (Taste C) auf/zu; waehrend einer eigenen Abfrage gesperrt (macht Lua)
//   Aim(json)              Zielmodus (Client/Aim.lua), bei jeder Aenderung: { ask, seat (0 = niemand), name, label, hint,
//                          warn (Klick ohne Ziel), seconds (Restzeit), total, crosshair }
//   AimEnd(ask, reason)    Zielmodus vorbei ("confirm" = geschossen, "closed", "place", "end", "restart")
// An Lua:
//   Choose(ask_id, value)
//   PlayCard(uid, target_seat)   target_seat 0 = ohne Ziel. Lua schliesst danach die Hand (CardMode false).
//   CloseCards()
//   UiSound("hover" | "click" | "your_turn" | "round_out" | "round_safe")   Stings: Client/HUD.lua UI_SOUNDS
//
// Schickt der Server (noch) keine Show-Cues, uebernehmen Fx "start", "spin", "chosen" und "death"
// eine einfache Version derselben Auftritte. Sobald ein Cue ankam, bleiben diese Fx dezent.
//
// SICHERHEIT: Spielernamen und Texte werden IMMER per textContent gesetzt, nie per innerHTML.
// Sonst koennte ein praeparierter Spielername Code in fremden HUDs ausfuehren.

"use strict";

(function () {
	// Feste UI-Texte (Englisch). Jacks Saetze kommen vom Server (Shared/Text.lua).
	const TEXT = {
		SHOW: "Jack's Last Show",
		WAITING: "Waiting for more victims",
		COUNTDOWN: "The next show starts in",
		QUEUE_INFO: (n, seats) => `${n} / ${seats} seats taken`,
		QUEUE_FILL: (humans, bots) => humans > 0 && bots > 0
			? `${humans} player${humans === 1 ? "" : "s"} + ${bots} puppet${bots === 1 ? "" : "s"} · late arrivals take a puppet's seat`
			: `${humans} player${humans === 1 ? "" : "s"}`,
		TABLES_FULL: "All tents are full. Please wait…",
		NEXT_IN: "Back to the graveyard in",
		SPECTATING: "Had enough? Press N for the next show",
		JOINING_TITLE: "You're next!",
		JOINING_SUB: "You take over a puppet's seat when this round ends",
		YOU_JOINING: "You're next – watch, your seat is coming",
		JOINED_WORD: "YOU'RE IN!",
		JOINED_TOOK: "You took",
		JOINED_SEAT: "'s seat",
		JOINED_CARDS: (n) => n > 0 ? ` · ${n} card${n === 1 ? "" : "s"}, press C` : "",
		TAKES_SEAT: " takes the seat of ",
		YOU: "YOU",
		DEAD: "DEAD",
		POP_SMALL: "Jack picks",
		INTRO_SMALL: "Ladies and gentlemen...",
		ELIMINATED: "Eliminated",
		FLED: "Fled",
		SURVIVED: "Survived",
		WINNER_SUB: "survived the show",
		WINNER_YOU: "You survived the show!",
		WINNER_TITLE: "The last one standing",
		NOBODY_TITLE: "Nobody is left standing",
		NOBODY: "Jack wins",
		NOBODY_SUB: "The show swallowed them all",
		ODDS: (odds) => `${odds.n} in ${odds.of}`,
		ODDS_SUB: (odds) => odds.n >= odds.of ? `${odds.n} in ${odds.of} · no more luck` : `${odds.n} in ${odds.of} it fires`,
		CHOOSE_TARGET: "Choose your target",
		ALIVE: (alive, total) => `${alive} of ${total} alive`,

		// Regie oben (Stage-Zeile): Phase · was passiert · was DU tust
		ROUND: (n) => `Round ${n}`,
		FINAL: "The show is over",
		ST_INTRO: "The show begins…",
		ST_SPIN: "Jack is choosing…",
		ST_HOLD: "Jack has chosen…",
		ST_PICKED: (name) => `Jack picked ${name}`,
		ST_PICKED_YOU: "Jack picked YOU!",
		ST_SKIP: (a, b) => `Body double! ${a} slips away – Jack spins on to ${b}`,
		ST_CARD: (name, who) => (who ? `${name} – ${who}` : name),
		ST_AIMING: (shooter, target, meShooter) => (meShooter ? `You are aiming at ${target}…` : `${shooter} is aiming at ${target}…`),
		ST_AIMING_YOU: (shooter) => `${shooter} is aiming at YOU…`,
		ST_RESULT: (round, main, left) => `${round} – ${main} · ${left}`,
		ST_ROUND_OVER: "The round is over",
		ST_WIN: (name) => `${name} wins the show!`,
		ST_WIN_YOU: "YOU win the show!",
		ST_NOBODY: "Nobody survived the show",
		ST_NEXT: "Next round…",
		YOU_WATCH: "Just watch",
		YOU_OUT: "You are out – just watch",
		YOU_WAIT: "Get comfortable – the show starts soon",
		YOU_SPIN: "Pray it's not you…",
		YOU_STARE: "Jack is staring at YOU…",
		YOU_PICKED: "It's YOU!",
		YOU_NOT_PICKED: "Not you – this time. Just watch",
		YOU_TOO: "It's YOU too – you're in this one!",
		YOU_NEXT: "Breathe. The next round starts soon",
		YOU_OUT_NOW: "You are out – stay and watch the show",
		YOU_WON: "You are the last one standing!",
		YOU_OVER: "The show is over",
		YOU_AIMED: "That's YOU in the sights – pray it clicks",
		YOU_PULLED: (name) => `You pulled the trigger – if it clicks, ${name} shoots next`,
		YOU_SURVIVED: "You survived!",
		YOU_EVENT_OVER: "It's over – see who made it",
		YOU_JACK_AIMS: "Jack aims at YOU – only a Lucky Charm or a Funhouse Mirror can help",
		YOU_LINE: "You are in the line of fire – only a card can help",
		YOU_FATE: "You can't vote – your fate is in their hands",
		YOU_READY: "Get ready – you are up next",
		YOU_VOTED: (value) => `You voted ${value === "kill" ? "ELIMINATE" : "SPARE"} – wait for the count`,
		YOUR_TURN: "Your turn",
		YOUR_VOTE: "Your vote",
		GET_READY: "Get ready",
		TURN_KIND: {
			aim: "Aim with the mouse – click to shoot",
			target: "Click a player",
			pass: "Throw it – click left or right!",
			qte: "Press the key!",
			click: "Click the flame!",
			vote: "Spare or eliminate?",
			splitsteal: "Split or steal?",
			pickcard: "Pick one card",
			wire: "Cut the right wire",
		},

		// Zielmodus (Revolver). Lua schickt label/hint fertig mit, das hier ist nur der Ersatz.
		AIM_NONE: "Aim at a player – click to shoot",
		AIM_AT: (name) => `Aiming at ${name} – click to shoot`,
		AIM_HINT: "Move the mouse to aim · Left click to shoot",
		AIM_WARN: "Aim at a player first!",

		// Rundenende
		RE_OUT_ONE: (name) => `${name} is OUT`,
		RE_OUT_YOU: "YOU are OUT",
		RE_OUT_MANY: (names) => `${names} are OUT`,
		RE_OUT_N: (n) => `${n} players are OUT`,
		RE_NOBODY: "Nobody is out",
		RE_SURVIVED: (names) => `Survived: ${names}`,
		RE_FLED: (names) => `Fled: ${names}`,
		RE_LEFT: (n) => (n === 1 ? "1 left" : `${n} left`),
		RE_MORE: (n) => `+${n}`,

		// Revolver-Kette
		HELD_BY: "Held by",
		AIMED_AT: "aims at",
		REV_GIVE_KICKER: "Five blanks · one bullet",
		REV_GIVE: (name) => `${name} gets the revolver`,
		REV_GIVE_YOU: "You get the revolver",
		REV_AIM_KICKER: (chamber, chambers) => `Chamber ${chamber} of ${chambers}`,
		REV_AIM_HOLD: "Hold your breath…",
		REV_AIM: (shooter, target) => `${shooter} aims at ${target}`,
		REV_AIM_SELF: (name) => `Jack turns the gun on ${name}`,
		REV_PASS_KICKER: "*click* · the gun moves on",
		REV_PASS: (name) => `The gun passes to ${name}`,
		REV_RELOAD: (odds) => `Jack loads another bullet: ${odds.n} in ${odds.of}`,
		JACK_AIMS: (name) => `Jack aims at ${name}`,
		ANGRY_KICKER: "Jack has run out of patience",
		ONLY_CARDS: "Only a Lucky Charm or a Funhouse Mirror can help",
		GALLERY_KICKER: (k, n) => `Shooting gallery · duck ${k} of ${n}`,

		// Karten-Cues
		SKIP_WORD: "BODY DOUBLE!",
		SKIP_KICKER: "Body Double card",
		SKIP_MAIN: (name) => `${name} slips away`,
		SKIP_TO: (name) => `…Jack spins on to ${name}`,
		RICOCHET_WORD: "RICOCHET!",
		RICOCHET_KICKER: "Funhouse Mirror card",
		RICOCHET_MAIN: (name) => `The bullet bounces off ${name}`,
		RICOCHET_TO: (name) => `…straight toward ${name}!`,

		// Abstimmung
		VOTE_KICKER: "The audience decides",
		VOTE_ON: (name) => `Spare or eliminate ${name}?`,
		VOTE_ON_YOU: "The table votes on YOU",
		VOTE_ALL: (secret) => secret ? "Secret ballot · everyone votes, even the dead" : "Everyone votes, even the dead",
		VOTE_CAST: (voted, voters) => `${voted} of ${voters} vote${voters === 1 ? "" : "s"} cast`,
		VOTE_SECRET: "Secret ballot",
		VOTE_YOU: (value) => `You voted ${value === "kill" ? "ELIMINATE" : "SPARE"}`,
		VOTE_MISSED: "You did not vote",
		VOTE_FATE: "Your fate is in their hands",
		VOTE_IN: "The votes are in",
		VOTE_TIE: "A tie! Jack flips a coin…",
		VOTE_SPARE: "Spare!",
		VOTE_KILL: "Eliminate!",
		VOTE_FINAL: "Final count",

		// Kuerbis
		PUMPKIN_KICKER: "It's lit!",
		PUMPKIN_MAIN: "Pass the pumpkin!",
		PUMPKIN_YOU: "You hold it · throw it to a neighbour!",
		PUMPKIN_HOLDS: (name) => `${name} holds it · the fuse is secret`,
		PUMPKIN_RING: "Pass the pumpkin!",
		PUMPKIN_HINT: "Throw it left or right",
		BOOM: "BOOM!",

		// Split or Steal
		SPLIT_KICKER: "Share or snatch",
		SPLIT_SUB: "One deal. Two secrets.",
		SPLIT_HANDS: (name, theirs, mine) => `${name} holds ${theirs} card${theirs === 1 ? "" : "s"} · you hold ${mine}`,
		SPLIT_WAIT: (name) => `${name} is still deciding…`,
		SPLIT_LOCKED: (name) => `${name} has decided`,
		SPLIT_YOU: (value) => `You chose ${value === "steal" ? "STEAL" : "SPLIT"} · wait for the reveal`,
		SPLIT: "Split",
		STEAL: "Steal",
		DECIDED: "decided",
		THINKING: "thinking…",
		GAIN: (n) => n > 0 ? `+${n} card${n === 1 ? "" : "s"}` : n < 0 ? `-${-n} card${n === -1 ? "" : "s"}` : "nothing",
		RV_BOTH_SPLIT: "Both split · a card for each",
		RV_BOTH_STEAL: "Both steal · nobody gets a thing",
		RV_STEALS: (name) => `${name} steals everything!`,

		// Bombe
		BOMB_KICKER: "Jack built it himself",
		BOMB_MAIN: "Snip the wire",
		BOMB_YOU: (s) => `You have ${s} seconds · read the manual!`,
		BOMB_OTHER: (name, s) => `${name} has ${s} seconds`,
		DEFUSED: "DEFUSED!",
		WRONG_WIRE: "Wrong wire!",
		TOO_SLOW: "Time's up!",
		WIRE_KICKER: (color) => `The ${color} wire`,
		WIRE: { red: "Red", green: "Green", blue: "Blue" },
		CUT: "Cut",

		// Duell
		DUEL_KICKER: "Quick draw",
		DUEL_VS: (a, b) => `${a} vs ${b}`,
		DUEL_SUB: "Wait for DRAW! · then hit the key first",
		DRAW: "DRAW!",
		DUEL_WIN: (name) => (name === TEXT.YOU ? "YOU were faster" : `${name} was faster`),
		DUEL_HIT: (name) => `fires at ${name}`,   // getroffen? Ricochet/Safety entscheiden erst danach
		DUEL_MISFIRE: (name) => `${name} misfires!`,
		DUEL_FOOT: "Wrong key · right in the foot",
		DUEL_BOTH: "Too slow!",
		DUEL_BOTH_SUB: "Jack shoots them both",
		DUEL_JACK: "Jack loses his patience",
		DUEL_JACK_SUB: (name) => `…and shoots ${name}`,
		FINALE_WORD: "FINAL SHOWDOWN",
		FINALE_KICKER: "Only two left",
		FINALE_MAIN: (a, b) => `${a} vs ${b}`,
		FINALE_SUB: "The winner takes the show",

		// Deal / Karten
		DEAL_KICKER: "Jack is feeling generous",
		DEAL_MAIN: (n) => n <= 0 ? "Everybody's hands are full" : n === 1 ? "1 player will now be given a card" : `${n} players will now be given cards`,
		DEAL_YOU: "One of them is YOU",
		DRAWS: (n) => n === 1 ? "a card" : `${n} cards`,
		TAKES: " takes ",
		TAKE: " take ",
		USED: " used ",
		ON: " on ",
		SAVED: " saved ",
		THEMSELF: "themself",
		STOLE: " stole your ",
		YOURSELF: "yourself",
		YOU_LOWER: "You",

		// Kartenhand
		HAND_TITLE: (n, max) => `${n} of ${max} cards`,
		HAND_EMPTY: "Your hands are empty",
		PICK_HAND: (names) => `In your hand: ${names}`,
		HAND_EMPTY_NOTE: "Jack hands out new cards in Party Favors.",
		HAND_DEAD: "The dead hold no cards",
		HAND_NOTE: "Click a playable card to use it · automatic cards work by themselves",
		HAND_NOTE_AUTO: "Automatic cards work by themselves when their moment comes",
		BADGE_AUTO: "Auto",
		BADGE_PLAYABLE: "Playable",
		BREAKS: (n) => `Breaks in ${n} round${n === 1 ? "" : "s"}`,
		PLAY_HINT: "Click to play",
		PLAY_NOT_YET: "Not before the show starts",
		PLAY_OVER: "The show is over",
		PLAY_DEAD: "The dead can't play cards",
		PLAY_BUSY: "Not now",
		PLAY_COOLDOWN: "Wait a moment…",
		NO_THIEF_TARGETS: "Nobody has a card to steal",
		NO_TARGETS: "No valid target right now",
		TARGET_TITLE: { guardian: "Who gets the Lucky Charm?", thief: "Steal from whom?" },
		TARGET_SUB: { guardian: "Any living player · you too", thief: "Players with cards" },
		TARGET_ANY: "Choose a target",
		CARDS_SHORT: (n) => `${n} card${n === 1 ? "" : "s"}`,
		HAND_FULL: "hand full",
	};

	const URGENT_SECONDS = 3;
	const MANY_SEATS = 12;         // Zielwahl: ab hier kleinere Schilder
	const CROWD_SEATS = 20;        // Zielwahl: ab hier ganz kompakt
	const LIST_COMPACT = 16;       // Liste rechts: ab hier niedrigere Zeilen
	const POP_MS = 2600;           // Name nach "Jack picks" (Server: REVEAL_TIME 3 s)
	const STAMP_MS = 2300;         // Stempel inkl. kurzer Verzoegerung nach dem Knall
	const CARD_AWAY_MS = 450;
	const DEATH_REORDER_MS = 1500; // ein gerade Gestorbener bleibt so lange an seinem Platz in der Liste
	const TYPE_MS = 24;            // Schreibmaschine: Zeit pro Zeichen
	const SAY_HOLD_MS = 2600;      // so lange bleibt Jacks Satz mindestens nach dem Tippen stehen
	const FALLBACK_MS = 160;       // so lange wartet ein Fx auf einen passenden Show-Cue
	const MAX_HAND = 5;            // = Config.CARDS.MAX_HAND (Shared/Config.lua)
	const PLAY_COOLDOWN_MS = 2000; // = Config.CARDS.PLAY_COOLDOWN
	const BANNER_MS = 3200;        // Standard-Anzeigedauer einer Ansage (Detail-Zeile der Regie)
	const BANNER_MIN_MS = 1400;    // so lange bleibt eine Ansage mindestens, wenn schon die naechste wartet
	const BANNER_QUEUE = 3;        // mehr wartende Ansagen werden verworfen (die aelteste zuerst)
	const TOAST_MS = 4800;
	const TOAST_MAX = 3;           // weniger gleichzeitig: die Regie oben ist die Hauptquelle
	const RESULT_CARD_MS = 3300;   // Rundenergebnis-Karte (Server: RESULT_PAUSE 4 s, danach dreht Jack)
	const TURN_GAP_MS = 1500;      // YOUR TURN: Sting nur, wenn dein letzter Zug so lange vorbei ist (nicht bei jeder Messer-Taste)
	// Phasen einer Runde (State.stage, PROTOCOL)
	const STAGES = ["intro", "spin", "skip", "pop", "card", "event", "result", "ended"];
	// Cues, die nur waehrend eines laufenden Events kommen (Phase "event", auch wenn der State noch nachhinkt)
	const EVENT_CUES = new Set(["revolver_give", "revolver_aiming", "revolver_aim", "revolver_shot", "revolver_pass", "ricochet",
		"knife_raise", "knife_throw", "fire_breath", "fire_off", "stab_raise", "stab_strike", "angry_aim", "vote_start", "vote_result",
		"pumpkin_start", "pumpkin_pass", "pumpkin_boom", "splitsteal_start", "splitsteal_result", "bomb_start", "bomb_result",
		"duel_start", "duel_draw", "duel_result", "deal", "survive"]);
	// Events, in denen der Gewaehlte nichts tun kann (Karte: kein "GET READY", sondern Gefahr bzw. zuschauen)
	const PASSIVE = { angry: "danger", gallery: "danger", vote: "danger", deal: "watch" };
	// Leitwort vor Server-Texten, das schon das Etikett sagt ("YOU: ...", "GET READY – ...", "YOUR TURN – ...")
	const LEAD = /^\s*(?:you\s*:|get ready\s*[:!–—-]|your turn\s*[:!–—-]|your vote\s*[:!–—-])\s*/i;
	const REVEAL_MS = 3000;        // = Config.SPLITSTEAL.RESULT_TIME
	const WORD_LOCK_MS = 800;      // ein Cue-Wort (BOOM!, SKIP!) wird so lange nicht von einem Fx-Wort ueberschrieben
	const REASK_MS = 450;          // neue Abfrage gleicher Art kurz nach dem Schliessen: ohne Einblend-Animation
	const LINGER_MS = { splitsteal: 1300, pickcard: 700, wire: 750 };   // gewaehltes Panel bleibt kurz stehen
	const CUT_MS = 250;            // Bombe: so lange ist der gekappte Draht zu sehen, bevor das Ergebnis die Bombe abraeumt
	const BOMB_LEAVE_MS = 150;     // Bombe blendet aus, damit BOOM!/DEFUSED! und der Stempel frei stehen
	const CARD_ART = /^[a-z0-9_]+$/i;
	const WIRE_COLORS = ["red", "green", "blue"];
	const SVG_NS = "http://www.w3.org/2000/svg";
	// Cues, die ein laufendes Gluecksrad NICHT beenden (koennen jederzeit kommen, z. B. Karte waehrend des Drehens;
	// death waehrend des Drehens = jemand hat die Show verlassen, left = true)
	const KEEP_SPIN = new Set(["card_play", "card_gain", "card_trigger", "point", "death", "seat_taken", "you_joined", "finale"]);
	// nur 3D/Ton (Client/Presentation.lua), das HUD zeigt dazu nichts Eigenes
	const SILENT_CUES = new Set(["point", "knife_raise", "knife_throw", "fire_breath", "fire_off", "stab_raise", "stab_strike"]);

	// nanos stellt "Events" bereit. Im Browser (Vorschau) gibt es einen Ersatz.
	const Bus = window.Events;

	let localId = -1;
	let place = "hub";
	let lobby = null;
	let lobbyAt = 0;              // Empfangszeit (performance.now()) von lobby
	let state = null;
	let stateAt = 0;              // Empfangszeit von state
	let choice = null;            // offene Abfrage oder null
	let cuesSeen = false;         // Server schickt Show-Cues
	let actCount = 0;             // wievielter Akt (Event-Karte) dieser Show
	let lastPick = 0;             // Platz, den Jack zuletzt gezeigt hat
	const spin = { active: false, lit: 0, victim: 0, alt: false, ends: 0, total: 0 };
	// Regie: letzte Phase laut Cue (gilt, solange kein neuerer State da ist) und was die Cues dazu wissen
	//   skip { seat, name, next, nextName }   card { id, name, seat, actors, who, you_actor, you_others }
	//   result { round, out, survived, left, alive }
	//   actors [seat]   alle Gewaehlten laut spin/pop (Duell, Split or Steal: zwei)
	const act = { stage: "", seq: 0, pick: 0, actors: [], skip: null, card: null, result: null };
	let msgSeq = 0;               // Reihenfolge der Nachrichten: was zuletzt kam, gilt (Cue oder State)
	let stateSeq = 0;
	// Zielmodus (Aim/AimEnd von Client/Aim.lua bzw. Abfrage target + aim)
	const aim = { active: false, ask: 0, seat: 0, name: "", label: "", hint: "", warn: false, ends: 0, total: 0 };
	let choiceClock = { ends: 0, total: 0 };   // Restzeit der eigenen Abfrage (seconds ab Empfang)
	const turnFx = { mode: "", key: "", offAt: -1e9 };   // YOUR TURN: letzter Modus, Sting-Merker
	const clock = { key: "", ends: 0 };       // laufende Restzeit-Anzeige oben
	let stampUntil = 0;           // bis dahin steht der Stempel (das Rundenergebnis wartet darauf)
	const winner = { on: false, seat: 0, since: 0 };   // Siegerplakat (seat 0 = niemand)
	const countdowns = new Map(); // Element -> { ends (performance.now() in ms), fmt }
	const timers = new Map();     // Gruppe -> Set(Timer-IDs)
	const rows = new Map();       // Platz -> Listenzeile
	const diedAt = new Map();     // Platz -> Zeitpunkt des Todes (performance.now())
	let rowsMatch = null;

	// Karten
	let cardDefs = {};            // id -> { name, description, type, target, art }
	let hand = [];                // [ { uid, id, rounds_left } ] in Server-Reihenfolge
	const handSeen = new Set();   // uids, die schon angezeigt wurden (neue fliegen ein)
	let handBarSig = "";
	let handSig = "";
	let cardMode = false;         // Kartenhand offen (CardMode true)
	let cardTarget = null;        // { uid, id } waehrend der Zielwahl einer Karte
	let lastPlayAt = -1e9;
	let lastLost = { ids: [], at: -1e9 };   // zuletzt von der Hand verschwundene Karten (Thief: welche wurde gestohlen?)
	let bombCutAt = -1e9;         // Zeitpunkt des eigenen Drahtschnitts (Bombe)

	// Ring (Zielwahl): gehoert einer Abfrage (target, pass) oder der Kartenhand
	let ringOwner = null;         // "choice" | "card" | null
	let ringSig = "";
	const lastClosed = { kind: null, at: -1e9 };

	// Merkzettel fuer das laufende Event (wird bei jedem neuen Event geleert)
	// aiming = { shooter, seat } aus revolver_aiming (gilt bis revolver_aim/shot/pass oder round_end)
	const memo = { id: null, shots: new Map(), vote: null, voteMissed: false, voteResult: null, split: null, galleryAnnounced: false, aiming: null };

	// Ansagen (eine zur Zeit, kurze Warteschlange, als Detail-Zeile der Regie) und grosse Woerter
	const banners = { queue: [], current: null, shownAt: 0 };
	let wordLock = { prio: 0, until: 0 };

	const $ = (id) => document.getElementById(id);

	// Lua-Tabellen ohne Eintraege kommen als {} statt [] an
	const asArray = (value) => Array.isArray(value) ? value : (value && typeof value === "object" ? Object.values(value) : []);

	function num(value, min, max, fallback) {
		const n = Number(value);
		if (!Number.isFinite(n)) return fallback;
		return Math.max(min, Math.min(max, n));
	}

	function el(tag, className, text) {
		const node = document.createElement(tag);
		if (className) node.className = className;
		if (text !== undefined) node.textContent = text;
		return node;
	}

	// Text nur schreiben, wenn er sich aendert (render() laeuft bei jedem State und vielen Cues)
	function setText(node, text) {
		const value = String(text === undefined || text === null ? "" : text);
		if (node.textContent !== value) node.textContent = value;
		return node;
	}

	function svgEl(tag, attrs) {
		const node = document.createElementNS(SVG_NS, tag);
		Object.keys(attrs || {}).forEach((key) => node.setAttribute(key, String(attrs[key])));
		return node;
	}

	// Ring und Kartenwahl decken die Mitte ganz ab: solange einer offen ist, ruht oben alles (Eventkopf, Trommel,
	// Live-Anzeigen, Ansagen). Der Ring bzw. die Kartenwahl tragen Titel und Zeit selbst.
	const MODALS = ["ring", "pick"];

	function show(id, visible) {
		$(id).classList.toggle("hidden", !visible);
		if (MODALS.includes(id)) document.body.classList.toggle("modal", MODALS.some((m) => !$(m).classList.contains("hidden")));
	}

	function isShown(id) {
		return !$(id).classList.contains("hidden");
	}

	function restartAnimation(node, className) {
		node.classList.remove(className);
		void node.offsetWidth;   // Reflow erzwingen, damit die Animation neu startet
		node.classList.add(className);
	}

	function rem(value) {
		return value * (parseFloat(getComputedStyle(document.documentElement).fontSize) || 16);
	}

	// Schrift so weit verkleinern, dass der Text in maxWidth passt (Element: inline-block, nowrap)
	function fitText(node, maxWidth, maxPx, minPx) {
		node.style.fontSize = maxPx + "px";
		const width = node.offsetWidth;
		if (width > maxWidth) node.style.fontSize = Math.max(minPx, Math.floor(maxPx * maxWidth / width)) + "px";
	}

	// Wie fitText, Startgroesse aus dem Stylesheet (gilt auch fuer @media-Groessen, 720p)
	function fitTextCss(node, maxWidth, minPx) {
		node.style.fontSize = "";
		fitText(node, maxWidth, parseFloat(getComputedStyle(node).fontSize) || rem(2), minPx);
	}

	function parse(json, what) {
		if (json && typeof json === "object") return json;
		try {
			return JSON.parse(json);
		} catch (e) {
			console.error(`[DeathBox] Invalid ${what}`, e);
			return null;
		}
	}

	// ------------------------------------------------------------ Timer-Gruppen

	function after(group, ms, fn) {
		let set = timers.get(group);
		if (!set) {
			set = new Set();
			timers.set(group, set);
		}
		const id = setTimeout(() => {
			set.delete(id);
			fn();
		}, Math.max(0, ms));
		set.add(id);
		return id;
	}

	function cancel(group) {
		const set = timers.get(group);
		if (!set) return;
		set.forEach((id) => clearTimeout(id));
		set.clear();
	}

	// ------------------------------------------------------------ Hilfen zum Spielstand

	// Vor Init ist localId -1 – genau die ID aller Bots. HUD.lua schickt gepufferte Aufrufe (State, Show) vor Init.
	function mySeat() {
		if (!state || !(localId >= 0)) return null;
		return asArray(state.seats).find((s) => s.id === localId) || null;
	}

	// Bin ich Nachruecker an diesem Tisch (schaue zu, bekomme zur naechsten Runde einen Bot-Platz)?
	function amJoining() {
		return !!(state && localId >= 0 && asArray(state.joining).some((id) => Number(id) === localId));
	}

	function seatByIndex(index) {
		if (!state) return null;
		return asArray(state.seats).find((s) => s.seat === index) || null;
	}

	function seatName(index, given) {
		if (given !== undefined && given !== null && given !== "") return String(given);
		const s = seatByIndex(index);
		return s ? String(s.name) : "";
	}

	function isMe(index) {
		const me = mySeat();
		return !!(me && me.seat === index);
	}

	// Name fuer Ansagen: "YOU" fuer den eigenen Platz
	function who(index, given) {
		return isMe(index) ? TEXT.YOU : seatName(index, given);
	}

	function eventData(id) {
		const event = state && state.event;
		return event && event.id === id && event.data && typeof event.data === "object" ? event.data : null;
	}

	function resetMemo(id) {
		memo.id = id;
		memo.shots = new Map();
		memo.vote = null;
		memo.voteMissed = false;
		memo.voteResult = null;
		memo.split = null;
		memo.galleryAnnounced = false;
		memo.aiming = null;
	}

	// ------------------------------------------------------------ Karten-Definitionen

	function cardDef(id) {
		const def = cardDefs && cardDefs[id];
		return def && typeof def === "object" ? def : null;
	}

	function cardName(id) {
		const def = cardDef(id);
		if (def && def.name) return String(def.name);
		const text = String(id || "?");
		return text.charAt(0).toUpperCase() + text.slice(1);
	}

	function artUrl(id) {
		const def = cardDef(id);
		let art = def && typeof def.art === "string" ? def.art : String(id || "");
		if (!CARD_ART.test(art)) art = "back";
		return `img/cards/${art}.png`;
	}

	// Eigene Kartenbilder tragen den Namen auf dem Band. Nur die Ersatz-Rueckseite nicht: dann bekommt die
	// Kartenflaeche die Klasse no-art und der Name erscheint im Text darunter.
	function hasArt(id) {
		return id === "back" || artUrl(id) !== "img/cards/back.png";
	}

	function cardImg(id, alt) {
		const img = document.createElement("img");
		img.onerror = () => {   // unbekannte Karte: Rueckseite statt kaputtem Bild
			img.onerror = null;
			img.src = "img/cards/back.png";
			if (img.parentElement) img.parentElement.classList.add("no-art");
		};
		img.src = artUrl(id);
		img.alt = alt || "";
		img.draggable = false;
		return img;
	}

	// ------------------------------------------------------------ Zeit (Zuendschnur + Zaehler)

	// Server-Timer { total, remaining } gilt ab Empfang. render() laeuft auch spaeter (Cues),
	// deshalb immer die seitdem vergangene Zeit abziehen.
	function timeLeft(timer, receivedAt) {
		if (!timer || !(Number(timer.remaining) > 0)) return 0;
		return Math.max(0, Number(timer.remaining) - (performance.now() - receivedAt) / 1000);
	}

	function startFuse(fill, seconds, total) {
		const start = Math.max(0, Math.min(1, seconds / (total || seconds)));
		fill.style.transition = "none";
		fill.style.width = (start * 100) + "%";
		void fill.offsetWidth;
		fill.style.transition = `width ${seconds}s linear`;
		fill.style.width = "0%";
	}

	// Zaehler (Ziffern). fmt(left) formatiert selbst (z. B. LED der Bombe), sonst ganze Sekunden.
	function startCountdown(seconds, node, fmt) {
		const running = countdowns.size > 0;
		const left = Math.max(0, Number(seconds) || 0);
		countdowns.set(node, { ends: performance.now() + left * 1000, fmt: fmt || null });
		node.textContent = fmt ? fmt(left) : Math.ceil(left).toString();   // sofort, nicht erst im naechsten Frame
		node.classList.toggle("urgent", left <= URGENT_SECONDS);
		if (!running) requestAnimationFrame(tickCountdowns);
	}

	function stopCountdown(node) {
		countdowns.delete(node);
	}

	function tickCountdowns() {
		const now = performance.now();
		countdowns.forEach((c, node) => {
			const left = Math.max(0, (c.ends - now) / 1000);
			const text = c.fmt ? c.fmt(left) : Math.ceil(left).toString();
			if (node.textContent !== text) node.textContent = text;
			node.classList.toggle("urgent", left <= URGENT_SECONDS);
			if (left <= 0) countdowns.delete(node);
		});
		if (countdowns.size > 0) requestAnimationFrame(tickCountdowns);
	}

	const ledFormat = (left) => "00:" + String(Math.ceil(left)).padStart(2, "0");

	// ------------------------------------------------------------ Rendern

	function render() {
		const inMatch = place === "match" && !!state;
		show("hub", place === "hub");
		if (!inMatch) {
			show("event", false);
			renderClock(null);
			show("cylinder", false);
			show("circle", false);
			show("gallery", false);
			show("versus", false);
			hideVote();
			hideAim();
			renderHandBar();
			renderHubLobby();
			return;
		}

		const me = mySeat();
		renderStage(me);
		renderCylinder();
		renderGallery();
		renderVote();
		renderSplit();
		renderVersus();
		renderSeats(me);
		if (aim.active) renderAim();
		renderMatchLobby(me);
		renderHandBar();
		if (cardMode) refreshCardMode();
		updateStatusSlot();

		// Siegerplakat bleibt, bis die Phase wechselt (kurze Schonfrist gegen spaete Zustaende)
		if (winner.on && state.phase !== "ENDED" && performance.now() - winner.since > 1500) {
			hideCue("winner");
		}
	}

	function renderHubLobby() {
		const text = $("lobby-text");
		const sub = $("lobby-sub");
		const note = $("lobby-note");
		$("lobby").classList.remove("ghost");
		if (!lobby) {
			stopCountdown(sub);
			show("lobby", false);
			return;
		}
		$("stat-online").textContent = String(lobby.online || 0);
		$("stat-queued").textContent = String(lobby.queued || 0);
		$("stat-tables").textContent = String(lobby.tables || 0);

		show("lobby", true);
		const left = timeLeft(lobby.timer, lobbyAt);
		const counting = left > 0;
		sub.classList.toggle("big", counting);
		if (counting) {
			text.textContent = TEXT.COUNTDOWN;
			note.textContent = (typeof lobby.humans === "number")
				? TEXT.QUEUE_FILL(lobby.humans, Math.max(0, (lobby.next_table || 0) - lobby.humans))
				: TEXT.QUEUE_INFO(lobby.next_table || 0, lobby.seats || 8);
			startCountdown(left, sub);
			return;
		}
		stopCountdown(sub);
		sub.classList.remove("urgent");
		note.textContent = "";
		if ((lobby.tables || 0) >= (lobby.max_tables || 1) && (lobby.queued || 0) > 0) {
			text.textContent = TEXT.TABLES_FULL;
			sub.textContent = "";
		} else {
			text.textContent = TEXT.WAITING;
			sub.textContent = `${lobby.next_table || 0} / ${lobby.needed || 2}`;
		}
	}

	// ------------------------------------------------------------ Regie oben: Stage-Zeile, YOUR TURN, Restzeit

	// PROTOCOL "Klarheit": jederzeit lesbar (a) Phase/Runde, (b) was passiert und wer, (c) was DU tun musst – oder nur
	// zuschauen, (d) Restzeit. Die Phase kommt aus State.stage (gilt auch nach Neuladen). Ein Cue, der neuer ist als der
	// letzte State, gilt sofort: der passende State kommt oft einen Augenblick spaeter (oder gar nicht, z. B. bei der Karte).
	function setAct(stage) {
		act.stage = stage;
		act.seq = ++msgSeq;
	}

	function resetAct() {
		act.stage = "";
		act.seq = 0;
		act.pick = 0;
		act.actors = [];
		act.skip = null;
		act.card = null;
		act.result = null;
		turnFx.mode = "";
		turnFx.key = "";
		turnFx.offAt = -1e9;
	}

	function currentStage() {
		if (!state) return "";
		if (state.phase === "ENDED") return "ended";
		if (state.phase === "STARTING") return "intro";
		let stage = STAGES.includes(state.stage) ? state.stage : (state.event ? "event" : "");
		if (act.stage && (act.seq > stateSeq || !stage)) stage = act.stage;
		if (stage === "ended" || stage === "intro") stage = state.event ? "event" : "spin";   // Phase sagt PLAYING
		return stage || "spin";
	}

	function eventOf(stateEvent) {
		return stateEvent && typeof stateEvent === "object" ? stateEvent : null;
	}

	// Eigener Name in Server-Texten -> "YOU" ("BANG! Nibbles is OUT" -> "BANG! YOU are OUT", "Nibbles's" -> "YOUR").
	// Nur ganze Namen (Gross/klein genau), nicht bei kurzen Namen, "Jack" oder Namen, die auch als Wort in den Texten stehen.
	const YOU_VERBS = { is: "are", was: "were", has: "have", gets: "get", wins: "win", holds: "hold", picks: "pick",
		pulls: "pull", tries: "try", raises: "raise", dodges: "dodge", steals: "steal" };
	const YOU_SKIP = new Set(["jack", "you", "your", "the", "and", "out", "gun", "bang", "boom", "fire", "knife", "bomb", "card",
		"cards", "wire", "key", "vote", "deal", "split", "steal", "click", "draw", "both", "safety", "skip", "ricochet", "pumpkin",
		"block", "dodge", "pray", "wait", "next", "round", "table", "show", "spare", "eliminate", "too", "slow", "get", "ready"]);
	const NAME_CHARS = "A-Za-z0-9_\\u00C0-\\uFFFF";
	let youRe = { name: null, re: null };
	function youify(text) {
		const s = String(text || "");
		const me = mySeat();
		const name = me ? String(me.name || "").trim() : "";
		if (!s || name.length < 3 || YOU_SKIP.has(name.toLowerCase()) || s.indexOf(name) < 0) return s;
		if (youRe.name !== name) {
			const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
			youRe = { name, re: new RegExp(`(^|[^${NAME_CHARS}])${esc}(?![${NAME_CHARS}])`, "g") };
		}
		const marked = s.replace(youRe.re, (m, pre) => pre + "\u0001");
		if (marked === s) return s;
		return marked
			.replace(/\u0001's\b/g, "YOUR")
			.replace(/\u0001 ([A-Za-z]+)\b/g, (m, verb) => {
				const fix = YOU_VERBS[verb.toLowerCase()];
				return fix ? "\u0001 " + (verb === verb.toUpperCase() ? fix.toUpperCase() : fix) : m;
			})
			.replace(/(\u0001 must shoot )THEMSELVES/g, "$1YOURSELF")
			.replace(/\u0001/g, TEXT.YOU);
	}

	// "YOU: watch – ..." -> "Watch – ..." (das Etikett YOU / YOUR TURN steht schon davor)
	function stripLead(text) {
		const rest = String(text || "").trim().replace(LEAD, "");
		return rest ? rest.charAt(0).toUpperCase() + rest.slice(1) : "";
	}

	function roundNo() {
		const r = Number(state && state.round);
		return Number.isFinite(r) && r > 0 ? Math.floor(r) : actCount;
	}

	// (a) Runde und Event
	function eyebrowText(stage, event) {
		if (stage === "intro") return TEXT.SHOW;
		if (stage === "ended") return TEXT.FINAL;
		const parts = [];
		const round = stage === "result" && act.result ? act.result.round : roundNo();
		if (round > 0) parts.push(TEXT.ROUND(round));
		let name = "";
		if (stage === "event" && event) name = String(event.name || "");
		else if ((stage === "card" || stage === "result") && act.card) name = act.card.name;
		if (name) parts.push(name);
		return parts.join(" · ");
	}

	// (b) Die Stage-Zeile: { main, tone }
	function stageLine(stage, event, involved) {
		switch (stage) {
			case "intro": return { main: TEXT.ST_INTRO };
			case "spin": return { main: spin.active && spin.victim > 0 ? TEXT.ST_HOLD : TEXT.ST_SPIN };
			case "skip": {
				const s = act.skip;
				if (!s) return { main: TEXT.SKIP_WORD, tone: "gold" };
				return { main: TEXT.ST_SKIP(who(s.seat, s.name), who(s.next, s.nextName)), tone: isMe(s.next) ? "danger" : "gold" };
			}
			case "pop": {
				const seat = act.pick || Number(state.turn) || 0;
				if (!(seat > 0)) return { main: TEXT.ST_SPIN };
				if (act.actors.length > 1) return { main: TEXT.ST_PICKED(joinNames(act.actors)), tone: act.actors.some(isMe) ? "danger" : "" };
				return isMe(seat) ? { main: TEXT.ST_PICKED_YOU, tone: "danger" } : { main: TEXT.ST_PICKED(seatName(seat)) };
			}
			case "card": {
				const c = act.card;
				if (!c) return stageLine("pop", event, involved);
				return { main: TEXT.ST_CARD(c.name, c.who), tone: c.actors.some(isMe) ? "danger" : "" };
			}
			case "result": {
				const r = act.result;
				if (!r) return { main: TEXT.ST_ROUND_OVER };
				return { main: TEXT.ST_RESULT(TEXT.ROUND(r.round), resultTexts(r).main, TEXT.RE_LEFT(r.alive)), tone: r.out.some(isMe) ? "danger" : "" };
			}
			case "ended": {
				const seat = winner.on ? winner.seat : Number(state.winner) || 0;
				if (!(seat > 0)) return { main: TEXT.ST_NOBODY, tone: "danger" };
				return { main: isMe(seat) ? TEXT.ST_WIN_YOU : TEXT.ST_WIN(seatName(seat)), tone: "gold" };
			}
		}
		if (!event) return act.card ? stageLine("card", event, involved) : { main: TEXT.ST_NEXT };   // Event-Cue vor dem State
		// Revolver-Wahl: wer zielt gerade auf wen (revolver_aiming ersetzt die Zeile des Servers)
		const data = event.data && typeof event.data === "object" ? event.data : {};
		const a = memo.aiming;
		if (event.id === "revolver" && a && a.seat > 0 && !(Number(data.target) > 0) && !(Number(data.holder) > 0 && Number(data.holder) !== a.shooter)) {
			if (isMe(a.seat)) return { main: TEXT.ST_AIMING_YOU(seatName(a.shooter)), tone: "danger" };
			return { main: TEXT.ST_AIMING(seatName(a.shooter), seatName(a.seat), isMe(a.shooter)) };
		}
		return { main: youify(String((involved ? event.instruction_actor : event.instruction_others) || "").trim()) };
	}

	// Detail-Zeile unter der Stage-Zeile: laufende Ansage (Chance, Nachladen, Querschlaeger ...) oder Live-Wert
	function stageDetail(stage, event) {
		const beat = banners.current;
		if (beat) return { text: youify(beat.detail !== undefined ? beat.detail : [beat.kicker, beat.sub].filter(Boolean).join(" · ")), tone: beat.tone || "" };
		if (stage === "event" && event && event.id === "revolver" && eventData("revolver")) return { text: TEXT.ODDS_SUB(revolverOdds(null)), tone: "" };
		return { text: "", tone: "" };
	}

	// Gefahr fuer dich, ohne dass du etwas tun kannst
	function dangerText(event, me) {
		if (!event || !me || event.final) return "";   // Ergebnis steht fest (Server: Context:Conclude)
		const d = event.data && typeof event.data === "object" ? event.data : {};
		switch (event.id) {
			case "revolver":
				if (Number(d.target) === me.seat || (memo.aiming && memo.aiming.seat === me.seat)) return TEXT.YOU_AIMED;
				break;
			case "angry":
				if (Number(event.focus) === me.seat) return TEXT.YOU_JACK_AIMS;
				break;
			case "gallery":
				if (Number(d.aim) === me.seat) return TEXT.YOU_JACK_AIMS;
				if (asArray(d.targets).map(Number).includes(me.seat)) return TEXT.YOU_LINE;
				break;
			case "vote":
				if (Number(d.target) === me.seat) return TEXT.YOU_FATE;
				break;
		}
		return "";
	}

	// (c) Was DU tust: { mode: "turn" | "ready" | "danger" | "watch" | "out" | "win", word, text, kind }
	//   turn   eine Abfrage ist fuer dich offen (oder der Zielmodus laeuft) -> grosser YOUR-TURN-Hinweis + Sting
	//   ready  du bist dran, die Abfrage kommt gleich (event.involved, eigene Event-Karte) -> GET READY
	function youLine(stage, event, me, involved) {
		if (choice || aim.active) {
			const kind = aim.active || isAimChoice(choice) ? "aim" : String(choice.kind);
			const own = event && involved ? youify(stripLead(event.instruction_actor)) : "";
			return { mode: "turn", word: kind === "vote" ? TEXT.YOUR_VOTE : TEXT.YOUR_TURN, text: own || TEXT.TURN_KIND[kind] || "", kind };
		}
		if (stage === "ended") {
			const seat = winner.on ? winner.seat : Number(state.winner) || 0;
			return seat > 0 && isMe(seat) ? { mode: "win", text: TEXT.YOU_WON } : { mode: "watch", text: TEXT.YOU_OVER };
		}
		if (!me) return { mode: "watch", text: localId >= 0 ? (amJoining() ? TEXT.YOU_JOINING : TEXT.YOU_WATCH) : "" };
		if (!me.alive) {
			const r = act.result;
			if (stage === "result" && r && r.out.includes(me.seat)) return { mode: "out", text: TEXT.YOU_OUT_NOW };
			// Ausgeschiedene stimmen mit ab (Spare or Eliminate): Karte und Vorbereitung = GET READY, danach "You voted ..."
			if (stage === "card" && act.card && act.card.id === "vote") return { mode: "ready", word: TEXT.GET_READY, text: stripLead(act.card.you_others) || TEXT.YOU_READY };
			if (stage === "event" && event && !event.final) {
				if (involved) return { mode: "ready", word: TEXT.GET_READY, text: youify(stripLead(event.instruction_actor)) || TEXT.YOU_READY };
				if (event.id === "vote" && (memo.vote || memo.voteMissed)) return { mode: "out", text: memo.vote ? TEXT.YOU_VOTED(memo.vote) : TEXT.VOTE_MISSED };
			}
			return { mode: "out", text: TEXT.YOU_OUT };
		}
		switch (stage) {
			case "intro": return { mode: "watch", text: TEXT.YOU_WAIT };
			case "spin":
				if (spin.active && spin.victim > 0) {
					if (isMe(spin.victim)) return { mode: "danger", text: TEXT.YOU_STARE };
					// Zwei Gewaehlte (Duell, Split or Steal): der zweite ist auch dran, nie "Not you"
					return act.actors.some(isMe) ? { mode: "danger", text: TEXT.YOU_TOO } : { mode: "watch", text: TEXT.YOU_NOT_PICKED };
				}
				return { mode: "watch", text: TEXT.YOU_SPIN };
			case "skip":
				if (act.skip && isMe(act.skip.next)) return { mode: "danger", text: TEXT.YOU_PICKED };
				return act.actors.some(isMe) ? { mode: "danger", text: TEXT.YOU_TOO } : { mode: "watch", text: TEXT.YOU_SPIN };
			case "pop": {
				const seat = act.pick || Number(state.turn) || 0;
				if (isMe(seat)) return { mode: "danger", text: TEXT.YOU_PICKED };
				return act.actors.some(isMe) ? { mode: "danger", text: TEXT.YOU_TOO } : { mode: "watch", text: TEXT.YOU_NOT_PICKED };
			}
			case "card": {
				const c = act.card;
				if (c && c.actors.some(isMe)) {
					const text = stripLead(c.you_actor);
					if (PASSIVE[c.id]) return { mode: PASSIVE[c.id], text: text || TEXT.YOU_PICKED };
					return { mode: "ready", word: TEXT.GET_READY, text: text || TEXT.YOU_READY };
				}
				return { mode: "watch", text: (c && stripLead(c.you_others)) || TEXT.YOU_WATCH };
			}
			case "result": return { mode: "watch", text: TEXT.YOU_NEXT };
		}
		if (involved) return { mode: "ready", word: TEXT.GET_READY, text: youify(stripLead(event && event.instruction_actor)) || TEXT.YOU_READY };
		// Ergebnis steht fest (event.final): keine veralteten Hinweise mehr ("Watch out ...", "Jack aims at YOU ...")
		if (event && event.final) {
			const endangered = seatList(event.endangered);
			if (endangered.includes(me.seat)) return { mode: "win", text: TEXT.YOU_SURVIVED };
			if (endangered.length) return { mode: "watch", text: TEXT.YOU_EVENT_OVER };
		}
		// Revolver: du hast abgedrueckt, jetzt entscheidet die Trommel
		if (event && event.id === "revolver") {
			const d = event.data && typeof event.data === "object" ? event.data : {};
			const target = Number(d.target);
			if (Number(d.holder) === me.seat && target > 0 && target !== me.seat) return { mode: "watch", text: TEXT.YOU_PULLED(seatName(target)) };
		}
		const danger = dangerText(event, me);
		if (danger) return { mode: "danger", text: danger };
		// Schon entschieden: das sagen statt der Zeile von der Karte ("vote when the panel opens")
		if (event && event.id === "vote" && (memo.vote || memo.voteMissed)) return { mode: "watch", text: memo.vote ? TEXT.YOU_VOTED(memo.vote) : TEXT.VOTE_MISSED };
		if (event && event.id === "splitsteal" && memo.split) return { mode: "watch", text: TEXT.SPLIT_YOU(memo.split) };
		const c = act.card;
		const watch = c && event && c.id === event.id ? stripLead(c.you_others) : "";
		return { mode: "watch", text: watch || TEXT.YOU_WATCH };
	}

	// Breite fuer die Stage-Zeile (= max-width von .stage-inner, siehe style.css; schmale Bildschirme lassen der Liste rechts Platz)
	function stageWidth() {
		const share = window.innerWidth / Math.max(1, window.innerHeight) < 1.45 ? 0.56 : 0.78;
		return Math.min(rem(60), window.innerWidth * share) - rem(4.8);
	}

	function renderStage(me) {
		const header = $("event");
		if (place !== "match" || !state) {
			show("event", false);
			renderClock(null);
			return;
		}
		show("event", true);
		const stage = currentStage();
		const event = eventOf(state.event);
		const involved = !!(me && event && asArray(event.involved).map(Number).includes(me.seat));
		header.dataset.stage = stage;

		// (a)
		setText($("event-act"), eyebrowText(stage, event));

		// (c) – bei YOUR TURN / GET READY steht der grosse Hinweis an Stelle der Stage-Zeile
		const you = youLine(stage, event, me, involved);
		const plate = you.mode === "turn" || you.mode === "ready";
		renderTurn(plate ? you : null, event ? event.id : stage);
		header.classList.toggle("turn", you.mode === "turn");

		// (b) – auch unter dem grossen Hinweis aktuell halten (er kann jederzeit wieder verschwinden)
		show("stage", !plate);
		const line = stageLine(stage, event, involved);
		const detail = stageDetail(stage, event);
		let main = line.main;
		if (!main && banners.current && banners.current.main) main = banners.current.main;   // Server ohne Stage-Zeile
		if (!main && event) main = String(event.name || "");
		setStage(main, detail.text, detail.tone || line.tone || (you.mode === "danger" ? "danger" : ""), !plate);
		const youNode = $("you");
		const youShown = !plate && !!you.text;
		youNode.className = "mode-" + you.mode + (youShown ? "" : " hidden");
		if (youShown) setText($("you-text"), you.text);

		// (d)
		renderClock(clockSource(stage, you.mode));
		if (ringOwner === "choice" && choice && choice.kind === "target") updateRingTitle();
		updateStatusSlot();   // die Regie kann hoeher/flacher werden: Live-Anzeigen bleiben direkt darunter
	}

	// visible = false: Zeile liegt unter dem YOUR-TURN-Schild (versteckt) – Text aktuell halten, einpassen erst beim Zeigen
	function setStage(main, detail, tone, visible) {
		const strip = $("stage");
		["danger", "luck", "gold", "pumpkin"].forEach((t) => strip.classList.toggle(t, t === tone));
		const mainEl = $("stage-main");
		if (mainEl.textContent !== main) {
			mainEl.textContent = main;
			mainEl._fitted = false;
			if (visible) restartAnimation(strip, "swap");
		}
		if (visible && !mainEl._fitted) {
			fitTextCss(mainEl, stageWidth(), rem(1.25));
			mainEl._fitted = true;
		}
		const sub = $("stage-sub");
		setText(sub, detail);
		sub.classList.toggle("empty", !detail);
	}

	// Der grosse Hinweis. Sting + Auftritt, wenn dein Zug beginnt – nicht bei jeder Folgefrage desselben Zugs
	// (Messer: drei Tasten, Feuer: zehn Flammen), aber wieder, wenn der Revolver spaeter zu dir zurueckkommt.
	function renderTurn(you, key) {
		const node = $("turn");
		const now = performance.now();
		const prev = turnFx.mode;
		if (!you) {
			if (prev === "turn") turnFx.offAt = now;
			turnFx.mode = "";
			show("turn", false);
			return;
		}
		const wasHidden = node.classList.contains("hidden");
		show("turn", true);
		node.classList.toggle("ready", you.mode === "ready");
		setText($("turn-word"), you.word || TEXT.YOUR_TURN);
		const text = $("turn-text");
		if (text.textContent !== you.text) {
			text.textContent = you.text;
			fitTextCss(text, stageWidth() - rem(1), rem(1));   // das Schild hat etwas mehr Rand als das Band
		}
		if (you.mode !== prev) node.classList.remove("slam", "enter");   // Auftritt des alten Modus nicht weiterspielen
		if (you.mode === "turn" && prev !== "turn") {
			if (now - turnFx.offAt > TURN_GAP_MS || turnFx.key !== key) {
				Bus.Call("UiSound", "your_turn");
				restartAnimation(node, "slam");
				restartAnimation($("vignette"), "pulse");
			} else if (wasHidden) {
				restartAnimation(node, "enter");
			}
			turnFx.key = key;
		} else if (wasHidden) {
			restartAnimation(node, "enter");
		}
		if (prev === "turn" && you.mode !== "turn") turnFx.offAt = now;
		turnFx.mode = you.mode;
	}

	// (d) Woher die Restzeit kommt: eigene Abfrage > Server-Timer > Gluecksrad. Der Kuerbis hat keine (Zuendschnur geheim).
	function clockSource(stage, mode) {
		if (stage === "ended") return null;   // "Back to the graveyard in N" steht schon unten
		const now = performance.now();
		if (mode === "turn") {
			if (aim.active && aim.ends > now) return { key: "aim" + aim.ask, ends: aim.ends, total: aim.total };
			if (choice && choice.kind !== "pass" && choiceClock.ends > now) return { key: "ask" + choice.ask, ends: choiceClock.ends, total: choiceClock.total };
		}
		if (choice && choice.kind === "pass") return null;
		const left = timeLeft(state.timer, stateAt);
		if (left > 0.05) return { key: "state", ends: now + left * 1000, total: Number(state.timer.total) || left };
		if (stage === "spin" && spin.active && spin.ends > now) return { key: "spin", ends: spin.ends, total: spin.total };
		return null;
	}

	function renderClock(src) {
		const wick = $("wick");
		const fill = $("wick-fill");
		const secs = $("clock-secs");
		const now = performance.now();
		if (!src || src.ends - now <= 50) {
			if (clock.key) {
				clock.key = "";
				clearTimeout(wick._urgent);
				show("wick", false);
				stopCountdown(secs);
				secs.textContent = "";
				secs.classList.remove("urgent");
			}
			return;
		}
		if (clock.key === src.key && Math.abs(clock.ends - src.ends) < 250) return;   // laeuft schon
		clock.key = src.key;
		clock.ends = src.ends;
		const left = (src.ends - now) / 1000;
		show("wick", true);
		clearTimeout(wick._urgent);
		fill.classList.toggle("urgent", left <= URGENT_SECONDS);
		startFuse(fill, left, Math.max(left, Number(src.total) || left));
		if (left > URGENT_SECONDS) wick._urgent = setTimeout(() => fill.classList.add("urgent"), (left - URGENT_SECONDS) * 1000);
		startCountdown(left, secs);
	}

	// ------------------------------------------------------------ Revolver-Trommel

	// Kammern einmal aufbauen: Messinghuelse mit Zuendhuetchen, dazwischen Kehlen im Stahl
	function buildCylinder(total) {
		const rotor = $("cyl-rotor");
		rotor.textContent = "";
		const radius = total > 6 ? 33 : 30;
		const r = total > 8 ? 7.5 : total > 6 ? 9 : 11.5;
		for (let i = 0; i < total; i++) {
			const fluteAngle = (i + 0.5) * 360 / total;
			rotor.appendChild(svgEl("ellipse", { class: "cyl-flute", cx: 0, cy: -47.5, rx: 3.6, ry: 8.5, transform: `rotate(${fluteAngle.toFixed(2)})` }));
		}
		for (let i = 0; i < total; i++) {
			const a = (i * 360 / total - 90) * Math.PI / 180;
			const g = svgEl("g", { class: "chamber", transform: `translate(${(Math.cos(a) * radius).toFixed(2)} ${(Math.sin(a) * radius).toFixed(2)})` });
			g.appendChild(svgEl("circle", { class: "ch-bore", r: (r + 2).toFixed(2) }));
			g.appendChild(svgEl("circle", { class: "ch-case", r: r.toFixed(2) }));
			g.appendChild(svgEl("circle", { class: "ch-rim", r: (r * 0.78).toFixed(2) }));
			g.appendChild(svgEl("circle", { class: "ch-primer", r: (r * 0.34).toFixed(2) }));
			g.appendChild(svgEl("circle", { class: "ch-dent", r: (r * 0.13).toFixed(2) }));
			rotor.appendChild(g);
		}
		rotor.dataset.total = String(total);
	}

	// Chance des naechsten Abzugs (PROTOCOL, event.data revolver):
	//   load_extra (Standard): Jack laedt nach jedem Klick nach -> bullets IN chambers ("2 IN 6")
	//   klassisch:             eine Kugel                       -> 1 IN (chambers - spent)
	// fields: Felder eines Cues (chambers, bullets, spent), sonst gilt der State
	function revolverOdds(fields) {
		const data = eventData("revolver") || {};
		const pick = (key) => (fields && fields[key] !== undefined && fields[key] !== null ? fields[key] : data[key]);
		const chambers = Math.max(1, Math.min(12, Math.round(Number(pick("chambers")) || 6)));
		const bullets = Math.max(1, Math.round(Number(pick("bullets")) || 1));
		const extra = data.load_extra !== undefined ? data.load_extra === true : bullets > 1;
		if (extra) return { n: Math.min(bullets, chambers), of: chambers, extra: true, bullets };
		const spent = Math.max(0, Math.round(Number(pick("spent")) || 0));
		return { n: 1, of: Math.max(1, chambers - spent), extra: false, bullets: 1 };
	}

	// Reihenfolge, in der nachgeladene Kugeln in der Trommel erscheinen (sieht zufaellig aus, bleibt stabil)
	function scatter(total) {
		const half = Math.floor(total / 2);
		const out = [];
		for (let i = 0; i < half; i++) out.push(i, i + half);
		if (total % 2) out.push(total - 1);
		return out;
	}

	function renderCylinder() {
		const data = eventData("revolver");
		if (state.phase !== "PLAYING" || !data || spin.active) {
			show("cylinder", false);
			return;
		}
		show("cylinder", true);

		const rotor = $("cyl-rotor");
		const total = Math.max(1, Math.min(12, Math.round(Number(data.chambers) || 6)));
		const spent = Math.max(0, Math.round(Number(data.spent) || 0));
		const chance = revolverOdds(null);
		if (rotor.dataset.total !== String(total)) buildCylinder(total);

		const chambers = rotor.querySelectorAll(".chamber");
		if (chance.extra) {
			// Nachladen: so viele Kammern geladen wie Kugeln; die Trommel wird nach jedem Klick gedreht
			const loaded = new Set(scatter(total).slice(0, chance.n));
			chambers.forEach((c, i) => c.setAttribute("class", "chamber " + (loaded.has(i) ? "loaded" : "empty")));
			rotor.style.transform = `rotate(${spent * (720 + 2 * 360 / total)}deg)`;
		} else {
			// klassisch: abgefeuerte Kammern verrusst, die naechste steht oben unter dem Hahn
			chambers.forEach((c, i) => c.setAttribute("class", "chamber" + (i < spent ? " spent" : " live") + (i === spent ? " next" : "")));
			rotor.style.transform = `rotate(${-Math.min(spent, total) * 360 / total}deg)`;
		}
		$("cylinder").classList.toggle("extra", chance.extra);

		const odds = $("cyl-odds");
		odds.textContent = TEXT.ODDS(chance);
		odds.classList.toggle("danger", chance.n * 2 >= chance.of);

		// Kette: wer den Revolver hat und auf wen er zielt
		const holderBox = $("cyl-holder");
		holderBox.textContent = "";
		const holder = Number(data.holder);
		const target = Number(data.target);
		if (Number.isFinite(holder) && holder > 0) {
			holderBox.appendChild(el("span", "ch-label", TEXT.HELD_BY));
			holderBox.appendChild(el("span", "ch-name" + (isMe(holder) ? " me" : ""), who(holder)));
			if (Number.isFinite(target) && target > 0) {
				holderBox.appendChild(el("span", "ch-label", TEXT.AIMED_AT));
				holderBox.appendChild(el("span", "ch-name ch-target" + (isMe(target) ? " me" : ""), who(target)));
			}
		}
	}

	// ------------------------------------------------------------ Schiessbude (drei Blechenten)

	const DUCK_BODY = "M6 44 C4 34 10 30 18 33 L30 38 C40 30 56 28 66 32 C64 22 70 12 80 12 C90 12 95 20 92 27 L99 30 L91 34 C88 40 84 44 82 48 C88 54 86 64 72 66 L28 66 C14 66 6 58 6 44 Z";
	const DUCK_WING = "M32 45 C42 37 57 39 64 46 C56 55 41 55 32 45 Z";

	function makeDuck(seat, middle) {
		const duck = el("div", "duck" + (middle ? " big" : ""));
		duck.dataset.seat = String(seat);
		const fig = el("div", "duck-fig");
		const svg = svgEl("svg", { viewBox: "0 0 100 78", "aria-hidden": "true" });
		svg.appendChild(svgEl("rect", { class: "d-stick", x: 45, y: 64, width: 10, height: 14, rx: 1 }));
		svg.appendChild(svgEl("path", { class: "d-body", d: DUCK_BODY }));
		svg.appendChild(svgEl("path", { class: "d-wing", d: DUCK_WING }));
		svg.appendChild(svgEl("circle", { class: "d-eye", cx: 82, cy: 21, r: 2.8 }));
		fig.appendChild(svg);
		fig.appendChild(el("i", "duck-cross"));
		duck.appendChild(fig);
		duck.appendChild(el("div", "duck-name"));
		duck.appendChild(el("div", "duck-tag"));
		return duck;
	}

	function renderGallery() {
		const data = eventData("gallery");
		const targets = data ? asArray(data.targets).map(Number).filter((n) => Number.isFinite(n) && n > 0).slice(0, 3) : [];
		if (state.phase !== "PLAYING" || !targets.length || spin.active) {
			show("gallery", false);
			return;
		}
		show("gallery", true);
		const box = $("gal-ducks");
		const sig = targets.join(",");
		if (box.dataset.sig !== sig) {
			box.textContent = "";
			targets.forEach((seat, i) => box.appendChild(makeDuck(seat, targets.length === 3 && i === 1)));
			box.dataset.sig = sig;
		}
		const aim = Number(data.aim);
		Array.from(box.children).forEach((duck) => {
			const seat = Number(duck.dataset.seat);
			const s = seatByIndex(seat);
			const shot = memo.shots.get(seat);
			const dead = !!(s && !s.alive);
			duck.classList.toggle("aim", !dead && seat === aim);
			duck.classList.toggle("hit", dead);
			duck.classList.toggle("safe", !dead && shot === "safety");
			duck.classList.toggle("deflect", !dead && shot === "ricochet");
			duck.classList.toggle("me", isMe(seat));
			const name = duck.querySelector(".duck-name");
			const label = who(seat);
			if (name.textContent !== label) name.textContent = label;
			const tag = duck.querySelector(".duck-tag");
			const tagText = dead ? TEXT.DEAD : shot === "safety" ? "Safe" : shot === "ricochet" ? "Ricochet" : "";
			if (tag.textContent !== tagText) tag.textContent = tagText;
		});
	}

	// ------------------------------------------------------------ Zwei gegeneinander (Split or Steal, Quick Draw)

	function renderVersus() {
		const event = state && state.event;
		const id = event ? event.id : null;
		let a = 0;
		let b = 0;
		let states = null;
		if (id === "splitsteal" && event.data) {
			a = Number(event.data.a);
			b = Number(event.data.b);
			states = [!!event.data.locked_a, !!event.data.locked_b];
		} else if (id === "duel") {
			const actors = asArray(event.actors).map(Number);
			a = actors[0];
			b = actors[1];
		}
		// waehrend der eigenen Wahl zeigt das Panel dasselbe
		const busy = (choice && choice.kind === "splitsteal") || isShown("split") || isShown("reveal");
		if (!state || state.phase !== "PLAYING" || !(a > 0) || !(b > 0) || busy || spin.active) {
			show("versus", false);
			return;
		}
		show("versus", true);
		const box = $("versus");
		box.dataset.event = id;
		[[a, "vs-a", 0], [b, "vs-b", 1]].forEach(([seat, nodeId, k]) => {
			const side = $(nodeId);
			side.querySelector(".vs-name").textContent = who(seat);
			side.classList.toggle("me", isMe(seat));
			const st = side.querySelector(".vs-state");
			if (states) {
				st.textContent = states[k] ? TEXT.DECIDED : TEXT.THINKING;
				side.classList.toggle("locked", states[k]);
			} else {
				st.textContent = "";
				side.classList.remove("locked");
			}
		});
	}

	// Oben wird gestapelt: Regie (Stage-Zeile, YOU, Zeit) -> Live-Anzeige (Trommel, Enten, Zaehlung, Duellanten). Die
	// Live-Anzeige steht direkt unter der Regie, nie darauf. offsetTop/-Height statt getBoundingClientRect:
	// Einblend-Animationen (transform) verfaelschen die Messung nicht.
	function updateStatusSlot() {
		const head = $("event");
		const bottom = head.classList.contains("hidden") ? 0 : head.offsetTop + head.offsetHeight;
		const statusTop = Math.round(Math.max(window.innerHeight * 0.16, bottom + rem(0.7))) + "px";
		["cylinder", "gallery", "versus", "vote"].forEach((id) => {
			const node = $(id);
			const slot = id !== "vote" || node.classList.contains("watch");   // die grosse Abstimmung steht in der Mitte
			const top = slot ? statusTop : "";
			if (node.style.top !== top) node.style.top = top;
		});
	}

	// ------------------------------------------------------------ Liste rechts

	// Eine Zeile pro Platz. Zeilen bleiben bestehen (keine Neuerzeugung bei jedem State),
	// damit Animationen (Gluecksrad, Tod) nicht abbrechen.
	// Bild in der Spielerliste: Steam-Profilbild (nur steam-avatar://<Ziffern>), Clown-Portraet fuer Bots, sonst Ersatz.
	// Nie eine beliebige Adresse vom Server uebernehmen (SICHERHEIT wie bei den Kartenbildern).
	const AVATAR_URL = /^steam-avatar:\/\/\d{1,25}$/;
	const GUEST_PIC = "img/portraits/guest.png";
	function seatPic(s) {
		if (typeof s.avatar === "string" && AVATAR_URL.test(s.avatar)) return s.avatar;
		const n = Number(s.portrait);
		if (Number.isInteger(n) && n >= 1 && n <= 12) return `img/portraits/bot${String(n).padStart(2, "0")}.png`;
		return GUEST_PIC;
	}

	function makeRow(seat) {
		const li = el("li", "seat");
		li.dataset.seat = String(seat);
		const stub = el("span", "stub");
		const pic = document.createElement("img");
		pic.className = "pic";
		pic.alt = "";
		pic.onerror = () => { if (!pic.src.endsWith(GUEST_PIC)) pic.src = GUEST_PIC; };   // Steam-Bild nicht ladbar
		stub.appendChild(pic);
		stub.appendChild(el("span", "candle"));
		stub.appendChild(el("span", "cross"));
		const name = el("span", "name");
		const text = el("span", "txt");
		name.appendChild(text);
		const mark = el("span", "mark");
		const hold = el("span", "hold");
		const cards = el("span", "cards");
		li.appendChild(stub);
		li.appendChild(name);
		li.appendChild(el("span", "tag", TEXT.YOU));   // ausserhalb des Namens: wird nie abgeschnitten
		li.appendChild(hold);
		li.appendChild(mark);
		li.appendChild(cards);
		return { li, text, cards, pic, picSrc: "", alive: true, cardCount: -1 };
	}

	function renderSeats(me) {
		const seats = asArray(state.seats);
		const circle = $("circle");
		const list = $("seats");
		if (rowsMatch !== state.match) {
			rows.clear();
			diedAt.clear();
			list.textContent = "";
			rowsMatch = state.match;
		}
		if (seats.length === 0) {
			show("circle", false);
			return;
		}
		show("circle", true);
		circle.classList.toggle("many", seats.length > LIST_COMPACT);
		circle.style.setProperty("--rows", String(seats.length));
		// Weniger auf einmal: waehrend Jack dreht und zeigt, gehoert der Blick dem Zelt (PROTOCOL "Klarheit")
		circle.classList.toggle("rest", spin.active || ["intro", "spin", "skip", "pop"].includes(currentStage()));

		const now = performance.now();
		const event = state.event;
		const data = event && event.data && typeof event.data === "object" ? event.data : null;
		const target = data ? Number(data.target) : NaN;
		const aimed = data ? Number(data.aim) : NaN;
		const aiming = memo.aiming && event && event.id === "revolver" ? memo.aiming.seat : NaN;
		const holder = data && (event.id === "revolver" || event.id === "pumpkin") ? Number(data.holder) : NaN;
		const showTurn = state.phase === "PLAYING" && !spin.active;
		const recent = (s) => !s.alive && now - (diedAt.has(s.seat) ? diedAt.get(s.seat) : -1e9) < DEATH_REORDER_MS;
		const present = new Set();
		let alive = 0;

		seats.forEach((s) => {
			present.add(s.seat);
			let row = rows.get(s.seat);
			if (!row) {
				row = makeRow(s.seat);
				row.alive = !!s.alive;
				rows.set(s.seat, row);
			}
			if (row.alive && !s.alive) diedAt.set(s.seat, now);
			row.alive = !!s.alive;
			if (s.alive) alive++;

			const name = String(s.name);
			if (row.text.textContent !== name) row.text.textContent = name;
			const src = seatPic(s);
			if (row.picSrc !== src) {   // nur bei Aenderung (z. B. Nachruecker uebernimmt einen Bot)
				row.picSrc = src;
				row.pic.src = src;
			}
			const li = row.li;
			li.classList.toggle("dead", !s.alive);
			li.classList.toggle("just-died", recent(s));
			li.classList.toggle("turn", showTurn && s.alive && s.seat === state.turn);
			li.classList.toggle("you", !!(me && me.seat === s.seat));
			li.classList.toggle("aimed", !!s.alive && (s.seat === target || s.seat === aimed || s.seat === aiming));
			const holds = showTurn && !!s.alive && s.seat === holder;
			li.classList.toggle("holds", holds);
			if (holds) li.dataset.holds = event.id; else delete li.dataset.holds;

			const count = Math.max(0, Math.min(Number(s.cards) || 0, MAX_HAND));
			if (row.cardCount !== count) {
				row.cards.textContent = "";
				row.cards.style.setProperty("--n", String(count));
				for (let i = 0; i < count; i++) {
					const pip = el("i");
					pip.style.setProperty("--k", String(i));
					row.cards.appendChild(pip);
				}
				row.cardCount = count;
			}
		});
		rows.forEach((row, seat) => {
			if (!present.has(seat)) {
				row.li.remove();
				rows.delete(seat);
			}
		});

		// Lebende (und gerade Gestorbene) zuerst, damit bei 32 Plaetzen die wichtigen oben stehen
		const order = seats.slice().sort((a, b) => ((b.alive || recent(b)) - (a.alive || recent(a))) || (a.seat - b.seat));
		order.forEach((s, i) => {
			const li = rows.get(s.seat).li;
			if (list.children[i] !== li) list.insertBefore(li, list.children[i] || null);
		});
		updateSpinMarks();

		if (seats.some(recent)) {
			cancel("reorder");
			after("reorder", DEATH_REORDER_MS + 40, () => {
				if (place === "match" && state) render();
			});
		}
		$("circle-count").textContent = TEXT.ALIVE(alive, seats.length);
	}

	function updateSpinMarks() {
		rows.forEach((row, seat) => {
			row.li.classList.toggle("spin-lit", spin.active && seat === spin.lit && seat !== spin.victim);
			row.li.classList.toggle("spin-victim", spin.active && seat === spin.victim);
		});
	}

	function highlightSeat(index) {
		const row = rows.get(Number(index));
		if (row) restartAnimation(row.li, "bump");
	}

	// Zeile kurz aufleuchten lassen (Karte bekommen / gespielt)
	function flashRow(index, className) {
		const row = rows.get(Number(index));
		if (!row) return;
		restartAnimation(row.li, className);
		after("row-" + className + index, 1300, () => row.li.classList.remove(className));
	}

	// Platz sofort als tot zeigen (der naechste State bestaetigt es)
	function markDead(index) {
		const s = seatByIndex(Number(index));
		if (s && s.alive) {
			s.alive = false;
			if (place === "match") render();
		}
	}

	function renderMatchLobby(me) {
		const box = $("lobby");
		const text = $("lobby-text");
		const sub = $("lobby-sub");
		const note = $("lobby-note");
		const left = timeLeft(state.timer, stateAt);
		const ended = state.phase === "ENDED" && left > 0;
		if (!ended) stopCountdown(sub);
		sub.classList.toggle("big", !!ended);
		sub.classList.remove("urgent");
		note.textContent = "";
		box.classList.remove("ghost");

		if (ended) {
			show("lobby", true);
			text.textContent = TEXT.NEXT_IN;
			startCountdown(left, sub);
		} else if (state.phase !== "ENDED" && !me && amJoining()) {
			// Nachruecker: schaut zu, bis er zu Beginn der naechsten Runde einen Bot-Platz uebernimmt
			show("lobby", true);
			text.textContent = TEXT.JOINING_TITLE;
			sub.textContent = TEXT.JOINING_SUB;
		} else if (state.phase !== "ENDED" && localId >= 0 && (!me || !me.alive)) {   // vor Init: noch unbekannt, wer du bist
			// Zuschauer; waehrend der eigenen Abstimmung (auch Tote stimmen ab) stoert der Satz nur
			show("lobby", !(choice && choice.kind === "vote"));
			box.classList.add("ghost");
			text.textContent = "";
			sub.textContent = TEXT.SPECTATING;
		} else {
			show("lobby", false);
		}
	}

	// ------------------------------------------------------------ Jack (Schreibmaschine)

	function typewriter(group, typedEl, restEl, text, speed, onDone) {
		cancel(group);
		const chars = Array.from(String(text));
		let i = 0;
		typedEl.textContent = "";
		restEl.textContent = chars.join("");
		if (chars.length === 0) {
			if (onDone) onDone();
			return;
		}
		const step = () => {
			i++;
			typedEl.textContent = chars.slice(0, i).join("");
			restEl.textContent = chars.slice(i).join("");
			if (i >= chars.length) {
				if (onDone) onDone();
				return;
			}
			const c = chars[i - 1];
			const next = chars[i];
			let delay = speed;
			if (".!?…".includes(c)) delay = next === " " ? speed * 9 : speed * 4;
			else if (",;:".includes(c)) delay = speed * 5;
			after(group, delay, step);
		};
		after(group, speed, step);
	}

	function say(text) {
		const box = $("jack");
		const line = $("jack-text");
		show("jack", true);
		box.classList.remove("fading");
		box.classList.add("typing");
		restartAnimation(line, "enter");
		typewriter("say", line.querySelector(".typed"), line.querySelector(".rest"), text, TYPE_MS, () => {
			box.classList.remove("typing");
			after("say", Math.max(SAY_HOLD_MS, text.length * 45), () => box.classList.add("fading"));
		});
	}

	// ------------------------------------------------------------ Effekte

	// Grosses Wort in der Mitte. prio: 0 = Fx (BANG, *click* ...), 2 = Cue (SKIP!, BOOM!, DRAW! ...).
	// Ein Cue-Wort wird kurz nicht von einem Fx-Wort ueberschrieben (Bombe: BOOM! statt BURNED).
	// Cue-Woerter (prio 2) liegen ueber den Abfrage-Panels: sie sind die Aufloesung (BOOM!, DEFUSED!, DRAW! ...).
	function word(text, kind, prio) {
		const p = prio || 0;
		const now = performance.now();
		if (p < wordLock.prio && now < wordLock.until) return;
		wordLock = { prio: p, until: now + WORD_LOCK_MS };
		const node = $("word");
		node.textContent = text;
		node.className = kind + (p >= 2 ? " cue" : "");
		restartAnimation(node, "show");
	}

	function flash(kind) {
		const node = $("flash");
		node.className = "";
		void node.offsetWidth;
		node.className = kind;
	}

	function shake(kind) {
		document.body.classList.remove("shake", "shake-hard");
		restartAnimation(document.body, kind);
	}

	// Ersatz fuer Server ohne Show-Cues: kurz warten, ob doch ein Cue kommt
	function fallback(fn) {
		after("fallback", FALLBACK_MS, () => {
			if (!cuesSeen) fn();
		});
	}

	function fx(kind, seat) {
		if (place !== "match") return;
		switch (kind) {
			case "spin":
				fallback(() => { if (!spin.active) play({ action: "spin", duration: 2, hold: 0, ticks: [] }); });
				break;
			case "chosen":
				highlightSeat(seat);
				fallback(() => play({ action: "pop", seat, me: isMe(seat) }));
				break;
			case "start":
				fallback(() => play({ action: "intro", duration: 3 }));
				break;
			case "death":
				markDead(seat);
				restartAnimation($("vignette"), "pulse");
				fallback(() => play({ action: "death", seat }));
				break;
			case "winner":
				play({ action: "winner", seat });   // gleiches Plakat wie der Show-Cue, doppelt schadet nicht
				break;
			case "aim":
			case "knife_raise":
				highlightSeat(seat);
				break;
			case "click":
				word("*click*", "click");
				break;
			case "bang":
				flash("bang");
				shake("shake");
				word("BANG!", "bang");
				break;
			case "safety":
				flash("safety");
				word("LUCKY!", "safety");
				break;
			case "dodge":
				word("DODGED", "dodge");
				break;
			case "block":
				word("BLOCKED", "dodge");
				break;
			case "stab":
				flash("bang");
				shake("shake");
				word("STAB!", "bang");
				break;
			case "fire":
				flash("fire");
				word("FWOOSH", "fire");
				break;
			case "burn":
				flash("fire");
				shake("shake");
				word("BURNED", "fire");
				break;
			case "extinguish":
				word("PUT OUT", "dodge");
				break;
			case "qte_ok":
				restartAnimation($("qte"), "good");
				after("qte-good", 450, () => $("qte").classList.remove("good"));
				break;
		}
	}

	// ------------------------------------------------------------ Ansagen (Detail-Zeile der Regie, mit Warteschlange)

	// Es gibt nur noch EINE Stage-Zeile (oben). Ansagen zu Cues fuellen ihre Detail-Zeile und faerben sie kurz.
	// spec: { detail, kicker, main, sub, tone, ms, key, unless }
	//   detail  Zeile unter der Stage-Zeile (fehlt sie: "kicker · sub")
	//   main    nur Ersatz, solange der Server (noch) keine Stage-Zeile schickt
	//   tone    "" | "danger" | "luck" | "gold" | "pumpkin"
	//   key     eine neue Ansage mit gleichem key loest die alte sofort ab (Revolver-Kette)
	//   unless  Abfrage-Art: ist sie offen, entfaellt die Ansage (das Panel sagt dasselbe)
	function banner(spec) {
		if (place !== "match") return;
		spec.ms = spec.ms || BANNER_MS;
		if (spec.key) {
			banners.queue = banners.queue.filter((b) => b.key !== spec.key);
			if (banners.current && banners.current.key === spec.key) {
				banners.queue.unshift(spec);
				nextBanner();
				return;
			}
		}
		banners.queue.push(spec);
		while (banners.queue.length > BANNER_QUEUE) banners.queue.shift();
		if (banners.current) scheduleBanner();
		else nextBanner();
	}

	function scheduleBanner() {
		cancel("banner");
		if (!banners.current) return;
		const now = performance.now();
		let end = banners.shownAt + banners.current.ms;
		if (banners.queue.length) end = Math.min(end, Math.max(banners.shownAt + BANNER_MIN_MS, now));
		after("banner", end - now, nextBanner);
	}

	function nextBanner() {
		cancel("banner");
		banners.current = null;
		let spec = null;
		while (banners.queue.length) {
			const next = banners.queue.shift();
			if (next.unless && choice && choice.kind === next.unless) continue;
			spec = next;
			break;
		}
		if (spec) {
			banners.current = spec;
			banners.shownAt = performance.now();
			scheduleBanner();
		}
		if (place === "match" && state) renderStage(mySeat());
	}

	// Ansage passt nicht mehr (eigene Abfrage dieser Art ist jetzt offen)
	function dropBanners(kind) {
		banners.queue = banners.queue.filter((b) => b.unless !== kind);
		if (banners.current && banners.current.unless === kind) nextBanner();
	}

	// Ansagen einer Kette (key) sind ueberholt, ohne dass eine neue kommt (Galerie: Jack legt auf die naechste Ente an)
	function dropBannerKey(key) {
		banners.queue = banners.queue.filter((b) => b.key !== key);
		if (banners.current && banners.current.key === key) nextBanner();
	}

	function clearBanners() {
		cancel("banner");
		const had = !!banners.current;
		banners.queue = [];
		banners.current = null;
		if (had && place === "match" && state) renderStage(mySeat());
	}

	// ------------------------------------------------------------ Meldungen unten links (Karten)

	// parts: [[text, className], ...] – className leer = einfacher Text
	function toast(spec) {
		if (place !== "match") return;
		const list = $("toasts");
		const li = el("li", "toast" + (spec.tone ? " " + spec.tone : ""));
		if (spec.art) {
			const thumb = el("span", "thumb");
			thumb.appendChild(cardImg(spec.art));
			li.appendChild(thumb);
		}
		const p = el("p", "toast-text");
		spec.parts.forEach(([text, cls]) => {
			p.appendChild(cls ? el("span", cls, text) : document.createTextNode(text));
		});
		li.appendChild(p);
		list.appendChild(li);
		while (list.children.length > TOAST_MAX) list.firstElementChild.remove();
		after("toast", TOAST_MS, () => {
			li.classList.add("leave");
			after("toast", 450, () => li.remove());
		});
	}

	function clearToasts() {
		cancel("toast");
		$("toasts").textContent = "";
	}

	// Name als Teil einer Meldung (eigener Platz hervorgehoben)
	function namePart(index, given, you) {
		return isMe(index) ? [you || TEXT.YOU_LOWER, "who me"] : [seatName(index, given), "who"];
	}

	// ------------------------------------------------------------ Show-Cues

	const CENTER = ["pop", "card", "reveal", "stamp", "winner", "result"];

	function hideCue(name) {
		cancel(name);
		const node = $(name);
		node.classList.add("hidden");
		node.classList.remove("show", "away");
		if (name === "winner") {
			winner.on = false;
			winner.seat = 0;
		}
		if (name === "reveal" && place === "match" && state) renderVersus();
	}

	// Mitte gehoert immer nur einem Auftritt
	function claimCenter(name) {
		CENTER.forEach((other) => {
			if (other !== name) hideCue(other);
		});
	}

	function hideIntro() {
		cancel("intro");
		cancel("intro-type");
		const node = $("intro");
		node.classList.add("hidden");
		node.classList.remove("show", "lit", "open", "how");
		document.body.classList.remove("intro-on");
	}

	function hideAllCues() {
		stopSpin();
		CENTER.forEach(hideCue);
		hideIntro();
		clearBanners();
	}

	// Cue vom Server: ab jetzt keine Ersatz-Auftritte mehr aus Fx
	function cue(data) {
		if (!data || typeof data !== "object") return;
		cuesSeen = true;
		cancel("fallback");
		play(data);
	}

	function play(data) {
		const action = String(data.action || "");
		// Ein neuer Auftritt beendet ein laufendes Gluecksrad (Karten-Meldungen nicht: die kommen jederzeit)
		if (!KEEP_SPIN.has(action)) stopSpin();
		if (EVENT_CUES.has(action)) setAct("event");
		if (SILENT_CUES.has(action)) {
			if (place === "match" && state) renderStage(mySeat());
			return;
		}
		switch (action) {
			case "intro": cueIntro(data); break;
			case "spin": cueSpin(data); break;
			case "pop": cuePop(data); break;
			case "card": cueCard(data); break;
			case "death": cueStamp("death", data); break;
			case "survive": cueStamp("survive", data); break;
			case "winner": cueWinner(data); break;
			case "round_end": cueRoundEnd(data); break;
			case "skip": cueSkip(data); break;
			case "revolver_give": cueRevolverGive(data); break;
			case "revolver_aiming": cueRevolverAiming(data); break;
			case "revolver_aim": cueRevolverAim(data); break;
			case "revolver_shot": cueRevolverShot(data); break;
			case "revolver_pass": cueRevolverPass(data); break;
			case "ricochet": cueRicochet(data); break;
			case "angry_aim": cueAngryAim(data); break;
			case "vote_start": cueVoteStart(data); break;
			case "vote_result": cueVoteResult(data); break;
			case "pumpkin_start": cuePumpkinStart(data); break;
			case "pumpkin_pass": cuePumpkinPass(data); break;
			case "pumpkin_boom": cuePumpkinBoom(data); break;
			case "splitsteal_start": cueSplitStart(data); break;
			case "splitsteal_result": cueSplitResult(data); break;
			case "bomb_start": cueBombStart(data); break;
			case "bomb_result": cueBombResult(data); break;
			case "duel_start": cueDuelStart(data); break;
			case "duel_draw": cueDuelDraw(data); break;
			case "duel_result": cueDuelResult(data); break;
			case "deal": cueDeal(data); break;
			case "card_gain": cueCardGain(data); break;
			case "card_play": cueCardPlay(data); break;
			case "card_trigger": cueCardTrigger(data); break;
			case "seat_taken": cueSeatTaken(data); break;
			case "finale": cueFinale(data); break;
			case "you_joined": cueYouJoined(data); break;
			default: console.warn("[DeathBox] Unknown show cue", action);
		}
	}

	// Vorhang, "Ladies and gentlemen...", Leuchttitel, "How to play", Vorhang auf
	function cueIntro(data) {
		const duration = num(data.duration, 1.5, 20, 4) * 1000;
		hideAllCues();
		actCount = 0;
		act.pick = 0;
		act.actors = [];
		act.skip = null;
		act.card = null;
		act.result = null;
		setAct("intro");
		const node = $("intro");
		node.classList.remove("hidden", "lit", "open", "how");
		restartAnimation(node, "show");
		document.body.classList.add("intro-on");   // Jacks Untertitel liegt waehrenddessen ueber dem Vorhang
		const small = $("intro-small");
		small.querySelector(".typed").textContent = "";
		small.querySelector(".rest").textContent = TEXT.INTRO_SMALL;
		after("intro", 250, () => {
			typewriter("intro-type", small.querySelector(".typed"), small.querySelector(".rest"), TEXT.INTRO_SMALL, 40);
		});
		const litAt = Math.min(duration * 0.32, 1500);
		// Vorhang auf kurz vor Jacks POP (pop_at), damit man ihn aus der Kiste springen sieht; sonst kurz vor Schluss
		const popAt = num(data.pop_at, 0, 20, 0) * 1000;
		const openAt = popAt > 0 ? Math.max(litAt + 700, Math.min(duration - 400, popAt - 800)) : Math.max(litAt + 700, duration - 900);
		after("intro", litAt, () => node.classList.add("lit"));
		// Spielregeln in vier Zeilen, solange der Vorhang zu ist (nur wenn genug Zeit zum Lesen bleibt)
		if (openAt - litAt > 4000) after("intro", litAt + 900, () => node.classList.add("how"));
		after("intro", openAt, () => node.classList.add("open"));
		after("intro", duration, hideIntro);
		if (place === "match" && state) render();
	}

	function cueSpin(data) {
		const ticks = asArray(data.ticks)
			.map((t) => ({ t: Number(t && t.t), seat: Number(t && t.seat) }))
			.filter((t) => Number.isFinite(t.t) && Number.isFinite(t.seat) && t.t >= 0 && t.t < 30)
			.sort((a, b) => a.t - b.t);
		const lastT = ticks.length ? ticks[ticks.length - 1].t : num(data.duration, 0, 20, 2);
		const hold = num(data.hold, 0, 10, 1);

		// Neue Runde: Rundenergebnis, Pick und Karte der letzten Runde sind vorbei
		hideCue("result");
		act.pick = 0;
		act.actors = seatList(data.actors);
		act.skip = null;
		act.card = null;
		memo.aiming = null;
		setAct("spin");
		spin.active = true;
		spin.lit = 0;
		spin.victim = 0;
		spin.total = Math.max(lastT, num(data.duration, 0, 20, lastT)) + hold;
		spin.ends = performance.now() + spin.total * 1000;
		$("spin-name").textContent = "";
		$("spin-name").classList.remove("victim", "flip");
		$("spin").classList.remove("hold");
		show("spin", true);
		ticks.forEach((tick, i) => {
			after("spin", tick.t * 1000, () => spinTick(tick.seat, i === ticks.length - 1));
		});
		// Sicherheitsnetz, falls kein "pop" folgt
		after("spin", (lastT + hold + 1.5) * 1000, stopSpin);
		if (place === "match" && state) render();
	}

	function spinTick(seat, last) {
		spin.lit = seat;
		spin.alt = !spin.alt;
		if (last) spin.victim = seat;
		updateSpinMarks();
		const nameEl = $("spin-name");
		nameEl.textContent = seatName(seat);
		restartAnimation(nameEl, "flip");
		$("spin-sign").classList.toggle("alt", spin.alt);
		if (last) {
			nameEl.classList.add("victim");
			$("spin").classList.add("hold");
			$("vignette").classList.add("heartbeat");
			if (place === "match" && state) renderStage(mySeat());
		}
	}

	function stopSpin() {
		cancel("spin");
		if (!spin.active) return;
		spin.active = false;
		spin.lit = 0;
		spin.victim = 0;
		$("vignette").classList.remove("heartbeat");
		$("spin-name").classList.remove("victim", "flip");
		$("spin").classList.remove("hold");
		show("spin", false);
		updateSpinMarks();
		if (place === "match" && state) render();
	}

	function cuePop(data) {
		const seat = Number(data.seat);
		act.actors = seatList(data.actors);
		if (seat > 0 && !act.actors.includes(seat)) act.actors.unshift(seat);
		const me = data.me === true || act.actors.some(isMe);
		claimCenter("pop");
		lastPick = seat;
		act.pick = seat;
		setAct("pop");
		const node = $("pop");
		const nameEl = $("pop-name");
		$("pop-small").textContent = TEXT.POP_SMALL;
		nameEl.textContent = act.actors.length > 1 ? joinNames(act.actors) : (me ? TEXT.YOU : seatName(seat, data.name));
		node.classList.toggle("me", me);
		node.classList.remove("hidden");
		fitText(nameEl, window.innerWidth * 0.88, rem(me ? 11 : 9), rem(3.2));
		restartAnimation(node, "show");
		highlightSeat(seat);
		restartAnimation($("vignette"), "pulse");
		if (me) {
			flash("red");
			shake("shake-hard");
		}
		after("pop", POP_MS, () => hideCue("pop"));
		if (place === "match" && state) render();
	}

	// Event-Karte: Name, wer (who), wie es geht (how, 2–3 Punkte) und was DU tust (you_actor / you_others).
	// Fehlen die Felder (aelterer Server), stehen Name, Tagline und Regel da wie bisher.
	function cueCard(data) {
		const duration = num(data.duration, 1, 15, 3) * 1000;
		claimCenter("card");
		resetMemo(memo.id);   // neues Event kuendigt sich an: alte Merkzettel weg
		const round = Number(data.round);
		actCount = Number.isFinite(round) && round > 0 ? Math.floor(round) : actCount + 1;
		const seat = Number(data.seat) || 0;
		const actors = asArray(data.actors).map(Number).filter((n) => Number.isFinite(n) && n > 0);
		if (!actors.length && seat > 0) actors.push(seat);
		const seat2 = Number(data.seat2);
		if (seat2 > 0 && !actors.includes(seat2)) actors.push(seat2);
		const mine = actors.some(isMe);
		const whoText = youify(typeof data.who === "string" && data.who ? data.who : actors.map((s) => seatName(s)).filter(Boolean).join(" & "));
		let how = asArray(data.how).map((h) => youify(String(h || "").trim())).filter(Boolean).slice(0, 3);
		if (!how.length && data.rules) how = [String(data.rules)];
		const id = String(data.event || "");
		act.card = {
			id, name: String(data.name || ""), seat, actors, who: whoText,
			you_actor: String(data.you_actor || ""), you_others: String(data.you_others || ""),
		};
		setAct("card");

		const node = $("card");
		$("card-act").textContent = TEXT.ROUND(actCount);
		const name = $("card-name");
		name.textContent = String(data.name || "");
		$("card-tagline").textContent = String(data.tagline || "");
		$("card-who").textContent = whoText;
		const list = $("card-how");
		list.textContent = "";
		how.forEach((line) => list.appendChild(el("li", "", line)));
		list.classList.toggle("hidden", !how.length);
		const you = $("card-you");
		const youText = String((mine ? data.you_actor : data.you_others) || "");
		you.textContent = youText;
		you.classList.toggle("hidden", !youText);
		you.classList.toggle("act", mine);
		node.dataset.event = id;
		node.classList.toggle("repeat", data.first === false);
		node.classList.toggle("mine", mine);
		node.classList.remove("hidden", "away");
		fitText(name, rem(31), rem(3.5), rem(2));
		restartAnimation(node, "show");
		after("card", duration, () => {
			node.classList.add("away");
			after("card", CARD_AWAY_MS, () => hideCue("card"));
		});
		if (place === "match" && state) render();
	}

	function cueStamp(kind, data) {
		const seat = Number(data.seat);
		if (kind === "death") markDead(seat);
		claimCenter("stamp");
		const node = $("stamp");
		const me = isMe(seat);
		// Der Stempel liegt ueber den Abfrage-Panels (Urteil), ausser jemand anderes ist gemeint und du waehlst gerade
		node.className = kind + (choice && !me ? " under" : "");
		$("stamp-word").textContent = kind === "death" ? (data.left === true ? TEXT.FLED : TEXT.ELIMINATED) : TEXT.SURVIVED;
		$("stamp-name").textContent = me ? TEXT.YOU : seatName(seat, data.name);
		restartAnimation(node, "show");
		if (me && kind === "death") {
			flash("red");
			shake("shake-hard");
		} else if (me) {
			flash("safety");
		}
		stampUntil = performance.now() + STAMP_MS;
		after("stamp", STAMP_MS, () => hideCue("stamp"));
		if (place === "match" && state) renderStage(mySeat());
	}

	// ---- Rundenende: Ergebnis-Karte (nach dem Stempel), Stage-Zeile "Round 7 – Bonzo is OUT · 12 left", Sting
	function seatList(value) {
		return asArray(value).map(Number).filter((n) => Number.isFinite(n) && n > 0);
	}

	// Namen fuer die Ergebniszeilen: "Bonzo", "Bonzo & Tilly", "Bonzo, Tilly & Pip", mehr -> "Bonzo, Tilly, Pip +2"
	function joinNames(seats, max) {
		const names = seats.map((s) => (isMe(s) ? TEXT.YOU : seatName(s)));
		const limit = max || 3;
		if (names.length > limit) return names.slice(0, limit).join(", ") + " " + TEXT.RE_MORE(names.length - limit);
		if (names.length <= 1) return names.join("");
		return names.slice(0, -1).join(", ") + " & " + names[names.length - 1];
	}

	function resultTexts(r) {
		let main;
		if (!r.out.length) main = TEXT.RE_NOBODY;
		else if (r.out.length === 1) main = isMe(r.out[0]) ? TEXT.RE_OUT_YOU : TEXT.RE_OUT_ONE(seatName(r.out[0]));
		else if (r.out.length <= 3) main = TEXT.RE_OUT_MANY(joinNames(r.out));
		else main = TEXT.RE_OUT_N(r.out.length);
		const lines = [];
		if (r.out.length > 3) lines.push(joinNames(r.out, 4));
		if (r.survived.length) lines.push(TEXT.RE_SURVIVED(joinNames(r.survived, 4)));
		if (r.left.length) lines.push(TEXT.RE_FLED(joinNames(r.left, 3)));
		return { main, names: lines.join(" · ") };
	}

	function cueRoundEnd(data) {
		const out = seatList(data.out);
		const survived = seatList(data.survived).filter((s) => !out.includes(s));
		const left = seatList(data.left).filter((s) => out.includes(s));
		const round = Number(data.round) > 0 ? Math.floor(Number(data.round)) : roundNo();
		let alive = Number(data.alive);
		if (!Number.isFinite(alive)) alive = asArray(state ? state.seats : []).filter((s) => s.alive && !out.includes(s.seat)).length;
		act.result = { round, out, survived, left, alive: Math.max(0, Math.floor(alive)) };
		memo.aiming = null;
		setAct("result");
		clearBanners();   // das Ergebnis ist jetzt die Schlagzeile
		cancel("result");
		// Erst wenn der Stempel (ELIMINATED / SURVIVED) durch ist, sonst verdeckt die Karte ihn
		after("result", Math.max(0, stampUntil - performance.now()), showResultCard);
		if (place === "match" && state) render();
	}

	function showResultCard() {
		const r = act.result;
		if (!r || place !== "match") return;
		claimCenter("result");
		const node = $("result");
		const text = resultTexts(r);
		$("result-round").textContent = TEXT.ROUND(r.round);
		const main = $("result-main");
		main.textContent = text.main;
		const names = $("result-names");
		names.textContent = text.names;
		names.classList.toggle("hidden", !text.names);
		$("result-left").textContent = TEXT.RE_LEFT(r.alive);
		node.className = r.out.length ? "danger" : "luck";
		node.classList.toggle("me-out", r.out.some(isMe));
		node.classList.toggle("me-safe", r.survived.some(isMe));
		fitText(main, rem(30), rem(3), rem(1.6));
		restartAnimation(node, "show");
		Bus.Call("UiSound", r.out.length ? "round_out" : "round_safe");
		after("result", RESULT_CARD_MS, () => {
			node.classList.add("away");
			after("result", CARD_AWAY_MS, () => hideCue("result"));
		});
	}

	function cueWinner(data) {
		const seat = Number(data.seat);
		const node = $("winner");
		if (winner.on && winner.seat === seat && !node.classList.contains("hidden")) return;   // schon da (Fx + Show)
		claimCenter("winner");
		clearBanners();
		setAct("ended");
		winner.on = true;
		winner.seat = seat;
		winner.since = performance.now();
		// seat 0 = niemand hat ueberlebt (PROTOCOL: winner)
		const nobody = !(seat > 0);
		const me = !nobody && isMe(seat);
		const name = $("winner-name");
		$("winner-title").textContent = nobody ? TEXT.NOBODY_TITLE : TEXT.WINNER_TITLE;
		name.textContent = nobody ? TEXT.NOBODY : seatName(seat, data.name);
		$("winner-sub").textContent = nobody ? TEXT.NOBODY_SUB : me ? TEXT.WINNER_YOU : TEXT.WINNER_SUB;
		node.classList.toggle("me", me);
		node.classList.toggle("nobody", nobody);
		node.classList.remove("hidden");
		fitText(name, rem(28), rem(4.4), rem(2));
		restartAnimation(node, "show");
		if (place === "match" && state) renderStage(mySeat());
	}

	// ---- Karte Skip: Jack dreht weiter, der POP auf den Ersatz folgt (SKIP_TIME). Die Stage-Zeile sagt, wer wem entkommt.
	function cueSkip(data) {
		const seat = Number(data.seat);
		const next = Number(data.new_seat);
		act.skip = { seat, name: data.name, next, nextName: data.new_name };
		if (act.actors.length) act.actors = act.actors.map((s) => (s === seat ? next : s));
		setAct("skip");
		word(TEXT.SKIP_WORD, "skip", 2);
		highlightSeat(next);
		if (isMe(next)) flash("red");
		if (place === "match" && state) render();
	}

	// ---- Revolver-Kette: Halter + Chance "N IN 6" (Trommel oben, Ansagen)
	function cueRevolverGive(data) {
		const seat = Number(data.seat);
		const odds = TEXT.ODDS_SUB(revolverOdds({ spent: 0, bullets: 1 }));
		memo.aiming = null;
		banner({
			kicker: TEXT.REV_GIVE_KICKER,
			main: isMe(seat) ? TEXT.REV_GIVE_YOU : TEXT.REV_GIVE(seatName(seat)),
			sub: odds,
			detail: `${TEXT.REV_GIVE_KICKER} · ${odds}`,
			tone: isMe(seat) ? "danger" : "",
			key: "revolver",
			ms: 2800,
		});
		highlightSeat(seat);
	}

	// Der Halter zielt (nur in der Wahl-Phase, bis zu 5x pro Sekunde): Stage-Zeile "NIBBLES IS AIMING AT BONZO…",
	// Zeile in der Liste rot. Zielt er auf dich, pulsiert der Rand einmal (nicht bei jedem Update).
	function cueRevolverAiming(data) {
		const shooter = Number(data.shooter) || 0;
		const seat = Number(data.seat) || 0;
		const before = memo.aiming;
		memo.aiming = seat > 0 ? { shooter, seat } : null;
		if (seat > 0 && isMe(seat) && !(before && before.seat === seat)) restartAnimation($("vignette"), "pulse");
		if (place === "match" && state) {
			const me = mySeat();
			renderSeats(me);
			renderStage(me);
		}
	}

	function cueRevolverAim(data) {
		memo.aiming = null;
		const shooter = Number(data.shooter);
		const seat = Number(data.seat);
		const chamber = Math.round(Number(data.chamber));
		const fields = { chambers: data.chambers, bullets: data.bullets };
		if (Number.isFinite(chamber) && chamber > 0) fields.spent = chamber - 1;   // chamber = Nummer dieses Abzugs
		const chance = revolverOdds(fields);
		let kicker = TEXT.REV_GIVE_KICKER;
		if (chance.extra) kicker = TEXT.REV_AIM_HOLD;
		else if (Number.isFinite(chamber) && chamber > 0) kicker = TEXT.REV_AIM_KICKER(chamber, chance.of + chamber - 1);
		const odds = TEXT.ODDS_SUB(chance);
		banner({
			kicker,
			main: seat === shooter ? TEXT.REV_AIM_SELF(who(seat)) : TEXT.REV_AIM(who(shooter), who(seat)),
			sub: odds,
			detail: `${kicker} · ${odds}`,
			tone: isMe(seat) ? "danger" : "",
			key: "revolver",
			ms: Math.max(1800, num(data.aim_time, 0, 10, 1.5) * 1000 + 700),
		});
		if (isMe(seat)) restartAnimation($("vignette"), "pulse");
	}

	function cueRevolverShot(data) {
		const seat = Number(data.seat);
		const result = String(data.result || "");
		memo.aiming = null;
		if (eventData("gallery")) {
			memo.shots.set(seat, result);
			if (place === "match" && state) renderGallery();
		}
		if (data.shooter !== undefined && isShown("cylinder")) restartAnimation($("cylinder"), "fired");
		// Die Woerter (*click*, BANG!, SAFETY) kommen per Fx; die Stage-Zeile ("*click* – ...", "BANG! ...") vom Server
		if (place === "match" && state) renderStage(mySeat());
	}

	function cueRevolverPass(data) {
		const seat = Number(data.seat);
		const chance = revolverOdds({ chambers: data.chambers, bullets: data.bullets });
		const sub = chance.extra && chance.bullets > 1 ? TEXT.REV_RELOAD(chance) : TEXT.ODDS_SUB(chance);
		memo.aiming = null;
		banner({
			kicker: TEXT.REV_PASS_KICKER,
			main: TEXT.REV_PASS(who(seat)),
			sub,
			detail: `${TEXT.REV_PASS(who(seat))} · ${sub}`,
			tone: isMe(seat) ? "danger" : "",
			key: "revolver",
			ms: 2600,
		});
		highlightSeat(seat);
	}

	function cueRicochet(data) {
		const from = Number(data.from);
		const seat = Number(data.seat);
		word(TEXT.RICOCHET_WORD, "ricochet", 2);
		banner({
			kicker: TEXT.RICOCHET_KICKER,
			main: TEXT.RICOCHET_MAIN(who(from)),
			sub: TEXT.RICOCHET_TO(who(seat)),
			detail: `${TEXT.RICOCHET_WORD} ${TEXT.RICOCHET_MAIN(who(from))} ${TEXT.RICOCHET_TO(who(seat))}`,
			tone: isMe(seat) ? "danger" : "gold",
			ms: 2200,
		});
		if (eventData("gallery")) memo.shots.set(from, "ricochet");
		highlightSeat(seat);
		if (isMe(seat)) flash("red");
		if (place === "match" && state) render();
	}

	// Angry Clown: einmal. Shooting Gallery: einmal pro Ente (linker Nachbar, Gewaehlter, rechter Nachbar).
	// Galerie: Kopf und Fadenkreuz auf der Ente sagen schon, auf wen Jack anlegt -> Ansage nur beim ersten Anlegen
	// und wenn du selbst dran bist.
	function cueAngryAim(data) {
		const seat = Number(data.seat);
		const gallery = eventData("gallery");
		if (gallery) {
			const targets = asArray(gallery.targets).map(Number);
			const k = targets.indexOf(seat);
			if (!memo.galleryAnnounced || isMe(seat)) {
				memo.galleryAnnounced = true;
				banner({
					kicker: k >= 0 ? TEXT.GALLERY_KICKER(k + 1, targets.length) : TEXT.ANGRY_KICKER,
					main: TEXT.JACK_AIMS(who(seat)),
					sub: TEXT.ONLY_CARDS,
					detail: `${k >= 0 ? TEXT.GALLERY_KICKER(k + 1, targets.length) : TEXT.ANGRY_KICKER} · ${TEXT.JACK_AIMS(who(seat))}`,
					tone: isMe(seat) ? "danger" : "",
					key: "gallery",
					ms: Math.max(1500, num(data.aim_time, 0, 10, 1.1) * 1000 + 400),
				});
			} else {
				dropBannerKey("gallery");   // "Jack aims at YOU" stimmt nicht mehr
			}
		} else {
			banner({
				kicker: TEXT.ANGRY_KICKER,
				main: TEXT.JACK_AIMS(who(seat)),
				sub: TEXT.ONLY_CARDS,
				detail: TEXT.ONLY_CARDS,
				tone: isMe(seat) ? "danger" : "",
				ms: Math.max(2000, num(data.aim_time, 0, 10, 2.2) * 1000 + 400),
			});
		}
		highlightSeat(seat);
		if (isMe(seat)) restartAnimation($("vignette"), "pulse");
		if (place === "match" && state) render();
	}

	// ---- Spare or Eliminate
	function cueVoteStart(data) {
		const seat = Number(data.seat);
		memo.voteResult = null;
		banner({
			kicker: TEXT.VOTE_KICKER,
			main: isMe(seat) ? TEXT.VOTE_ON_YOU : TEXT.VOTE_ON(seatName(seat, data.name)),
			sub: TEXT.VOTE_ALL(data.secret === true),
			tone: isMe(seat) ? "danger" : "",
			unless: "vote",
			ms: 3200,
		});
	}

	function cueVoteResult(data) {
		const kill = data.result === "kill";
		const spare = Math.max(0, Number(data.spare) || 0);
		const killN = Math.max(0, Number(data.kill) || 0);
		memo.voteResult = { result: kill ? "kill" : "spare", tie: data.tie === true, spare, kill: killN };
		// Die Zahlen stehen in der Zaehlung direkt darueber, das Urteil steht nur hier (danach kommt der Stempel)
		banner({
			kicker: data.tie === true ? TEXT.VOTE_TIE : TEXT.VOTE_IN,
			main: kill ? TEXT.VOTE_KILL : TEXT.VOTE_SPARE,
			detail: `${data.tie === true ? TEXT.VOTE_TIE : TEXT.VOTE_IN} ${(kill ? TEXT.VOTE_KILL : TEXT.VOTE_SPARE).toUpperCase()}`,
			tone: kill ? "danger" : "luck",
			ms: 2600,
		});
		if (place === "match" && state) render();
	}

	// ---- Pass the Pumpkin
	function cuePumpkinStart(data) {
		const seat = Number(data.seat);
		banner({
			kicker: TEXT.PUMPKIN_KICKER,
			main: TEXT.PUMPKIN_MAIN,
			sub: isMe(seat) ? TEXT.PUMPKIN_YOU : TEXT.PUMPKIN_HOLDS(seatName(seat)),
			tone: "pumpkin",
			unless: "pass",
			ms: 2800,
		});
		highlightSeat(seat);
	}

	function cuePumpkinPass(data) {
		highlightSeat(Number(data.seat));
	}

	function cuePumpkinBoom(data) {
		dropBanners("pass");
		word(TEXT.BOOM, "boom", 2);
		flash("fire");
		shake("shake-hard");
		highlightSeat(Number(data.seat));
	}

	// ---- Split or Steal
	function cueSplitStart(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		banner({
			kicker: TEXT.SPLIT_KICKER,
			main: `${who(a, data.name)} & ${who(b, data.name2)}`,
			sub: TEXT.SPLIT_SUB,
			tone: "gold",
			unless: "splitsteal",   // die beiden selbst haben gleich das Panel
			ms: 2800,
		});
	}

	function fillRevealSide(nodeId, seat, value, gained) {
		const side = $(nodeId);
		const steal = value === "steal";
		side.querySelector(".rv-name").textContent = who(seat);
		side.querySelector(".rv-word").textContent = steal ? TEXT.STEAL : TEXT.SPLIT;
		side.classList.toggle("steal", steal);
		side.classList.toggle("split", !steal);
		side.classList.toggle("me", isMe(seat));
		const gain = side.querySelector(".rv-gain");
		const n = Math.round(Number(gained) || 0);
		gain.textContent = TEXT.GAIN(n);
		gain.className = "rv-gain" + (n > 0 ? " up" : n < 0 ? " down" : "");
	}

	function cueSplitResult(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		// eigenes Panel (steht nach der Wahl kurz) sofort weg: das Aufdecken gehoert in die Mitte
		cancel("split");
		stopCountdown($("split-timer"));
		show("split", false);
		const ca = data.choice === "steal" ? "steal" : "split";
		const cb = data.choice2 === "steal" ? "steal" : "split";
		claimCenter("reveal");
		fillRevealSide("rv-a", a, ca, data.gained);
		fillRevealSide("rv-b", b, cb, data.gained2);
		let verdict;
		if (ca === "split" && cb === "split") verdict = TEXT.RV_BOTH_SPLIT;
		else if (ca === "steal" && cb === "steal") verdict = TEXT.RV_BOTH_STEAL;
		else verdict = TEXT.RV_STEALS(who(ca === "steal" ? a : b));
		const v = $("rv-verdict");
		v.textContent = verdict;
		v.className = ca === "split" && cb === "split" ? "luck" : "danger";
		const node = $("reveal");
		node.classList.remove("hidden");
		restartAnimation(node, "show");
		show("versus", false);
		after("reveal", REVEAL_MS, () => hideCue("reveal"));
	}

	// ---- Defuse or Die
	function cueBombStart(data) {
		const seat = Number(data.seat);
		const secs = Math.round(num(data.seconds, 1, 99, 10));
		banner({
			kicker: TEXT.BOMB_KICKER,
			main: TEXT.BOMB_MAIN,
			sub: isMe(seat) ? TEXT.BOMB_YOU(secs) : TEXT.BOMB_OTHER(seatName(seat), secs),
			tone: "danger",
			unless: "wire",   // wer schneidet, hat gleich Handbuch und Bombe vor sich
			ms: 2400,
		});
		highlightSeat(seat);
	}

	function cueBombResult(data) {
		retireBomb();
		const wire = WIRE_COLORS.includes(String(data.wire)) ? String(data.wire) : "";
		if (data.defused === true) {
			word(TEXT.DEFUSED, "defused", 2);
			flash("safety");
			if (wire) banner({ kicker: TEXT.WIRE_KICKER(TEXT.WIRE[wire]), main: TEXT.DEFUSED, detail: `${TEXT.WIRE_KICKER(TEXT.WIRE[wire])}: ${TEXT.DEFUSED}`, tone: "luck", ms: 1800 });
		} else {
			word(TEXT.BOOM, "boom", 2);
			flash("fire");
			shake("shake-hard");
			const kicker = wire ? TEXT.WIRE_KICKER(TEXT.WIRE[wire]) : TEXT.BOMB_MAIN;
			const main = wire ? TEXT.WRONG_WIRE : TEXT.TOO_SLOW;
			banner({ kicker, main, detail: `${kicker}: ${main}`, tone: "danger", ms: 1800 });
		}
	}

	// ---- Quick Draw
	function cueDuelStart(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		banner({
			kicker: TEXT.DUEL_KICKER,
			main: TEXT.DUEL_VS(who(a, data.name), who(b, data.name2)),
			sub: TEXT.DUEL_SUB,
			tone: isMe(a) || isMe(b) ? "danger" : "",
			ms: 3000,
		});
	}

	function cueDuelDraw(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		clearBanners();
		flash("draw");
		// Die Duellanten sehen "DRAW!" auf ihrer Taste (qte-Abfrage), alle anderen riesig in der Mitte
		if (!isMe(a) && !isMe(b)) word(TEXT.DRAW, "draw", 2);
	}

	function cueDuelResult(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		const spec = { kicker: TEXT.DUEL_KICKER, ms: 2200 };
		if (data.result === "win") {
			spec.main = TEXT.DUEL_WIN(who(a));
			spec.sub = TEXT.DUEL_HIT(who(b));
			spec.tone = isMe(b) ? "danger" : isMe(a) ? "luck" : "";
		} else if (data.result === "misfire") {
			spec.main = TEXT.DUEL_MISFIRE(who(a));
			spec.sub = TEXT.DUEL_FOOT;
			spec.tone = isMe(a) ? "danger" : "";
		} else if (data.result === "jack") {
			// Finale ohne Schuss: Jack waehlt selbst (seat = getroffen)
			spec.main = TEXT.DUEL_JACK;
			spec.sub = TEXT.DUEL_JACK_SUB(who(a));
			spec.tone = isMe(a) ? "danger" : isMe(b) ? "luck" : "";
		} else {
			spec.main = TEXT.DUEL_BOTH;
			spec.sub = TEXT.DUEL_BOTH_SUB;
			spec.tone = isMe(a) || isMe(b) ? "danger" : "";
		}
		spec.detail = `${spec.main} · ${spec.sub}`;
		banner(spec);
	}

	// ---- Karten
	function cueDeal(data) {
		const seats = asArray(data.seats).map(Number).filter(Number.isFinite);
		const count = Number.isFinite(Number(data.count)) ? Number(data.count) : seats.length;
		banner({
			kicker: TEXT.DEAL_KICKER,
			main: TEXT.DEAL_MAIN(count),
			sub: seats.some(isMe) ? TEXT.DEAL_YOU : "",
			detail: TEXT.DEAL_MAIN(count) + (seats.some(isMe) ? ` · ${TEXT.DEAL_YOU}` : ""),
			tone: "gold",
			ms: 3000,
		});
		seats.forEach((seat, i) => after("deal", 140 * i, () => flashRow(seat, "dealt")));
	}

	// Finale: nur noch zwei leben (kommt einmal pro Show direkt vor dem letzten Spin)
	function cueFinale(data) {
		const a = Number(data.seat);
		const b = Number(data.seat2);
		word(TEXT.FINALE_WORD, "finale", 3);
		banner({
			kicker: TEXT.FINALE_KICKER,
			main: TEXT.FINALE_MAIN(who(a), who(b)),
			sub: TEXT.FINALE_SUB,
			detail: `${TEXT.FINALE_KICKER} · ${TEXT.FINALE_MAIN(who(a), who(b))} · ${TEXT.FINALE_SUB}`,
			tone: isMe(a) || isMe(b) ? "danger" : "gold",
			ms: 4000,
		});
	}

	// Nachruecker uebernimmt einen Bot-Platz (alle am Tisch)
	function cueSeatTaken(data) {
		const seat = Number(data.seat);
		if (isMe(seat)) return;   // der Nachruecker selbst bekommt "you_joined"
		toast({ tone: "gold", parts: [[String(data.name || "?"), "who"], [TEXT.TAKES_SEAT, ""], [String(data.old || "?"), "em"]] });
		flashRow(seat, "dealt");
	}

	// Nur an den Nachruecker: du sitzt jetzt am Tisch
	function cueYouJoined(data) {
		const cards = Math.max(0, Number(data.cards) || 0);
		word(TEXT.JOINED_WORD, "skip", 2);
		toast({ tone: "gold", parts: [[TEXT.JOINED_TOOK + " ", ""], [String(data.old || "?"), "who"], [TEXT.JOINED_SEAT + TEXT.JOINED_CARDS(cards), ""]] });
	}

	function cueCardGain(data) {
		const seat = Number(data.seat);
		const n = Math.max(1, Number(data.count) || 1);
		toast({ art: "back", tone: "gold", parts: [namePart(seat), [isMe(seat) ? TEXT.TAKE : TEXT.TAKES, ""], [TEXT.DRAWS(n), "em"]] });
		flashRow(seat, "dealt");
	}

	function cueCardPlay(data) {
		const seat = Number(data.seat);
		const target = Number(data.target);
		const id = String(data.card || "");
		// Thief gegen dich: die private Hand kam kurz vorher an -> sagen, welche Karte weg ist
		if (id === "thief" && isMe(target) && seat !== target && lastLost.ids.length === 1 && performance.now() - lastLost.at < 1500) {
			const stolen = lastLost.ids[0];
			lastLost = { ids: [], at: -1e9 };
			toast({ art: stolen, tone: "danger", parts: [[seatName(seat), "who"], [TEXT.STOLE, ""], [cardName(stolen), "card c-" + (CARD_ART.test(stolen) ? stolen : "x")], ["!", ""]] });
			flashRow(seat, "played");
			return;
		}
		const parts = [namePart(seat), [TEXT.USED, ""], [cardName(id), "card c-" + (CARD_ART.test(id) ? id : "x")]];
		if (Number.isFinite(target) && target > 0) {
			parts.push([TEXT.ON, ""]);
			if (target === seat) parts.push([isMe(seat) ? TEXT.YOURSELF : TEXT.THEMSELF, "who"]);
			else parts.push(isMe(target) ? [TEXT.YOU, "who me"] : [seatName(target), "who"]);
		}
		toast({ art: id, parts, tone: isMe(target) && target !== seat && id === "thief" ? "danger" : "" });
		flashRow(seat, "played");
		if (Number.isFinite(target) && target > 0 && target !== seat) flashRow(target, "played-on");
	}

	function cueCardTrigger(data) {
		const seat = Number(data.seat);
		const id = String(data.card || "safety");
		toast({
			art: id,
			tone: "luck",
			parts: [[cardName(id), "card c-" + (CARD_ART.test(id) ? id : "x")], [TEXT.SAVED, ""], isMe(seat) ? [TEXT.YOU, "who me"] : [seatName(seat), "who"]],
		});
	}

	// ------------------------------------------------------------ Ring (Zielwahl, Kuerbis, Kartenziel)

	// Platz-Winkel (Grad, wie am Tisch) -> Position auf dem Bildschirm.
	// Der eigene Platz liegt unten, alle anderen so, wie man sie vom eigenen Stuhl aus sieht.
	function screenAngle(seatAngle, myAngle) {
		return (seatAngle - myAngle + 90) * Math.PI / 180;
	}

	// mode "target" | "pass" (Abfrage) | "card" (Kartenziel)
	// opts { options: Set<seat>, seconds, title, art, onPick(seat), counts: zeigt Kartenzahl, instant }
	function openRing(mode, opts) {
		const ring = $("ring");
		const board = $("ring-board");
		board.querySelectorAll(".target").forEach((n) => n.remove());
		ringOwner = mode === "card" ? "card" : "choice";
		ringSig = Array.from(opts.options).sort((x, y) => x - y).join(",");

		const seats = asArray(state ? state.seats : []);
		ring.classList.toggle("mid", seats.length > MANY_SEATS && seats.length <= CROWD_SEATS);
		ring.classList.toggle("many", seats.length > CROWD_SEATS);
		ring.classList.toggle("pass", mode === "pass");
		ring.classList.toggle("card", mode === "card");
		ring.classList.toggle("instant", !!opts.instant);

		const me = mySeat();
		const myAngle = me ? Number(me.angle) || 0 : 90;
		const radius = seats.length > CROWD_SEATS ? 45 : 43;   // Prozent der Brettgroesse

		// Kuerbis an grossen Tischen: die beiden Nachbarn liegen dicht neben dir -> etwas auseinanderruecken
		const minSep = mode === "pass" && seats.length > MANY_SEATS ? 26 * Math.PI / 180 : 0;
		const bottom = Math.PI / 2;
		seats.forEach((s) => {
			let angle = screenAngle(Number(s.angle) || 0, myAngle);
			if (minSep && opts.options.has(s.seat) && !(me && s.seat === me.seat)) {
				const delta = Math.atan2(Math.sin(angle - bottom), Math.cos(angle - bottom));
				if (Math.abs(delta) < minSep) angle = bottom + (delta < 0 ? -minSep : minSep);
			}
			const x = 50 + Math.cos(angle) * radius;
			const y = 50 + Math.sin(angle) * radius;
			const button = el("button", "target");
			button.type = "button";
			button.dataset.seat = String(s.seat);
			button.style.left = x + "%";
			button.style.top = y + "%";
			// Eigener Platz: nur "YOU" (kurz, ueberdeckt bei 32 Plaetzen keine Nachbarn)
			const self = !!(me && s.seat === me.seat);
			const allowed = opts.options.has(s.seat);
			button.appendChild(document.createTextNode(self ? TEXT.YOU : s.name));
			if (!self && !s.alive) button.appendChild(el("span", "sub", TEXT.DEAD));
			else if (opts.counts && allowed && !self) button.appendChild(el("span", "sub", TEXT.CARDS_SHORT(Math.max(0, Number(s.cards) || 0))));
			if (self) button.classList.add("self");
			if (!s.alive) button.classList.add("dead");
			// Kuerbis: Wurfrichtung zeigen (links/rechts von dir)
			if (mode === "pass" && allowed) button.classList.add(x < 50 ? "go-left" : "go-right");
			button.disabled = !allowed;
			if (allowed) {
				button.addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
				button.addEventListener("click", () => opts.onPick(s.seat));
			}
			board.appendChild(button);
		});

		// Mitte
		const art = $("ring-art");
		art.classList.toggle("hidden", !opts.art);
		if (opts.art) {
			const img = art.querySelector("img");
			img.src = artUrl(opts.art);
			img.alt = cardName(opts.art);
		}
		show("ring-pumpkin", mode === "pass");
		show("ring-back", mode === "card");
		const title = $("ring-title");
		title.textContent = opts.title || TEXT.CHOOSE_TARGET;
		title.dataset.sub = opts.sub || "";
		if (mode === "target") updateRingTitle();

		show("ring", true);
		const count = $("ring-count");
		if (opts.seconds > 0) {
			startCountdown(opts.seconds, count);
		} else {
			stopCountdown(count);
			count.textContent = "";
			count.classList.remove("urgent");
		}
	}

	function hideRing() {
		show("ring", false);
		stopCountdown($("ring-count"));
		ringOwner = null;
		ringSig = "";
		$("ring").classList.remove("pass", "card", "instant");
	}

	// Ueberschrift der Zielwahl: Anweisung des laufenden Events, sonst ein allgemeiner Satz
	function updateRingTitle() {
		const event = state && state.event;
		const own = !!(choice && choice.kind === "target" && event && event.id === choice.event && event.instruction_actor);
		$("ring-title").textContent = own ? stripLead(event.instruction_actor) || TEXT.CHOOSE_TARGET : TEXT.CHOOSE_TARGET;
	}

	// Gleiche Art kurz nach dem Schliessen wieder offen (Kuerbis: neue Abfrage nach Zeitablauf) -> ohne Animation
	function reopened(kind) {
		return lastClosed.kind === kind && performance.now() - lastClosed.at < REASK_MS;
	}

	function openTargetRing(data) {
		openRing("target", {
			options: new Set(asArray(data.options).map(Number)),
			seconds: Number(data.seconds) || 0,
			onPick: (seat) => choose(seat),
			instant: reopened("target"),
		});
	}

	function openPassRing(data) {
		openRing("pass", {
			options: new Set(asArray(data.options).map(Number)),
			// keine Zahl: seconds gilt nur fuer diese eine Frage, danach kommt sofort die naechste. Ein Zaehler wuerde
			// eine Explosion bei 0 vortaeuschen (Server: no_timer), die echte Zuendschnur ist geheim.
			seconds: 0,
			title: TEXT.PUMPKIN_RING,
			sub: TEXT.PUMPKIN_HINT,
			onPick: (seat) => choose(seat),
			instant: reopened("pass"),
		});
	}

	// ------------------------------------------------------------ Revolver: Zielen mit der Kamera (Zielmodus)

	// Abfrage target mit aim = true: KEIN Ring. Die Maus bleibt im Spiel und dreht die Kamera; Client/Aim.lua bestimmt das
	// Ziel (Kamerastrahl), meldet es per Aim(json) und schiesst mit der linken Maustaste. Das HUD zeigt nur Fadenkreuz,
	// "AIMING AT NIBBLES – CLICK TO SHOOT" und die Restzeit. Kommt Aim(json) vor der Abfrage, gilt es trotzdem.
	function isAimChoice(c) {
		return !!(c && c.kind === "target" && (c.aim === true || c.aim === 1));
	}

	function openAim(data) {
		const ask = Number(data.ask) || 0;
		if (!(aim.active && aim.ask === ask)) {
			aim.seat = 0;
			aim.name = "";
			aim.label = "";
			aim.hint = "";
			aim.warn = false;
		}
		aim.active = true;
		aim.ask = ask;
		const seconds = Math.max(0, Number(data.seconds) || 0);
		if (seconds > 0 && !(aim.ends > performance.now())) {
			aim.total = seconds;
			aim.ends = performance.now() + seconds * 1000;
		}
		renderAim();
	}

	function renderAim() {
		const node = $("aim");
		if (!aim.active || place !== "match") {
			hideAim();
			return;
		}
		const entering = node.classList.contains("hidden");
		node.classList.remove("hidden");
		const locked = aim.seat > 0;
		node.classList.toggle("locked", locked);
		node.classList.toggle("warn", !!aim.warn && !locked);
		const name = locked ? (isMe(aim.seat) ? TEXT.YOU : seatName(aim.seat, aim.name)) : "";
		const label = aim.label || (locked ? TEXT.AIM_AT(name) : TEXT.AIM_NONE);
		const nameEl = $("aim-name");
		if (nameEl.textContent !== label) {
			nameEl.textContent = label;
			fitText(nameEl, Math.min(rem(46), window.innerWidth * 0.8), rem(2.1), rem(1.2));
			if (!entering) restartAnimation(nameEl, "swap");
		}
		setText($("aim-hint"), aim.warn && !locked ? (aim.hint || TEXT.AIM_WARN) : (aim.hint || TEXT.AIM_HINT));
		const timer = $("aim-timer");
		const left = (aim.ends - performance.now()) / 1000;
		if (left > 0 && (entering || Math.abs((timer._ends || 0) - aim.ends) > 400)) {
			timer._ends = aim.ends;
			startCountdown(left, timer);
		}
		timer.classList.toggle("hidden", !(left > 0));
		if (entering) restartAnimation(node, "enter");
	}

	function hideAim() {
		const node = $("aim");
		node.classList.add("hidden");
		node.classList.remove("locked", "warn");
		const timer = $("aim-timer");
		stopCountdown(timer);
		timer._ends = 0;
	}

	function endAim() {
		aim.active = false;
		aim.seat = 0;
		aim.name = "";
		aim.label = "";
		aim.hint = "";
		aim.warn = false;
		aim.ends = 0;
		hideAim();
	}

	// AimEnd von Lua: geschossen ("confirm"), Abfrage zu, Ortswechsel. Fuer das HUD ist die Abfrage damit erledigt
	// (das ChoiceEnd des Servers kommt spaeter und findet nichts mehr). ask 0 = egal welche.
	function aimEnded(ask) {
		const wasAim = isAimChoice(choice) && (!(ask > 0) || Number(choice.ask) === ask);
		if (!wasAim && aim.active && ask > 0 && aim.ask !== ask) return;   // spaetes Ende einer frueheren Zielphase
		endAim();
		if (wasAim) closeChoice("aim");
		else if (place === "match" && state) renderStage(mySeat());
	}

	// ------------------------------------------------------------ Abfragen

	function choose(value) {
		if (!choice) return;
		Bus.Call("UiSound", "click");
		Bus.Call("Choose", choice.ask, value);
		closeChoice("chosen", value);
	}

	// Tasten-Abfrage: nur Anzeige. Die Taste liest Lua (Client/HUD.lua, KeyDown).
	function openQte(data) {
		cancel("qte");
		const label = String(data.label || "PRESS!");
		$("qte-label").textContent = label;
		$("qte").classList.toggle("draw", data.event === "duel");
		const key = $("qte-key");
		key.classList.remove("pressed", "hit", "miss");
		$("qte-letter").textContent = String(data.prompt || "?");
		restartAnimation(key, "pop");
		$("qte-steps").textContent = (Number(data.steps) > 1) ? `${Number(data.step) || 1} / ${Number(data.steps)}` : "";
		show("qte", true);
		startFuse($("qte-fill"), Number(data.seconds) || 1, Number(data.seconds) || 1);
	}

	// Klick-Abfrage: Flamme an der vom Server vorgegebenen Stelle
	function openClicker(data) {
		cancel("clicker");
		const flame = $("flame");
		flame.style.left = num(data.x, 3, 97, 50) + "%";
		flame.style.top = num(data.y, 3, 97, 50) + "%";
		flame.onclick = () => choose(asArray(data.options)[0]);
		flame.classList.remove("used");
		restartAnimation(flame, "appear");

		const total = Math.floor(num(data.total, 0, 30, 0));
		const done = Math.floor(num(data.progress, 0, total, 0));
		const pips = $("clicker-pips");
		pips.textContent = "";
		for (let i = 0; i < total; i++) pips.appendChild(el("i", i < done ? "out" : ""));
		$("clicker-count").textContent = `${done} / ${total}`;
		show("clicker", true);
	}

	// ---- Spare or Eliminate

	function openVote(data) {
		cancel("vote");
		memo.vote = null;
		memo.voteMissed = false;
		const node = $("vote");
		const target = Number(data.target);
		node.dataset.target = String(target);
		node.dataset.targetName = seatName(target, data.target_name);
		node.classList.remove("watch", "hidden");
		node.classList.add("ask");
		node.classList.toggle("instant", reopened("vote"));
		["vote-spare", "vote-kill"].forEach((id) => {
			const b = $(id);
			b.disabled = false;
			b.classList.remove("chosen");
		});
		$("vote-spare").onclick = () => castVote("spare");
		$("vote-kill").onclick = () => castVote("kill");
		startCountdown(Number(data.seconds) || 0, $("vote-timer"));
		renderVote();
		updateStatusSlot();
	}

	function castVote(value) {
		if (!choice || choice.kind !== "vote") return;
		memo.vote = value;
		const b = $(value === "kill" ? "vote-kill" : "vote-spare");
		b.classList.add("chosen");
		choose(value);
	}

	function closeVoteAsk(reason) {
		stopCountdown($("vote-timer"));
		if (reason !== "chosen" && !memo.vote) memo.voteMissed = true;
		const node = $("vote");
		node.classList.remove("ask");
		if (reason === "place") {
			hideVote();
			return;
		}
		if (place === "match" && state) renderVote();
		else hideVote();
	}

	function hideVote() {
		const node = $("vote");
		node.classList.add("hidden");
		node.classList.remove("ask", "watch");
		stopCountdown($("vote-timer"));
	}

	// Live-Zaehlung aus State (event.data). Waehrend der eigenen Abfrage gross, sonst klein unter dem Eventkopf.
	function renderVote() {
		const node = $("vote");
		const data = eventData("vote");
		const asking = !!(choice && choice.kind === "vote");
		if (place !== "match" || !state || (!data && !asking) || (state.phase !== "PLAYING" && !asking)) {
			if (!asking) hideVote();
			return;
		}
		node.classList.remove("hidden");
		node.classList.toggle("ask", asking);
		node.classList.toggle("watch", !asking);

		const target = data && Number.isFinite(Number(data.target)) ? Number(data.target) : Number(node.dataset.target);
		const name = seatName(target, asking ? node.dataset.targetName : undefined);
		const nameEl = $("vote-name");
		const label = isMe(target) ? TEXT.YOU : `${name}?`;
		if (nameEl.textContent !== label) nameEl.textContent = label;
		nameEl.classList.toggle("me", isMe(target));
		if (asking) fitText(nameEl, rem(40), rem(4.6), rem(2.2));

		const result = memo.voteResult;
		const secret = !!(data && data.secret) && !result;
		let spare = data && Number.isFinite(Number(data.spare)) ? Number(data.spare) : null;
		let kill = data && Number.isFinite(Number(data.kill)) ? Number(data.kill) : null;
		if (result) {
			spare = result.spare;
			kill = result.kill;
		}
		const voted = Math.max(0, Number(data && data.voted) || 0, (spare || 0) + (kill || 0));
		const voters = Math.max(voted, Number(data && data.voters) || 0, 1);
		const hidden = secret || spare === null || kill === null;
		$("vote-spare-n").textContent = hidden ? "?" : String(spare);
		$("vote-kill-n").textContent = hidden ? "?" : String(kill);
		const bar = $("vote-bar");
		bar.querySelector(".spare").style.width = hidden ? "0%" : (100 * spare / voters) + "%";
		bar.querySelector(".kill").style.width = hidden ? "0%" : (100 * kill / voters) + "%";
		bar.querySelector(".cast").style.width = hidden ? (100 * voted / voters) + "%" : "0%";
		node.classList.toggle("secret", hidden);
		node.classList.toggle("lead-spare", !hidden && spare > kill);
		node.classList.toggle("lead-kill", !hidden && kill > spare);

		// Statuszeile
		const cast = TEXT.VOTE_CAST(voted, voters);
		let status;
		if (result) status = `${TEXT.VOTE_FINAL} · ${cast}`;   // das Urteil sagt die Ansage darunter
		else if (asking) status = hidden ? `${TEXT.VOTE_SECRET} · ${cast}` : cast;
		else if (isMe(target)) status = `${TEXT.VOTE_FATE} · ${cast}`;
		else if (memo.vote) status = `${TEXT.VOTE_YOU(memo.vote)} · ${cast}`;
		else if (memo.voteMissed) status = `${TEXT.VOTE_MISSED} · ${cast}`;
		else status = hidden ? `${TEXT.VOTE_SECRET} · ${cast}` : cast;
		$("vote-status").textContent = status;
		node.classList.toggle("result", !!result);
		node.classList.toggle("result-kill", !!result && result.result === "kill");
		node.classList.toggle("result-spare", !!result && result.result === "spare");
	}

	// ---- Split or Steal

	function openSplit(data) {
		cancel("split");
		memo.split = null;
		const node = $("split");
		const partner = Number(data.partner);
		node.dataset.partner = String(partner);
		node.dataset.partnerName = seatName(partner, data.partner_name);
		node.classList.remove("hidden", "locked");
		["split-split", "split-steal"].forEach((id) => {
			const b = $(id);
			b.disabled = false;
			b.classList.remove("chosen");
		});
		$("split-split").onclick = () => pickSplit("split");
		$("split-steal").onclick = () => pickSplit("steal");
		const partnerEl = $("split-partner");
		partnerEl.textContent = node.dataset.partnerName;
		fitText(partnerEl, rem(30), rem(3), rem(1.6));
		startCountdown(Number(data.seconds) || 0, $("split-timer"));
		renderSplit();
		restartAnimation(node, "enter");
		renderVersus();
	}

	function pickSplit(value) {
		if (!choice || choice.kind !== "splitsteal") return;
		memo.split = value;
		$(value === "steal" ? "split-steal" : "split-split").classList.add("chosen");
		choose(value);
	}

	function renderSplit() {
		const node = $("split");
		if (node.classList.contains("hidden")) return;
		const partner = Number(node.dataset.partner);
		const name = seatName(partner, node.dataset.partnerName);
		const them = seatByIndex(partner);
		const me = mySeat();
		$("split-hands").textContent = TEXT.SPLIT_HANDS(name, Math.max(0, Number(them && them.cards) || 0), Math.max(0, Number(me && me.cards) || 0));
		const data = eventData("splitsteal");
		let locked = false;
		if (data) locked = partner === Number(data.a) ? !!data.locked_a : partner === Number(data.b) ? !!data.locked_b : false;
		const status = $("split-status");
		if (memo.split) status.textContent = TEXT.SPLIT_YOU(memo.split);
		else status.textContent = locked ? TEXT.SPLIT_LOCKED(name) : TEXT.SPLIT_WAIT(name);   // "geheim" sagt schon die Anweisung oben
		status.classList.toggle("locked", locked);
	}

	function closeSplit(reason) {
		stopCountdown($("split-timer"));
		const node = $("split");
		if (reason === "chosen") {
			node.classList.add("locked");
			$("split-split").disabled = true;
			$("split-steal").disabled = true;
			renderSplit();
			after("split", LINGER_MS.splitsteal, () => {
				show("split", false);
				if (place === "match" && state) renderVersus();
			});
		} else {
			cancel("split");
			show("split", false);
		}
	}

	// ---- Choose a Card

	function openPick(data) {
		cancel("pick");
		const node = $("pick");
		const options = asArray(data.options).map(String);
		let cards = asArray(data.cards).map(String).filter((id) => options.includes(id));
		if (!cards.length) cards = options;
		const box = $("pick-cards");
		box.textContent = "";
		box.style.setProperty("--n", String(cards.length));
		cards.forEach((id, i) => {
			const def = cardDef(id) || {};
			const playable = def.type === "playable";
			const b = el("button", "pcard " + (playable ? "playable" : "auto"));
			b.type = "button";
			b.dataset.card = id;
			b.style.setProperty("--i", String(i));
			const face = el("span", "pc-face" + (hasArt(id) ? "" : " no-art"));
			face.appendChild(cardImg(id, cardName(id)));
			face.appendChild(el("span", "badge", playable ? TEXT.BADGE_PLAYABLE : TEXT.BADGE_AUTO));
			b.appendChild(face);
			const slip = el("span", "pc-slip");
			slip.appendChild(el("b", "pc-name", cardName(id)));
			slip.appendChild(el("span", "pc-desc", String(def.description || "")));
			b.appendChild(slip);
			b.addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
			b.addEventListener("click", () => pickCard(id, b));
			box.appendChild(b);
		});
		node.classList.remove("done");
		show("pick", true);
		restartAnimation(node, "enter");
		startCountdown(Number(data.seconds) || 0, $("pick-timer"));
		renderPickHand();
	}

	// Kopfzeile der Kartenwahl: was du schon hast (die Kartenleiste liegt unter der Abdunklung)
	function renderPickHand() {
		const held = hand.map((c) => cardName(c.id));
		$("pick-hand").textContent = held.length ? TEXT.PICK_HAND(held.join(" · ")) : TEXT.HAND_EMPTY;
	}

	function pickCard(id, button) {
		if (!choice || choice.kind !== "pickcard") return;
		button.classList.add("chosen");
		$("pick").classList.add("done");
		choose(id);
	}

	function closePick(reason) {
		stopCountdown($("pick-timer"));
		if (reason === "chosen") {
			after("pick", LINGER_MS.pickcard, () => show("pick", false));
		} else {
			cancel("pick");
			show("pick", false);
		}
	}

	// ---- Defuse or Die

	// Regel mit hervorgehobenen GROSSBUCHSTABEN-Woertern (Farben in ihrer Farbe)
	function setRule(node, text) {
		node.textContent = "";
		String(text).split(/(\b[A-Z]{2,}(?:\s+[A-Z]{2,})*\b)/).forEach((part, i) => {
			if (!part) return;
			if (i % 2 === 1) {
				const span = el("span", "hl", part);
				const lower = part.toLowerCase();
				if (WIRE_COLORS.includes(lower)) span.classList.add("c-" + lower);
				node.appendChild(span);
			} else {
				node.appendChild(document.createTextNode(part));
			}
		});
	}

	// Draht: zwei Haelften (oben/unten), beim Schneiden gehen sie auseinander
	function makeWire(wire, index) {
		const color = String(wire.color);
		const b = el("button", "wire c-" + color);
		b.type = "button";
		b.dataset.color = color;
		b.setAttribute("aria-label", `Cut the ${TEXT.WIRE[color]} wire`);
		const k = [-13, 11, -7][index % 3];
		const mx = 30 + k * 0.8;
		const top = `M30 6 C30 58 ${30 + k} 92 ${mx} 150`;
		const bottom = `M${mx} 150 C${30 + k * 0.6} 206 ${30 - k * 0.5} 242 30 294`;
		const svg = svgEl("svg", { class: "wire-svg", viewBox: "0 0 60 300", preserveAspectRatio: "none", "aria-hidden": "true" });
		[["w-top", top], ["w-bottom", bottom]].forEach(([cls, d]) => {
			const g = svgEl("g", { class: "w-half " + cls });
			g.appendChild(svgEl("path", { class: "w-shadow", d }));
			g.appendChild(svgEl("path", { class: "w-core", d }));
			g.appendChild(svgEl("path", { class: "w-shine", d }));
			svg.appendChild(g);
		});
		const strands = svgEl("g", { class: "w-strands", transform: `translate(${mx} 150)` });
		[[-3, -9], [0, -11], [3, -8], [-2, 9], [2, 11], [4, 7]].forEach(([dx, dy]) => {
			strands.appendChild(svgEl("line", { x1: 0, y1: 0, x2: dx, y2: dy }));
		});
		svg.appendChild(strands);
		svg.appendChild(svgEl("circle", { class: "w-terminal", cx: 30, cy: 6, r: 6 }));
		svg.appendChild(svgEl("circle", { class: "w-terminal", cx: 30, cy: 294, r: 6 }));
		b.appendChild(svg);
		const tag = el("span", "wire-tag");
		const paper = el("span", "tag-paper");
		paper.appendChild(el("b", "", String(Math.round(Number(wire.number) || 0))));
		paper.appendChild(el("i", "", TEXT.WIRE[color]));
		tag.appendChild(paper);
		b.appendChild(tag);
		b.appendChild(el("span", "wire-cut", TEXT.CUT));
		b.addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
		b.addEventListener("click", () => cutWire(color, b));
		return b;
	}

	function openBomb(data) {
		cancel("bomb");
		bombCutAt = -1e9;
		const node = $("bomb");
		const wires = asArray(data.wires).filter((w) => w && WIRE_COLORS.includes(String(w.color))).slice(0, 3);
		const box = $("bomb-wires");
		box.textContent = "";
		wires.forEach((w, i) => box.appendChild(makeWire(w, i)));
		setRule($("bomb-rule"), String(data.rule || ""));
		node.classList.remove("hidden", "done", "leave");
		restartAnimation(node, "enter");
		startCountdown(Number(data.seconds) || 0, $("bomb-led"), ledFormat);
	}

	function cutWire(color, button) {
		if (!choice || choice.kind !== "wire") return;
		button.classList.add("cut");
		$("bomb").classList.add("done");
		bombCutAt = performance.now();
		choose(color);
	}

	// Nach dem Schnitt: Bombe bleibt stehen, bis bomb_result kommt (Server antwortet sofort), hoechstens LINGER_MS
	function closeBomb(reason) {
		stopCountdown($("bomb-led"));
		if (reason === "chosen") {
			after("bomb", LINGER_MS.wire, retireBomb);
		} else {
			hideBomb();
		}
	}

	// Ergebnis da: der Schnitt war CUT_MS lang zu sehen, dann blendet die Bombe schnell aus.
	// BOOM!/DEFUSED! und der Stempel liegen ohnehin darueber, die Bombe soll sie nur nicht zustellen.
	function retireBomb() {
		const node = $("bomb");
		if (node.classList.contains("hidden") || node.classList.contains("leave")) return;
		cancel("bomb");
		stopCountdown($("bomb-led"));
		after("bomb", Math.max(0, bombCutAt + CUT_MS - performance.now()), () => {
			node.classList.add("leave");
			after("bomb", BOMB_LEAVE_MS, hideBomb);
		});
	}

	function hideBomb() {
		cancel("bomb");
		stopCountdown($("bomb-led"));
		show("bomb", false);
		$("bomb").classList.remove("leave");
	}

	// ---- Verteilen und Schliessen

	// Panels, die nach einer Wahl kurz stehen bleiben, sofort weg (neue Abfrage, Ortswechsel)
	function hidePanels(except) {
		if (except !== "splitsteal") { cancel("split"); stopCountdown($("split-timer")); show("split", false); }
		if (except !== "pickcard") { cancel("pick"); stopCountdown($("pick-timer")); show("pick", false); }
		if (except !== "wire") hideBomb();
		if (except !== "vote") $("vote").classList.remove("ask");
	}

	function openChoice(data) {
		if (!data || typeof data !== "object") return;
		const kind = String(data.kind || "");
		const aimMode = isAimChoice(data);
		choice = data;
		// Restzeit dieser Abfrage fuer die Regie oben (der Kuerbis hat keine: die Zuendschnur ist geheim)
		const seconds = Math.max(0, Number(data.seconds) || 0);
		choiceClock = { ends: seconds > 0 ? performance.now() + seconds * 1000 : 0, total: seconds };
		if (!aimMode && aim.active) endAim();
		// Abfragen haben Vorrang vor Auftritten in der Mitte
		hideCue("pop");
		hideCue("card");
		hideCue("stamp");
		hideCue("reveal");
		dropBanners(kind);
		// Kartenhand zu (Lua schickt gleich CardMode(false), die Hand ist waehrend einer Abfrage gesperrt)
		if (cardMode) setCardMode(false);
		// Reste einer anderen Abfrage schliessen (z. B. Feuer-Hintergrund, der noch kurz stehen bleibt)
		if ((kind !== "target" && kind !== "pass") || aimMode) {
			if (ringOwner) hideRing();
		}
		if (kind !== "qte") show("qte", false);
		if (kind !== "click") {
			cancel("clicker");
			show("clicker", false);
		}
		hidePanels(kind);

		switch (kind) {
			case "target": if (aimMode) openAim(data); else openTargetRing(data); break;
			case "pass": openPassRing(data); break;
			case "qte": openQte(data); break;
			case "click": openClicker(data); break;
			case "vote": openVote(data); break;
			case "splitsteal": openSplit(data); break;
			case "pickcard": openPick(data); break;
			case "wire": openBomb(data); break;
			default:
				console.error("[DeathBox] Unknown choice kind", kind);
		}
		if (place === "match" && state) render();
	}

	// reason: "chosen" (eigene Wahl), "end" (ChoiceEnd vom Server), "place" (Ortswechsel)
	function closeChoice(reason) {
		const kind = choice ? choice.kind : null;
		const wasAim = isAimChoice(choice);
		choice = null;
		choiceClock = { ends: 0, total: 0 };
		lastClosed.kind = kind;
		lastClosed.at = performance.now();
		if (wasAim) endAim();
		if (ringOwner === "choice") hideRing();
		show("qte", false);
		// Feuer: Hintergrund kurz stehen lassen, die naechste Flamme kommt gleich (kein Flackern)
		$("flame").classList.add("used");
		if (kind === "click" && reason !== "place") {
			after("clicker", 400, () => show("clicker", false));
		} else {
			cancel("clicker");
			show("clicker", false);
		}
		if (kind === "vote") closeVoteAsk(reason);
		if (kind === "splitsteal") closeSplit(reason);
		if (kind === "pickcard") closePick(reason);
		if (kind === "wire") closeBomb(reason);
		if (reason === "place") {
			hidePanels(null);
			hideVote();
		}
		if (place === "match" && state) render();
	}

	// ------------------------------------------------------------ Kartenhand

	function parseHand(json) {
		const data = parse(json, "hand");
		return asArray(data && data.cards)
			.filter((c) => c && typeof c === "object" && c.id !== undefined && c.id !== null)
			.map((c) => {
				const rounds = Number(c.rounds_left);
				return { uid: Number(c.uid), id: String(c.id), rounds_left: c.rounds_left !== undefined && c.rounds_left !== null && Number.isFinite(rounds) ? rounds : null };
			})
			.filter((c) => Number.isFinite(c.uid));
	}

	function handVisible() {
		if (place !== "match" || !state || hand.length === 0 || cardMode) return false;
		const me = mySeat();
		return !(me && !me.alive);
	}

	// Kleine Leiste unten links: Karten (Bild), Anzahl, Hinweis [C]
	function renderHandBar() {
		const bar = $("handbar");
		if (!handVisible()) {
			show("handbar", false);
			return;
		}
		const sig = hand.map((c) => `${c.uid}:${c.id}:${c.rounds_left || 0}`).join("|") + "#" + Object.keys(cardDefs).length;
		show("handbar", true);
		if (sig === handBarSig) return;
		handBarSig = sig;
		const box = $("hb-cards");
		box.textContent = "";
		let playable = 0;
		let fresh = 0;
		hand.forEach((card, i) => {
			const def = cardDef(card.id);
			const mini = el("span", "mini");
			mini.style.setProperty("--i", String(i));
			if (def && def.type === "playable") {
				mini.classList.add("playable");
				playable++;
			}
			if (!handSeen.has(card.uid)) {
				mini.classList.add("new");
				mini.style.animationDelay = (fresh++ * 120) + "ms";
			}
			mini.appendChild(cardImg(card.id));
			if (card.rounds_left) mini.appendChild(el("b", "rounds", String(card.rounds_left)));
			box.appendChild(mini);
		});
		hand.forEach((c) => handSeen.add(c.uid));
		bar.classList.toggle("has-playable", playable > 0);
		$("hb-count").querySelector("b").textContent = String(hand.length);
		$("hb-count").querySelector("span").textContent = `/ ${MAX_HAND}`;
	}

	// Darf diese Karte jetzt gespielt werden? null = ja, sonst der Grund (Text)
	function playBlock(card, def) {
		if (!state || place !== "match") return TEXT.PLAY_BUSY;
		if (state.phase === "STARTING") return TEXT.PLAY_NOT_YET;
		if (state.phase !== "PLAYING") return TEXT.PLAY_OVER;
		const me = mySeat();
		if (!me || !me.alive) return TEXT.PLAY_DEAD;
		if (choice) return TEXT.PLAY_BUSY;
		if (performance.now() - lastPlayAt < PLAY_COOLDOWN_MS) return TEXT.PLAY_COOLDOWN;
		if (def.target && cardTargets(card, def).size === 0) return card.id === "thief" ? TEXT.NO_THIEF_TARGETS : TEXT.NO_TARGETS;
		return null;
	}

	// Erlaubte Ziele nach der Zielregel (Shared/Cards.lua, geprueft wird auf dem Server):
	//   alive             lebender Platz, auch man selbst; Guardian: Ziel braucht Platz auf der Hand (ausser man selbst)
	//   other_with_cards  anderer lebender Platz mit mindestens einer Karte (State.seats[].cards)
	function cardTargets(card, def) {
		const out = new Set();
		const me = mySeat();
		if (!state || !me) return out;
		asArray(state.seats).forEach((s) => {
			if (!s.alive) return;
			const self = s.seat === me.seat;
			const cards = Math.max(0, Number(s.cards) || 0);
			if (def.target === "alive") {
				if (self || card.id !== "guardian" || cards < MAX_HAND) out.add(s.seat);
			} else if (def.target === "other_with_cards") {
				if (!self && cards > 0) out.add(s.seat);
			}
		});
		return out;
	}

	function bigCard(card, index, count) {
		const def = cardDef(card.id) || {};
		const playable = def.type === "playable";
		const why = playable ? playBlock(card, def) : null;
		const node = el(playable ? "button" : "div", "bigcard " + (playable ? "playable" : "auto"));
		if (playable) node.type = "button";
		node.dataset.card = card.id;
		node.dataset.uid = String(card.uid);
		node.style.setProperty("--i", String(index));
		node.style.setProperty("--off", String(index - (count - 1) / 2));
		const face = el("span", "bc-face" + (hasArt(card.id) ? "" : " no-art"));
		face.appendChild(cardImg(card.id, cardName(card.id)));
		face.appendChild(el("span", "badge", playable ? TEXT.BADGE_PLAYABLE : TEXT.BADGE_AUTO));
		if (card.rounds_left) face.appendChild(el("span", "bc-rounds", TEXT.BREAKS(card.rounds_left)));
		node.appendChild(face);
		const slip = el("span", "bc-slip");
		slip.appendChild(el("b", "bc-name", cardName(card.id)));
		slip.appendChild(el("span", "bc-desc", String(def.description || "")));
		if (playable) slip.appendChild(el("span", "bc-action", why || TEXT.PLAY_HINT));
		node.appendChild(slip);
		if (playable) {
			if (why) {
				node.disabled = true;
				node.classList.add("blocked");
			} else {
				node.addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
				node.addEventListener("click", () => useCard(card));
			}
		}
		return node;
	}

	function renderHand() {
		const me = mySeat();
		const dead = !!(me && !me.alive);
		const sig = hand.map((c) => `${c.uid}:${c.id}:${c.rounds_left || 0}:${(cardDef(c.id) || {}).type === "playable" ? playBlock(c, cardDef(c.id) || {}) : ""}`).join("|")
			+ "#" + Object.keys(cardDefs).length + (dead ? "d" : "");
		if (sig === handSig) return;
		handSig = sig;
		const box = $("hand-cards");
		box.textContent = "";
		box.style.setProperty("--n", String(Math.max(1, hand.length)));
		$("hand-title").textContent = hand.length ? TEXT.HAND_TITLE(hand.length, MAX_HAND) : (dead ? TEXT.HAND_DEAD : TEXT.HAND_EMPTY);
		const anyPlayable = hand.some((c) => (cardDef(c.id) || {}).type === "playable");
		$("hand-note").textContent = !hand.length ? (dead ? "" : TEXT.HAND_EMPTY_NOTE) : anyPlayable ? TEXT.HAND_NOTE : TEXT.HAND_NOTE_AUTO;
		hand.forEach((card, i) => box.appendChild(bigCard(card, i, hand.length)));
		if (!hand.length) {
			const empty = el("div", "hand-empty");
			empty.appendChild(cardImg("back"));
			box.appendChild(empty);
		}
		// Abklingzeit vorbei: Karten wieder freigeben
		const wait = PLAY_COOLDOWN_MS - (performance.now() - lastPlayAt);
		cancel("hand-cooldown");
		if (wait > 0) after("hand-cooldown", wait + 30, () => { if (cardMode) refreshCardMode(); });
	}

	function setCardMode(open) {
		if (open) {
			if (place !== "match" || !state) return;
			cardMode = true;
			cardTarget = null;
			handSig = "";
			const node = $("hand");
			node.classList.remove("hidden", "targeting");
			restartAnimation(node, "enter");
			renderHand();
			document.body.classList.add("cards-open");
		} else {
			cardMode = false;
			cardTarget = null;
			cancel("hand-cooldown");
			$("hand").classList.add("hidden");
			$("hand").classList.remove("targeting");
			if (ringOwner === "card") hideRing();
			document.body.classList.remove("cards-open");
		}
		renderHandBar();
	}

	// Kartenhand offen: Inhalt und (bei der Zielwahl) die erlaubten Ziele aktuell halten
	function refreshCardMode() {
		if (!cardMode) return;
		if (cardTarget) {
			const card = hand.find((c) => c.uid === cardTarget.uid);
			const def = card ? cardDef(card.id) || {} : null;
			if (!card || playBlock(card, def)) {
				closeCardTarget();   // Karte weg (gestohlen) oder nicht mehr spielbar
				return;
			}
			const options = cardTargets(card, def);
			const sig = Array.from(options).sort((x, y) => x - y).join(",");
			if (sig !== ringSig) openCardRing(card, def, options, true);
			return;
		}
		renderHand();
	}

	function useCard(card) {
		const def = cardDef(card.id) || {};
		if (playBlock(card, def)) return;
		Bus.Call("UiSound", "click");
		if (!def.target) {
			playCard(card.uid, 0);
			return;
		}
		cardTarget = { uid: card.uid, id: card.id };
		$("hand").classList.add("targeting");
		openCardRing(card, def, cardTargets(card, def), false);
	}

	function openCardRing(card, def, options, instant) {
		openRing("card", {
			options,
			seconds: 0,
			art: card.id,
			title: TEXT.TARGET_TITLE[card.id] || TEXT.TARGET_ANY,
			sub: TEXT.TARGET_SUB[card.id] || "",
			counts: def.target === "other_with_cards",
			onPick: (seat) => {
				Bus.Call("UiSound", "click");
				playCard(card.uid, seat);
			},
			instant,
		});
	}

	function closeCardTarget() {
		cardTarget = null;
		if (ringOwner === "card") hideRing();
		$("hand").classList.remove("targeting");
		handSig = "";
		if (cardMode) renderHand();
	}

	function playCard(uid, seat) {
		lastPlayAt = performance.now();
		Bus.Call("PlayCard", uid, seat);
		// Lua schliesst danach die Hand (CardMode false). Bis dahin nichts doppelt ausspielen:
		handSig = "";
		if (cardTarget && ringOwner === "card") closeCardTarget();
		else if (cardMode) renderHand();
	}

	function preloadCards() {
		Object.keys(cardDefs).concat(["back"]).forEach((id) => {
			const img = new Image();
			img.src = artUrl(id);
		});
	}

	// ------------------------------------------------------------ Events

	// Fehler in einem Handler duerfen das HUD nicht lahmlegen (Vorschau meldet console.error)
	function on(name, fn) {
		Bus.Subscribe(name, (...args) => {
			try {
				fn(...args);
			} catch (e) {
				console.error(`[DeathBox] ${name} failed:`, e && e.stack ? e.stack : String(e));
			}
		});
	}

	on("Init", (id) => {
		localId = Number(id);
		render();
	});

	on("Place", (kind) => {
		const next = kind === "match" ? "match" : "hub";
		if (next !== place) stopSpin();   // Ortswechsel bricht das Gluecksrad ab
		if (next === "hub") {
			hideAllCues();
			clearToasts();
			state = null;
			actCount = 0;
			lastPick = 0;
			resetAct();
			resetMemo(null);
			endAim();
			closeChoice("place");
			setCardMode(false);
			hand = [];
			handSeen.clear();   // naechste Show: Startkarte fliegt wieder ein
		}
		place = next;
		render();
	});

	on("Lobby", (json) => {
		const next = parse(json, "lobby");
		if (!next) return;
		lobby = next;
		lobbyAt = performance.now();
		if (place === "hub") render();
	});

	on("State", (json) => {
		const next = parse(json, "state");
		if (!next || typeof next !== "object") return;
		if (state && next.match !== state.match) {
			// anderer Tisch: nichts vom alten Tisch weiterzeigen
			hideAllCues();
			clearToasts();
			actCount = 0;
			lastPick = 0;
			resetAct();
			resetMemo(null);
		}
		const eventId = next.event && typeof next.event === "object" ? String(next.event.id) : null;
		if (eventId !== memo.id) resetMemo(eventId);
		state = next;
		stateAt = performance.now();
		stateSeq = ++msgSeq;
		if (place === "match") render();
	});

	on("Say", (text) => say(String(text)));
	on("Fx", (kind, seat) => fx(String(kind), Number(seat)));

	on("Show", (json) => {
		const data = parse(json, "show cue");
		if (data) cue(data);
	});

	on("Choice", (json) => {
		const data = parse(json, "choice");
		if (data) openChoice(data);
	});

	// Lua hat die Taste geschickt: Taste kurz gedrueckt zeigen, dann schliessen
	on("QtePressed", (key) => {
		if (!choice || choice.kind !== "qte") return;
		const hit = String(key).toUpperCase() === String(choice.prompt || "").toUpperCase();
		$("qte-key").classList.add("pressed", hit ? "hit" : "miss");
		choice = null;
		after("qte", 180, () => {
			if (!choice || choice.kind !== "qte") show("qte", false);
		});
		if (place === "match" && state) renderStage(mySeat());
	});

	on("ChoiceEnd", (ask) => {
		if (!choice) return;
		if (Number(ask) === 0 || Number(ask) === Number(choice.ask)) closeChoice("end");
	});

	// Zielmodus (Client/Aim.lua): bei jeder Aenderung des Ziels, sofort lokal (das Echo des Servers kommt spaeter)
	on("Aim", (json) => {
		const data = parse(json, "aim");
		if (!data || typeof data !== "object") return;
		if (data.active === false) {
			aimEnded(Number(data.ask) || aim.ask);
			return;
		}
		const ask = Number(data.ask) || aim.ask;
		if (aim.active && ask !== aim.ask) aim.ends = 0;   // neue Abfrage (z. B. nach einem Abgang neu gestellt)
		aim.active = true;
		aim.ask = ask;
		aim.seat = Math.max(0, Math.round(Number(data.seat) || 0));
		aim.name = typeof data.name === "string" ? data.name : "";
		aim.label = typeof data.label === "string" ? data.label : "";
		aim.hint = typeof data.hint === "string" ? data.hint : "";
		const warn = data.warn === true;
		if (warn && !aim.warn) restartAnimation($("aim"), "nudge");
		aim.warn = warn;
		const seconds = Number(data.seconds);
		if (seconds > 0) {
			const ends = performance.now() + seconds * 1000;
			if (Math.abs(ends - aim.ends) > 400) aim.ends = ends;
			aim.total = Math.max(Number(data.total) || 0, seconds, aim.total || 0);
		}
		if (place !== "match" || !state) return;
		renderAim();
		const me = mySeat();
		renderSeats(me);
		renderStage(me);
	});

	on("AimEnd", (ask) => aimEnded(Number(ask) || 0));

	on("Hand", (json) => {
		const before = hand;
		hand = parseHand(json);
		const kept = new Set(hand.map((c) => c.uid));
		const lost = before.filter((c) => !kept.has(c.uid)).map((c) => c.id);
		if (lost.length) lastLost = { ids: lost, at: performance.now() };
		if (isShown("pick")) renderPickHand();
		renderHandBar();
		if (cardMode) refreshCardMode();
	});

	on("CardDefs", (json) => {
		const defs = parse(json, "card defs");
		if (!defs || typeof defs !== "object") return;
		cardDefs = defs;
		preloadCards();
		handBarSig = "";
		handSig = "";
		renderHandBar();
		if (cardMode) refreshCardMode();
	});

	on("CardMode", (open) => {
		setCardMode(open === true || open === 1 || open === "true");
	});

	// Knoepfe der Kartenhand und der Kartenziel-Wahl
	$("hand-close").addEventListener("click", () => {
		Bus.Call("UiSound", "click");
		Bus.Call("CloseCards");
	});
	$("hand-close").addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
	$("ring-back").addEventListener("click", () => {
		Bus.Call("UiSound", "click");
		closeCardTarget();
	});
	["vote-spare", "vote-kill", "split-split", "split-steal", "ring-back"].forEach((id) => {
		$(id).addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
	});
	// Escape schliesst die Kartenhand (falls die WebUI die Taste ueberhaupt bekommt; C macht Lua)
	document.addEventListener("keydown", (e) => {
		if (e.key !== "Escape" || !cardMode) return;
		if (cardTarget) closeCardTarget();
		else Bus.Call("CloseCards");
	});

	// Schriften frueh laden, damit Messungen (Namen einpassen) stimmen
	if (document.fonts && document.fonts.load) {
		["Rye", "Creepster", "Special Elite"].forEach((family) => {
			document.fonts.load(`32px "${family}"`).catch(() => {});
		});
	}
})();
