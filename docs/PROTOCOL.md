# Protokoll (Vertrag zwischen Server, 3D-Regie und HUD)

Stand: v0.10 (14.10., Tempo, Klarheit, echtes Zielen mit dem Revolver). Dieses Dokument ist die **einzige Quelle der Wahrheit** für alle Nachrichten.
Wer etwas hinzufügt, trägt es hier ein. Alle JSON-Felder sind optional, wenn nicht anders angegeben.
Plätze (`seat`) sind Indizes in `State.seats`. Für jedes Platz-Feld (`seat`, `seat2`, `new_seat`, `shooter`, `holder`, `from`,
`target`) hängt der Server automatisch `<feld>_chair` (Stuhlnummer) an, plus `seat_count`. Platznummern laufen in
Stuhl-Reihenfolge: aufsteigend = im Uhrzeigersinn (Revolver-Weitergabe), ±1 = Nachbarn (Stab, Kürbis).

## Server -> Client (Remote Events)

| Event | Argumente | Bedeutung |
|---|---|---|
| `DeathBox:Place` | `kind`, `info_json` | `"hub"` oder `"match"`; info: `{ seat_count, jack_yaw, match }` |
| `DeathBox:Lobby` | `json` | Hub-Anzeige: `{ online, queued, needed, next_table, humans, seats, bots, tables, max_tables, timer:{total,remaining} }` (`humans` = Menschen am nächsten Tisch, `bots` = Bots, die ihn auf `seats` auffüllen; v0.11). Geht auch an die 3D-Anzeigetafel über dem Zelteingang im Hub (`Hub.SetLobby`) |
| `DeathBox:State` | `json` | Tischzustand (siehe unten) |
| `DeathBox:Say` | `text`, `voice` | Jacks Untertitel; `voice` = Kennung der Aufnahme (`chosen_2` → `Client/sounds/voice/chosen_2.ogg`, Liste `Shared/Voice.lua`) oder `""` |
| `DeathBox:Fx` | `kind`, `seat` | kleiner Sound/HUD-Effekt: `aim click bang safety qte_ok dodge stab block burn extinguish knife_raise fire chosen death winner` |
| `DeathBox:Show` | `json` | Regieanweisung `{ action, ... }` (Tabelle unten) |
| `DeathBox:Choice` | `json` | Abfrage für genau diesen Spieler (unten) |
| `DeathBox:ChoiceEnd` | `ask_id` | Abfrage schließen (0 = alle) |
| `DeathBox:Admin` | `enabled` | nur an diesen Spieler: Admin-Befehle per `db_admin` (Server-Konsole) an/aus. Der Client belegt dann Taste B (Noclip) |
| `DeathBox:Hand` | `json` | **privat**: eigene Kartenhand `{ cards: [ { uid, id, rounds_left? } ] }`. Kommt nach **jeder** Änderung, bei `RequestState` und leer beim Wechsel in den Hub (Ausgeschiedene haben keine Karten). `rounds_left` (nur Safety aus Guardian) zählt bei jeder neuen Runde herunter, bei 0 verschwindet die Karte. |

### State
```
{ match, phase: "STARTING"|"PLAYING"|"ENDED", seat_count, turn, winner, jack_yaw,
  round, stage: "intro"|"spin"|"skip"|"pop"|"card"|"event"|"result"|"ended",
  timer: {total, remaining}?,
  seats: [ { seat, chair, angle, name, id (Player-ID oder -1), bot, alive, cards (Anzahl),
             avatar? (Menschen: Steam-Bild "steam-avatar://<Ziffern>"), portrait? (Bots: 1..12 = img/portraits/botNN.png) } ],
  joining: [Player-ID],   -- Nachrücker: schauen im Zelt zu, übernehmen zu Beginn der nächsten Runde einen Bot-Platz (v0.11)
  event: { id, name, actors:[seat], awaiting:[seat], involved:[seat], focus, instruction_actor, instruction_others, final?,
           endangered?:[seat], data:{...} }? }
```
- `round`: laufende Runde (0 im Intro, 1 ab dem ersten Spin). Dreht Jack neu, weil ein Gewählter vor dem Event gegangen ist,
  zählt das nicht als neue Runde.
- `stage`: wo die Runde gerade steht (Stage-Zeile, auch nach Neuladen): `intro`, `spin` (inkl. Stille), `skip`, `pop`, `card`,
  `event`, `result` (Rundenergebnis, Cue `round_end`), `ended`.
