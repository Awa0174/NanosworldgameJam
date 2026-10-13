# Design-Dokument – [SPIELNAME]

> Arbeitstitel: **DeathBox** (Ordner-/Package-Name `deathbox`).
> Inspiriert vom Spielprinzip von „Death in the Box“ (Roblox). Name, Figuren, Texte und Grafiken sind eigene Inhalte.
> Platzhalter stehen in `[ECKIGEN KLAMMERN]` und werden später ersetzt.

## 1. Kurzbeschreibung

[KURZBESCHREIBUNG – 1–2 Sätze, z. B.: „Bis zu 8 Spieler sitzen um einen Tisch. [SPIELLEITER] reicht reihum eine Pistole weiter, die nicht immer feuert. Wer zuletzt übrig ist, gewinnt.“]

## 2. Setting & Identität

| Element | Inhalt |
|---|---|
| Spielname | [SPIELNAME] |
| Spielleiter | [NAME DES SPIELLEITERS] – [KURZE BESCHREIBUNG] |
| Ort | [ORT, z. B. Keller, Zirkuszelt, Zugabteil] |
| Stimmung | [STIMMUNG, z. B. düster, schwarzhumorig] |

## 3. Spielregeln (MVP)

### 3.1 Spieler
- Mindestens **2** Spieler, maximal **8** (einstellbar in `Shared/Config.lua`).
- Ab 2 Spielern startet automatisch ein Countdown von 10 Sekunden.

### 3.2 Startaufstellung
- Zu Beginn jeder Partie wird die Reihenfolge der Spieler **zufällig** gemischt.
- Diese Reihenfolge entspricht den Sitzplätzen am Tisch.

### 3.3 Ablauf einer Runde
1. Es ist **reihum im Uhrzeigersinn** jeweils ein Spieler dran.
2. Der Spieler am Zug bekommt die **Pistole**.
3. Die Pistole **zündet nicht immer**:
   - Chance auf Schuss: **1 zu 6** (einstellbar)
   - Bei Schuss: Der Spieler scheidet aus.
   - Kein Schuss: Der Spieler überlebt, der nächste ist dran.
4. Ausgeschiedene Spieler werden übersprungen.

> MVP: Der Spieler schießt auf **sich selbst** (reines Glück, keine Eingabe nötig).
> Später möglich: Ziel wählen (Strategie) – braucht eine Eingabe vom Client.

### 3.4 Karten
- Für den MVP gibt es **eine** Karte: **[KARTENNAME]** (intern `shield`)
- Wirkung: rettet einmal vor einem Schuss, wird **automatisch** verbraucht
- Erhalt: jeder Spieler startet mit einer (`Config.START_CARDS`)

### 3.5 Spielende
- Sobald nur noch **ein** Spieler lebt, hat er gewonnen.
- Nach 10 Sekunden geht es zurück in die Lobby, alle werden wiederbelebt.

### 3.6 Sonderfälle
- Spieler verlässt das Spiel während der Partie → zählt wie gestorben (ausgeschieden).
- Spieler am Zug verlässt das Spiel → sein Zug wird abgebrochen, der nächste ist dran.
- Nur noch 1 Spieler übrig → er gewinnt, Partie endet.
- Spieler joint während einer Partie → wartet, bis die Partie zu Ende ist, und spielt ab der nächsten mit.
- Spieler geht während des Countdowns und es sind zu wenige → Countdown wird abgebrochen.
- Mehr Spieler als Plätze → die übrigen schauen zu.

### 3.7 Spielort (Arena)
- Eigene Fläche **20 m × 20 m** mit 4 m hohen Wänden, **200 m über der Map** – funktioniert auf jeder Map.
- In der Mitte ein Tisch, darum **8 Stühle** (einer pro möglichem Platz), Platz 1 bei 0°, dann im Uhrzeigersinn.
- Lobby: Spieler spawnen frei im Raum und können herumlaufen.
- Partie: Jeder Spieler wird hinter seinen Stuhl gestellt, Blick zum Tisch, Bewegung gesperrt. Bei weniger als 8 Spielern werden die Plätze gleichmäßig verteilt.
- Alle Maße und Meshes stehen in `Shared/Config.lua` unter `ARENA`.

