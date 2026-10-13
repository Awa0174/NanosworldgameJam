# Design-Dokument – The Last Séance

> **Arbeitstitel:** *The Last Séance* (Package-Name bleibt `deathbox`)
> **Jam:** nanos world Halloween Game Jam 2026 – Abgabe **23. Oktober 2026, 23:59 UTC**, öffentlicher Playtest 30. Oktober – 1. November
> **Inspiration:** das Spielprinzip von *Death in the Box* (Roblox). Setting, Host, Rituale, Karten, Texte und Präsentation sind eigene Inhalte.
> **Sprache:** Alle Texte im Spiel auf **Englisch** (internationales Playtest-Publikum). Code-Kommentare und Doku auf Deutsch.

---

## 1. Vision

Bis zu 8 Spieler sitzen um einen Séance-Tisch in einem dunklen Salon. **Madame**, ein Medium, das selbst schon halb Geist ist, leitet die Sitzung. Sie wählt Spieler aus und beschwört **Rituale**: Mal entscheidet Glück, mal Reaktion, mal Vertrauen. Tarotkarten geben jedem einen Ausweg, aber nicht für immer. Wer zuletzt noch am Tisch sitzt, verlässt die Séance lebend.

**Leitsatz:** *Wir bauen keine Inhalte, sondern Situationen, in denen Spieler füreinander zum Inhalt werden.*

### Was wir vom Vorbild übernehmen (die Prinzipien)
- Ein Host gibt dem Zufall ein Gesicht („Madame hat mich gewählt“, nicht „der Algorithmus“).
- Spannung entsteht vor dem Ereignis: Auswahl, Pause, Spotlight.
- Entscheidungen sind öffentlich, alle schauen zu.
- Kurze Rituale mit klarer Aufgabe, Rhythmuswechsel zwischen Glück, Reaktion und Vertrauen.
- Karten geben dem Zufall eine strategische Ebene.

### Was wir bewusst anders machen
- **Mehr Kontrolle statt reinem RNG:** Der Revolver hat eine sichtbare Trommel. Die Wahrscheinlichkeit steigt nachvollziehbar. Wer zählt, entscheidet besser.
- **Jede Gefahr hat eine Antwort:** Zu jedem Ritual gibt es mindestens eine Karte, die hilft.
- **Lesbarkeit vor Menge:** 3 Rituale, jedes mit eindeutiger Anzeige und einem einzigen Input.
- Keine Monetarisierung, kein Glücksrad, kein FOMO.

---

## 2. Setting & Präsentation

| Element | Umsetzung |
|---|---|
| Ort | Geschlossener, dunkler Salon (Decke, Wände, Teppich), runder Tisch in der Mitte |
| Licht | Nur Kerzen bzw. Öllampen auf dem Tisch + ein Spotlight auf den gewählten Spieler |
| Host | **Madame**: Figur am Kopfende bzw. als Stimme/Text. Kommentiert jedes Ereignis |
| Ton | Leises Ambient, Leerklick (`A_Pistol_Dry`), Schuss, Lachen bei Tod |
| Palette | Schwarz, warmes Kerzen-Orange, tiefes Violett für Geister-Effekte |

**Madames Sprechweise (Beispiele, Englisch):**
- *„The spirits have chosen… **Awa**.“*
- *„Click. The dead are patient.“*
- *„The candle goes out. Goodbye, **Max**.“*

---

## 3. Spielablauf

```
LOBBY ──(≥2 Spieler, Countdown)──> SÉANCE
SÉANCE:  Madame wählt Ritual + Spieler ──> Spotlight ──> Ritual ──> Auflösung ──> nächstes Ritual
SÉANCE ──(1 Spieler übrig)──> ENDE (Sieger) ──> LOBBY
```

- **Sitzordnung:** zufällig, Reihenfolge im Uhrzeigersinn.
- **Auswahl:** Madame geht reihum (Uhrzeigersinn). Welches Ritual kommt, ist zufällig gewichtet, nie zweimal dasselbe hintereinander.
- **Ausscheiden:** Spieler stirbt am Tisch, Kerze vor ihm erlischt. Danach Zuschauer.
- **Sonderfälle:** Verlassen = ausgeschieden. Wer während einer Séance joint, wartet. Bei Zeitüberschreitung gibt es immer ein festes Standardverhalten, damit nichts hängenbleibt.