- `event.instruction_actor` / `event.instruction_others`: **Stage-Zeilen**, sie wechseln mit jeder Phase des Events (Texte:
  `Shared/Text.lua`, `EVENTS.<id>.stage`). `instruction_actor` gilt für jeden Platz in `involved`, `instruction_others` für alle
  anderen (Zuschauer, Ausgeschiedene). Am Event-Ende steht dort das Ergebnis („BANG! Bonzo is OUT“).
- `event.involved`: wer gerade handeln muss oder sich vorbereiten soll = `awaiting` + z. B. der Messer-Gewählte im Intro
  („GET READY …“), der Revolver-Halter, während ihm der Revolver zugeworfen wird, nach einem Klick der nächste Halter
  („*click* - YOU get the gun next! …“), das Stab-Opfer vor dem Block, bei der Abstimmung alle Wähler (auch Ausgeschiedene).
- `event.final = true`: das Ergebnis steht fest (`Context:Conclude`): niemand muss mehr etwas tun, keine Kugel ist mehr
  unterwegs, nur noch die Ergebnis-Pause des Events läuft. Nur dann gibt es `event.endangered` = wer in diesem Event in Gefahr
  war (wie `survived` im Rundenergebnis, aber vor dem Filter „lebt noch“). HUD: „You survived!“ (eigener Platz darin und lebt),
  sonst „It's over – see who made it“; bei Events ohne Gefahr (Deal, Choose a Card, Split or Steal) bleibt die normale Zeile.
- `timer` (Restzeit, Regel (d) unten): jede offene Abfrage, außerdem `pop` (`REVEAL_TIME`), `skip` (`SKIP_TIME`), `card`
  (`duration`), jede „GET READY“-Phase der Events bis zur ersten Abfrage (`Context:Stage(..., seconds)`: Revolver
  `GIVE_TIME` / nach einem Klick `PASS_TIME`, Messer, Feuer, Bombe, Stab, Abstimmung, Kürbis bis zum ersten Wurf, Split or Steal
  inkl. Aufdecken), `result` (`RESULT_PAUSE`). Nie, wo die Zeit geheim ist (Duell bis „DRAW!“, Zündschnur des Kürbisses).
`event.data` je Event:
- `revolver`: `{ chambers: 6, spent, bullets, load_extra, holder, target }` (`spent` = bisherige Abzüge, `holder` = wer den
  Revolver gerade hat, `target` = worauf gezielt wird, fehlt während der Wahl).
  **`load_extra = true` (Standard, `Config.REVOLVER.LOAD_EXTRA`):** Nach jedem Klick lädt Jack eine Kugel nach und dreht die
  Trommel. `bullets` = geladene Kugeln für den nächsten Abzug (1, 2, 3 …), Chance = bullets / chambers („2 IN 6“).
  **`load_extra = false` (klassisch):** eine Kugel, `bullets` bleibt 1, Chance = 1 / (chambers − spent).
- `vote`: `{ target, spare, kill, voted, voters, secret }` (Live-Zählung; bei `secret` fehlen `spare`/`kill` bis zum Ergebnis,
  `voted`/`voters` = abgegebene/mögliche Stimmen; geht ein Wähler, ohne abzustimmen, sinkt `voters`)
- `pumpkin`: `{ holder }`
- `splitsteal`: `{ a, b, locked_a, locked_b }` (nur ob schon gewählt, nicht was)
- `gallery`: `{ targets: [seat, seat, seat], aim }` (`targets` = linker Nachbar, Gewählter, rechter Nachbar in Schussreihenfolge,
  `aim` = auf wen Jack gerade anlegt, fehlt zwischen den Schüssen)

## Client -> Server

| Event | Argumente | Prüfung auf dem Server |
|---|---|---|
| `DeathBox:Input` | `ask_id`, `choice` (Zahl oder Text ≤ 32) | Abfrage offen für diesen Platz, ID stimmt, Wahl erlaubt |
| `DeathBox:Aim` | `ask_id`, `seat` (0 = zielt auf niemanden) | Revolver-Zielmodus. Nur ganze Zahlen; höchstens 6 pro Sekunde je Spieler (der Rest wird verworfen). Abfrage `ask_id` ist offen für den Platz des Absenders und hat `aim = true` (= Halter in der Wahl-Phase); `seat` = 0 oder ein lebender Platz aus den `options` dieser Abfrage. Gültig → Show `revolver_aiming` an den Tisch (höchstens 5 pro Sekunde, die neueste Wahl gewinnt) und die sitzende Figur des Halters dreht sich zum Ziel. Geschossen wird wie immer mit `DeathBox:Input` (gleiche `ask_id`, Platznummer) |
| `DeathBox:RequestState` | – | gedrosselt (1/s) |
| `DeathBox:PlayCard` | `uid`, `target_seat` (0 = keins) | nur in `PLAYING`, Spieler sitzt und lebt, besitzt die Karte (uid), Karte ist ausspielbar, Ziel gültig (guardian: lebender Platz, auch man selbst, mit Platz auf der Hand; thief: anderer Lebender mit ≥ 1 Karte), max. 1 erfolgreich gespielte Karte pro 2 s. Abgelehnt = nichts passiert, die Karte bleibt. Erfolg = Show `card_play` + neue Hand |
| `DeathBox:Leave` | – | Taste N „Next show“: nur Ausgeschiedene und Nachrücker (wie `/leave`), höchstens 1/s. Danach nicht wieder an denselben Tisch |
| `DeathBox:Diag` | `index`, `total`, `text` | Selbstdiagnose, nur von Admins |
| `DeathBox:ToggleNoClip` | – | nur Admins (DEBUG oder `db_admin`) |

