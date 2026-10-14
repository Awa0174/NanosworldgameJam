# Verbesserungen bis zur Abgabe (23.10.2026)

Ausgangsstand war v0.10.0 des Owners, umgesetzt ist das in **v0.11.0**. Für den Jam ist der Server auf **12 Spieler** begrenzt, gespielt wird an **2 Tischen mit je 8 Plätzen**.

**Leitlinien:**
- Spieler spielen mit Spielern.
- Eine Show soll kurz Spaß machen.
- Fremde müssen das Spiel sofort verstehen.
- Beim Playtest darf nichts hängen.

**Was „getestet“ in dieser Datei bedeutet:** Alle Häkchen sind in der Server-Simulation geprüft (Szenarien `all` und `jam`, mehrere Seeds), außerdem im Client-Test und im HUD-Test in Chromium. **Im echten Spiel ist v0.11 noch nicht getestet.** Siehe Testplan unten.

## Erledigt in v0.11

### Kritisch
- [x] **Debug-Befehle sind aus** (`DEBUG_COMMANDS = false`).
  - Admins schaltet der Server-Betreiber in der Server-Konsole frei: `db_admin <name oder id>`. Das gilt bis zum Verlassen des Servers.
  - `db_status` zeigt Tische und Warteschlange.
- [x] **Bots ohne Debug:** Jeder neue Tisch wird bis 8 Plätze mit Bots aufgefüllt (`BOT_FILL`). Wer allein ist, startet nach 20 s.
- [x] **Keine eingefrorene Show mehr:**
  - Jeder Timer-Schritt und jede Eingabe läuft geschützt (`Match:Guard`). Ein Lua-Fehler beendet die Show sauber mit Sieger-Anzeige und Rückkehr in den Hub.
  - Zusätzlich gibt es einen Watchdog (`Server/Rescue.lua`): Läuft eine Show 60 s ohne Fortschritt, wird sie beendet.
- [ ] **Vor dem Playtest erledigt der Owner:** Egg auf den normalen Steam-Zweig umstellen, mit `--steam_app "game"` starten, `max_players = 12`.

### Matchmaking (Wunsch: 2 Tische à 8, erst einen füllen)
- [x] Wer joint, während eine Show mit lebenden Bots läuft, kommt sofort ins Zelt.
  - Im HUD steht „You're next!“.
  - Zu Beginn der nächsten Runde übernimmt er einen lebenden Bot, mit dessen Karten.
  - Alle sehen dazu: „X takes the seat of Bonzo“.
- [x] Tisch 2 öffnet erst, wenn an Tisch 1 kein Bot mehr übernommen werden kann.
  - Ausnahme: Warten 8 Menschen (zum Beispiel eine Gruppe nach ihrer Show), starten sie zusammen an einem neuen Tisch.
- [x] **Im Finale kommt niemand mehr dazu** (weniger als 4 Lebende). Wartende werden dann an einen anderen Tisch geschickt, falls dort Platz ist. Sonst schauen sie das Finale zu Ende.
- [x] Mit **Taste N** („Next show“) gehen Ausgeschiedene und Nachrücker in die nächste Show. Sie kommen nicht wieder an denselben Tisch.

### Tempo und Klarheit
- [x] **Zeiten gekürzt:**

  | Schritt | vorher | jetzt |
  |---|---|---|
  | Spin | 10 s | 8 s (Spieluhr-Melodien mit dem Synth des Owners neu erzeugt) |
  | Stille | 2 s | 1,5 s |
  | POP | 3 s | 2,5 s |
  | Karte beim ersten Mal / danach | 5 s / 3,5 s | 4,5 s / 2 s |
  | Ergebnis | 4 s | 2,5 s |
  | Intro | 12 s | 10 s |
  | Revolver-Zielzeit | 12 s | 8 s |
  | Abstimmung | 15 s | 10 s |
  | Kürbis-Zündschnur | 8–15 s | 6–11 s |

- [x] **Ergebnis:** Eine 8er-Show dauert in der Simulation mit menschlicher Bedenkzeit im Median 5,6 min (Spanne 4,3–8 min). Vorher waren es 7,75 min.
- [x] **Aktive Events:** Clown Roulette, Jack Snaps, The Knife Act, Fire Eater, Cheer or Jeer, Pass the Pumpkin, Quick Draw, dazu selten Party Favors.
  - Abgeschaltet (Gewicht 0, der Code bleibt): Chop Chop, Snip the Wire, Share or Snatch, Fortune Teller.
- [x] Jede Show beginnt mit Clown Roulette (`FIRST_EVENT`), das erklärt das Spiel am besten.
- [x] Tote Bots stimmen bei Cheer or Jeer nicht mehr ab. Bots stimmen zu 50 % statt 60 % für „Eliminate“.