---

## 4. Rituale (Jam-Umfang: 3)

### 4.1 The Chamber (Revolver) – *Glück + Taktik*
- Ein Revolver mit **6 Kammern und 1 Kugel**. Die Trommel bleibt zwischen den Zügen bestehen. Die Chance steigt sichtbar: 1/6 → 1/5 → … → 1/1.
- Der gewählte Spieler **wählt ein Ziel** (einen anderen lebenden Spieler) und drückt ab.
- **Zeitlimit 10 s:** Wer nicht wählt, richtet die Waffe auf sich selbst.
- Nach einem Schuss wird neu geladen (wieder 1/6).
- **UI:** Trommel mit verbleibenden Kammern, Zielauswahl per Klick auf Spielernamen.

### 4.2 The Pact (Vertrauen / Verrat) – *Social*
- Madame wählt **zwei Spieler**. Beide haben **20 s Redezeit** (Chat/Voice) und dann **8 s**, um geheim zu wählen: **Keep** oder **Break**.

| A | B | Ergebnis |
|---|---|---|
| Keep | Keep | Beide bekommen eine Tarotkarte |
| Break | Keep | A bekommt zwei Karten, B verliert eine Karte |
| Break | Break | Beide verlieren **alle** Karten |

- Keine Wahl gilt als **Keep**.
- Das Ergebnis wird gleichzeitig aufgedeckt, für alle sichtbar.

### 4.3 Possession (Reaktion) – *Skill*
- Ein Geist fährt in den gewählten Spieler. Es erscheint eine Folge von **5 Tasten** (Pfeile/WASD), eine nach der anderen, mit kürzer werdendem Zeitfenster.
- Eine falsche Taste oder zu langsam bedeutet, dass der Geist gewinnt und der Spieler ausscheidet (Karten können retten).
- Die Tastenfolge erzeugt der Server, und der Server prüft auch. Der Client meldet nur die gedrückten Tasten mit Zeitstempel-Toleranz.

---

## 5. Tarotkarten (Jam-Umfang: 4)

Jeder Spieler startet mit **1 zufälligen Karte**, maximal **3 auf der Hand**. Weitere Karten gibt es über *The Pact*.

| Karte | Typ | Wirkung |
|---|---|---|
| **The Ward** | automatisch | Verhindert einmal den eigenen Tod. Wird verbraucht. |
| **The Mirror** | automatisch | Wird man in *The Chamber* zum Ziel, wird der Schuss auf den Schützen umgelenkt. Wird verbraucht. |
| **The Moon** | ausspielbar | Zeigt dir (nur dir), ob die nächste Kammer geladen ist. |
| **The Hermit** | ausspielbar | Wenn du gewählt wirst: Das Ritual geht an den nächsten Spieler weiter. |

- **Typen:** *automatisch* = greift von selbst, wenn die Bedingung eintritt. *Ausspielbar* = der Spieler entscheidet per Klick, wann.
- Kartenhand ist privat. Andere sehen nur, **wie viele** Karten jemand hat.

---

## 6. UI (WebUI, HTML/CSS/JS)

| Bereich | Inhalt |
|---|---|
| Oben Mitte | Ritualname + eine Zeile Anweisung („Choose your target“) |
| Darunter | Zeitbalken |
| Rechts | Spielerliste: lebend / tot, Anzahl Karten, wer gerade dran ist |
| Unten | Eigene Tarotkarten, ausspielbare leuchten |
| Mitte (situativ) | Entscheidungsbuttons (Ziele, Keep/Break, Tastenfolge) |
| Untertitel | Madames Sätze |

Prinzip: **Ein Ritual = eine Frage = ein Input.** Wer stirbt, darf es nicht wegen einer unklaren UI tun.

---

## 7. Architektur