Flutschutz (Token-Eimer pro Spieler, `Server/Net.lua`): `Input` 12/s, `PlayCard` 3/s, `Aim` 6/s, `Leave` 1/s; der Rest wird verworfen.

## Lua <-> WebUI (Client/HUD.lua <-> Client/UI/hud.js)

Lua -> JS: `Init(local_player_id, version)`, `Place(kind)`, `Lobby(json)`, `State(json)`, `Say(text)`, `Fx(kind, seat)`,
`Show(json)` (wie oben, bei `spin` ergänzt um `ticks:[{t,seat}]`, bei `pop` um `me`), `Choice(json)`, `ChoiceEnd(ask_id)`,
`QtePressed(key)`, **`Hand(json)`** (eigene Karten), **`CardMode(open)`** (Kartenhand per Taste C auf/zu; Maus ist dann frei),
**`CardDefs(json)`** (einmal nach Ready: `{ <id>: { name, description, type, target, art } }` aus Shared/Cards.lua; Bilder: `img/cards/<id>.png`),
**`Aim(json)`** (Revolver-Zielmodus, bei Start und jeder Zieländerung: `{ ask, seat (0 = niemand), chair, name, label
("AIMING AT NIBBLES – CLICK TO SHOOT" bzw. "AIM AT A PLAYER – CLICK TO SHOOT"), hint, warn (true = Klick ohne Ziel), seconds
(Restzeit), total, crosshair: true }`), **`AimEnd(ask, reason)`** (`"confirm"` = geschossen, `"closed"`, `"end"`, `"place"`,
`"restart"`, `"timeout"`).

JS -> Lua: `Choose(ask_id, value)`, `UiSound("hover"|"click"|"your_turn"|"round_out"|"round_safe")` (Stings aus
`Client/sounds/<name>.ogg`, andere Namen werden ignoriert), **`PlayCard(uid, target_seat)`** (target_seat 0 = ohne Ziel),
**`CloseCards()`**.

Zielmodus (Client/Aim.lua): Abfrage `target` mit `aim = true` -> die WebUI bekommt `Choice(json)` wie immer (YOUR TURN, Zeit),
aber **keinen Ring**; die Maus bleibt gefangen (WebUI nicht klickbar), Lua sucht jedes Bild den Platz am Kamerastrahl (≤ 10°,
Kopf oder Brust), schickt `Aim(json)` und `DeathBox:Aim` (≤ 5/s), die linke Maustaste wählt über denselben Weg wie `Choose`
(`DeathBox:Input`). Das Echo `revolver_aiming` des eigenen Zielens geht nur ans HUD, wenn es zum lokalen Stand passt (sonst
verworfen). `round_end`, `spin`, `intro`, `winner` und Ortswechsel schalten alle Markierungen und Zielposen aus.
Client-API für die Regie: `DeathBox.Highlight.Set(seat | {seats}, "actor"|"target", keep?)`, `.Clear(kind?)`,
`.FindCharacter(seat)` (Client/Highlight.lua: Index 0 GOLD = gewählt/am Zug, 1 ROT = Ziel/in Gefahr, ROT gewinnt);
`DeathBox.Poses.SetAiming(character, on)` (Oberkörper-Zielpose); `DeathBox.Revolver.Hold/Release` (Revolver in der Hand).
Markierungen der Regie: Starren im `spin` ROT, `pop` GOLD, Revolver Halter GOLD + Ziel ROT, `knife_raise`/`fire_breath`/
`angry_aim` (wandert bei der Gallery mit)/`vote_start`/`bomb_start` ROT auf `seat`, `stab_raise` `holder` GOLD + `seat` ROT,
`pumpkin_start`/`pumpkin_pass` ROT wandert mit dem Halter, `duel_start`/`splitsteal_start` beide GOLD; `round_end` löscht alles.
Konsole: `db_aimanim <anim> [rate] [hold]`, `db_gunhand <x> <y> <z> [palm] [scale] [bone]`, `db_hl <füllung> [helligkeit] [umriss]`,
`db_aimcone <grad>`.

