# Jack's Last Show (Arbeitstitel, Package `deathbox`)

Beitrag zum nanos world Halloween Game Jam 2026: Nachbau des Spielprinzips von *Death in the Box*. Bis zu 999 Spieler pro Server, Friedhof als Hub, viele Zirkuszelte gleichzeitig mit je 16 (max. 32) Spielern um Jack in der Box. Zufällige Events, Karten, Last One Standing.
Regeln, Umfang und Architektur: [`docs/DESIGN.md`](docs/DESIGN.md) · Zeitplan: [`docs/ROADMAP.md`](docs/ROADMAP.md) · Eigene Assets: [`docs/ASSETS.md`](docs/ASSETS.md)

## Installation auf dem Server

1. Dieses Repository als Ordner `Packages/deathbox/` auf den Server legen.
2. In der `Config.toml` im Block `[game]` eintragen:
   ```toml
   game_mode = "deathbox"
   ```
   und `map = "default-empty-map"` (schwarze, leere Map: die Welt baut der Client), unter `[general]` `max_players = 999`.
3. **Pterodactyl:** Die Startvariablen schlagen die `Config.toml`. Zurzeit startet der Server mit
   `--max_players 10 --map default-testing-map` – im Panel unter *Startup* auf `999` und `default-empty-map` stellen.
   (Die Welt liegt auf Z = 20000 und schwebt auch über der Testing-Map frei, sie funktioniert also mit beiden Maps.)
4. Server neu starten. In der Konsole muss stehen:
   ```
   [DeathBox] Server-Package geladen (Version 0.10.0)
   ```

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

Im Chat: `/bots 15` und danach `/start`. Mit `/event <id>` lässt sich das nächste Event erzwingen:
`revolver`, `knife`, `fire`, `stab`, `angry`, `gallery` (Schießbude; von selbst nur ab 17 Lebenden), `vote`, `pumpkin`, `splitsteal`, `bomb`, `duel`,
`deal`, `choosecard`. `/card <id>` gibt dir eine Karte (`safety skip ricochet guardian thief`), Taste **C** öffnet die Hand.
`/status` zeigt Hubs, Warteschlange und Tische. Weitere Befehle stehen in `docs/DESIGN.md`, Abschnitt 8.