## 4. Umfang in Stufen

| Stufe | Inhalt | Fertig, wenn … |
|---|---|---|
| **MVP** | Rundenschleife, Spielleiter wählt Spieler, Pistole, Ausscheiden, Sieger | Ein komplettes Spiel funktioniert, wenn auch nur im Chat |
| **Kern** | Karten in der Hand, UI zum Ausspielen | Spieler treffen echte Entscheidungen |
| **Atmosphäre** | Tisch, Sitzplätze, Kamera, Spielleiter-Figur, Sounds, Licht | Es fühlt sich wie ein Spiel an |
| **Bonus** | Ereignisse, mehr Karten, Statistiken | Nur wenn Zeit übrig ist |

Beim Jam gilt: **Lieber eine fertige Stufe abgeben als drei halbe.**

## 5. Architektur

### 5.1 Wer macht was
- **Server:** entscheidet alles (Zustand, Würfe, Kartenwirkungen) und prüft jede Eingabe vom Client. Sonst kann ein Spieler einfach „ich spiele Schild“ senden, obwohl er keins hat.
- **Client:** zeigt nur an (UI, Kamera, Effekte) und schickt Wünsche an den Server.
- **Shared:** gemeinsame Daten, z. B. Kartendefinitionen und Konfiguration.

### 5.2 Dateien

```
deathbox/
├── Package.toml
├── Shared/
│   ├── Index.lua        Einstieg, lädt die anderen Shared-Dateien
│   ├── Config.lua       Einstellungen (Chancen, Zeiten, Spielerzahl)
│   └── Cards.lua        Kartendefinitionen
├── Server/
│   ├── Index.lua        Einstieg, Spieler-Join/-Leave
│   ├── Arena.lua        Boden, Wände, Tisch und Stühle hoch über der Map
│   ├── Characters.lua   Figuren spawnen, wiederbeleben, ausschalten
│   ├── GameState.lua    Ablauf: Warten → Partie → Zug → Spielende
│   └── Table.lua        Sitzplätze und Reihenfolge
├── Client/
│   └── Index.lua        Anzeige (später UI)
└── docs/
    └── DESIGN.md        dieses Dokument
```

### 5.3 Spielzustände (Server)

```
WARTEN ──(≥ 2 Spieler + Countdown)──> PARTIE
PARTIE:  ZUG ──> AUFLÖSUNG ──> nächster ZUG ...
PARTIE ──(nur noch 1 lebt)──> SPIELENDE ──(Wartezeit)──> WARTEN
```

## 6. Debug-Befehle (nur zum Testen)

Aktiv, solange `DEBUG_COMMANDS = true` in `Shared/Config.lua` steht. **Vor dem Jam auf `false` stellen.**

| Befehl | Wirkung |
|---|---|
| `/bots 3` | 3 Test-Bots spielen in der nächsten Partie mit (0–7) |
| `/start` | Partie sofort starten |
| `/stop` | laufende Partie abbrechen |
| `/status` | Zustand, Bots, Lebende, Sitzordnung anzeigen |

## 7. Offene Punkte

- [ ] Spielname, Spielleiter und Setting festlegen
- [ ] Schusschance festlegen (aktuell 1/6 in `Shared/Config.lua`)
- [ ] Name der Karte festlegen
- [ ] Jam-Abgabetermin eintragen: [DATUM]
- [ ] Jam-Thema/-Regeln prüfen: [THEMA]
- [ ] Server vor dem Jam vom `bleeding-edge`- auf den normalen Zweig umstellen (sonst kommen nur Playtest-Spieler rein)