Kartenhand-Ablauf im HUD: Taste C -> `CardMode(true)` -> Hand groß unten, ausspielbare Karten (guardian, thief) klickbar ->
bei Karten mit Ziel erscheint der Ziel-Ring (erlaubte Ziele: guardian = alle Lebenden inkl. dir, thief = andere Lebende mit Karten
laut `State.seats[].cards`) -> `PlayCard(uid, seat)`. Automatische Karten (safety, skip, ricochet) sind nur sichtbar, nicht klickbar.
`CardMode(false)` schließt alles. Während einer eigenen Abfrage ist die Hand gesperrt.

## Abfragen (`DeathBox:Choice`)
Gemeinsam: `{ ask, event, kind, options, seconds, ... }`

**HUD-Sperre:** Der Server würfelt nur Events aus, deren Abfrage-Arten (`kinds` im Event-Modul) alle in
`Config.HUD_CHOICE_KINDS` (Shared/Config.lua) stehen – wer eine Frage nicht sieht, darf an ihr nicht sterben. Ausgeliefert: alle
acht Arten dieser Tabelle (`target`, `qte`, `click`, `vote`, `pass`, `splitsteal`, `pickcard`, `wire`; die fünf neuen seit dem
HUD-Stand vom 14.10.). **Wer eine neue Art einführt, trägt sie dort erst ein, wenn das HUD ihr Panel hat.**
`/event <id>` erzwingt ein Event trotzdem (zum Testen der Panels).

| kind | Zusatzfelder | Anzeige | Antwort |
|---|---|---|---|
| `target` | `aim` (nur Revolver, dann `true`) | Ring mit Plätzen, erlaubte = options. **Mit `aim = true` kein Ring, sondern Zielmodus:** Revolver in der rechten Hand, Maus bleibt gefangen und steuert die Kamera, Fadenkreuz; Ziel = lebender Platz aus `options` (nie man selbst), dessen Kopfpunkt den kleinsten Winkel zum Kamerastrahl hat (höchstens 10°); jede Änderung per `DeathBox:Aim` (max. 5/s); linke Maustaste schießt | Platznummer |
| `qte` | `prompt`, `label`, `step`, `steps` | große Taste (W/A/S/D), Eingabe liest Lua per KeyDown | Taste als Text |
| `click` | `x`, `y` (Prozent), `progress`, `total` | springende Flamme | das eine Token |
| `vote` | `target` (Platz), `target_name` | Panel SPARE (grün) / ELIMINATE (rot), Live-Zählung aus State. Gefragt werden alle Plätze mit verbundenem Spieler – **auch Ausgeschiedene** – außer dem Opfer | `"spare"` / `"kill"` |
| `splitsteal` | `partner` (Platz), `partner_name` | Panel SPLIT / STEAL, geheim | `"split"` / `"steal"` |
| `pass` | – | Ring, nur Nachbarn erlaubt ("Pass the pumpkin!"), options = 1–2 lebende Nachbarn. Läuft `seconds` ab, kommt sofort eine neue Abfrage, solange die Zündschnur brennt | Platznummer |
| `pickcard` | `cards: [card_id]` (= options, verschiedene Karten) | 3 Karten zur Wahl. Zeitlimit = Jack zieht zufällig | card_id |
| `wire` | `wires: [{color, number}]` (3, Farben red/green/blue), `rule` (Text aus Jacks Manual) | Bombe: drei Drähte mit Nummern + Manual-Zeile, Draht anklicken = kappen | `"red"`/`"green"`/`"blue"` |

Verlässt ein angebotener Platz die Show, schickt der Server dieselbe Abfrage mit **neuer** `ask`-ID, angepassten `options` und
der Restzeit erneut (gilt für `target` und `pass`, auch im Zielmodus: dann mit der neuen `ask`-ID weiterzielen; der Client meldet seinen aktuellen Stand mit der neuen ID einmal neu, auch 0). Antworten auf
Plätze, die nicht mehr leben, werden abgelehnt.

## Regieanweisungen (`DeathBox:Show`, action = …)

