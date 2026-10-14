-- Client/Audio.lua
-- Sounds und Musik. Eigene Dateien liegen in Client/sounds/*.ogg (selbst synthetisiert),
-- Standard-Sounds kommen aus dem nanos-Pack (DeathBox.Asset).
-- Alles laeuft lokal beim Client; der Server schickt nur, WAS passiert.

DeathBox.Audio = {
	ambience = nil,        -- laufender Hintergrund-Loop
	ambience_name = nil,
	ambience_volume = 0.5,
	layer = nil,           -- zweite, leisere Schicht unter der Atmo (Hub: Dampforgel), siehe LAYERS
	layer_volume = 0,
	music = nil,           -- laufende Spieluhr
	loops = {},            -- weitere benannte Loops (z. B. Herzschlag)
}

local Audio = DeathBox.Audio

-- Spin-Melodien (scratchpad audio/synth.py, v0.9): je GENAU 10.0 s = Config.SPIN_TIME, Ritardando, letzter Ton bei
-- 8.75 s, die Mechanik bleibt bei 9.7 s mit leisem Klack stehen, ab 10.0 s ist Ruhe. Danach kommt die Stille vor dem
-- POP (Config.HOLD_TIME) mit Herzschlag: Audio.Music(name, volume, hold) startet ihn selbst, sobald die Melodie zu
-- Ende ist - nur wenn hold angegeben ist (der Spin gibt ihn an, das Intro nicht: dort kommt der POP direkt am Ende).
-- Loop-Schluessel "heart": ein spaeter gestarteter Herzschlag unter demselben Schluessel ersetzt diesen.
-- Name -> Laenge in Sekunden.
Audio.SPIN_TUNES = { spin_rosie = 8.0, spin_weasel = 8.0, spin_bridge = 8.0, spin_lullaby = 8.0 }   -- = Config.SPIN_TIME (v0.11: 8 s)
Audio.HOLD_HEART_VOLUME = 0.7

-- Zweite Schicht je Ort, leise unter der Atmo (Lautstaerke relativ zu ambience_volume).
-- Hub: eine alte Dampforgel spielt weit weg Fuciks "Einzug der Gladiatoren" (32-s-Loop, nahtlos).
Audio.LAYERS = {
	hub = { name = "hub_calliope_loop", volume = 0.6 },
}

-- Eigener Sound (2D, ueberall gleich laut)
function Audio.Play(name, volume, pitch)
	return Sound(Vector(), DeathBox.SoundFile(name), true, true, SoundType.SFX, volume or 1, pitch or 1)
end

-- Eigener Sound an einem Ort in der Welt
function Audio.Play3D(name, location, volume, pitch, falloff)
	return Sound(location, DeathBox.SoundFile(name), false, true, SoundType.SFX, volume or 1, pitch or 1,
		300, falloff or 3600, AttenuationFunction.NaturalSound)
end

-- Standard-Sound aus dem nanos-Pack (Name aus Shared/Assets.lua)
function Audio.PlayAsset(asset_name, volume, pitch)
	return Sound(Vector(), DeathBox.Asset(asset_name), true, true, SoundType.SFX, volume or 1, pitch or 1)
end

-- Spieluhr / Musikstueck (es laeuft immer nur eines). hold (Sekunden, optional): nach einer Spin-Melodie die Stille
-- vor dem POP mit Herzschlag fuellen (siehe SPIN_TUNES)
function Audio.Music(name, volume, hold)
	Audio.StopMusic(0.15)
	local music = Sound(Vector(), DeathBox.SoundFile(name), true, false, SoundType.SFX, volume or 1, 1,
		400, 3600, AttenuationFunction.Linear, false, SoundLoopMode.Never, true)
	Audio.music = music
	local length = Audio.SPIN_TUNES[name]
	if (length and hold and hold > 0) then
		Timer.SetTimeout(function()
			if (Audio.music == music) then Audio.HoldHeartbeat(hold) end   -- nicht, wenn inzwischen ersetzt/gestoppt
		end, length * 1000)
	end
	return music
end

-- Herzschlag fuer die Stille vor dem POP (endet kurz vor dem POP und blendet darunter aus)
function Audio.HoldHeartbeat(seconds)
	return Audio.StartLoop("heart", "heartbeat_loop", Audio.HOLD_HEART_VOLUME, 0.05, math.max(0.5, (seconds or 2) - 0.15))
end

function Audio.StopMusic(fade)
	local music = Audio.music
	Audio.music = nil
	if (music and music:IsValid()) then
		if (fade and fade > 0) then music:FadeOut(fade, 0, true) else music:Destroy() end
	end
end

-- Benannter Loop (z. B. Herzschlag waehrend einer Entscheidung). max_seconds: Sicherheits-Abschaltung,
-- falls das Ende-Signal ausbleibt (z. B. weil jemand mitten im Event den Server verlaesst).
function Audio.StartLoop(key, name, volume, fade_in, max_seconds)
	Audio.StopLoop(key, 0)
	local sound = Sound(Vector(), DeathBox.SoundFile(name), true, false, SoundType.SFX, volume or 1, 1,
		400, 3600, AttenuationFunction.Linear, false, SoundLoopMode.Forever, false)
	sound:FadeIn(fade_in or 0.3, 1)
	Audio.loops[key] = sound
	Timer.SetTimeout(function()
		if (Audio.loops[key] == sound) then Audio.StopLoop(key, 0.5) end
	end, (max_seconds or 15) * 1000)
	return sound
end

function Audio.StopLoop(key, fade)
	local sound = Audio.loops[key]
	Audio.loops[key] = nil
	if (sound and sound:IsValid()) then
		if (fade and fade > 0) then sound:FadeOut(fade, 0, true) else sound:Destroy() end
	end
end

-- Hintergrund je Ort ("hub" / "tent"), weich ueberblendet
function Audio.SetAmbience(kind)
	local name = (kind == "hub") and "hub_ambience_loop" or "tent_ambience_loop"
	if (DeathBox.HasCustomAsset("music_" .. kind)) then
		name = nil   -- eigenes Musikstueck aus dem Asset Pack hat Vorrang (siehe unten)
	end
	if (Audio.ambience_name == (name or kind)) then return end

	if (Audio.ambience and Audio.ambience:IsValid()) then
		Audio.ambience:FadeOut(2.0, 0, true)
	end
	Audio.ambience_name = name or kind

	local path = name and DeathBox.SoundFile(name) or DeathBox.Asset("music_" .. kind)
	Audio.ambience = Sound(Vector(), path, true, false, SoundType.Music, Audio.ambience_volume, 1,
		400, 3600, AttenuationFunction.Linear, false, SoundLoopMode.Forever, false)
	Audio.ambience:FadeIn(2.5, 1)
	Audio.SetLayer(name and kind or nil)   -- ein eigenes Musikstueck ersetzt auch die zweite Schicht
end

-- Zweite Schicht (Audio.LAYERS) passend zum Ort wechseln, weich ueberblendet; nil = keine
function Audio.SetLayer(kind)
	if (Audio.layer and Audio.layer:IsValid()) then
		Audio.layer:FadeOut(2.0, 0, true)
	end
	Audio.layer, Audio.layer_volume = nil, 0
	local def = kind and Audio.LAYERS[kind]
	if (not def) then return end
	Audio.layer_volume = Audio.ambience_volume * def.volume
	Audio.layer = Sound(Vector(), DeathBox.SoundFile(def.name), true, false, SoundType.Music, Audio.layer_volume, 1,
		400, 3600, AttenuationFunction.Linear, false, SoundLoopMode.Forever, false)
	Audio.layer:FadeIn(4.0, 1)
end

-- Hintergrund leiser machen (z. B. waehrend Jack dreht), 1 = normal
function Audio.DuckAmbience(factor)
	if (Audio.ambience and Audio.ambience:IsValid()) then
		Audio.ambience:SetVolume(Audio.ambience_volume * factor)
	end
	if (Audio.layer and Audio.layer:IsValid()) then
		Audio.layer:SetVolume(Audio.layer_volume * factor)
	end
end

function Audio.StopAll()
	Audio.StopMusic(0)
	for key in pairs(Audio.loops) do Audio.StopLoop(key, 0) end
	if (Audio.ambience and Audio.ambience:IsValid()) then Audio.ambience:Destroy() end
	if (Audio.layer and Audio.layer:IsValid()) then Audio.layer:Destroy() end
	Audio.ambience, Audio.ambience_name = nil, nil
	Audio.layer, Audio.layer_volume = nil, 0
end
