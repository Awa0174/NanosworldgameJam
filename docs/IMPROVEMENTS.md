# Verbesserungen bis zur Abgabe (23.10.2026)

Ausgangsstand ist v0.10.0 des Owners. Der Server wird vor der Abgabe auf **12 Spieler** begrenzt.
Bei der Gewichtung zählen kurzer Spaß, Verständlichkeit für fremde Spieler und Stabilität beim öffentlichen Playtest (30.10.–01.11.).

Grundlage sind drei Code-Reviews (Spieldesign, Server, Client). Ausgeführt oder im Spiel getestet wurde dabei nichts.
- **[V]** = im Code nachgeprüft
- **[S]** = Schätzung (z. B. Partielänge aus einem Rechenmodell)

---

## Kritisch: muss vor dem Playtest erledigt sein

| # | Problem | Datei | Fix |
|---|---|---|---|
| K1 | `DEBUG_COMMANDS = true` und keine Admin-Prüfung. Jeder Fremde kann `/stop`, `/card`, `/god`, `/noclip`, `/sitpos` und Noclip auf B nutzen. Außerdem schreibt Diag Dateien auf den Server. [V] | `Shared/Config.lua:287`, `Server/Commands.lua` | Vor dem Playtest auf `false` setzen. Wenn ihr Debug trotzdem braucht: eine Steam-ID-Whitelist in `Commands.Handle`. |
| K2 | Bots gibt es nur über `/bots`. Ist Debug aus, wartet ein einzelner Spieler endlos auf „Waiting for more victims (1/2)“. [V] | `Server/Lobby.lua:24, 92, 143, 187` | Neuer Wert `Config.BOT_FILL_TO = 6`. In `NextTableSize()`: `bots = math.max(Lobby.bot_count, Config.BOT_FILL_TO - real)` |
| K3 | Wirft ein Timer-Callback einen Lua-Fehler, hängt die Show für immer: Die Spieler sitzen eingefroren, und es gibt keinen Watchdog. [V] | `Server/Events.lua:275-284` (`Context:After`), `Server/Match.lua:155-161` (`SetMatchTimer`) | Den Callback mit `pcall` umschließen. Bei Fehler `Console.Error` aufrufen und das Match mit `End()` beenden. |
| K4 | Server-Branch steht noch auf Bleeding-Edge. | Pterodactyl-Egg | Vor dem Playtest auf den normalen Steam-Branch umstellen und mit `--steam_app "game"` starten. |

## Wichtig: deutlich besseres Spielgefühl oder weniger Risiko

### W1: Matchmaking für 12 Spieler
Mit `MIN_PLAYERS = 2` und 15 s Countdown entstehen lauter 2er-Tische, sobald Spieler nacheinander joinen.
`QUEUE_COUNTDOWN_FULL` greift nie, weil 16 Plätze bei einer 12er-Grenze nicht voll werden. [V]

**Empfehlung, nur in der Config:**

| Konstante | alt | neu |
|---|---|---|
| `TABLE_SEATS` | 16 | **8** (Alternative: 12, siehe unten) |
| `MAX_MATCHES` | 64 | **2** |
| `HUB_CAPACITY` | 64 | 12 (macht keinen Unterschied, ist nur ehrlicher) |
| `QUEUE_COUNTDOWN` | 15 | **25** |
| `MIN_PLAYERS` | 2 | 2 bleibt, die Bot-Füllung aus K2 sorgt für volle Tische |
| Server-`Config.toml` | 999 | `max_players = 12` (diese Datei liegt nicht im Repo) |

- **8 Plätze:** Partien sind kürzer, und wer spät kommt, wartet weniger, weil ein zweiter Tisch starten kann.
- **12 Plätze:** Alle sitzen in einer großen Show, die aber etwa 6 min statt 4–5 min dauert. Die Entscheidung liegt beim Owner.
- **Instanzen und Hub-Shards bleiben im Code:** Sie schaden nicht, ein Umbau wäre riskanter als der Nutzen.

### W2: Partien kürzer machen
Heute dauert eine Runde allein durch Spin, Pausen, Karte und Ergebnis etwa 23 s Fixzeit, ohne das eigentliche Event.

**Heutige Partielänge [S]:**

| Spieler | Dauer |
|---|---|
| 6 | ca. 5,8 min |
| 8 | ca. 8,0 min |
| 12 | ca. 11,8 min |

**Vorschlag (alles in `Shared/Config.lua`):**

| Konstante | alt → neu |
|---|---|
| `SPIN_TIME` | 10 → **9** (`spin_musicbox_fast.ogg` mit 8,98 s gibt es schon [V]) oder 6 mit Pitch-Trick* |
| `HOLD_TIME` / `REVEAL_TIME` | 2 / 3 → **1 / 2** |
| `CARD_TIME` / `CARD_TIME_REPEAT` | 5 / 3,5 → **4 / 1,5** |
| `RESULT_PAUSE` | 4 → **2** |
| `INTRO_TIME` / `INTRO_POP_AT` / `GAME_END_DELAY` | 12 / 10 / 10 → **8 / 6,5 / 8** |
| `REVOLVER.CHOOSE_TIME` | 12 → **7** |
| `VOTE.TIME` | 15 → **8** |
| `PUMPKIN.FUSE` | {8,15} → **{5,10}** |

