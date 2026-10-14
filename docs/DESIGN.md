# Design-Dokument – Jack's Last Show

> **Arbeitstitel:** *Jack's Last Show* (Package-Name bleibt `deathbox`, Titel noch nicht final)
> **Jam:** nanos world Halloween Game Jam 2026 – Abgabe **23. Oktober 2026, 23:59 UTC**, öffentlicher Playtest 30. Oktober – 1. November
> **Vorbild:** *Death in the Box* (Roblox, ARK-ADE). Wir bauen das Spielprinzip bewusst nach: Clown in der Mitte, Spieler im Kreis, zufällige Events, Karten, Last One Standing.
> **Abgrenzung:** Eigener Titel, eigener Clown-Look (aus Standard-Assets), eigene Texte. Nicht übernommen werden Name, Logo und Grafiken des Originals.
> **Sprache:** Alle Texte im Spiel auf **Englisch** (internationales Playtest-Publikum). Code-Kommentare und Doku auf Deutsch.
>
> **Richtungswechsel 14.10.:** Das frühere Séance-Konzept (Madame, Tarot, 8 Plätze) ist ersetzt. Die Technik dahinter (Ablauf, Module, Netzwerk, HUD) bleibt und wird umgebaut.
> **Umbau v0.7 (14.10. nachts) nach Spielerfeedback („billig“, „wegfliegen“, „keine Spannung“):** Die ganze Welt (Zelt, Friedhof, Jack, Effekte) wird jetzt **lokal beim Client** gebaut und Bild für Bild animiert; der Server schickt nur Regieanweisungen. Eigene, selbst erzeugte **Texturen und Sounds** werden ohne Unreal direkt aus dem Package geladen (`package://`). Map: `default-empty-map` mit Nachthimmel. Jede Auswahl läuft als Spieluhr-Sequenz mit Abbremsen, Stille und „POP!“.
> **Umbau v0.10 (14.10. Tag) nach dem Spielertest von v0.8 („VIEL zu schnell“, „man weiß nie, wer dran ist und was man tun muss“, „Jacks Gesicht ist Mist“, „beim Revolver will ich richtig zielen“):** Lesbarkeit vor Tempo. Langsamer, immer gleicher Spin (10 s Spieluhr mit zufälliger Kinderlied-Melodie, 2 s Stille), jede Phase länger lesbar, ein **Rundenergebnis** nach jedem Event, eine **Stage-Zeile** (Phase, wer, was ICH tun muss, Restzeit), „GET READY“-Vorwarnung vor jeder Eingabe, der **Revolver liegt in der Hand und wird mit der Maus gezielt** (alle sehen, auf wen). Details: Abschnitt 3 und 4.1, Vertrag: [`PROTOCOL.md`](PROTOCOL.md) („Klarheit“).
> **Server-Größe 14.10.:** Bis zu **999 Spieler** auf einem Server. Viele Shows laufen gleichzeitig, jede in einer eigenen Instanz (nanos-Dimension). Ab sofort Halloween-Look: Friedhof als Hub, Zirkuszelt als Show-Raum. Eigene Assets/Map folgen über ein Asset Pack, siehe [`ASSETS.md`](ASSETS.md).

---

## 1. Vision

Spieler landen auf einem nächtlichen **Friedhof (Hub)**. Sobald genug warten, öffnet sich ein **Zirkuszelt**: bis zu **16 Spieler (konfigurierbar bis 32)** sitzen im Kreis um eine Box. Auf einem Server laufen viele Zelte gleichzeitig. Darin wohnt **Jack**, ein Clown, der die Show leitet. Jack dreht sich, zeigt auf einen Spieler und startet ein **Event**: mal Revolver, mal Reaktion, mal Abstimmung, mal Deal zwischen zwei Spielern. Karten geben jedem einen Ausweg, aber nicht für immer. Wer als Letzter übrig ist, gewinnt.

### Was das Original ausmacht (und wir übernehmen)
- **Rundenbasierte Eliminierung:** Jede Runde ein Event, danach wird neu gemischt.
- **Zufällige Events:** Niemand weiß, was als Nächstes kommt.
- **Karten:** Schutz, Ausweichen, Stehlen. Sie geben dem Zufall eine strategische Ebene.
- **Social PvP:** Spieler zielen aufeinander, stimmen übereinander ab, machen Deals.
- **Präsentation:** Der Clown, der sich dreht und zeigt, macht aus RNG ein Erlebnis. Spannung entsteht *vor* dem Ereignis.

### Bewusst nicht im Jam-Umfang
- Spielmodi (Bloodbath, Double Cards, Four Teams, Roundabout …), Map-Vote, mehrere Maps
- Währung, Shop, Cosmetics, Spins, Badges, Speicherung
- Lobby-Geheimnisse (Höhle, Backrooms)
- Bots mit echter Intelligenz (Bots wählen zufällig)

Die Architektur soll Modi später erlauben (Regeln über Config statt kopierter Event-Logik), gebaut werden sie im Jam nicht.

---

## 2. Setting & Präsentation