| action | Felder | 3D/Ton (Client/Presentation.lua) | HUD |
|---|---|---|---|
| `intro` | `duration, pop_at, music` (`duration` = `INTRO_TIME` 10 s, `pop_at` = Sekunde des POP = `INTRO_POP_AT`, `music` = `INTRO_MUSIC`) | Jack in der Kiste, Spieluhr, POP heraus | Titel-Intro + „How to play“ |
| `spin` | `seat, start_yaw, target_yaw, turns, duration, hold, music, actors` — `actors` = alle Gewählten (Duell, Split or Steal: zwei; `[1]` = `seat`), `turns` = 1 (Weg = `turns`·360° + Rest bis `target_yaw`, also 1–2 Umdrehungen), `duration` = `SPIN_TIME` (8 s), `hold` = `HOLD_TIME` (1,5 s), `music` = zufällig aus `Config.SPIN_TUNES`, nie zweimal hintereinander dieselbe (jede genau `SPIN_TIME` lang, Ritardando, endet auf dem Stopp). Kein schneller Spin mehr | Jack lugt aus der offenen Kiste und dreht sich langsam mit, roter Suchscheinwerfer streift die Stühle (Flackern + Tick), Kriechen am Ende, Stopp; Stille + Herzschlag (`hold`): Jack starrt das Opfer an (Kopf kippt, Strahl heller, Opfer ROT markiert) | „JACK IS CHOOSING…“, Sitzliste aus (Client ergänzt `ticks:[{t,seat}]`) |
| `pop` | `seat, name, actors` (`actors` = alle Gewählten, `[1]` = `seat`; nach einem Skip schon mit dem Ersatz) | Jack schießt aus der offenen Kiste heraus und beugt sich übers Opfer: Stoß bis ca. 50 cm vor sein Gesicht, dann schwebt Jacks Gesicht ca. 1 m davor und lacht; alle Gewählten GOLD markiert (bleibt bis `round_end`, ROT gewinnt, sobald es in Gefahr ist) | großer Name (zwei Gewählte: „MUMBLES & YOU“); Stage-Zeile „JACK PICKED MUMBLES & YOU“, der zweite Gewählte liest „It's YOU too“ (schon beim Starren im `spin`), nie „Not you“ |
| `skip` | `seat, new_seat, name, new_name, target_yaw` | Karte zerbricht, Jacks Blick (Suchstrahl) reißt zum neuen Opfer herum, kurzes Starren (neues Opfer ROT) | „SKIP!“ — kommt statt des `pop`; `SKIP_TIME` (3 s) später folgt `pop` auf `new_seat`. Höchstens einmal pro Runde |
| `card` | `event, name, tagline, rules, duration, seat, seat2?, actors, who, how, you_actor, you_others, first, round` — `actors` = Gewählte (Liste), `who` = wer mit Namen („Nibbles gets the revolver“, „Nibbles vs Bonzo“), `how` = 2–3 Stichpunkte, `you_actor` (für Plätze in `actors`) / `you_others` (alle anderen) = fertige Zeile mit „YOU: …“, `first` = erstes Mal in dieser Show (`duration` dann `CARD_TIME` 4,5 s, sonst `CARD_TIME_REPEAT` 2 s) | Trommelwirbel; bei `event = "choosecard"` fächert Jack drei leuchtende Karten vor dem Gewählten auf | Event-Karte |
| `point` | `seat` | Jack dreht sich kurz hin | – |
| `revolver_give` | `seat` | 3D-Revolver (eigenes Modell, `Client/World/Revolver.lua`) fliegt aus Jacks Hand in die rechte Hand des Halters (Knochen `hand_r`), Trommel wirbelt. Die Zielabfrage (`aim = true`) folgt `REVOLVER.GIVE_TIME` (2,5 s) später | – |
| `revolver_aiming` | `shooter, seat` (`seat` = 0: zielt auf niemanden) | Nur in der Wahl-Phase. Die sitzende Figur des Halters dreht sich (Server) zum Ziel, der Revolver in seiner Hand zeigt hin. Menschen: per `DeathBox:Aim`; Bots schwenken 2–3-mal, bevor sie wählen | Highlight Halter GOLD, Ziel ROT; Stage-Zeile „NIBBLES IS AIMING AT BONZO…“. Gilt bis zum nächsten `revolver_aiming`, `revolver_aim`, `revolver_shot`, `revolver_pass` oder `round_end` |
| `revolver_aim` | `shooter, seat, aim_time, chamber, chambers, bullets` (`chamber` = Nummer des Abzugs, 1–6; `seat` = shooter, wenn Jack den Zögernden auf sich selbst zielen lässt) | Revolver zielt aufs Ziel (bzw. dem Halter ins Gesicht), Hahn gespannt, Hand zittert, Spot, Herzschlag | Chance anzeigen: `bullets` IN `chambers` (klassisch: 1 IN chambers − chamber + 1) |
| `revolver_shot` | `shooter, seat, result ("click"/"dead"/"safety"/"ricochet"), chamber, chambers, bullets` — beim Angry Clown und bei der Shooting Gallery ohne `shooter` (Jack schießt mit seinem eigenen Revolver) und ohne Kammern/Kugeln | Klick (Trommel dreht weiter) oder Schuss (Mündungsfeuer, Rückstoß, Revolver fällt) | – |
| `revolver_pass` | `from, seat, bullets, chambers` (`bullets` = Kugeln für den nächsten Abzug). Kommt `REVOLVER.PASS_DELAY` (0,8 s) nach dem Klick (`revolver_shot` mit `click`); die Zielabfrage des neuen Halters folgt `PASS_TIME` (3 s) nach dem Klick, er hat den Revolver also gut 2 s vorher in der Hand. Geht der Empfänger vorher, fliegt der Revolver gleich zum nächsten Lebenden (Stage-Zeile nennt ihn); geht er danach, bekommt ihn der nächste Lebende beim Zielen | Revolver fliegt zum neuen Halter (nach Klick: zum Ziel; nach Klick auf sich selbst oder wenn der Halter geht: nächster Lebender im Uhrzeigersinn); mit `load_extra` fliegt eine Patrone aus Jacks Hand hinein | „THE GUN PASSES TO …“ + „JACK LOADS ANOTHER BULLET: 2 IN 6“ (wenn bullets > 1) |
| `ricochet` | `from, seat` | Querschläger zu neuem Opfer | „RICOCHET!“ — Revolver/Angry/Gallery/Duell: `death` bzw. `card_trigger` des neuen Opfers folgt `RICOCHET_TIME` (1,2 s) später |
| `knife_raise` / `knife_throw` | `seat` / `seat, hit` | Messer | – |
| `fire_breath` / `fire_off` | `seat, delay` / `seat, survived` | Feuer | – |
| `stab_raise` / `stab_strike` | `seat, holder` / `seat, blocked` | Hackbeil | – |
| `angry_aim` | `seat, aim_time` | Jack zielt selbst. Angry Clown: einmal. Shooting Gallery: einmal pro Ziel, nacheinander (linker Nachbar, Gewählter, rechter Nachbar; das erste Anlegen dauert länger) | – |
| `vote_start` | `seat, name, duration, secret, intro` (`intro` = Sekunden, bis die Abstimmung öffnet; `duration` zählt ab dann) | Licht auf das Opfer | Abstimmungs-Banner |
| `vote_result` | `seat, spare, kill, result ("spare"/"kill"), tie` (`tie` = Gleichstand, Jack hat eine Münze geworfen) | – | Ergebnis; das Urteil (`death`/`survive`) folgt 2,6 s später |
| `pumpkin_start` | `seat, duration_hint` (= längste mögliche Zündschnur in s; die echte ist geheim) | Kürbisbombe fliegt zum Halter, Zündschnur | „PASS THE PUMPKIN!“ |
| `pumpkin_pass` | `from, seat` | Kürbis fliegt weiter | – |
| `pumpkin_boom` | `seat` | Explosion | – |
| `splitsteal_start` | `seat, seat2, name, name2` | zwei Spots | Split-or-Steal-Banner |
| `splitsteal_result` | `seat, seat2, choice, choice2, gained, gained2` (`gained` = Änderung der Kartenzahl, negativ = verloren) | – | Ergebnis |
| `bomb_start` | `seat, seconds, intro` | Bombe vor den Füßen, LED-Countdown, Blinken | „DEFUSE OR DIE“ |
| `bomb_result` | `seat, defused, wire` | entschärft (LED grün) oder BOOM | Ergebnis |
| `duel_start` | `seat, seat2, name, name2` | zwei Spots, Stille, Herzschlag | „QUICK DRAW: A vs B“ |
| `duel_draw` | `seat, seat2` | Glocke, Blitz | riesiges „DRAW!“ (die Taste kommt als `qte`-Abfrage mit label "DRAW!") |
| `duel_result` | `seat, seat2, result ("win"/"misfire"/"both"/"jack")` | Treffer | bei win: seat = Sieger, seat2 = Verlierer („YOU were faster · fires at Bonzo“ – ob er getroffen ist, entscheiden erst Ricochet/Safety); misfire: seat = Pechvogel. Ein Querschläger (`ricochet`) trifft wie beim Revolver erst `RICOCHET_TIME` später, die Stage-Zeile nennt danach das Opfer („BANG! X is OUT“) |
| `deal` | `seats:[seat], count` (Empfänger, aufsteigend; volle Hände werden übersprungen) | Karten fliegen | „N PLAYERS WILL NOW BE GIVEN CARDS“ |
| `card_gain` | `seat, count` | Karte fliegt zum Spieler (Choose a Card: die mittlere der drei schwebenden Karten, die anderen zurück in die Kiste; `/card`: aus der Kiste) | Toast „X takes a card“ |
| `card_play` | `seat, card, target` | Karte leuchtet über dem Spieler | Toast „X used THIEF on Y“ |
| `card_trigger` | `seat, card` | Karte zerbricht | Toast „SAFETY saved X“ — nur Safety; Skip und Ricochet haben eigene Cues (`skip`, `ricochet`) |
| `death` | `seat, name, left?` | Licht bricht ein, Blut, Lachen | „ELIMINATED“ |
| `survive` | `seat, name` | Posaune, Jack enttäuscht | „SURVIVED“ — am Ende eines Events (ausgewichen, gelöscht, geblockt, Safety, verschont, Duell kampflos gewonnen). Nicht bei Revolver-Klicks |
| `round_end` | `round, alive, out:[seat], survived:[seat], left?:[seat]` — `out` = in dieser Runde ausgeschieden (inkl. Gegangene), `left` = davon gegangen (fehlt, wenn leer), `survived` = war in dieser Runde in Gefahr (anvisiert, beschossen, Messer, Feuer, Hackbeil, Abstimmung, Kürbis gehalten, Bombe, Duell) und lebt noch, `alive` = Lebende danach | Highlights aus | Rundenergebnis-Karte „ROUND 7 – Bonzo is OUT · 12 left“. Kommt nach **jedem** Event direkt vor `RESULT_PAUSE` (2,5 s), auch vor `winner` |
| `winner` | `seat, name` (seat 0 = niemand) | Spot, Konfetti | Sieger-Plakat |
| `finale` | `seat, seat2` — nur noch zwei leben (einmal pro Show, direkt vor dem letzten Spin). Danach immer `Config.FINALE_EVENT` (Duell) mit Karte „Final Showdown“; drückt keiner, zieht Jack bis zu `FINALE_REDRAWS`-mal neu (Stage `again`), dann `duel_result` mit `result = "jack"` (seat = Getroffener) | Trommelwirbel, rote Spots auf beiden, Jack lacht, Kamera-Ruck | großes „FINAL SHOWDOWN“ + Ansage |
| `seat_taken` | `seat, name, old` — Nachrücker `name` übernimmt den Bot-Platz `seat` von `old`. Kommt zu Beginn einer Runde direkt vor `spin`, NACH dem State (wer sitzt wo) | Funkeln, Schild „NEW: name“ steigt auf | Toast „name takes the seat of old“ (nicht für ihn selbst) |
| `you_joined` | `seat, old, cards` — nur an den Nachrücker (`Net.ShowTo`) | goldener Blitz, Sting | großes „YOU'RE IN!“ + Toast „You took old's seat · N cards, press C“ |