**Erwartete Partielänge danach [S]:**

| Spieler | Dauer |
|---|---|
| 8 | ca. 4,5–6 min (mit menschlicher Bedenkzeit) |
| 12 | ca. 6–7 min |

\* **Pitch-Trick:** Die 10-s-Spieluhr mit Pitch ≈ 1,67 abspielen (`Client/Audio.lua:53`). Ob Pitch in nanos world auch das Tempo ändert, ist **nicht geprüft**, bitte vorher im Spiel ausprobieren.

Der Config-Kommentar „NIE die Show kürzen“ war für 16er-Tische gedacht. Für Partien mit höchstens 12 Spielern und dem Ziel „kurzer Spaß“ passt er nicht mehr.

### W3: Event-Auswahl
Abschalten geht allein über die Gewichte: Events mit Gewicht 0 lässt `Pick` aus [V, `Server/Events.lua:111`].

**Behalten, weil klar verständlich und lustig:** revolver, angry, knife, fire, vote, pumpkin, duel.

**Mit geringem Gewicht (0,3–0,5):** deal.

**Abschalten (`{0,0,0,0}`):**

| Event | Grund |
|---|---|
| stab | zwei Stufen plus Block, unter Zeitdruck schwer zu verstehen |
| bomb | die Regel ist englischer Text unter Zeitdruck |
| splitsteal | braucht Absprache, Sprachbarriere, niemand stirbt |
| choosecard | wenig Spannung |

**Vorgeschlagene Gewichte (viele / mittel / wenige Lebende):**

| Event | viele | mittel | wenige |
|---|---|---|---|
| revolver | 2 | 2,5 | 3 |
| angry | 3 | 2 | 0,5 |
| knife | 3 | 3 | 3 |
| fire | 2 | 2 | 2 |
| vote | 2 | 2 | 1 |
| pumpkin | 2 | 2 | 1,5 |
| duel | 2 | 1,5 | 1,5 |

`gallery` wird bei höchstens 12 Plätzen mit `EVENT_PHASES.HUGE = 17` nie gezogen. Das ist in Ordnung so.

### W4: Eigene Namen statt der Roblox-Originalnamen (Kreativität ist ein Bewertungskriterium)
Alle 5 Karten und die meisten Event-Namen sind identisch oder fast identisch mit dem Original. Geändert werden nur die `name`-Felder in `Shared/Cards.lua` und `Shared/Text.lua`. Die IDs bleiben gleich, der Code muss also nicht angefasst werden.

**Events:**

| Original | Vorschlag |
|---|---|
| Revolver | Pass the Pistol |
| Angry Clown | Jack Snaps |
| Knife Toss | The Knife Act |
| Fire Breath | Fire Eater |
| Spare or Eliminate | Cheer or Jeer |
| Card Deal | Party Favors |
| Stab Your Neighbour | Chop Chop *(nur falls es aktiv bleibt)* |
| Defuse or Die | Snip the Wire *(nur falls es aktiv bleibt)* |
| Split or Steal | Share or Snatch *(nur falls es aktiv bleibt)* |
| Choose a Card | Fortune Teller *(nur falls es aktiv bleibt)* |

**Karten:**

| Original | Vorschlag |
|---|---|
| Safety | Iron Nose |
| Skip | Understudy |
| Ricochet | Funhouse Mirror |
| Guardian | Lucky Charm |
| Thief | Pickpocket |

Pass the Pumpkin, Shooting Gallery und Quick Draw sind schon eigene Namen und können bleiben.
Die Kartenbilder (`Client/UI/img/cards/*.png`) zeigen den Namen eventuell als Text. Das muss geprüft werden.

### W5: Bots bei Abstimmungen
Tote Bots stimmen bei der Abstimmung mit (`Vote.lua:41` prüft nur `is_bot`), und zwar mit 60 % für „Eliminate“.
Folge: An einem Tisch mit vielen Bots entscheiden die Bots. [V]

**Fix:**
- In `Voters()` die Bedingung `seat.player or (seat.is_bot and seat.alive)` verwenden.
- `BOT_KILL` auf 0,5 setzen.

### W6: Client-Leistung (Hub und Zelt)
Etwa 35 Ticker setzen in jedem Frame Lichtwerte und Materialien neu, auch wenn sich nichts ändert. Im Zelt passiert das gerade in den spannenden Momenten mit etwa 79 Birnen. [V]
- `Client/World/Hub.lua:207-219, 241`: nur neu setzen, wenn sich `step` oder die Farbe ändert.
- `Client/World/Tent.lua:185-190`: nur neu setzen, wenn sich `dim` um mehr als 0,02 ändert.
- `Client/World/Builder.lua:99-104`: das Flackern auf etwa 20 Hz drosseln.
- Schatten: Den Mond-Spot (`Hub.lua:256`) und die beiden Ziel-Spots (`Tent.lua:169-178`) mit `shadows = false` anlegen.
- Bodennebel-Skalierung von 4 auf 2–3 senken (`Hub.lua:292-294`).

