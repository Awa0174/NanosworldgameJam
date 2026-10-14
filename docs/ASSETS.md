# Eigene Assets (Custom Asset Pack) – Anleitung

Ziel: Jack, die Map (Hub + Zirkuszelt), Sounds und Musik durch eigene Modelle ersetzen.
Der Code ist schon darauf vorbereitet. Alle Assets laufen über **`Shared/Assets.lua`**: Ist dort ein eigenes Asset eingetragen, ersetzt es den Platzhalter.

## Nicht auf dem Server, nur am Desktop-PC (Windows empfohlen)

Eigene Assets müssen in **Unreal Engine** mit dem **nanos world ADK** (Assets Development Kit) importiert und **gecookt** werden. Das geht nicht auf dem Server (kein Bildschirm, kein Unreal). Die nanos-Doku beschreibt den Weg für Windows. Unreal gibt es auch für Linux, und das ADK-Projekt ist für Windows und Linux eingestellt; getestet ist diese Anleitung aber nur gegen die Windows-Doku.

0. **Einmalig vorbereiten:**
   - Unreal Engine **5.7.x** über den Epic Games Launcher installieren (*Unreal Engine → Library → `+` → 5.7 → Install*) und einmal starten. Der Server läuft laut Log mit Unreal 5.7.4; im `Assets.toml` steht dann `unreal_version = "5.7.0"`.
   - **Windows SDK** installieren, sonst bricht das erste *Cook Content* ab: im Visual Studio Installer unter *Individual components* `Windows 11 SDK (10.0.26100.0)` anhaken, oder den Installer von Microsofts Windows-SDK-Seite nehmen (*Download the Installer*). So verlangt es die nanos-Doku „Setting Up Unreal Engine“.
   - ADK herunterladen: <https://github.com/nanos-world/assets-development-kit/>, dann `NanosWorldADK.uproject` öffnen.
- Doku: <https://docs.nanos-world.com/docs/assets-modding/creating-assets/setting-up-ue>, <https://docs.nanos-world.com/docs/assets-modding/creating-assets/adk-assets-development-kit> und <https://docs.nanos-world.com/docs/assets-modding/creating-assets/importing-assets>

## Ablauf

1. Im ADK einen eigenen Ordner anlegen, z. B. `Content/DeathBoxAssets/`. **Nichts im Ordner `NanosWorld/` ändern.**
2. Modelle/Sounds importieren (FBX, WAV …). Das Skelett **`SKEL_Mannequin`** brauchen nur Spielerfiguren (Klasse `Character`, die nur der Server spawnen darf). Jack wird beim Client gebaut und nutzt Static Meshes, `CharacterSimple` oder einen Blueprint (siehe „Schritt 3b“ weiter unten).
3. **Platforms → Cook Content → Cook Content**.
4. Ergebnis liegt unter `assets-development-kit/Saved/Cooked/Windows/NanosWorldADK/Content/DeathBoxAssets/`.
5. Auf dem Server den Ordner `Assets/deathbox-assets/` anlegen und den gecookten Ordner `DeathBoxAssets/` hineinkopieren. **Dateien darin nicht umbenennen.**
6. Daneben `Assets/deathbox-assets/Assets.toml` anlegen (das ADK hat einen *Assets.toml Generator*). Aufbau wie die offizielle Vorlage (`Assets.toml` im Repo nanos-world-server): Titel, Autor und Version stehen unter `[meta]`.

```toml
[meta]
    title = "Jack's Last Show Assets"
    author = "Gluonjustforyou"
    version = "0.1.0"

[asset_pack]
    assets_requirements = [ ]

[unreal]
    unreal_folders = [ "DeathBoxAssets" ]
    unreal_version = "5.7.0"
    is_plugin_content = false

[assets]
    [assets.static_meshes]
        SM_Jack_Box = "DeathBoxAssets/Jack/SM_Jack_Box"
    [assets.skeletal_meshes]
        SK_Jack = "DeathBoxAssets/Jack/SK_Jack"
    [assets.sounds]
        A_HubMusic = "DeathBoxAssets/Audio/A_HubMusic"
    [assets.maps]
        DeathBoxMap = "DeathBoxAssets/Maps/DeathBoxMap"
```

7. In `Packages/deathbox/Package.toml` steht unter `[game_mode]` schon `assets_requirements = [ ]`. Dort `"deathbox-assets"` eintragen, keine zweite Zeile anlegen: `assets_requirements = [ "deathbox-assets" ]`. Clients laden das Pack dann beim Verbinden automatisch herunter.
8. In `Shared/Assets.lua` unter `CUSTOM` die neuen Schlüssel eintragen, z. B. `music_hub = "deathbox-assets::A_HubMusic"`. Jacks Teile erscheinen erst nach der Code-Anpassung aus „Schritt 5“ weiter unten.

## Was wir brauchen (logische Namen aus `Shared/Assets.lua`)

| Name | Was | Hinweis |
|---|---|---|
| `clown_box` | Jacks Kiste | Static Mesh, Drehpunkt Mitte Unterseite (Maße in der Teile-Tabelle unter „Schritt 2“) |
| `clown_spring`, `clown_body`, `clown_head`, `clown_hat`, `clown_arm` | Jacks Teile | Static Meshes. Alternativ **ein** Skeletal Mesh mit Animationen (dann wird `Client/World/Jack.lua` angepasst, siehe „Schritt 3b“) |
| `chair` | Stuhl am Tisch | Sitzfläche zur Mitte drehen: `CHAIR_YAW_OFFSET` in `Config.lua` |
| `grave_*`, `pumpkin`, `ghost`, `torch`, `tree`, `rock` | Friedhof-Deko | |
| `snd_*` | Soundeffekte (Schuss, Klick, Lachen, Schrei …) | Jacks Lacher sind am wichtigsten |
| `music_hub`, `music_tent` | Hintergrund-Loop für Friedhof bzw. Zelt | Ersetzt den eingebauten OGG-Loop, sobald in `CUSTOM` eingetragen (`Client/Audio.lua`, `Audio.SetAmbience`). Muss ein Sound-Asset sein; der Code spielt es als Endlosschleife. Die Spieluhr beim Drehen bleibt eine OGG-Datei im Package |

## Custom Map

Eine eigene Map (Unreal-Level) kann den gebauten Hub und das Zelt ersetzen und echte Animationen enthalten (Sequencer, bewegte Lichter, Nebel).