## Synchronisierte Werte an Figuren (`character:GetValue`)

| Schlüssel | Wert | Bedeutung |
|---|---|---|
| `DB_Seat` | Platznummer, 0 = an keinem Platz | Figur dieses Platzes am Tisch (Spieler **und** Bots). Gesetzt beim Hinsetzen, 0 beim Versetzen (Hub, Zuschauerplatz). Ausgeschiedene Bots behalten ihn (liegen am Platz). Fallback: nächste Figur zu `Layout.SitTransform(chair)` |
| `DB_Chair` | Stuhlnummer, 0 = keiner | Stuhl dazu |
| `DB_SitAnim` | Animation oder `false` | sitzt: jeder Client spielt die Pose selbst (Client/Poses.lua) |

Die Blickrichtung (Yaw) einer sitzenden Figur setzt der Server: zur Mitte, beim Revolver-Halter zum Ziel (`revolver_aiming`,
`revolver_aim`); am Event-Ende und bei der Weitergabe wieder zur Mitte.

## Klarheit: Stage-Zeile, YOUR TURN, Rundenergebnis (Regeln fürs HUD)

Jederzeit muss lesbar sein: (a) Phase, (b) wer beteiligt ist, (c) was ICH tun muss – oder „nur zuschauen“, (d) Restzeit.
- **Stage-Zeile** oben in der Mitte, genau eine, nichts überdeckt sie: `stage = intro` „THE SHOW BEGINS…“ · `spin` „JACK IS
  CHOOSING…“ · `pop` „JACK PICKED NIBBLES“ / „JACK PICKED YOU!“ · `card` „REVOLVER – Nibbles gets the revolver“ (`name` + `who`) ·
  `event` → `instruction_actor`, wenn der eigene Platz in `event.involved` steht, sonst `instruction_others` (während der
  Revolver-Wahl ersetzt `revolver_aiming` sie durch „Nibbles is aiming at Bonzo…“) · `result` → Rundenergebnis (`round_end`).
