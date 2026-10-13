# DeathBox (Arbeitstitel)

Game-Jam-Projekt für [nanos world](https://nanos-world.com): ein rundenbasiertes Überlebensspiel am Tisch.
Regeln, Umfang und Architektur stehen in [`docs/DESIGN.md`](docs/DESIGN.md).

## Installation auf dem Server

1. Dieses Repository als Ordner `Packages/deathbox/` auf den Server legen.
2. In der `Config.toml` im Block `[game]` eintragen:
   ```toml
   game_mode = "deathbox"
   ```
3. Server neu starten. In der Konsole muss stehen:
   ```
   [DeathBox] Server-Package geladen (Version 0.2.0)
   ```

## Stand

- [x] Package lädt, Spieler spawnen, Join-/Leave-Nachricht im Chat
- [x] MVP-Logik: Rundenschleife, Pistole, Schutzkarte, Ausscheiden, Sieger (Ausgabe im Chat)
- [x] MVP im Spiel mit Bots getestet
- [x] Arena: Fläche, Wände, Tisch, Stühle; Spieler stehen während der Partie am Platz
- [ ] MVP mit mehreren echten Spielern getestet
- [ ] Kern: Kartenhand und UI

## Testen allein

Im Chat: `/bots 3` und danach `/start`. Weitere Befehle stehen in `docs/DESIGN.md`, Abschnitt 6.
