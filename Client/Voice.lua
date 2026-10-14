-- Client/Voice.lua
-- Jacks Stimme: spielt zu seinem Untertitel die passende Aufnahme (Client/sounds/voice/<id>.ogg) und bewegt dabei
-- seinen Kiefer im Takt der Lautstaerke (Huellkurve aus Shared/Voice.lua, beim Erzeugen der Aufnahmen berechnet).
--
-- Ablauf: Server Match:Say -> "DeathBox:Say"(text, voice) -> Client/HUD.lua -> Voice.Play(voice)
-- Regeln: immer nur EINE Stimme (ein neuer Satz beendet den alten mit kurzer Blende); unbekannte Kennung = still.
-- Konsole: db_voice <lautstaerke 0..2>   (0 = aus, Standard 1)

DeathBox.Voice = {
	volume = 1,
	current = nil,   -- laufender Sound
	until_time = 0,  -- Builder.time, bis zu der Jack spricht
}

local Voice = DeathBox.Voice
local BASE_VOLUME = 1.0

function Voice.Stop(fade)
	local sound = Voice.current
	Voice.current = nil
	if (sound and sound:IsValid()) then
		if (fade and fade > 0) then sound:FadeOut(fade, 0, true) else sound:Destroy() end
	end
end

function Voice.Play(id)
	local entry = DeathBox.VOICE and DeathBox.VOICE[id]
	if (not entry or Voice.volume <= 0) then return end
	Voice.Stop(0.08)
	-- 2D: Jack ist der Ansager, er soll ueberall im Zelt gleich gut zu verstehen sein (Hall ist in der Aufnahme)
	Voice.current = Sound(Vector(), DeathBox.SoundFile("voice/" .. id), true, true, SoundType.SFX, BASE_VOLUME * Voice.volume, 1)
	Voice.until_time = (DeathBox.Builder and DeathBox.Builder.time or 0) + (entry[1] or 2)
	local tent = DeathBox.World and DeathBox.World.tent
	if (tent and tent.jack and DeathBox.Jack.Talk) then
		DeathBox.Jack.Talk(tent.jack, entry[1], entry[2])
	end
end

-- Spricht Jack gerade? (Client/Audio.lua macht sein Lachen dann leiser, damit man die Worte versteht)
function Voice.Speaking()
	return Voice.current ~= nil and (DeathBox.Builder and DeathBox.Builder.time or 0) < Voice.until_time
end

Console.RegisterCommand("db_voice", function(value)
	Voice.volume = math.max(0, math.min(2, tonumber(value) or 1))
	if (Voice.volume <= 0) then Voice.Stop(0) end
	Console.Log("[DeathBox] Jacks Stimme: %s", tostring(Voice.volume))
end, "DeathBox: Lautstaerke von Jacks Stimme (0 = aus)", { "lautstaerke" })