- **YOUR TURN**: Sobald für mich eine Abfrage offen ist (`DeathBox:Choice`, eigener Platz in `event.awaiting`): großer Hinweis +
  `instruction_actor` + Zeitbalken (`seconds` bzw. `State.timer`) + Sting.
- **Event-Karte** (`card`): Name, `who`, `how` (Stichpunkte), „YOU“-Zeile (`you_actor`, wenn der eigene Platz in `actors` steht,
  sonst `you_others`). Beim ersten Mal (`first`) länger.
- **Rundenergebnis** (`round_end`) während `RESULT_PAUSE`; Sitzliste während `spin`/`pop` ausblenden.
- **Eigener Name = YOU**: Server-Texte (Stage-Zeile, Detail-Zeile, `who`/`how` der Karte) nennen alle Spieler beim Namen; das HUD
  ersetzt den eigenen Namen durch „YOU“ und passt einfache Verben an („BANG! YOU are OUT“, „YOU pull the trigger on …“, „YOUR
  feet“). Nicht bei Namen unter 3 Zeichen, „Jack“ oder Namen, die selbst ein Wort der Texte sind.
- **Nach dem eigenen Zug**: Revolver-Halter nach dem Abzug „You pulled the trigger – if it clicks, Bonzo shoots next“; Ziel
  „That's YOU in the sights – pray it clicks“; ab `event.final` keine Gefahr-Zeile mehr (siehe oben).