- Die Map enthält **einen** Hub und **ein** Zirkuszelt. Durch die Dimensionen sieht jede Instanz dieselbe Map, Spieler anderer Tische sieht man nicht.
- In `Config.lua`: `WORLD.BUILD_GEOMETRY = false` (dann baut der Code keine Wände/Böden/Deko mehr) und `HUB_CENTER` / `SHOW_CENTER` auf die Positionen in der Map setzen. **Stand 14.10.:** Den Schalter `BUILD_GEOMETRY` gibt es nur als Kommentar in `Config.lua`; `Client/World/Hub.lua` und `Tent.lua` müssen ihn erst noch abfragen.
- Stühle, Jack und Spots spawnt weiterhin der Code, weil sie sich bewegen bzw. je nach Platzzahl anders stehen.
- In `Config.toml` des Servers: `map = "deathbox-assets::DeathBoxMap"`.

## Lizenz

Nur Assets verwenden, die wir selbst gemacht haben oder deren Lizenz die Nutzung erlaubt (z. B. CC0). Keine Modelle, Sounds oder Logos aus dem Roblox-Original.

## 3D-Modell für Jack (Vorschläge und Import)

Stand 14.10.2026, nach einer unabhängigen Prüfung überarbeitet. Durchsucht: Sketchfab (öffentliche API, rund 1.500 herunterladbare Modelle gesichtet), Fab, OpenGameArt, itch.io, Poly Haven, Poly Pizza, CGTrader, TurboSquid, Kenney.
Lizenzen über die Sketchfab-API geprüft (dieselben Daten, die die Download-Seite zeigt). Im zweiten Durchgang wurden **alle** Uploads jedes Accounts durchgesehen (vorher nur die beliebtesten), um Spiel-Rips und Fan-Modelle zu erkennen. Auffälligkeiten stehen beim jeweiligen Modell.
Kein Material von FNAF, Poppy Playtime oder anderen fremden Marken, auch keine „Fan-Modelle“. Gesucht wurde stattdessen der gleiche Stil: alter Porzellan-/Puppen-Look, mechanische Teile, Kurbelkiste.

### Das Wichtigste vorweg

- **Ein Animatronic besteht aus starren Teilen mit Gelenken.** Genau so ist Jack 2.0 gebaut (`Client/World/Jack.lua`): Kiste, Klappdeckel, Kurbel, Feder, Rumpf, Kopf, Gelenkarme. Lua bewegt die Teile ruckartig wie Servos, dreht den Kopf zur Kamera jedes Spielers und lässt Jack genau vor dem Opfer aus der Kiste schnellen. Dafür braucht es **kein Skelett**, sondern **einzelne Static Meshes mit dem Drehpunkt am Gelenk**. Ein echter 3D-Kopf ersetzt nebenbei das flache Masken-Gesicht.
- **Plan A – beste Wirkung (Empfehlung):** Kopf = *Creepy Doll Head* (Fotoscan eines echten alten Puppenkopfs; vorher deutlich umformen und neu texturieren, siehe Hinweis in der Rangliste), Kiste = *Old Storage Wooden Box* (fotorealistische alte Holzkiste; zum Würfel umbauen, Inhaltszettel im Deckel übermalen). Ersatz-Kopf, falls der Scan nicht in Frage kommt: Kopf von Nr. 4 (*Jack-in-a-box*, burntclowns) oder *Horror Doll* (LukasBobor, siehe unten). Rumpf, Arme und Feder bleiben vorerst aus dem Code. Aufwand ca. 4–6 Std. (Blender + ADK).
- **Plan B – am schnellsten:** *Jack in a box* von DINOWAAA: fertiger böser Narr in rostiger Kurbelkiste, mit Rig, Idle-Animation und leuchtenden Augen. Schlichter Look. Aufwand ca. 1–2 Std.
- **Plan C – echte Skelett-Animationen:** *Scary Clown* (T-Pose) über Mixamo riggen (Lachen, Zeigen, Spotten …). Die Kiste bleibt ein Static Mesh. Aufwand ca. 3–4 Std.

### Rangliste

