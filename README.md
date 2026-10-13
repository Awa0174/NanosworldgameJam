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
   [DeathBox] Server-Package geladen (Version 0.0.1)
   ```

## Stand

- [x] Package lädt, Spieler spawnen, Join-/Leave-Nachricht im Chat
- [ ] MVP: Rundenschleife mit Pistole und Sieger