### Eigene Namen
- [x] **Events:**

  | Original | neu |
  |---|---|
  | Revolver | Clown Roulette |
  | Angry Clown | Jack Snaps |
  | Knife Toss | The Knife Act |
  | Fire Breath | Fire Eater |
  | Spare or Eliminate | Cheer or Jeer |
  | Card Deal | Party Favors |
  | Stab Your Neighbour | Chop Chop |
  | Defuse or Die | Snip the Wire |
  | Split or Steal | Share or Snatch |
  | Choose a Card | Fortune Teller |

- [x] **Karten:**

  | Original | neu |
  |---|---|
  | Safety | Lucky Charm |
  | Skip | Body Double |
  | Ricochet | Funhouse Mirror |
  | Guardian | Bodyguard |
  | Thief | Pickpocket |

  Die Kartenbilder sind mit dem Generator des Owners neu erzeugt. Die IDs im Code bleiben gleich.

### Sicherheit und Robustheit
- [x] **Flutschutz pro Spieler:** Input 12/s, PlayCard 3/s, Aim 6/s, Leave 1/s.
- [x] Die Begrüßung kommt beim Event `Ready` statt bei `Spawn`, damit sie beim Client ankommt.
- [x] Diag schreibt nur noch für Admins.
- [x] **Client:**
  - Bleibt das `ChoiceEnd` aus, schließt eine Abfrage nach `seconds + 3` s selbst.
  - Beim Entladen des HUD wird die Maus zurückgesetzt.
  - Bei jedem Ortswechsel werden Abfragen und Kartenhand geschlossen.
  - Reaktionstasten und Taste N reagieren nicht, solange der Chat offen ist.

### Leistung
- [x] **Hub:** Die 42 Rahmen-Glühbirnen und die Leuchtschrift werden nur noch bei einer Änderung gesetzt (8×/s statt in jedem Frame). Flackerlichter laufen mit 20 Hz.
- [x] **Zelt:** Glühbirnen werden nur noch bei einer Stimmungsänderung gesetzt. Nebenbei behoben: Birnen blieben vorher bei 95 % hängen.
- [x] **Schatten aus:** beim Mond-Spot (Hub) und beim zweiten Ziel-Spot (Zelt). Der Bodennebel ist kleiner.

## Offen (optional, nach Priorität)

1. **Grafik einstellen:**
   - An einem Abend auf 2 PCs mit `db_exposure`, `db_light`, `db_look` die Werte finden und fest eintragen.
   - `Client.SetSettingGammaOverride` (`Client/Atmosphere.lua`) überschreibt die Helligkeit der Spieler. Auf einem dunklen Monitor prüfen.
2. **Kamera-Effekt:** Ein kurzer FOV-Ruck beim POP oder bei einem Tod (`Player:SetCameraFOV`).
3. **Farb-LUT** über `PostProcess.SetLookupTable`.
4. „How to play“ dauerhaft im Hub anzeigen.
5. **Nicht vor dem Jam:** `hud.js` und `style.css` aufteilen.

## Testplan (im Spiel, bitte mit 2–3 Leuten)

| # | Test | erwartet |
|---|---|---|
| 1 | Allein joinen | Hub-Tafel „NEXT SHOW IN 0:20 · 1 PLAYER“, danach eine Show mit 7 Bots, die erste Runde ist Clown Roulette |
| 2 | Zweiter Spieler joint während der Show | Er landet im Zelt („You're next!“), zur nächsten Runde verschwindet ein Bot, er sitzt dort: „YOU'RE IN!“ und Toast. Namensschild über dem Stuhl ist neu, Taste C zeigt die Karten des Bots |
| 3 | Taste N als Ausgeschiedener | Zurück in den Hub bzw. an den anderen Tisch, nie an denselben |
| 4 | Taste N als Lebender, Taste N im Chat | Es passiert nichts |
| 5 | Eine ganze Show durchspielen | ca. 5 min, kein Hänger, Rückkehr in den Hub |
| 6 | Jedes aktive Event einmal: `db_admin <name>` in der Server-Konsole, dann `/event revolver`, `angry`, `knife`, `fire`, `vote`, `pumpkin`, `duel`, `deal` | Pro Event notieren: funktioniert / verstanden / Spaß 1–5 |
| 7 | Musik | Die Spieluhr endet genau, wenn Jack stoppt (8 s). Im Intro POP am Ende der Melodie |
| 8 | Kartenbilder | Neue Namen auf allen 5 Karten |

**Abbruchkriterien:**
- Läuft bis **Sa 18.10.** keine fehlerfreie Show mit 4 oder mehr Menschen, keine neuen Features mehr, nur noch Fehler beheben.
- Ist das Asset-Pack bis **Mo 20.10.** nicht auf dem Server, wird es gestrichen.

## Zusammenarbeit
- v0.11 ist die neue Basis. Der Owner holt sie mit `git pull` und arbeitet darauf weiter, nicht auf seiner alten Kopie.
- Pro Datei arbeitet immer nur einer. Kleine Commits mit klarer Nachricht.
