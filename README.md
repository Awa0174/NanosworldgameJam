# Jack's Last Show (Arbeitstitel, Package `deathbox`)

Beitrag zum nanos world Halloween Game Jam 2026: Party-Survival nach dem Spielprinzip von *Death in the Box*. Jam-Server: 12 Spieler, Friedhof als Hub, **2 Zirkuszelte mit je 8 Plätzen** um Jack in der Box. Freie Plätze füllen Bots („Puppets“), wer später kommt, übernimmt zur nächsten Runde einen Bot-Platz – Spieler spielen mit Spielern. Zufällige Events, Karten, Last One Standing, eine Show dauert ca. 5 Minuten.
Regeln, Umfang und Architektur: [`docs/DESIGN.md`](docs/DESIGN.md) · Zeitplan: [`docs/ROADMAP.md`](docs/ROADMAP.md) · Eigene Assets: [`docs/ASSETS.md`](docs/ASSETS.md)

## Installation auf dem Server

1. Dieses Repository als Ordner `Packages/deathbox/` auf den Server legen.
2. In der `Config.toml` im Block `[game]` eintragen:
   ```toml
   game_mode = "deathbox"
   ```
   und `map = "default-empty-map"` (schwarze, leere Map: die Welt baut der Client), unter `[general]` `max_players = 12`.
3. **Pterodactyl:** Die Startvariablen schlagen die `Config.toml`. Im Panel unter *Startup* `max_players` auf `12` und die Map
   auf `default-empty-map` stellen. Vor dem Playtest: Egg auf den normalen Steam-Zweig (nicht bleeding-edge) und mit
   `--steam_app "game"` starten.
   (Die Welt liegt auf Z = 20000 und schwebt auch über der Testing-Map frei, sie funktioniert also mit beiden Maps.)
4. Server neu starten. In der Konsole muss stehen:
   ```
   [DeathBox] Server-Package geladen (Version 0.11.0)
   ```

## Stand (0.11.0, 14.10. abends) – Jam-Fassung

- [x] **Matchmaking für 12 Spieler:** 2 Tische à 8. Wer allein ist, startet nach 20 s mit Bots. Wer später kommt, schaut im
      Zelt zu („You're next!“) und übernimmt zu Beginn der nächsten Runde einen lebenden Bot – mit dessen Karten. Erst wenn
      Tisch 1 keine Bots mehr hat, öffnet Tisch 2. Eine Gruppe, die zusammen gespielt hat, startet zusammen neu.
- [x] **Kürzer:** Spin 8 s (Spieluhr-Melodien neu erzeugt), kürzere Pausen, Event-Karte beim zweiten Mal 2 s. 8er-Show ca. 5 min
      (Simulation mit Bedenkzeit: Median 334 s). Jede Show beginnt mit Clown Roulette.
- [x] **Klarer:** 8 verständliche Events aktiv; Chop Chop (Stab), Snip the Wire (Bombe), Share or Snatch (Split or Steal) und
      Fortune Teller (Choose a Card) abgeschaltet (Gewicht 0, Code bleibt, `/event` geht weiter).
- [x] **Eigene Namen** statt der Roblox-Namen: Clown Roulette, Jack Snaps, The Knife Act, Fire Eater, Cheer or Jeer, Party Favors;
      Karten Lucky Charm, Body Double, Funhouse Mirror, Bodyguard, Pickpocket (Kartenbilder neu erzeugt).
- [x] **Taste N** „Next show“ für Ausgeschiedene und Nachrücker.
- [x] **Robuster:** Fehler in einem Timer friert keine Show mehr ein (`Match:Guard` → Show endet sauber), Watchdog nach 60 s
      Stillstand, Flutschutz für alle Eingaben, tote Bots stimmen nicht mehr ab, Sicherheitsnetz gegen hängende Maus.
- [x] **Admin statt Debug:** `DEBUG_COMMANDS = false`. In der Server-Konsole: `db_admin <name>` schaltet die Chat-Befehle
      (`/status`, `/event`, `/card`, `/bots`, `/start`, `/stop`, B = Noclip) für einen Spieler frei, `db_status` zeigt die Tische.
- [x] **Leistung:** Glühbirnen und Flackerlichter im Hub/Zelt werden nicht mehr in jedem Frame neu gesetzt, weniger Schatten.
- [ ] Im Spiel prüfen (siehe `docs/IMPROVEMENTS.md`, „Testplan“).

## Stand (0.10.0, 14.10. vormittags)

- [x] v0.7/0.8: Welt beim Client (Zelt, Friedhof), eigene Sounds und Texturen, Instanzen für 999 Spieler, alle 13 Events, 5 Karten
- [x] v0.10 nach dem ersten Ingame-Test („viel zu schnell, unübersichtlich“):
  - Langsameres Tempo: Spin 10 s + 2 s Stille, Event-Karte 5 s, Ergebnis 4 s, „GET READY“ vor jeder Eingabe
  - HUD-Regiezeile oben (Phase, wer, was DU tun musst, Zeit), große „YOUR TURN“-Tafel, Rundenergebnis-Karte, „How to play“
  - Jack schaut beim Drehen aus der Kiste, roter Suchscheinwerfer über die Stühle; Gesicht nur noch aus 3D-Teilen
  - Echter Revolver in der Hand: mit der Maus zielen, Ziel wird rot hervorgehoben, Linksklick schießt; alle sehen, auf wen gezielt wird
  - Spieluhr-Melodien (Ring Around the Rosie, London Bridge, Rock-a-bye Baby, Pop Goes the Weasel), Kirmes-Orgel im Hub
- [x] **Engine-Befund (In-Engine-Diagnose):** `AttachTo(..., KeepWorld)` hält in nanos 1.159 die Lage nicht ein – angehängte Teile
      sprangen in den Drehpunkt (Ursache für „Gesicht kaputt, Kiste kaputt“). `Builder.Attach` setzt die relative Lage jetzt selbst.
      Der Torus ist 100 × 100 × 30 cm mit Drehpunkt unten (`Builder.Shape` gleicht das aus).
- [ ] v0.10 im Spiel prüfen. Live-Einstellungen in der Konsole: `db_aimanim`, `db_gunhand`, `db_hl` (Revolver/Highlight),
      `db_head` (Kopfhöhe für Effekte), `db_exposure`, `db_light`; `db_diag` schickt eine neue Diagnose an den Server
      (`deathbox_diag.txt` im Server-Ordner)
- [ ] Vor der Abgabe: `DEBUG_COMMANDS = false` in `Shared/Config.lua`

## Testen allein

Ohne Admin: einfach joinen – nach 20 s startet eine Show mit 7 Bots. Mit Admin (Server-Konsole `db_admin <dein name>`):
im Chat `/start` startet sofort. Mit `/event <id>` lässt sich das nächste Event erzwingen:
`revolver`, `knife`, `fire`, `stab`, `angry`, `gallery` (Schießbude; von selbst nur ab 17 Lebenden), `vote`, `pumpkin`, `splitsteal`, `bomb`, `duel`,
`deal`, `choosecard`. `/card <id>` gibt dir eine Karte (`safety skip ricochet guardian thief`), Taste **C** öffnet die Hand.
`/status` zeigt Hubs, Warteschlange und Tische. Weitere Befehle stehen in `docs/DESIGN.md`, Abschnitt 8.