### 7.1 Grundsätze
- **Server entscheidet alles:** Zufall, Treffer, Kartenwirkung, Zeitlimits.
- **Client zeigt an und meldet Wünsche.** Jede Client-Nachricht wird geprüft: Ist der Spieler dran? Ist die Wahl gültig? Ist die Zeit noch offen? Besitzt er die Karte?
- **Rituale sind Module:** Jedes Ritual ist eine eigene Datei mit derselben Schnittstelle. Neue Rituale kommen dazu, ohne den Ablauf anzufassen.
- **Alle Zahlen in `Config.lua`**, alle Spielertexte in einer Textdatei (`Shared/Text.lua`).

### 7.2 Dateien (Ziel)

```
deathbox/
├── Package.toml
├── Shared/
│   ├── Index.lua
│   ├── Config.lua          Zahlen und Einstellungen
│   ├── Text.lua            alle englischen Spielertexte, Madames Sätze
│   └── Cards.lua           Tarotkarten-Definitionen
├── Server/
│   ├── Index.lua           Einstieg, Events verbinden
│   ├── Arena.lua           Salon, Tisch, Stühle, Licht
│   ├── Characters.lua      Figuren, Sitzen, Ausscheiden
│   ├── Table.lua           Sitzplätze, Reihenfolge, Hände
│   ├── GameState.lua       Ablauf der Séance
│   ├── Rituals.lua         Ritual-Register und Auswahl
│   ├── Rituals/
│   │   ├── Chamber.lua
│   │   ├── Pact.lua
│   │   └── Possession.lua
│   ├── Net.lua             Server -> Client Nachrichten, Client-Eingaben prüfen
│   └── Cheats.lua          Testbefehle
├── Client/
│   ├── Index.lua
│   ├── HUD.lua             WebUI erstellen, Nachrichten weiterreichen
│   └── Input.lua           Tasten für Possession, Kartenausspielen
├── UI/
│   ├── index.html
│   ├── style.css
│   └── hud.js
└── docs/
    ├── DESIGN.md
    └── ROADMAP.md
```

### 7.3 Schnittstelle eines Rituals

```lua
-- Jedes Ritual liefert eine Tabelle mit:
{
    id = "chamber",
    weight = 3,                         -- Häufigkeit
    min_alive = 2,                      -- braucht mindestens so viele Lebende
    Start = function(ctx) end,          -- ctx: gewählte Plätze, Hilfsfunktionen
    OnInput = function(ctx, player, data) end,   -- geprüfte Client-Eingabe
    OnTimeout = function(ctx) end,      -- Standardverhalten, wenn niemand reagiert
    -- Ruft am Ende ctx.Finish() auf
}
```

---

## 8. Debug-Befehle (nur Testmodus)

Aktiv, solange `DEBUG_COMMANDS = true` in `Shared/Config.lua` steht. **Vor der Abgabe auf `false` stellen.**

| Befehl | Wirkung |
|---|---|
| `/bots 3` | 3 Test-Bots in der nächsten Partie |
| `/start` / `/stop` | Partie sofort starten / abbrechen |
| `/status` | Zustand anzeigen |
| Taste **B** / `/noclip` | Fliegen |
| `/god` | Unverwundbar (nicht am Tisch) |
| `/arena` | Zurück in den Raum |
| `/sit` / `/sitpos <höhe> <vor>` | Sitzen testen und feinjustieren |
| geplant: `/ritual <id>` | Ein bestimmtes Ritual erzwingen |
| geplant: `/card <id>` | Sich eine Karte geben |

---

## 9. Bewusst NICHT im Jam-Umfang

- Mehr als 3 Rituale, Spielmodi, Map-Abstimmung
- Währung, Cosmetics, Fortschritt, Speicherung
- Eigene 3D-Modelle (nur Standard-Assets)
- Bots mit echter Intelligenz (Bots wählen zufällig)

---

## 10. Offene Punkte

- [ ] Name final: *The Last Séance*?
- [ ] Madame als sichtbare Figur oder nur Stimme/Licht?
- [ ] Server vor dem Playtest vom `bleeding-edge`-Zweig auf die normale Version umstellen (der öffentliche Playtest läuft auf der Steam-Standardversion)
- [ ] Jam-Seite: Eintrag anlegen, Server registrieren
- [ ] `DEBUG_COMMANDS = false` vor Abgabe
