# The Last Séance (Arbeitstitel, Package `deathbox`)

Beitrag zum nanos world Halloween Game Jam 2026: ein Séance-Überlebensspiel am Tisch.
Regeln, Umfang und Architektur: [`docs/DESIGN.md`](docs/DESIGN.md) · Zeitplan: [`docs/ROADMAP.md`](docs/ROADMAP.md)

## Installation auf dem Server

1. Dieses Repository als Ordner `Packages/deathbox/` auf den Server legen.
2. In der `Config.toml` im Block `[game]` eintragen:
   ```toml
   game_mode = "deathbox"
   ```
3. Server neu starten. In der Konsole muss stehen:
   ```
   [DeathBox] Server-Package geladen (Version 0.5.0)
   ```

## Stand

- [x] Package lädt, Spieler spawnen, Join-/Leave-Nachricht im Chat
- [x] MVP-Logik: Rundenschleife, Pistole, Schutzkarte, Ausscheiden, Sieger (Ausgabe im Chat)
- [x] MVP im Spiel mit Bots getestet
- [x] Arena: Fläche, Wände, Tisch, Stühle
- [x] Test-Cheats: Noclip (B), /god, /arena, /sit, /sitpos
- [ ] Sitzen: Position im Spiel feinjustiert
- [x] Ritual-System (Module), The Chamber mit gemeinsamer Trommel
- [x] HUD (WebUI): Ritual, Docht-Timer, Trommel, Runde, Madame-Untertitel, Séance-Ring zur Zielwahl
- [ ] HUD im Spiel getestet
- [ ] MVP mit mehreren echten Spielern getestet
- [ ] Kern: Kartenhand und UI

## Testen allein

Im Chat: `/bots 3` und danach `/start`. Mit `/ritual chamber` lässt sich das nächste Ritual erzwingen. Weitere Befehle stehen in `docs/DESIGN.md`, Abschnitt 6.