### W7: Maus kann hängen bleiben
- `HUD.Destroy` gibt bei offener Kartenhand die Maus nicht zurück (`Client/HUD.lua:194-204`).
- Bei Klick-Abfragen fehlt ein Timeout auf dem Client. Fix: in `DeathBox:Choice` (`HUD.lua:272`) einen Timer `seconds + 3` setzen, der danach `CloseChoice` aufruft.
- Offene Abfragen bei jedem Ortswechsel schließen, nicht nur beim Wechsel in den Hub.

### W8: Rate-Limit für Remote-Events
Für `DeathBox:Input` und `DeathBox:PlayCard` gibt es keine Drossel (`Server/Net.lua:112-154`). Den Token-Bucket aus dem `Aim`-Handler wiederverwenden.

## Optional: Feinschliff, wenn noch Zeit ist

- **Für Ausgeschiedene:**
  - Ein „Next show“-Knopf im HUD ersetzt das Eintippen von `/leave`.
  - Ein Banner „The dead vote too!“ bei Cheer or Jeer.
  - Buh- und Applaus-Knöpfe für Geister.
- **Die ersten 60 Sekunden:**
  - „How to play“ dauerhaft im Hub anzeigen.
  - Ein Hinweis „C – your cards“ in der Ecke.
  - Das erste Event jeder Show fest auf Revolver setzen (`forced_event`).
- **Grafik mit gutem Aufwand-Nutzen-Verhältnis:**
  - Ein kurzer FOV-Ruck beim POP oder bei einem Tod (`Player:SetCameraFOV`).
  - Eine Farb-LUT über `PostProcess.SetLookupTable`.
  - Belichtung und Licht an einem Abend auf 2 PCs mit `db_exposure`, `db_light` und `db_look` einstellen und die Werte fest eintragen.
- **Gamma:** `Client.SetSettingGammaOverride(true, 1.0)` (`Client/Atmosphere.lua:41`) überschreibt die Helligkeitseinstellung der Spieler. Auf dunklen Monitoren testen.
- **Chat:** Die Begrüßung vom `Spawn`-Event ins `Ready`-Event verschieben (`Server/Index.lua:38-40`).
- **Dokumentation:** In `docs/PROTOCOL.md` den Eintrag `DeathBox:Diag` ergänzen.
- **Nicht vor dem Jam:** `hud.js` (3600 Zeilen) und `style.css` (3800 Zeilen) aufteilen. Toter Code ist dort kaum vorhanden.

## Bereits gut (nichts zu tun)

- Alle Remote-Handler prüfen auf dem Server Match, Platz, `ask_id` und erlaubte Optionen. Andere Tische lassen sich nicht beeinflussen.
- Die Fälle „Spieler verlässt das Spiel“ und „Package-Reload“ sind in allen 13 Events abgedeckt.
- Kein `innerHTML` in der WebUI: Namen werden nur über `textContent` gesetzt, damit ist XSS ausgeschlossen.
- Die API-Aufrufe stimmen mit der offiziellen API überein (geprüft in Stichproben und per Namensabgleich).
- Die Texturen sind höchstens 1024² groß, der Client-Download liegt bei etwa 15 MB.

## Reihenfolge und Fristen

| Tag | Aufgabe |
|---|---|
| bis Do 16.10. | K1, K2, K3, W1, W2, W3. Das sind fast nur Config-Werte, nur K2 und K3 brauchen ein paar Zeilen Code. |
| Fr 17. bis Sa 18.10. | In-Game-Test mit 3 oder mehr Menschen plus Bots: jedes aktive Event über `/event` und dazu 2 komplette Shows. Pro Event notieren: funktioniert / verstanden / Spaß 1–5. |
| **Abbruchkriterium Sa 18.10.** | Läuft bis dahin keine fehlerfreie Show mit 4 oder mehr Menschen, wird auf 5 Events gekürzt und es werden keine weiteren Features gebaut. |
| So 19. bis Di 21.10. | W4 (Namen), W5, W6, W7, W8 und Licht-Feinschliff. |
| **Mo 20.10.** | Ist das Asset-Pack bis dahin nicht auf dem Server, wird es gestrichen. |
| Mi 22.10. | Feature-Freeze, `DEBUG_COMMANDS = false`, Egg auf Steam-Branch, Abschlusstest. |
| Do 23.10. | Abgabe (23:59 UTC). |

## Zusammenarbeit

Pro Datei arbeitet immer nur einer: Der Owner übernimmt Client und Grafik, der zweite Entwickler Config, Texte und Server-Fixes. Vor jeder Arbeitssitzung `git pull`, danach kleine Commits mit klarer Nachricht.