- **Ausgeschiedene Wähler** (Spare or Eliminate): Karte und Vorbereitung = GET READY, dann YOUR VOTE, danach „You voted SPARE –
  wait for the count“ bzw. „You did not vote“; erst ab `event.final` wieder „You are out – just watch“.

## Karten (Shared/Cards.lua)

Seit v0.11 sehen Spieler eigene Namen (Spalte „Name“); im Code und im Protokoll bleiben die ids.

| id | Name | Typ | Wirkung |
|---|---|---|---|
| `safety` | Lucky Charm | auto | Überlebt einen Schuss (Revolver, Angry Clown, Shooting Gallery, Duell). Verbraucht. Die zuerst verfallende Safety wird zuerst verbraucht. |
| `skip` | Body Double | auto | Wählt Jack dich für ein Event aus, in dem du selbst in Gefahr bist (Angry Clown, Shooting Gallery, Knife, Fire, Vote, Pumpkin, Bomb, Duell), ist ein zufälliger anderer dran. Beim Duell gilt das für beide Duellanten (der Ersatz steht dann vorne, der POP zeigt ihn). Verbraucht. Höchstens ein Skip pro Runde: der Ersatz kann nicht weiter-skippen. |
| `ricochet` | Funhouse Mirror | auto | Ein Schuss auf dich (Revolver, Angry Clown, Shooting Gallery, Duell) trifft stattdessen einen zufälligen anderen Lebenden – auch den Schützen. Verbraucht. Greift vor Safety; keine Kette (beim neuen Opfer greift nur noch Safety). |
| `guardian` | Bodyguard | ausspielbar, Ziel: ein lebender Spieler (auch du) mit Platz auf der Hand | Gibt dem Ziel eine Safety mit `rounds_left` = 3 (verfällt nach 3 Runden). |
| `thief` | Pickpocket | ausspielbar, Ziel: ein anderer lebender Spieler mit Karten | Stiehlt eine zufällige Karte (sie behält uid und Restlaufzeit). |

Hand privat (nur Anzahl öffentlich). Maximal 5 Karten (was nicht mehr passt, verfällt). Start: 1 zufällige Karte (nach Gewicht).
Bots spielen Guardian/Thief selbst: zu Beginn einer Runde mit `Config.CARDS.BOT_PLAY` höchstens eine Karte (Cue `card_play` wie bei Menschen).
Mehr über `deal` (Jack verteilt an ⌈Lebende/3⌉, der Gewählte ist immer dabei), Split or Steal, Choose a Card. Debug: `/card <id>`.
Reihenfolge, wenn mehrere greifen: Skip (bei der Auswahl) → Ricochet → Safety (beim Treffer).

## Chat

Chat-Zeilen gehen nur an die eigene Instanz (Hub-Bereich bzw. Tisch inkl. Zuschauer). Der Server verteilt sie selbst per
`Chat.SendMessage` (`<bold>Name</>: Text`, Zuschauer `<grey>`), unterdrückt die Engine-Nachricht, entfernt Text-Stile aus der
Eingabe, kürzt auf 200 Zeichen und lässt pro Spieler höchstens eine Zeile pro 0,75 s durch.