| Element | Umsetzung |
|---|---|
| Hub | Friedhof unter Nachthimmel mit Mond und Bodennebel: Spawn-Gruft (Särge, Kerzen, grünes Licht), Steinmauer, Gräber, Kürbisse mit Kerzenschein, tote Bäume, Fackeln, kreisende Geister, Plakate, Jack als riesige Statue (dreht sich, lacht ab und zu), im Norden die Fassade eines Zirkuszelts mit Lichterkette |
| Show-Raum | Rundes Zirkuszelt aus gestreiftem Segeltuch (Textur), Holzbühne mit Sägemehl-Manege, Lichterketten vom Mast (flackernde/kaputte Birnen), Öllampen über dem Kreis, Plakate, Fässer, Kürbisse, schwebende Ballons; Jack in der Spielzeugkiste mit Kurbel |
| Look | Belichtung fixiert (kein Aufhellen dunkler Szenen), Vignette, Filmkorn, leicht entsättigt, Bloom auf leuchtenden Teilen; bei Spannung enger, farbloser, Farbsaum |
| Ton | Selbst synthetisierte Sounds: Spieluhr mit vier gemeinfreien Kinderliedern für den Spin (`spin_rosie` „Ring a Ring o' Roses“, `spin_weasel` „Pop Goes the Weasel“, `spin_bridge` „London Bridge“, `spin_lullaby` „Rock-a-bye Baby“; je genau 10,0 s mit Ritardando, leicht verstimmt, leiernd, die Mechanik bleibt am Ende mit einem Klack stehen; den Herzschlag in den 2 s Stille danach startet `Audio.Music(name, vol, hold)`), im Hub eine ferne, verstimmte Dampforgel mit Fučíks „Einzug der Gladiatoren“ (1897, 32-s-Loop unter der Friedhofs-Atmo), Stinger `your_turn`, `round_out`, `round_safe`, Holz-Ticks, Herzschlag, Trommelwirbel, Schock-Akkord, enttäuschte Posaune, Zelt-/Friedhofs-Atmo |
| Host | **Jack 2.0**: Animatronic in einer Harlekin-Spielzeugkiste mit Kurbel und Klappdeckel. Porzellanschädel mit Maske (drei Gesichter: Grinsen, Lachen, Wut mit glühenden Augenschlitzen), Zylinder, Halskrause, Messing-Gelenkarme mit Klauen, Feder aus Ringen. Bewegt sich „servo-artig“ (ruckelnde Gelenke, zufälliges Zucken, Servo-/Kiefer-Sounds), starrt in Ruhe jeden Spieler einzeln an. Aus Grundformen + eigenen Texturen gebaut; ein echtes 3D-Modell kann ihn ersetzen (`docs/ASSETS.md`) |
| Auswahl | Jack verschwindet in der Kiste, der Deckel schlägt zu, die **Kiste** dreht sich zur Spieluhr und rollt aus. Stille, Deckel klappert, rotes Licht aus dem Spalt – dann **POP**: Jack schießt auf seiner Feder bis kurz vor das Gesicht des Opfers. Spotlight auf das Ziel |
| Licht | Wenig Licht, Spotlight auf Jack und auf den gewählten Spieler |
| Ton | Leierkasten-/Spieluhr-Ambient, Ratschen beim Drehen, Leerklick, Schuss, Lachen bei Tod |
| Untertitel | Jack kommentiert jedes Ereignis (mehrere Sätze pro Situation, damit es sich nicht wiederholt) |

**Jacks Sprechweise (Beispiele, Englisch):**
- *„Round and round she goes… and stops on **Awa**!“*
- *„Click! Oh, you lucky little thing.“*
- *„Bye-bye, **Max**. Big round of applause!“*

---

## 3. Spielablauf

```
JOIN ──> HUB (Friedhof) ──> Warteschlange ──(≥ MIN_PLAYERS, Countdown)──> neues ZELT (eigene Instanz)
ZELT:  Event auswählen ──> Jack dreht sich ──> Ziel(e) ──> Event ──> Auflösung ──> nächste Runde
ZELT ──(1 Spieler übrig oder 0)──> ENDE ──> zurück in den HUB ──> wieder in die Warteschlange
```

- **Instanzen:** Jeder Hub-Bereich (je 64 Spieler) und jedes Zelt läuft in einer eigenen nanos-Dimension. Alle sehen identisch aus, man sieht aber nur die Leute der eigenen Instanz. Netzwerkdaten gehen nur an die betroffene Instanz.
- **Warteschlange:** gilt für alle Hubs zusammen. Countdown 15 s, sobald ein voller Tisch zusammen ist nur noch 5 s. Warten genug für mehrere volle Tische, starten die alle gleichzeitig. Höchstens 64 Zelte gleichzeitig.
- **Plätze:** Standard 16, per Config bis 32. Sitzordnung zufällig. Tische, die nicht voll sind, verteilen sich gleichmäßig um den Kreis.
- **Auswahl:** Der **Server** würfelt das Ziel (unter Berücksichtigung von Karten wie Skip). Jack dreht sich danach sichtbar dorthin. Die Drehung ist reine Anzeige.
- **Event-Auswahl:** gewichtet zufällig, nie zweimal dasselbe hintereinander, abhängig von der Zahl der Lebenden.
- **Ausscheiden:** Figur stirbt am Platz, Jack lacht. Nach 3 s steht man als **Zuschauer** hinter dem Stuhlkreis wieder auf, darf herumlaufen und bei bestimmten Abstimmungen mitstimmen. `/leave` bringt einen zurück in den Hub.
- **Sonderfälle:** Verlassen = ausgeschieden. Wer während einer Show joint, schaut zu. Jede Eingabe hat ein Zeitlimit mit festem Standardverhalten, damit nichts hängen bleibt. Sterben alle gleichzeitig, gibt es keinen Sieger (nie fälschlich einen ausrufen).

### Tempo (wichtig bei 32 Spielern)
Mit nur einem Revolver (Treffer 1 zu 6) würde eine 32er-Partie viel zu lang. Deshalb:
- **Tödlichkeit skaliert mit der Zahl der Lebenden.** Solange viele leben, sind Events häufiger tödlich (z. B. höhere Trefferchance, Abstimmungs-Events häufiger). Die Werte stehen in `Config.lua` und werden im Test eingestellt.
- Jede Wartezeit hat eine sichtbare Anzeige, jede Phase eine Stage-Zeile.
- **Ziel (v0.10, nach dem Spielertest „VIEL zu schnell“):** Längere Partien sind ausdrücklich in Ordnung. Spieluhr (10 s), Stille (2 s), POP (3 s), Event-Karte (5 s, bei Wiederholung 3,5 s) und Rundenergebnis (4 s) kosten pro Runde ca. 23 s und werden **nie** gekürzt. Grenze: Liegt der Median einer 16er-Partie über ca. 18 min, wird Jack tödlicher (`EVENT_WEIGHTS`), nicht schneller.
- **Simulation v0.10 (14.10., `sim/run.lua pace`, 40 Partien, alle Events, Karten werden gespielt):** 16 Spieler Median **16,6 min** (12,1–25,6 min; mit realistischer Bedenkzeit 15,3 min), 32 Spieler Median **25,9 min** (mit Bedenkzeit 24,8 min). Vorher (v0.8) 9,3 / 15,4 min. Für 32 Plätze ist die Spalte „riesig“ (≥ 17 Lebende) etwas tödlicher (mehr Schießbude und Angry Clown, weniger Atempausen); 16er-Partien ändert das nicht.
- *Frühere Ziele (v0.8):* 16 Spieler in ca. 8–11 Minuten, 32 Spieler in ca. 13–17 Minuten.
- **Große Tische:** Solange 17 oder mehr leben (nur mit mehr als 16 Plätzen), gibt es die **Shooting Gallery** (drei Ziele pro Runde, siehe 4.6b). Ohne sie brauchte ein 32er-Tisch allein für die ersten 16 Ausgeschiedenen 28 Runden (8,6 min), mit ihr ca. 19 Runden (6 min). Die 16er-Partie ändert sich dadurch nicht.
- **Simulation v0.8 (14.10. nachts, alle 13 Events, Karten werden gespielt, simulierte Spieler treffen QTE-Tasten zu 85 %, je 100 Partien):** 16 Spieler im Mittel 9,5 min (6,8–13,7 min), 32 Spieler im Mittel 14,9 min (11,6–19,5 min); vorher 9,2 / 17,7 min (bis 24 min). Mit realistischer Bedenkzeit 9,0 / 14,5 min. Atempausen (Deal, Split or Steal, Choose a Card) sind ca. 10 % der Runden. Solange das HUD noch keine Panels für Abstimmung, Kürbis, Split or Steal, Kartenwahl und Bombe hat (HUD-Sperre, Abschnitt 6), fehlen diese Events: dann 8,7 / 12,8 min. Echte Werte erst im Playtest; alle Stellschrauben stehen in `Config.lua` (`EVENT_WEIGHTS` je Phase, Zeitfenster, Bot-Quoten, Kartengewichte in `Shared/Cards.lua`).

---

### Dramaturgie einer Runde (v0.10)

| Phase (`State.stage`) | Dauer | Was passiert | Stage-Zeile (Beispiel) |
|---|---|---|---|
| Spin (`spin`) | 10 s, immer | Jack lugt aus der offenen Kiste (Deckel ~110°) und dreht sich langsam mit ihr, 1–2 Umdrehungen ab seiner Blickrichtung; roter Suchscheinwerfer aus seinen Augen streift die Stühle (Flackern + Tick), kriecht am Ende und stoppt. Spieluhr: zufällig „Ring a Ring o' Roses“, „Pop Goes the Weasel“, „London Bridge“ oder „Rock-a-bye Baby“ (gemeinfrei), nie zweimal hintereinander dieselbe, Ritardando bis zum Stopp | „JACK IS CHOOSING…“ |
| Stille | 2 s | Licht auf dem Opfer, Jack starrt, Herzschlag | |
| POP (`pop`) | 3 s | Jack springt bis ca. 1 m vor das Gesicht des Opfers und lacht, Name groß | „JACK PICKED NIBBLES“ |
| Karte (`card`) | 5 s (3,5 s bei Wiederholung) | Name, wer, 2–3 Stichpunkte „so geht's“, „YOU: …“ (für Gewählte bzw. alle anderen) | „REVOLVER – Nibbles gets the revolver“ |
| Event (`event`) | variabel | Minispiel. Vor jeder Eingabe mind. 2,5 s „GET READY …“, dann „YOUR TURN – …“ + Zeitbalken | „Nibbles is aiming at Bonzo…“ |
| Rundenergebnis (`result`) | 4 s | `round_end`: wer ist raus, wer hat überlebt, wie viele leben | „ROUND 7 – Bonzo is OUT · 12 left“ |

Showbeginn (12 s): „How to play“ im HUD, Jack steckt in der Kiste, Spieluhr („Pop Goes the Weasel“), POP bei 10 s mit Fanfare und Konfetti, Begrüßung. Es gibt keinen schnellen Spin mehr: Lesbarkeit vor Tempo.

## 4. Events (✅ = gebaut; Häufigkeit je Phase in `Config.EVENT_WEIGHTS`)

Die Regeln orientieren sich an den öffentlich dokumentierten Events des Originals. Was dort nicht genau beschrieben ist (Zeiten, Wahrscheinlichkeiten), legen wir selbst fest und machen es in `Config.lua` einstellbar.

### 4.1 Revolver – *Glück + Taktik* ✅ (Kette wie „Revolver Roulette“ im Original)
- Jack wirft dem gewählten Spieler einen Revolver zu (eigenes 3D-Modell, liegt in der **rechten Hand** des Halters): **sechs Kammern, eine Kugel**.
- Der Halter **zielt richtig** (v0.9, Wunsch aus dem Test): kein Ring, die Maus bleibt gefangen und dreht die Kamera, Fadenkreuz in der Bildmitte; anvisiert ist der lebende Spieler, dessen Kopf (oder Brust) dem Kamerastrahl am nächsten liegt (höchstens 10°). Alle sehen live, worauf er zielt: der Arm hebt sich, die Figur dreht sich hin, Halter **GOLD**, Ziel **ROT** markiert. **Linksklick** drückt ab; danach rastet der Hahn ein, die Hand zittert – Klick oder Knall. **Zeitlimit:** Wer nicht schießt, dem reißt Jack den Revolver aus der Hand und dreht ihm den Lauf vors eigene Gesicht.
- **Zeiten und Server (v0.10):** 2,5 s „GET READY“, während der Revolver in die Hand fliegt (`REVOLVER.GIVE_TIME`), dann 12 s zum Zielen und Abdrücken, 2,5 s Hahn gespannt, 3 s Weitergabe nach einem Klick, 3,5 s nach dem Knall. Zwischenstände (`DeathBox:Aim`) prüft der Server (nur der Halter, nur in der Wahl, nur erlaubte Ziele, max. 6/s pro Spieler) und zeigt sie allen höchstens 5×/s (`revolver_aiming`); die sitzende Figur des Halters dreht er zum Ziel. Bots schwenken erst über 1–2 andere Plätze, dann aufs echte Ziel.
- **Klick:** Die Trommel dreht weiter, das Ziel bekommt den Revolver und schießt als Nächstes. Hat sich der Halter selbst angeklickt, wandert der Revolver zum nächsten Lebenden im Uhrzeigersinn.
- **Nachladen (Standard, Wunsch aus dem Test):** Nach jedem Klick lädt Jack eine Kugel nach und dreht die Trommel. Chance pro Abzug **1/6, 2/6, 3/6, 4/6, 5/6, 6/6** – die Spannung steigt sichtbar (Messing in der Trommel, HUD „2 IN 6“). Simulation: Knall bei Abzug 1–6 im Verhältnis 17 / 28 / 28 / 19 / 8 / 1,5 %, im Mittel 2,8 Abzüge (klassisch 3,5). Klassisch mit `Config.REVOLVER.LOAD_EXTRA = false`: eine Kugel bleibt, Chance 1/6, 1/5, 1/4, 1/3, 1/2, 1/1 (kumuliert 1/6, 2/6, 3/6 …).
- **Der Knall beendet das Event.** Karten: Ricochet lenkt die Kugel ab, Safety rettet.
- Geht der Halter, wandert der Revolver weiter; geht das Ziel vor dem Abdrücken, wählt der Halter neu (die Kammer bleibt geladen).

### 4.2 Knife Toss – *Reaktion* ✅
- Jack holt aus (2,6 s „GET READY“) und wirft ein Messer auf den gewählten Spieler. Es erscheinen nacheinander **3 Tasten (W/A/S/D)**, groß in der Bildschirmmitte, mit kürzer werdendem Zeitfenster (1,6 s → 1,25 s → 1,0 s; v0.8: 1,3 → 1,0 → 0,8).
- Alle richtig = ausgewichen, das Messer fliegt vorbei. Falsche Taste oder zu langsam = getroffen, tot.
- Tastenfolge und Prüfung macht der Server. Der Client liest die Taste direkt aus dem Spiel (keine Maus nötig).
- Karten: Safety greift **nicht** (kein Schuss).

### 4.2b Fire Breath – *Klicken unter Druck* ✅
- Jack spuckt Feuer, der Spieler brennt (Feuer-Partikel am Platz). Nach 2,6 s „GET READY“ springt eine Flamme über den Bildschirm und muss **10-mal in 6,25 s** angeklickt werden.
- Geschafft = Feuer aus (Rauch). Nicht geschafft = verbrannt.
- Jede Position und jedes Klick-Token kommt vom Server, die Zeit misst der Server.

### 4.2c Stab Your Neighbour – *Social + Reaktion* ✅
- Jack gibt dem Spieler ein Messer (2,5 s „GET READY“). Er wählt seinen **linken oder rechten lebenden Sitznachbarn** (Ring, nur die zwei sind anklickbar, 8 s). Zu langsam = Jack sticht den Halter selbst.
- Das Messer schwebt 2,5 s über dem Opfer („GET READY TO BLOCK“). Dann bekommt es **eine Taste und 1,15 s zum Blocken**. Geblockt = überlebt, sonst tot.

### 4.3 Split or Steal – *Deal* (aus *The Pact* umgebaut)
- Jack wählt **zwei Spieler**. Kurze Redezeit (Chat/Voice), dann wählen beide **geheim**: Split oder Steal.

| A | B | Ergebnis |
|---|---|---|
| Split | Split | Beide bekommen eine Karte |
| Steal | Split | A bekommt alle Karten von B und eine zusätzliche Karte |
| Steal | Steal | Niemand bekommt etwas |

- Keine Wahl gilt als Split. Aufdecken gleichzeitig, für alle sichtbar. Was nicht mehr auf die Hand passt (max. 5), behält Jack.
- Niemand stirbt. Das Event ist bewusst ein Atemholen zwischen den tödlichen Runden. ✅

### 4.4 Spare or Eliminate – *Abstimmung*
- Jack wählt ein Ziel. **Alle** stimmen ab, auch Ausgeschiedene (und Bots, 60 % Eliminate): Spare oder Eliminate. Stimmen werden live sichtbar gezählt. Haben alle gewählt, endet die Abstimmung sofort. ✅
- Mehrheit entscheidet. Gleichstand (auch 0:0) = Jack wirft eine Münze (wie im Original).
- Gibt Zuschauern etwas zu tun und ist der stärkste Hebel fürs Tempo.
- Karten: Safety greift **nicht** (kein Schuss).

### 4.5 Card Deal und Choose a Card – *Atempausen* ✅
- **Card Deal:** „N PLAYERS WILL NOW BE GIVEN CARDS“ – Jack verteilt je eine zufällige Karte an ⌈Lebende/3⌉ Spieler, der Gewählte ist immer dabei.
- **Choose a Card:** Der Gewählte nimmt eine von drei verschiedenen Karten. Zeitlimit = Jack zieht zufällig.

### 4.6 Angry Clown – *Tempo* ✅
- Jack verliert die Geduld: Er zielt selbst (Trommelwirbel), dann BANG. Nur Karten helfen: Safety rettet, Ricochet lenkt ab.
- Häufiger, solange viele leben (Gewicht 3 ab 17 Lebenden, 4 ab 9, 1,5 ab 5, sonst 0,5). Hält große Runden im Tempo, ohne die Spannung der Auswahl zu kürzen.

### 4.6b Shooting Gallery – *Tempo an großen Tischen* ✅
- Nur solange 17 oder mehr leben. Jack spielt Schießbude: Er legt nacheinander auf den linken Nachbarn, den Gewählten und den rechten Nachbarn an und drückt jedes Mal ab („Pop goes …“). Wer neben dem Gewählten sitzt, zittert schon beim Drehen mit.
- Nur Karten helfen: Safety rettet, Ricochet lenkt ab, Skip gibt die Mitte der Reihe ab. Geht das Ziel, auf das Jack gerade anlegt, schwenkt er sofort weiter. Lebt nur noch einer, hört Jack auf.
- Darstellung wie Angry Clown (`angry_aim` und `revolver_shot` ohne Schütze), nur dreimal. Im Mittel ca. 2 Ausgeschiedene in 8 s.

### 4.7 Pass the Pumpkin – *Heiße Kartoffel* ✅
- Jack zündet einen Kürbis an und wirft ihn dem Gewählten zu. Die Zündschnur brennt geheim 7–14 s.
- Der Halter wirft ihn an seinen linken oder rechten lebenden Nachbarn (kurz in der Luft: der Fänger kann erst nach 0,5 s weiterwerfen).
- Wer ihn hält, wenn er explodiert, scheidet aus. Keine Karte rettet.

### 4.8 Defuse or Die und Quick Draw ✅
- **Defuse or Die** (`Server/Events/Bomb.lua`): Bombe mit drei Drähten und einer Regel aus Jacks Handbuch („Cut the wire with the HIGHEST number.“). Richtiger Draht = entschärft, falscher oder zu langsam = BOOM. Keine Karte rettet.
- **Quick Draw** (`Server/Events/Duel.lua`): Duell zweier Spieler auf „DRAW!“. Wer zuerst die richtige Taste drückt, schießt; falsche Taste = Schuss ins eigene Bein; drückt keiner, schießt Jack auf beide. Safety und Ricochet gelten wie bei jedem Schuss, Skip für beide Duellanten. Geht einer, gewinnt der andere kampflos.
- Zahlen in `Config.BOMB` / `Config.DUEL`, Texte in `Shared/Text.lua` wie bei allen Events.

### Später (nach dem Jam bzw. falls Puffer bleibt)
Multi-Vote, Life Saver, Laser Pointer, Clown Hostage.

---

## 5. Karten (Jam-Umfang: 5) ✅

Jeder Spieler startet mit **1 zufälligen Karte** (nach Gewicht, `Shared/Cards.lua`), maximal **5 auf der Hand**. Weitere Karten über Card Deal, Split or Steal und Choose a Card. Ausgeschiedene verlieren ihre Karten.

| Karte | Typ | Wirkung |
|---|---|---|
| **Safety** | automatisch | Überlebt einmal einen Schuss (Revolver, Angry Clown, Shooting Gallery, Duell). Wird verbraucht. Hilft nicht bei Messer, Feuer, Bombe, Kürbis oder Abstimmung. |
| **Skip** | automatisch | Wählt Jack dich für ein Event, in dem du selbst in Gefahr bist (nicht Revolver/Stab, dort bist du zuerst der Schütze), ist ein zufälliger anderer dran. Gilt auch für den zweiten Duellanten. Höchstens einmal pro Runde. Wird verbraucht. |
| **Ricochet** | automatisch | Ein Schuss auf dich (Revolver, Angry Clown, Shooting Gallery, Duell) wird auf einen zufälligen anderen Lebenden umgelenkt (auch den Schützen). Keine Kette. Wird verbraucht. |
| **Guardian** | ausspielbar | Gib einem lebenden Spieler (auch dir selbst) eine Safety, die nach 3 Runden verfällt. Wird verbraucht. |
| **Thief** | ausspielbar | Stiehl einem anderen Spieler eine zufällige Karte. Wird verbraucht. |

- **Typen:** *automatisch* greift von selbst, wenn die Bedingung eintritt. *Ausspielbar* heißt, der Spieler öffnet die Hand (Taste C), klickt die Karte und wählt ein Ziel. Jederzeit während der Show, höchstens eine Karte pro 2 s; der Server prüft alles (`DeathBox:PlayCard`). Bots spielen ihre Guardian- und Thief-Karten selbst (zu Beginn einer Runde, höchstens einer pro Runde).
- **Reihenfolge, wenn mehrere greifen:** Skip (beim Auswählen) → Ricochet → Safety (beim Treffer).
- Kartenhand ist privat. Andere sehen nur, **wie viele** Karten jemand hat.
- Jede Karte hat eine Liste von Events, in denen sie gilt. Eine Karte wirkt nie außerhalb davon.

---

## 6. UI (WebUI, HTML/CSS/JS)

| Bereich | Inhalt |
|---|---|
| Oben Mitte | **Stage-Zeile** (v0.10): genau eine Zeile, was gerade passiert und was ICH tun muss – oder „nur zuschauen“ (`State.stage`, `event.instruction_actor` für `event.involved`, sonst `instruction_others`). Bei eigener Abfrage riesiges „YOUR TURN“ + Anweisung + Zeitbalken + Sting |
| Darunter | Zeitbalken |
| Rechts | Spielerliste (kompakt, scrollbar bis 32): lebend / tot, Anzahl Karten, wer dran ist |
| Unten | Eigene Karten, ausspielbare leuchten |
| Mitte (situativ) | Zielwahl, Split/Steal, Dodge-Buttons, Abstimmung |
| Untertitel | Jacks Sätze |

- **Zielwahl bei bis zu 32 Spielern:** Ring wie bisher, aber kompakt (kurze Namen, kleinere Buttons). Alternativ Liste, falls der Ring bei 32 unlesbar wird. Wird an Tag 4 entschieden.
- Prinzip: **Ein Event = eine Frage = ein Input.** Wer stirbt, darf es nicht wegen einer unklaren UI tun.
- **HUD-Sperre:** Jedes Event meldet an, welche Abfrage-Arten es stellt (`kinds`). Ausgewürfelt wird es nur, wenn das HUD alle anzeigen kann (`Config.HUD_CHOICE_KINDS`, seit HUD v0.9 alle acht Arten). Neue Arten kommen erst dort hinein, wenn ihr Panel fertig ist; per `/event` lassen sie sich vorher testen.
- **Klarheit (v0.10, Spielertest):** Jederzeit lesbar: Phase, wer beteiligt ist, was ich tun muss, Restzeit. Event-Karte mit Stichpunkten und „YOU: …“, Rundenergebnis nach jedem Event, Sitzliste während Spin/POP aus, wenige gleichzeitige Toasts/Banner, nichts überdeckt die Stage-Zeile. Texte: `Shared/Text.lua` (`EVENTS.<id>`: `who`, `how`, `you_actor`, `you_others`, `stage`).
- **Sicherheit:** Spielernamen und Texte werden in der WebUI nur per `textContent` gesetzt, nie als HTML.

---

## 7. Architektur

### 7.1 Grundsätze
- **Server entscheidet alles:** Zufall, Auswahl, Treffer, Kartenwirkung, Zeitlimits, Abstimmungsergebnis.
- **Client zeigt an und meldet Wünsche.** Jede Client-Nachricht wird geprüft: Ist der Spieler gefragt? Ist die Wahl gültig? Gehört sie zur aktuellen Abfrage (Abfrage-ID)? Besitzt er die Karte?
- **Events sind Module:** Jedes Event ist eine eigene Datei mit derselben Schnittstelle. Neue Events kommen dazu, ohne den Ablauf anzufassen.
- **Alle Zahlen in `Config.lua`**, alle Spielertexte in `Shared/Text.lua`.

### 7.2 Dateien (v0.7)

```
deathbox/
├── Shared/
│   ├── Config.lua          Zahlen: Instanzen, Plätze, Dramaturgie-Zeiten, Minispiele, Welt-Koordinaten, Sitzwerte
│   ├── Assets.lua          logischer Name -> Asset; SoundFile()/TextureFile() fuer package://-Dateien
│   ├── Layout.lua          Stuhl-/Sitz-/Zuschauer-/Spawn-Positionen (Server UND Client rechnen identisch)
│   ├── Text.lua            englische Spielertexte, Jacks Saetze, Event-Karten (Name, Tagline, Regel)
│   └── Cards.lua
├── Server/                 nur Logik, KEINE Geometrie
│   ├── Instances.lua       Dimensionen vergeben
│   ├── Characters.lua      Figuren platzieren/hinsetzen (StopMovement + Flugmodus + synchrone Pose)
│   ├── Lobby.lua           Hubs, Warteschlange, Tische
│   ├── Match.lua           ein Tisch: Dramaturgie, Regieanweisungen (Show), Zuschauer, Ende
│   ├── Cards.lua           Kartenhand: geben, verfallen, privat synchronisieren, ausspielen (guardian, thief)
│   ├── Events.lua          Event-Kontext (Abfragen, Timer, Kill/Shoot mit Karten, Show)
│   ├── Events/             Revolver, KnifeToss, FireBreath, Stab, AngryClown, Gallery, Vote, Pumpkin, Bomb, Duel,
│   │                       Deal, SplitSteal, ChooseCard
│   ├── Rescue.lua          holt Abgestuerzte/Abgedriftete zurueck (1x pro Sekunde)
│   ├── Net.lua             Nachrichten pro Dimension
│   └── Commands.lua        Chat-Befehle, Cheats
├── Client/
│   ├── World/Builder.lua   lokale Bauhilfen (Texturen, Leuchten, Licht, Partikel, Billboards) + Tick-Animationen
│   ├── World/World.lua     baut den aktuellen Ort (Friedhof oder Zelt) und reisst den alten ab
│   ├── World/Hub.lua       Friedhof
│   ├── World/Tent.lua      Zirkuszelt, Licht-Stimmungen, Ziel-Spot
│   ├── World/Jack.lua      Jack 2.0: Animatronic + Kiste, Feder-Physik, Servo-Gelenke (Spin, PopOut, Laugh, Aim, Throw, Intro ...)
│   ├── Presentation.lua    Regie: setzt Show-Anweisungen in Bild/Ton um
│   ├── Audio.lua           Sounds, Spieluhr, Loops, Atmo
│   ├── Atmosphere.lua      Nachthimmel, Belichtung, PostProcess, Spannung, Blitze, Konsolenbefehle
│   ├── Poses.lua           spielt die Sitz-Pose fuer alle Figuren lokal ab
│   ├── HUD.lua             Bruecke Server <-> Welt/Regie <-> WebUI
│   ├── UI/                 WebUI (HTML/CSS/JS), Schriften
│   ├── sounds/             selbst synthetisierte .ogg
│   └── textures/           selbst generierte .png
└── docs/
```

**Regieanweisungen (Server -> Client, `DeathBox:Show`, pro Dimension):** vollständige Liste mit Feldern in [`PROTOCOL.md`](PROTOCOL.md) – Auswahl (`intro`, `spin`, `pop`, `skip`, `card`, `point`), Revolver-Kette, Messer, Feuer, Hackbeil, Angry Clown/Shooting Gallery, Abstimmung, Kürbis, Bombe, Duell, Split or Steal, Karten (`deal`, `card_gain`, `card_play`, `card_trigger`), `death`, `survive`, `winner`. Plätze werden um `<feld>_chair` ergänzt; der Client berechnet Positionen über `Shared/Layout.lua`.

**Warum die Welt beim Client:** `TranslateTo/RotateTo` vom Server werden zwar an alle Clients geschickt, aber jeder Schritt einzeln (ruckelig) und ohne Spieler mit Warnungen. Lokal gibt es eine flüssige Bild-für-Bild-Animation, null Netzwerk-Last und keinen Server-Speicher für Deko – wichtig bei 999 Spielern.

**Warum Spieler „wegflogen“ (Analyse der 1.159-Binary):** `SetGravityEnabled(false)` setzt bei Characters nur die Schwerkraft auf 0; die Figur bleibt im Fall-Zustand, in der Luft wird nicht gebremst, Restschwung + `NoCollision` = sie gleitet davon. Nach 1 s „HighFalling“ (zappelnde Bots). `PlayAnimation` wird nicht gespeichert (spätere Zuschauer sehen keine Sitz-Pose). Lösung: `StopMovement(true)` + `SetFlyingMode(true)` + synchroner Wert `DB_SitAnim`, den jeder Client abspielt; zusätzlich Rescue-Schleife.

### 7.3 Schnittstelle eines Events

```lua
{
    id = "revolver",                     -- Häufigkeit: Config.EVENT_WEIGHTS[id] (viele / mittel / wenige Lebende)
    min_alive = 2,
    actors = 1,                          -- wie viele Spieler Jack auswählt (Split or Steal, Duell: 2)
    kinds = { "target" },                -- Abfrage-Arten, die das Event stellt (HUD-Sperre, Config.HUD_CHOICE_KINDS)
    Start = function(ctx) end,           -- ctx.actors = gewählte Plätze
    OnInput = function(ctx, seat_index, choice, kind) end,
    OnSeatLeft = function(ctx, seat_index, was_alive) end,   -- optional, auch für Ausgeschiedene (Abstimmung)
    GetPublic = function(ctx) end,       -- optional: Daten fürs HUD
    -- Ruft am Ende ctx:Finish() auf
}
```

**Abfragen:** `ctx:Ask` / `ctx:AskMany` fragen einen oder **mehrere Plätze gleichzeitig** (Split or Steal: 2 geheim, Abstimmung: alle inkl. Toten, ein Zustand-Push). Jede Abfrage bekommt eine ID. Antworten mit alter ID werden verworfen. Wahlen dürfen Zahlen **oder** Texte sein (`"split"`, `"steal"`). Ist die Antwort ein Platz (`target`, `pass`), muss er noch leben; geht ein angebotener Platz, stellt `ctx:UpdateAsk` die Frage mit Restzeit neu.

**Treffer:** `ctx:Kill(platz, ursache)` wendet die Karten an (bei Schüssen: Ricochet, dann Safety) und gibt `ergebnis, getroffener_platz` zurück. `ctx:Shoot` macht dasselbe mit Regieanweisung `revolver_shot` und kurzer Flugzeit beim Ricochet.

---

## 8. Debug-Befehle (nur Testmodus)

Aktiv, solange `DEBUG_COMMANDS = true` in `Shared/Config.lua` steht. **Vor der Abgabe auf `false` stellen.**

| Befehl | Wirkung |
|---|---|
| `/leave` | **Immer aktiv:** als Ausgeschiedener zurück in den Hub |
| `/bots <n>` | Bots für den nächsten Tisch (bis Platzlimit) |
| `/start` | Nächsten Tisch sofort eröffnen |
| `/stop` | Eigenen Tisch beenden |
| `/status` | Hubs, Warteschlange, Tische, eigener Tisch |
| `/event <id>` | Nächstes Event am eigenen Tisch erzwingen |
| `/card <id>` | Sich selbst eine Karte geben (lebend am Tisch): `safety skip ricochet guardian thief` |
| Taste **B** / `/noclip` | Fliegen |
| `/god`, `/hub` | Unverwundbar, zurück zum Spawn |
| `/sitpos <höhe> <vor> [drehung]` | Sitzposition live feinjustieren (Startwerte 100 / 15 / 0 aus dem Ingame-Test von v0.5.3) |
| Konsole (F1/Client): `db_exposure <ausgleich> <min> <max>` | Belichtung festlegen (Standard 1 -1.5 3) |
| Konsole: `db_light <faktor>` | flackernde Lampen heller/dunkler |
| Konsole: `db_look <vignette> <filmkorn> <sättigung>` | Bildlook |

---

## 9. Offene Punkte

- [ ] Titel final (Arbeitstitel *Jack's Last Show*)
- [x] Jam-Regeln prüfen: Nachbauten sind erlaubt
- [x] Zielwahl-UI bei 32 Spielern: kompakter Ring (ab 12 Plätzen kleiner)
- [ ] Eigenes Asset Pack (Jack, Map, Sounds) am Windows-PC bauen, siehe `ASSETS.md`
- [ ] Ingame prüfen: Lichtstärken, Dimensionen, Jack-Drehung, Sitzposition bei 16/32 Stühlen
- [ ] Lasttest mit vielen echten Spielern (Bots zählen nicht für Netzwerklast)
- [ ] Server vom `bleeding-edge`-Zweig auf die normale Version umstellen (am 13.10. wurde ein Spieler mit Client 1.157.1 wegen Versionskonflikt gekickt)
- [ ] Server mit `--steam_app "game"` starten (läuft zurzeit mit der Playtest-App-ID)
- [ ] `Config.toml`: Servername und Beschreibung setzen
- [ ] **Pterodactyl-Startvariablen:** Der Server startet mit `--max_players 10 --map default-testing-map`; Kommandozeile schlägt `Config.toml`. Im Panel (Startup) auf 999 Spieler und `default-empty-map` stellen (die Welt liegt sicherheitshalber auf Z = 20000, damit sie auch auf der Testing-Map frei schwebt)
- [ ] Jam-Seite: Eintrag anlegen, Server registrieren
- [ ] `DEBUG_COMMANDS = false` vor Abgabe