| # | Modell (Autor) | Lizenz | Download-Format | Dreiecke | Rig / Animation | Texturen | Bewertung, Rolle |
|---|---|---|---|---|---|---|---|
| 1 | [Creepy Doll Head](https://sketchfab.com/3d-models/creepy-doll-head-05466f98b03e4a6bb35ee0d89d02ed18) (MacDesigns) | CC BY 4.0 (Credit Pflicht) | OBJ (Original) oder glTF/GLB | 510.272 (Scan), auf ca. 30.000 reduzieren | nein / nein | 1 Farbtextur 8100 × 8100 (JPG, kein PBR) | Fotoscan eines alten, im Wald gefundenen Puppenkopfs: leere Augen, Risse, Schmutz. Mit Abstand das Gruseligste im Test. Als Jacks Kopf; rote Nase und Hut kommen aus dem Code. 365 Likes, 5.550 Downloads. **Achtung:** Scan eines Serien-Puppenkopfs. CC BY deckt nur den Scan, nicht das Design des Herstellers. Der Uploader stellt auch den Scan einer Star-Wars-Figur (Rancor) unter CC BY, prüft fremde Rechte also nicht. Risiko gering (alt, generisch, Hersteller unbekannt); zur Sicherheit in Blender deutlich umformen und neu texturieren. Ersatz: Kopf von Nr. 4 oder *Horror Doll* (unten). |
| 2 | [Old Storage Wooden Box](https://sketchfab.com/3d-models/old-storage-wooden-box-6a6683d8533a412c822dd59627349985) (carlcapu9) | CC BY 4.0 | glTF/GLB (Original ist Alembic `.abc`) | 14.523 | nein / 1 (Alembic, vermutlich Deckel) | 1 Fototextur 4288 × 3518 (PNG, kein PBR) | Eigentlich ein **alter DDR-Verbandkasten** aus Holz (Fingerzinken, Eisenhaken, Scharniere), länglich statt würfelförmig. Auf der Deckel-Innenseite klebt ein fotografierter deutscher Inhaltszettel („Verbandkasten I“, „VEB Imbal-Werk Karl-Marx-Stadt“ mit Herstellerlogo). Jacks Deckel klappt bei jedem POP zum Opfer hin auf, der Zettel wäre also groß im Bild: vor dem Import übermalen (siehe Schritt 2). Danach `clown_box` + `clown_lid`, in Blender zum Würfel umbauen. Laut Sketchfab-Daten auch auf Fab. 620 Likes, 4.696 Downloads. Account: überwiegend eigene Umgebungs-Assets. |
| 3 | [Jack in a box](https://sketchfab.com/3d-models/jack-in-a-box-79af17dfa9f24fcc9e80b0cf8c5cec3d) (DINOWAAA, Danny Taylor) | CC BY 4.0 | FBX (Original `jack_in_a_box_anim.fbx`) | 6.714 | ja / 1 (Idle) | PBR 2048: BaseMap, Normal, Emissive, MaskMap | Kompletter Jack: roter Narr mit schwarzer Maske und glühenden Augen, rostige Holzkiste mit Kurbel. Spielfertig, aber wenig Details. Eigenes Werk (Kursarbeit); der Account enthält nur eigene Übungs- und Kursarbeiten. Plan B. |
| 4 | [Jack-in-a-box](https://sketchfab.com/3d-models/jack-in-a-box-e4963a7d83604a0ebc71af61460ef327) (burntclowns) | CC BY 4.0 | FBX (Original `2_Clown.fbx`, 33 MB) | 481.321 (ZBrush) | nein / nein | Farbe größtenteils als Vertex-Farben (Polypaint) + 1 Textur 2048 | Unheimlicher, realistisch modellierter Clown (Sternenhut, Halskrause, Ziehharmonika-Arme und -Beine) aus bunter Kiste. Am meisten „Jack“, aber viel Arbeit: reduzieren, Farbe auf Textur backen, Arme/Beine abtrennen (hängen aus der Kiste). Der Account enthält nur eigene Figuren (Kurs- und Portfolio-Arbeiten). Der Kopf allein ist der beste Ersatz für Nr. 1. |
| 5 | [Scary Clown](https://sketchfab.com/3d-models/scary-clown-6331a15229ee458fb45e7cc24a6d2aff) (RedDevon) | Sketchfab „Free Standard“ (kommerziell und mit Änderungen erlaubt, Credit nicht verlangt) | FBX (Original `Low_01.fbx`) | 10.712 (saubere Quads) | nein / nein, über Mixamo | PBR 2048: BaseColor, Normal, Roughness, Metallic, AO | Ganzer Horror-Clown in T-Pose, ideal für Mixamo (Plan C). Kein Animatronic-Look; der Unterkörper verschwindet in der Kiste. Account: ein Fan-Modell (Waffe aus *Bulletstorm*), das aber nicht zum Download freigegeben ist; der Clown wirkt eigenständig. |

Alle fünf brauchen ein kostenloses Sketchfab-Konto zum Herunterladen.

**Weitere brauchbare Funde**

- [Horror Doll](https://sketchfab.com/3d-models/horror-doll-5c9c1294796144249021535eea25aef2) (LukasBobor), CC BY 4.0, 4.214 Dreiecke, OBJ (Archiv 49 MB), PBR 4096 (Albedo, Normal, Roughness, Metallic, AO, Height): sitzende Flickenpuppe mit rissigem Babygesicht, 2016, 265 Likes, 5.268 Downloads. **Ersatz-Kopf** für Plan A: Kopf abtrennen, Texturen auf 2048 verkleinern. Der Account enthält nur eigene Spiel-Assets.
- [Porcelain Polly](https://sketchfab.com/3d-models/porcelain-polly-9ef34eb03f0a42978b3a9d20f0f8f389) (archmage40), CC BY 4.0, 20.000 Dreiecke, FBX, PBR 2048, Rig + 1 Animation: verfluchte Porzellanpuppe mit Haube aus einem Uni-Spielprojekt. Zweiter Ersatz-Kopf im Porzellan-Look (Haube weglassen). Account ohne Auffälligkeiten.
- [Grim Leaper](https://sketchfab.com/3d-models/grim-leaper-f873ffd71eba462aae3bed3a42343ccb) (duz_vr), CC BY 4.0, 68.942 Dreiecke, FBX, PBR 2048: Sensenmann auf Feder in Kiste, sehr hochwertig (#Sculptober 2022). Kein Clown, aber stark als Statue im Hub. Der Account enthält auch CC-BY-Fan-Modelle fremder Marken (z. B. „Darkhold Iron Man“); dieses Modell wirkt eigenständig.
- [Horror Toy Chest](https://sketchfab.com/3d-models/horror-toy-chest-af6bc05358fe45aa9719c26afe76ec85) (Christopher.260), CC BY 4.0, 4.500 Dreiecke, PBR 2048 + Emissive (Normalmap im OpenGL-Format): blutige Spielzeugtruhe mit roten Augen im Spalt. Alternative Kiste oder Deko. Der Account enthält CC-BY-Fan-Modelle fremder Marken (FF7-Buster-Sword, Pokéball, Nintendo DS mit Pokémon, Wallace & Gromit); die Truhe selbst wirkt eigenständig.
- [Jack-in-the-box](https://sketchfab.com/3d-models/jack-in-the-box-b2d3122a402b4fb185880a35c3ec7b9b) (ReoCreativeScanning), CC BY 4.0, 16.906 Dreiecke, OBJ, 4096 Diffuse/Roughness/Normal: Scan einer alten Blechkiste mit Kurbel (nur die Kiste). Der Aufdruck stammt vom Spielzeughersteller, also übermalen und nur die Form nutzen. Der Account scannt auch Markenprodukte (Hulk-Figur, LEGO-Koffer).
- Requisiten, beide CC BY 4.0: [Creepy Circus Tent](https://sketchfab.com/3d-models/creepy-circus-tent-54687a3046db4aa28978443d1740cd88) (Clownkopf-Bude für den Hub; für ein Studenten-Gruppenspiel gebaut, der Account enthält Fan-Modelle wie LEGO Star Wars AT-RT und eine Mega-Man-Maske), [Hurdy-Gurdy](https://sketchfab.com/3d-models/hurdy-gurdy-9f43682466aa42c4af15004f946cea9f) (Drehleier, historisches Instrument; der Account enthält Fan-Art zu Fallout und Warhammer, meist nicht zum Download).
- **Ohne Login, CC0 ([Poly Haven](https://polyhaven.com/models)):** [WoodenChair_01](https://polyhaven.com/a/WoodenChair_01) (gotischer Lehnstuhl, 19.992 Dreiecke, 2,27 m hoch, für `chair`), [Lantern_01](https://polyhaven.com/a/Lantern_01) (Petroleumlampe, für `oil_lamp`), [lantern_chandelier_01](https://polyhaven.com/a/lantern_chandelier_01) (Hängelaterne, Drehpunkt am Haken, fürs Zeltlicht).

**Ausgeschlossen, und warum**

- *Jack In The Box* von Vasian-Digital3D (grinsender Narr mit Bombe, sieht perfekt aus): Der Account lädt Spiel-Rips hoch (Lost Ark, Stellar Blade, Resident Evil …), alle fälschlich als CC BY. Die Lizenz ist damit wertlos.
- *jack in the box* von MOLLUSKK (7 Animationen): Der Account ist voller Garten-of-Banban-Rips und Memes, die Herkunft ist unklar.
- Fremde Marken und Figuren, auch als Fan-Art: FNAF (Mimic, Jackie, Vanny …), Poppy Playtime (Boxy Boo), Lethal Company (Jester), Dark Deception (Clown-Gremlins), Pennywise, Terrifier, The Amazing Digital Circus, Fall Guys, Pokémon, das Maskottchen der Fast-Food-Kette „Jack in the Box“.
- *Da-Clown #StylizedBustChallenge* von Nwilly_art (grotesker Clown als Büste): Der Account lizenziert Fan-Art fremder Marken als CC BY (Real Kirby, Wart aus Mario 2, Bowser n' Peach, Soul Crusher aus Spawn, Polka-Dot Man aus DC, Alien Hominid …). Die Herkunft des Designs ist nicht prüfbar.
- *Army Robot Clown* von kpoyteam (Mech mit Clown-Totenkopf, 73.156 Dreiecke, PBR 4096): Herkunft nicht prüfbar. AAA-Look von einem Account mit genau einem Upload; die Beschreibung („No animation“) widerspricht den 2 Animationen der Datei.
- *Music Box – Mid Poly* von Weirdo.ar: laut Beschreibung dem Modell „Timeless“ von Rocío García (ArtStation) nachempfunden, also ein abgeleitetes Design.
- Beim zweiten Durchgang verworfen: *Creepy Doll [Seamstress]* von mar.cos. (mechanische Spinnenpuppe, laut Beschreibung der „Seamstress“ aus dem Animationsfilm *9* nachempfunden), *Porcelain Mask* von sleepwalker77 (rissige Porzellanmaske; der Account stellt Filmkreaturen wie *Creature from the Black Lagoon* und *Critters* unter CC BY), *Clown Head – Halloween* von Swanm (der Account lädt KI-Modelle aus Meshy hoch).
- Scans aktueller Produkte: *Clown* von mofodinosao („Clown animatronic I bought“) und *Evil Clown 3D model* von guillermosainz (Scan einer Maske/Figur). Die Designrechte liegen beim Hersteller. Der Puppenkopf aus Nr. 1 ist ebenfalls ein Scan, aber alt und ohne bekannten Hersteller (siehe Hinweis dort).
- KI-Uploads (z. B. *Creepy clown head* von FBN911, als „createdwithai“ markiert) und *Lil HARLEQUINN* (itch.io, DRAGGONE STUDIO): kostenlos und gerigged, aber ohne Lizenzdatei (nur ein Kommentar des Autors) und mit deutlichen KI-Spuren (Mesh „temp“, exakt 10.000 Dreiecke, eine Farbtextur, automatisches Rig), obwohl die Seite „no AI“ angibt.
- CC BY-NC (nur nicht kommerziell): für ein öffentlich verteiltes Jam-Spiel riskant (mögliche Preise, spätere Nutzung). CC BY-ND (keine Änderungen erlaubt): Umbauten wie Teile trennen sind verboten. „Editorial“: nur für Berichterstattung.
- Ohne Treffer: OpenGameArt (nur 2D und Musik), Poly Pizza (blockt automatische Abfragen; nur Low-Poly-Cartoon), CGTrader und TurboSquid (kein passendes Gratis-Modell gefunden, bei CGTrader nur ein kostenpflichtiges 3D-Druck-Modell), Kenney (kein Clown; das *Graveyard Kit* (CC0) wäre Friedhofs-Deko im Cartoon-Stil).
- Fab blockt automatische Abfragen (Cloudflare). Dort bitte selbst suchen: „jack in the box“, „creepy clown“, „toy box“, Filter *Free*, Lizenz *Standard* oder *CC BY*. Zwei Fab-Treffer mit unbekanntem Preis: [Creepy clown (3 outfits + 3 assets)](https://www.fab.com/listings/e93b282b-7544-43da-a9ca-99ed77d88671), [Creepy Clown Decor – Low Poly Halloween Horror Prop](https://www.fab.com/listings/173b0df6-26b5-4231-ad7a-e4379029fd5f).

### Lizenzen und Credits

- **CC0:** frei, kein Credit nötig.
- **CC BY 4.0:** frei, auch kommerziell und mit Änderungen. **Credit ist Pflicht:** Titel, Autor, Link zur Quelle, Link zur Lizenz und ein Hinweis, was geändert wurde. Credits auf die Jam-Seite, in die README und ins Spiel (z. B. Tafel im Hub).
- **CC BY-SA:** wie CC BY; geänderte Modelle müssen wieder unter CC BY-SA stehen.
- **Sketchfab Standard / Free Standard:** weltweite, auch kommerzielle Nutzung, auch in abgeleiteten Werken; kein Credit verlangt. Modelle nur eingebaut (gecookt) verwenden, nicht als Rohdatei weitergeben.
- Beim Download die Lizenz im Download-Fenster noch einmal prüfen und einen Screenshot zu den Quelldateien legen. Laut Sketchfab gilt die Lizenz vom Download-Zeitpunkt, auch wenn der Autor sie später ändert.

Credit-Zeilen zum Kopieren (Englisch, nur die tatsächlich benutzten; die Klammer nach „modified“ an die wirklichen Änderungen anpassen):

```text
"Creepy Doll Head" by MacDesigns - https://sketchfab.com/3d-models/creepy-doll-head-05466f98b03e4a6bb35ee0d89d02ed18 - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (decimated, reshaped, re-textured)
"Old Storage Wooden Box" by carlcapu9 - https://sketchfab.com/3d-models/old-storage-wooden-box-6a6683d8533a412c822dd59627349985 - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (reshaped, lid separated, label removed)
"Jack in a box" by Danny Taylor (DINOWAAA) - https://sketchfab.com/3d-models/jack-in-a-box-79af17dfa9f24fcc9e80b0cf8c5cec3d - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (parts separated, rescaled)
"Jack-in-a-box" by burntclowns - https://sketchfab.com/3d-models/jack-in-a-box-e4963a7d83604a0ebc71af61460ef327 - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (decimated, colors baked, parts separated)
"Horror Doll" by LukasBobor - https://sketchfab.com/3d-models/horror-doll-5c9c1294796144249021535eea25aef2 - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (head extracted, textures resized)
"Porcelain Polly" by archmage40 - https://sketchfab.com/3d-models/porcelain-polly-9ef34eb03f0a42978b3a9d20f0f8f389 - CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - modified (head extracted)
"Scary Clown" by RedDevon - https://sketchfab.com/3d-models/scary-clown-6331a15229ee458fb45e7cc24a6d2aff - Sketchfab Free Standard license
Chair and lanterns: Poly Haven (CC0)
Jack's voice: synthesized with Piper TTS (https://github.com/rhasspy/piper, MIT license), voice model "en-us-libritts-high" trained on LibriTTS by Zen et al. (http://www.openslr.org/60/, CC BY 4.0, https://creativecommons.org/licenses/by/4.0/) - modified (pitch, tempo, effects)
```

### Jacks Stimme (v0.13, im Package)

- Erzeugt mit **Piper TTS** (MIT-Lizenz) und dem Stimmmodell `en-us-libritts-high`. Das Modell ist auf dem Datensatz
  **LibriTTS** trainiert (CC BY 4.0) → **Credit-Zeile oben ist Pflicht** (Jam-Seite und README).
- Dateien: `Client/sounds/voice/*.ogg` (94 Sätze, ca. 2 MB) und die Liste `Shared/Voice.lua` (erzeugt, nicht von Hand ändern).
- Andere Modelle derselben Quelle haben strengere Lizenzen (z. B. „ryan“: CC BY-NC-SA, „lessac“: eigene Blizzard-Lizenz).
  Für den Jam nur LibriTTS verwenden.

### Schritt 1: Herunterladen

- **Sketchfab:** kostenloses Konto, auf der Modellseite *Download 3D Model*. Möglichst **Original format** wählen (FBX/OBJ/blend mit Rig, Animation und Originaltexturen). Ausnahme *Old Storage Wooden Box*: Das Original ist Alembic, dort **glTF** oder **GLB** nehmen.
- **Fab:** Epic-Konto. Im ADK das Fab-Fenster öffnen (*Window → Fab* bzw. die Fab-Schaltfläche im Content Browser), anmelden, Listing öffnen, *Add to Project*. Danach nur die benötigten Dateien per *Advanced Copy* in unseren Ordner kopieren (so beschreibt es die nanos-Doku für Character Meshes).
- **Poly Haven:** ohne Login, Format **FBX**, Auflösung **2K**. Zusätzlich die Normalmap im **DX**-Format (`nor_dx`) laden, denn Unreal erwartet DirectX-Normalmaps.

### Schritt 2: In Blender vorbereiten (kostenlos, empfohlen)

Ziel: Jedes bewegliche Teil wird ein eigenes Mesh, sein Drehpunkt liegt am Gelenk.

1. **Importieren:** *File → Import → glTF 2.0 / FBX / Wavefront (OBJ)*.
2. **Scans reduzieren:** Modifier *Decimate* (Collapse), bis der Kopf ca. 20.000–40.000 und die Kiste ca. 5.000–15.000 Dreiecke hat, dann *Apply*. Bei Modellen mit Polypaint (siehe 3.) vorher eine Kopie behalten und nur die Kopie reduzieren.
3. **Vertex-Farben auf Textur backen** (nur bei Polypaint, z. B. burntclowns): Die reduzierte Kopie bekommt UVs (*UV → Smart UV Project*) und im Material einen leeren *Image Texture*-Knoten 2048 × 2048 (ausgewählt lassen). Im Material des Originals den Knoten *Color Attribute* an *Base Color* hängen. Render-Engine *Cycles*, *Bake → Diffuse*, nur *Color*, *Selected to Active* an (erst Original, dann Kopie auswählen). Das Bild speichern.
4. **Fremde Aufdrucke entfernen** (in der Textur, vor dem Import): bei der *Old Storage Wooden Box* den Inhaltszettel mit Herstellerlogo auf der Deckel-Innenseite, bei Blechkisten-Scans den Aufdruck. Im Bildprogramm (z. B. GIMP, Werkzeug *Klonen* oder *Heilen*) mit Holzmaserung aus der Umgebung übermalen, oder in Blender der Deckel-Innenseite ein eigenes Material mit eigener Holztextur geben. Danach prüfen, dass kein Text und kein Logo mehr zu sehen ist.
5. **Teile trennen:** im Edit Mode das Teil wählen (L), dann **P → Selection**. Deckel, Kurbel, Kopf, ggf. Unterkiefer und Arme werden eigene Objekte.
6. **Drehpunkt setzen:** Gelenk-Kante oder -Punkt wählen, *Shift+S → Cursor to Selected*, dann im Object Mode *Object → Set Origin → Origin to 3D Cursor*. Anschließend das Objekt mit **Alt+G** auf den Weltnullpunkt setzen. Jedes Teil liegt so beim Export mit seinem Gelenk auf 0,0,0 (das funktioniert unabhängig von den Unreal-Importoptionen).
7. **Größe:** in echter Größe bauen (Blender-Standard Meter, Unit Scale 1.0). Unreal rechnet beim FBX-Import Meter in Zentimeter um.
8. **Transformationen anwenden:** *Ctrl+A → All Transforms*.
9. **Exportieren**, jedes Teil einzeln: *File → Export → FBX*, *Limit to: Selected Objects*, Object Types *Mesh* (bei Rigs zusätzlich *Armature*), *Geometry → Smoothing: Face*, *Apply Modifiers* an. Bei Rigs *Add Leaf Bones* aus und *Bake Animation* an.

**Teile, Namen und Drehpunkte (passend zu Jack 2.0, Maße in cm bei Skalierung 1)**

| Teil | Asset-Name | Schlüssel in `Shared/Assets.lua` | Drehpunkt | Ausrichtung | Richtmaß |
|---|---|---|---|---|---|
| Kiste ohne Deckel | `SM_Jack_Box` | `clown_box` | Mitte Unterseite; im Code 10 cm über `box_root` anhängen (Oberseite Drehteller) | Front +X, Kurbelseite +Y | 184 × 184 × 155 (Oberkante 165 cm über dem Drehteller-Boden) |
| Deckel | `SM_Jack_Lid` | `clown_lid` (neu) | Mitte der Scharnierkante, hinten (−X), 164 cm über dem Drehteller-Boden | geschlossen flach, ragt nach +X | 178 × 178 × 10 (+ Messingrand 182 × 182 × 3) |
| Kurbel | `SM_Jack_Crank` | `clown_crank` (neu) | Achsmitte | Achse entlang Y | Griff ca. 45 lang |
| Federring | `SM_Jack_SpringRing` | `clown_spring` | Ringmitte | flach wie `SM_Torus` | Ø 46, 8 hoch (der Code verteilt 12 Stück) |
| Rumpf mit Halskrause | `SM_Jack_Body` | `clown_body` | Rumpfmitte | Brust nach +X | 128 × 128 × 112 (Rumpf 100 breit, Halskrause 128) |
| Kopf | `SM_Jack_Head` | `clown_head` | Halsgelenk (Unterkante Kopf) | Gesicht nach +X | 86 × 86 × 94 |
| Unterkiefer (optional) | `SM_Jack_Jaw` | `clown_jaw` (neu) | Kiefergelenk | Kinn nach +X | – |
| Oberarm | `SM_Jack_ArmUpper` | `clown_arm` | Schultergelenk | hängt nach −Z | 70 lang |
| Unterarm mit Klaue | `SM_Jack_ArmLower` | `clown_forearm` (neu) | Ellbogen | hängt nach −Z | ca. 100 lang (bis Klauenspitze) |
| Hut, Nase | `SM_Jack_Hat`, `SM_Jack_Nose` | `clown_hat`, `clown_nose` | Hut: Mitte Unterseite | – | – |

- Gelenkabstände im Code (relativ zur Rumpfmitte): Schultern bei Y ±62 und Z +36, Ellbogen 70 cm unter der Schulter, Halsgelenk bei Z +84. Passen die Proportionen eines Modells nicht, das Modell anpassen oder die Zahlen in `Jack.Build` ändern.
- **Passt Jack in die Kiste?** Alle Höhen gelten ab dem Drehteller-Boden (`box_root`). Jack 4 (v0.10) fährt nur im Intro und beim Vorhang ganz ein; beim Drehen lugt er mit Kopf und Schultern über den Rand (`PEEK_U`), der Deckel bleibt offen (höchstens 110 Grad, `LID_STOP`). Eingefahren steht die Rumpfmitte 52 cm *unter* dem Drehteller-Boden (`RETRACT_U`), der Teleskop-Hals ist ganz drin (`NECK_TUCK`), die Hutspitze liegt bei ca. 150 cm, die Unterkante des geschlossenen Deckels bei 161 cm. Der Deckel schneidet nie durch die Figur, weil er über den Punkten aus `FIGURE_TOP` bleibt (`head = true`: Punkt fährt mit dem Hals mit; neu berechnen mit `work_jack/figure_top4.lua`). Für ein eigenes Modell gilt deshalb:
  - Kopf und Hut dürfen eingefahren höchstens ca. 205 cm über der Rumpfmitte enden (161 + 52, abzüglich Reserve fürs Wippen). Sonst `RETRACT_U` weiter absenken.
  - Was eingefahren in der Kiste steckt (Kopf, Hut), muss in den Innenraum von 150 × 150 cm passen.
  - `FIGURE_TOP` in `Jack.lua` auf die höchsten Punkte des neuen Modells setzen (x = nach vorne, z = nach oben, jeweils ab Rumpfmitte, etwa 10 cm Reserve). Sonst bleibt der Deckel zu lange offen oder streift die Figur.

### Schritt 3: Import ins ADK (Unreal 5.7)

1. `NanosWorldADK.uproject` mit Unreal 5.7 öffnen und den Ordner `Content/DeathBoxAssets/Jack/` anlegen (nie etwas in `NanosWorld/` ablegen).
2. **Texturen zuerst** hineinziehen und einstellen:
   - Farbtexturen: sRGB an (Standard).
   - Normalmaps: Compression *Normalmap*. Bei OpenGL-Normalmaps (Dateiname mit `_gl` oder `OpenGL`, viele Sketchfab-/glTF-Dateien) **Flip Green Channel** anhaken. Test: Wirken Beulen bei Licht von oben eingedrückt, ist der Kanal falsch.
   - Roughness, Metallic, AO und MaskMap: **sRGB aus**, Compression *Masks*.
   - Kantenlängen sollten Zweierpotenzen sein (512 … 4096), sonst fehlen Mipmaps und Texture Streaming. 8100 × 8100 und 4288 × 3518 vorher auf 4096 × 4096 skalieren. Wegen der Downloadgröße **Maximum Texture Size 2048** setzen (nanos empfiehlt höchstens 2048), nur der Kopf darf 4096 bekommen.
3. **FBX oder GLB** in den Ordner ziehen. Im Import-Dialog (die Namen der Optionen unterscheiden sich je nach Importer leicht):
   - Typ *Static Mesh* für Teile, *Skeletal Mesh* für geriggte Modelle (bei Bedarf erzwingen).
   - **Combine Meshes aus** (bzw. *Combine Static Meshes*), wenn eine Datei mehrere Teile enthält, sonst entsteht ein einziges Mesh.
   - Größe über *Import Uniform Scale* bzw. *Offset Uniform Scale* korrigieren, falls nötig (z. B. 100, wenn ein Modell in Metern ohne Einheitenangabe kommt).
   - Drehung über *Import Rotation* bzw. *Offset Rotation* (Yaw 90, −90 oder 180), falls die Front nicht nach +X zeigt.
   - Normalen importieren, keine Kollision automatisch erzeugen, neue Materialien im eigenen Ordner anlegen lassen.
4. **Prüfen** im Static-Mesh-Editor: *Approx Size* (cm) stimmt mit der Tabelle oben überein, der Drehpunkt liegt am Gelenk, die Front zeigt zur roten **+X**-Achse. Einen falschen Drehpunkt kann man notfalls in Unreal ändern: *Modeling Mode → Edit Pivot → Accept*. Fehlt der Modeling Mode (das ADK-Projekt schaltet von sich aus nur das Plugin *Water* ein): *Edit → Plugins →* „Modeling Tools Editor Mode“ aktivieren und den Editor neu starten.
5. **Materialien:** ein eigenes Master-Material `M_Jack` mit Textur-Parametern (BaseColor, Normal, ORM) und einem Skalar für Leuchten anlegen, pro Teil eine Instanz `MI_Jack_*`.
   - DINOWAAA-*MaskMap* (Unity-HDRP-Packung): R = Metallic, G = Ambient Occlusion, A = Glätte. Also **Roughness = 1 − A** (*OneMinus*-Knoten).
   - Leuchtende Augen: `EmissiveTextur × Skalar-Parameter "EyeGlow"`. Lua kann den Wert dann mit `mesh:SetMaterialScalarParameter("EyeGlow", wert)` steuern.
   - Für die Kiste ein Physical Material aus `NanosWorld/MaterialLibrary/PhysicalMaterials/` wählen (z. B. Holz).
   - **Referenzen prüfen** (Rechtsklick → *Reference Viewer* oder *Size Map*): Alles muss in `DeathBoxAssets/` liegen oder in den erlaubten Engine-Ordnern (`/Engine/Functions`, `/Engine/BasicShapes`, `/Engine/ArtTools`, `/Engine/EngineMaterials`). GLB-Importe erzeugen oft Material-Instanzen, deren Eltern-Material in einem Engine- oder Plugin-Ordner liegt. Diese durch `M_Jack` ersetzen, sonst ist das Modell im Spiel grau.
6. **Kollision** nur für die Kiste: *Collision → Add Box Simplified Collision*. Bewegliche Teile bekommen keine Kollision.
7. **LODs:** bei Scans *LOD Settings → Number of LODs = 3*. Nanite nicht voraussetzen.

### Schritt 3b: Geriggte Modelle und Skelett-Animationen (Plan B/C)

- Import als **Skeletal Mesh** mit *Import Animations*. Ergebnis: `SK_Jack`, Skeleton, Physics Asset und `A_Jack_*`-Animationen.
- Jack ist kein Mensch, also **kein** `SKEL_Mannequin` zuweisen. Die nanos-Klasse `Character` braucht `SKEL_Mannequin` und darf nur vom Server gespawnt werden; Jack wird aber lokal beim Client gebaut. Deshalb einen der zwei folgenden Wege nehmen:
  - **`CharacterSimple`** (auch der Client darf spawnen, jedes Skelett geht): eigenes Animation Blueprint `ABP_Jack` für das Skelett anlegen. Im AnimGraph muss mindestens ein Slot-Knoten **„DefaultSlot“** vor *Output Pose* hängen, sonst laufen keine Montagen.
  - **Blueprint-Actor** `BP_Jack` (SkeletalMeshComponent + `ABP_Jack`, Custom Events wie „Pop“ und „Laugh“): `Blueprint(pos, rot, "deathbox-assets::BP_Jack")`, `bp:CallBlueprintEvent("Pop")`, `bp:SetBlueprintPropertyValue("HeadYaw", 35)`.

```lua
-- Beispiel (Client): CharacterSimple statt Grundformen
local sk = CharacterSimple(pos, Rotator(0, yaw, 0), "deathbox-assets::SK_Jack", "deathbox-assets::ABP_Jack", CollisionType.NoCollision, false)
sk:AttachTo(jack.box_root, AttachmentRule.SnapToTarget)
sk:PlayAnimation("deathbox-assets::A_Jack_Pop", "DefaultSlot", false, 0.05, 0.2)
sk:SetAnimationBlueprintPropertyValue("HeadYaw", 35)   -- Variable im ABP, z. B. für "Transform (Modify) Bone" am Kopf
revolver:AttachTo(sk, AttachmentRule.SnapToTarget, "hand_r")   -- Requisiten an einen Knochen hängen (Knochenname je nach Rig)
```

- Herausschießen zum Opfer, Kopf-Tracking und Servo-Zucken bleiben Lua-Sache (Actor bewegen, ABP-Variablen setzen). Fertige Animationen liefern nur Gesten wie Lachen, Zeigen oder Zucken.
- In `Assets.toml` gehören Skelett-Meshes unter `[assets.skeletal_meshes]`, Animationen unter `[assets.animations]`, Animation Blueprints und Blueprints unter `[assets.blueprints]` (so steht es auch im Standard-Pack, z. B. `ABP_StackOBot`).

### Schritt 4: Cooken und auf den Server

1. **Platforms → Cook Content → Cook Content** (genau so in der nanos-Doku; das erste Mal dauert lange).
2. `Saved/Cooked/Windows/NanosWorldADK/Content/DeathBoxAssets/` nach `Assets/deathbox-assets/DeathBoxAssets/` auf den Server kopieren. Nichts umbenennen.
3. `Assets/deathbox-assets/Assets.toml` (die Liste erledigt der *Assets.toml Generator* im ADK, `NanosWorld/Blueprints/Utility/WBP_AssetsTomlGenerator`):

```toml
[meta]
    title = "Jack's Last Show Assets"
    author = "Gluonjustforyou"
    version = "0.2.0"

[asset_pack]
    assets_requirements = [ ]

[unreal]
    unreal_folders = [ "DeathBoxAssets" ]
    unreal_version = "5.7.0"
    is_plugin_content = false

[assets]
    [assets.static_meshes]
        SM_Jack_Box = "DeathBoxAssets/Jack/SM_Jack_Box"
        SM_Jack_Lid = "DeathBoxAssets/Jack/SM_Jack_Lid"
        SM_Jack_Crank = "DeathBoxAssets/Jack/SM_Jack_Crank"
        SM_Jack_SpringRing = "DeathBoxAssets/Jack/SM_Jack_SpringRing"
        SM_Jack_Body = "DeathBoxAssets/Jack/SM_Jack_Body"
        SM_Jack_Head = "DeathBoxAssets/Jack/SM_Jack_Head"
        SM_Jack_ArmUpper = "DeathBoxAssets/Jack/SM_Jack_ArmUpper"
        SM_Jack_ArmLower = "DeathBoxAssets/Jack/SM_Jack_ArmLower"
        SM_GothicChair = "DeathBoxAssets/Props/SM_GothicChair"
        SM_Lantern = "DeathBoxAssets/Props/SM_Lantern"
    # nur für Plan B/C:
    [assets.skeletal_meshes]
        SK_Jack = "DeathBoxAssets/Jack/SK_Jack"
    [assets.animations]
        A_Jack_Idle = "DeathBoxAssets/Jack/A_Jack_Idle"
        A_Jack_Pop = "DeathBoxAssets/Jack/A_Jack_Pop"
        A_Jack_Laugh = "DeathBoxAssets/Jack/A_Jack_Laugh"
    [assets.blueprints]
        ABP_Jack = "DeathBoxAssets/Jack/ABP_Jack"
```

4. In `Package.toml` unter `[game_mode]` den vorhandenen Eintrag ergänzen: `assets_requirements = [ "deathbox-assets" ]`.
5. Testen: `/bots 15`, `/start`. In der Konsole auf `[DeathBox] Unbekanntes Asset` achten. Graue Modelle bedeuten falsches `unreal_folders` oder Material-Verweise außerhalb von `DeathBoxAssets/`.

### Schritt 5: Jack im Code ersetzen

`Shared/Assets.lua`, Tabelle `CUSTOM`:

```lua
local CUSTOM = {
	clown_box = "deathbox-assets::SM_Jack_Box",
	clown_lid = "deathbox-assets::SM_Jack_Lid",
	clown_crank = "deathbox-assets::SM_Jack_Crank",
	clown_spring = "deathbox-assets::SM_Jack_SpringRing",
	clown_body = "deathbox-assets::SM_Jack_Body",
	clown_head = "deathbox-assets::SM_Jack_Head",
	clown_arm = "deathbox-assets::SM_Jack_ArmUpper",
	clown_forearm = "deathbox-assets::SM_Jack_ArmLower",
	chair = "deathbox-assets::SM_GothicChair",
	oil_lamp = "deathbox-assets::SM_Lantern",
}
```

Damit allein ändert sich Jack noch nicht: `Jack.lua` baut die Figur bisher aus Grundformen und nutzt nur `clown_hat` als Schlüssel. Nötige Anpassung in `Jack.Build` (Vorschlag):

- Pro Teil mit `DeathBox.HasCustomAsset("clown_head")` usw. prüfen; ist es da, das eigene Mesh **an denselben Drehpunkt** hängen statt der Grundformen.
- `Builder.Mesh` **ohne** `color`, `texture`, `emissive` und `roughness` aufrufen, sonst überschreibt `Builder.Paint` das eigene Material mit `M_Default_Masked_Lit`. Erlaubt sind `scale` (für Jacks Skalierung, z. B. 2,2 bei der Statue im Hub) und `collision`.
- Neue Schlüssel (`clown_lid`, `clown_crank`, `clown_forearm`, `clown_jaw`) nur hinter dieser Prüfung verwenden oder in `DEFAULT` eintragen, sonst warnt `DeathBox.Asset`.
- **Gesicht:** Seit Jack 4 (v0.10) gibt es keine Bild-Masken mehr (flache Ebenen waren im Spiel unsichtbar): Das Gesicht besteht aus Grundformen am Kopf-Drehpunkt (`jack.head`), `jack.mask` ist nur noch der Bezugspunkt der Gesichtsmitte (POP-Abstand, Suchstrahl). `Jack.SetFace` (`idle`, `laugh`, `angry`) stellt Brauen (`jack.brows`), Lider (`jack.eyelids`, wachsen per `SetScale` von oben über die Augenhöhle) und die Kinnlade (`jack.jaw_pivot`); die Pupillen (`jack.eyes`) leuchten über `Jack.SetEyeGlow`. Ein eigener Kopf ersetzt die Grundformen am selben Drehpunkt; Brauen, Lider und Pupillen dann entweder als eigene Meshes in diese Listen eintragen oder die Listen leer lassen (dann passiert nichts).
- Den Hut (Grundformen an `jack.hat`, sitzt bei `head_at(-5, 4, 83)`, schief) auf die Oberkante des neuen Kopfes setzen oder weglassen. Danach `FIGURE_TOP` anpassen (siehe „Passt Jack in die Kiste?“).

```lua
if (DeathBox.HasCustomAsset("clown_head")) then
	-- eigener Kopf, Drehpunkt = Halsgelenk; keine Maske (jack.mask bleibt nil)
	jack.head_mesh = Part(Builder.Mesh(list, head_at(0, 0, 0), Rotator(), "clown_head", { scale = V(1, 1, 1) }), jack.head)
else
	-- bisheriges Gesicht aus Grundformen (Porzellan-Ei, Augen, Brauen, Lider, Nase, Grinsen, Kinnlade, Haare)
end
```

- Neuer Stuhl: `CHAIR_YAW_OFFSET` in `Config.lua` anpassen, bis die Sitzfläche zur Mitte zeigt, und die Sitzhöhe mit `/sitpos` nachstellen.

### Alternative: Mixamo (menschlicher Clown-Körper mit echten Animationen)

- Kostenlos mit Adobe-ID. Laut Adobe sind Figuren und Animationen lizenzfrei für private, kommerzielle und gemeinnützige Projekte nutzbar, auch für Spiele. Die Rohdateien darf man nicht weiterverteilen. Auto-Rig nur für zweibeinige Menschenformen; Kiste und Feder bleiben Static Meshes.
- Ablauf: auf <https://www.mixamo.com> die Figur hochladen (FBX/OBJ, T- oder A-Pose, ein Mesh), Marker setzen (Kinn, Handgelenke, Ellbogen, Knie, Leiste). Dann Animationen wählen, z. B. *Laughing*, *Pointing*, *Taunt*, *Shaking Head No*, *Zombie Scream*. Download als *FBX Binary*, 30 fps; die erste Datei *With Skin*, alle weiteren *Without Skin*.
- In Unreal: die erste Datei als Skeletal Mesh importieren (legt das Skeleton an), weitere Dateien nur als Animation auf dieses Skeleton.
- Abspielen über `CharacterSimple` + eigenes ABP wie in Schritt 3b. Der in der nanos-Doku beschriebene *Mixamo Converter* (Umbau auf `SKEL_Mannequin`) ist nur für die Klasse `Character` nötig, also für Spielerfiguren, nicht für Jack.

### Alternative: KI „Bild zu 3D“

- Eigenes Konzeptbild als Vorlage nehmen (selbst gezeichnet oder generiert, z. B. „antique porcelain clown animatronic head, cracked glaze, exposed brass gears, front view, white background“). **Keine FNAF-Bilder als Eingabe.**
- Werkzeuge: **Meshy** (Gratis-Plan: Ergebnisse unter CC BY 4.0 mit Credit an Meshy; bezahlt: eigene Nutzung ohne Credit). **TRELLIS / TRELLIS.2** von Microsoft (läuft lokal; laut README braucht TRELLIS eine NVIDIA-Karte mit mindestens 16 GB, TRELLIS.2 mit mindestens 24 GB). Code und Modelle stehen unter MIT, einzelne Bausteine aber unter eigenen, teils nicht-kommerziellen Lizenzen: bei TRELLIS *diffoctreerast* (abgeleitet von Inrias *diff-gaussian-rasterization*, nur Forschung/Evaluation), bei TRELLIS.2 *nvdiffrast* (NVIDIA, nur nicht-kommerziell) und *nvdiffrec*. Ob das die erzeugten Modelle betrifft, ist nicht geklärt; vor der Jam-Abgabe prüfen. Bei Tripo, Rodin u. a. vorher die Bedingungen lesen. **Hunyuan3D 2.x ist für uns tabu:** Die Lizenz gilt ausdrücklich nicht in der EU, in Großbritannien und Südkorea.
- Typisches Ergebnis: 10.000–50.000 wirre Dreiecke, eine Textur mit eingebackenem Licht, keine getrennten Teile, manchmal Löcher. Aufräumen: in Blender *Remesh* oder *Decimate*, Teile trennen, neu texturieren bzw. Schatten aus der Farbe entfernen, Drehpunkte setzen, dann weiter ab Schritt 2.
- Wegen der „AI slop“-Kritik: KI-Meshes nur als Rohling oder für kleine Requisiten verwenden, Jack selbst von Hand fertig machen.
