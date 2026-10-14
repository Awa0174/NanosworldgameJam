# Roadmap bis zur Abgabe

**Abgabe:** Fr 23.10.2026, 23:59 UTC (= Sa 24.10., 01:59 Uhr deutscher Zeit)
**Arbeitszeit:** allein, ca. 3+ Stunden pro Tag
**Stand 14.10. (früher Morgen):** v0.8.0 – siehe Zeile 4e. Davor **Stand 14.10. (Nacht):** Umbau auf Instanzen/999 Spieler fertig (nur Simulation, nicht im Spiel getestet). Davor: Richtungswechsel zum Nachbau von *Death in the Box* (Clown in der Mitte, 16–32 Spieler). Fertig aus der Séance-Version: Ablauf, Modul-System, *The Chamber* mit Zielwahl, HUD-Grundgerüst, Arena. Am 13.10. liefen komplette Partien im Spiel (Spieler + Bots) ohne Skriptfehler.

**Regel:** Jeder Tag endet mit einer Version, die man spielen kann. Lieber ein Feature streichen als den Build kaputt abgeben.

| Tag | Datum | Ziel | Fertig, wenn … |
|---|---|---|---|
| ✅ 1–3 | bis 13.10. | Séance-Grundgerüst: Module, Chamber, HUD, Zielwahl | Partie läuft bis zum Sieger |
| ✅ 4 | Mi 14.10. | **Umbau:** bis 32 Plätze, Zirkuszelt + Jack in der Mitte mit Drehung, Rituals → Events, gleichzeitige Abfragen mit Abfrage-ID, Text-Wahlen. **Zusätzlich:** 999 Spieler, Instanzen (Dimensionen), Friedhof-Hub mit Shards, Warteschlange, viele Tische gleichzeitig, Asset-Zuordnung für eigenes Pack | In der Simulation: 300 Spieler, 18 Tische nach 10 s, Partie mit 16 Spielern ca. 7,5 min. **Ingame-Test steht aus** |
| ✅ 4b | Mi 14.10. | Ingame-Test des Umbaus (Screenshot): läuft. Fixes: Bots saßen nicht (Animation erneut senden), Deckel verdeckte Jack, Licht zu rot/hell, Schnee-Partikel im Zelt raus. **Vorgezogen:** Knife Toss (WASD-QTE), Fire Breath (Flamme klicken), Stab Your Neighbour (Nachbar wählen + Block-QTE), Tempo nachjustiert | Simulation ok, **Ingame-Test der Minispiele steht aus** |
| ✅ 4c | Mi 14.10. (Nacht) | **v0.7 Präsentation:** Welt beim Client, Jack animiert, Spieluhr-Dramaturgie, Nachthimmel/Look, eigene Sounds + Texturen, Fix Wegfliegen, Angry Clown, Rescue | Simulation + strenger Client-Test ok, **Ingame-Test steht aus** |
| ✅ 4d | Mi 14.10. (Nacht) | **Vorgezogen (Server):** Revolver als Kette (1 Kugel, 6 Kammern, Weitergabe nach Klick), alle 5 Karten (Hand privat, `/card`, Ausspielen mit Prüfung), Skip/Ricochet/Safety, Spare or Eliminate (Tote stimmen mit), Pass the Pumpkin, Split or Steal, Card Deal, Choose a Card, Tempo-Gewichte je Phase, Chat pro Instanz | Simulation: alle Szenarien grün über 120 Seeds, 16 Spieler ≈ 9 min, 32 Spieler ≈ 18 min. **HUD für die neuen Abfragen und Ingame-Test stehen aus** |
| ✅ 4e | Mi 14.10. (Nacht, nach Screenshot-Feedback) | **v0.8:** Jack 2.0 als Animatronic in der Kiste (dreht sich drin, POP vors Gesicht des Opfers), Revolver mit eigenem 3D-Modell und Nachladen (1/6 → 2/6 → 3/6), Karten-Szenen (Fächer bei Choose a Card), HUD-Panels für alle Abfragen + Kartenhand, Anzeigetafel im Hub, 22 neue Sounds, Vorschau-Renderer für die Client-Welt | Simulation + strenger Client-Test grün; 16 Spieler ≈ 8 min, 32 ≈ 12 min (ohne HUD-gesperrte Events). **Ingame-Test steht aus** |
| ✅ 4f | Mi 14.10. (abends) | **v0.11 Jam-Fassung:** 12 Spieler, 2 Tische à 8, Bots füllen auf, Nachrücker übernehmen Bot-Plätze; Tempo (8er-Show ca. 5 min), 8 Events aktiv, eigene Namen + Kartenbilder, Admin per Server-Konsole statt Debug, Guard/Watchdog, Flutschutz, Leistung Hub/Zelt | Simulation (alt + Jam-Szenarien), Client- und HUD-Test grün. **Ingame-Test steht aus** (Testplan in `IMPROVEMENTS.md`) |
| ✅ 4g | Mi 14.10. (abends) | **v0.12:** Profilbilder/Clown-Porträts in der Spielerliste, Zelt wird mit jedem Toten dunkler und röter, Kamera-Ruck (POP/Tod/Finale), festes Finale „Final Showdown“ mit garantiertem Sieger | Simulation, Client- und HUD-Test grün. **Ingame-Test steht aus** |
| 5 | Fr 16.10. | ~~Karten~~ (vorgezogen, 4d/4e) → **Ingame-Test aller Events und Karten**, Licht/Look einstellen | Jedes Event einmal per `/event` im Spiel gesehen, Liste der Fehler |
| 6 | Sa 17.10. | Fehler aus Tag 5; optional **Multi-Saw** (zwei Spieler hämmern gegeneinander) | Keine bekannten Fehler aus dem Ingame-Test |
| 7 | So 18.10. | Eigenes Asset Pack (Jack-Modell, Map) einbauen, falls fertig; Tempo nachjustieren | 16er-Partie mit Bots in ca. 8–10 Minuten |
| 8 | Mo 19.10. | Zuschauer-Ansicht, Atmosphäre: Raum, Licht, Spotlight, Sounds, Jack-Animationen | Screenshot sieht nach Halloween-Clown-Show aus |
| 9 | Di 20.10. – Mi 21.10. | **Multiplayer-Test mit echten Spielern**, Balancing | Volle Partie mit 4+ Leuten + Bots ohne Fehler |
| 10 | Do 22.10. | Fehler aus dem Test, Polish, Lobby-Text | Keine bekannten Abstürze |
| 11 | Fr 23.10. | **Feature-Freeze 12:00**, Debug aus, Screenshots/Video, Einreichung | Eintrag auf der Jam-Seite abgeschickt |
| – | bis 29.10. | Nur Bugfixes und Polish (laut Jam erlaubt) | – |

## Puffer-Regel

Wenn ein Tag nicht reicht, in dieser Reihenfolge streichen:
1. Free Card
2. Thief, dann Guardian
3. Split or Steal

Nie gestrichen: Jack mit Drehung, Revolver, Spare or Eliminate, Atmosphäre, Multiplayer-Test.

## Was vorher erledigt sein muss (nicht Code)

- [x] Jam-Regeln: Nachbauten sind erlaubt
- [ ] Eigenes Asset Pack (Jack, Map, Sounds, Musik) am Windows-PC mit dem ADK bauen, siehe `ASSETS.md`. Spätestens 20.10. auf den Server, damit Zeit zum Testen bleibt
- [ ] Server-Admin: bis spätestens 20.10. auf den normalen Steam-Zweig umstellen und mit `--steam_app "game"` starten, `max_players = 12`
- [ ] Testspieler für den 20./21.10. organisieren (möglichst viele, Rest mit Bots)
- [ ] Jam-Eintrag auf nanos-world.com anlegen
