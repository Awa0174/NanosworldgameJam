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
- Mindestens **2** Spieler, maximal **[MAX SPIELER, Vorschlag: 8]**.
- Wer während einer laufenden Partie joint, schaut zu und spielt ab der nächsten Partie mit.

### 3.2 Startaufstellung
- Zu Beginn jeder Partie wird die Reihenfolge der Spieler **zufällig** gemischt.
- Diese Reihenfolge entspricht den Sitzplätzen am Tisch.

### 3.3 Ablauf einer Runde
1. Es ist **reihum im Uhrzeigersinn** jeweils ein Spieler dran.
2. Der Spieler am Zug bekommt die **Pistole**.
3. Die Pistole **zündet nicht immer**:
   - Chance auf Schuss: **[CHANCE, Vorschlag: 1 zu 6]**
   - Bei Schuss: Der Spieler scheidet aus.
   - Kein Schuss: Der Spieler überlebt, der nächste ist dran.
4. Ausgeschiedene Spieler werden übersprungen.

> Offene Entscheidung: Schießt der Spieler auf **sich selbst** (reines Glück) oder darf er ein **Ziel wählen** (Strategie)?
> MVP-Vorschlag: auf sich selbst – einfacher, keine Eingabe nötig.

### 3.4 Karten
- Für den MVP gibt es **eine** Karte: **[KARTENNAME]**
- Wirkung: [WIRKUNG, Vorschlag: „Schutz – überlebt den nächsten Schuss, danach verbraucht“]
- Wie man sie bekommt: [ERHALT, z. B. jeder Spieler startet mit einer / zufällig nach Überleben]

### 3.5 Spielende
- Sobald nur noch **ein** Spieler lebt, hat er gewonnen.
- Nach [WARTEZEIT, Vorschlag: 10 Sekunden] startet die nächste Partie.

### 3.6 Sonderfälle
- Spieler verlässt das Spiel während der Partie → zählt als ausgeschieden.
- Spieler am Zug verlässt das Spiel → der nächste ist sofort dran.
- Weniger als 2 Spieler übrig → Partie endet.

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

### 5.2 Geplante Dateien

```
deathbox/
├── Package.toml
├── Shared/
│   ├── Index.lua        Einstieg, lädt die anderen Shared-Dateien
│   ├── Config.lua       Einstellungen (Chancen, Zeiten, Spielerzahl)
│   └── Cards.lua        Kartendefinitionen
├── Server/
│   ├── Index.lua        Einstieg, Spieler-Join/-Leave
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

## 6. Offene Punkte

- [ ] Spielname, Spielleiter und Setting festlegen
- [ ] Pistole: auf sich selbst oder Ziel wählen?
- [ ] Schusschance festlegen
- [ ] Die eine Karte festlegen (Name, Wirkung, Erhalt)
- [ ] Jam-Abgabetermin eintragen: [DATUM]
- [ ] Jam-Thema/-Regeln prüfen: [THEMA]
- [ ] Server vor dem Jam vom `bleeding-edge`- auf den normalen Zweig umstellen (sonst kommen nur Playtest-Spieler rein)
