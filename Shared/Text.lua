-- Shared/Text.lua
-- Alle Texte, die Spieler sehen, an einer Stelle (Englisch).
-- Platzhalter: {name}, {target}, {winner}, {left}, {count} werden mit DeathBox.Text.Format ersetzt.
-- Madame hat pro Situation mehrere Saetze, damit sie sich nicht staendig wiederholt.

DeathBox = DeathBox or {}

DeathBox.Text = {
	TITLE = "The Last Séance",

	LOBBY_WAITING = "The table waits for more souls ({count}/{needed})",
	LOBBY_COUNTDOWN = "The séance begins",
	LOBBY_SPECTATING = "A séance is in progress. You will join the next one.",
	ENDED = "The séance is over",

	-- Madame (Untertitel)
	MADAME = {
		GAME_START = {
			"Join hands. Do not let go... whatever you hear.",
			"The candles are lit. The dead are listening.",
			"Welcome, my dears. Not all of you will leave.",
		},
		CHOSEN = {
			"The spirits whisper a name... {name}.",
			"{name}. They want you.",
			"Look at me, {name}. Your turn.",
		},
		CHAMBER_HAND = {
			"Take the revolver, {name}. Choose wisely.",
			"The revolver is yours, {name}. Who shall it be?",
		},
		CHAMBER_AIM = {
			"{name} aims at {target}...",
			"{name} points the revolver at {target}.",
		},
		CHAMBER_HESITATE = {
			"{name} hesitates. The revolver turns on its owner.",
			"Too slow, {name}. The spirits choose for you.",
		},
		CHAMBER_CLICK = {
			"*click* ... The dead are patient.",
			"*click*. Not yet.",
			"*click*. Breathe, {target}. For now.",
		},
		CHAMBER_BANG = {
			"The candle goes out. Goodbye, {target}.",
			"{target} joins us on the other side.",
		},
		WARD_SAVE = {
			"The Ward shatters. {target} lives.",
		},
		TARGET_FLED = {
			"{target} fled the table. Cowardice does not save the soul.",
		},
		LEFT_TABLE = {
			"{name} broke the circle. The spirits take them anyway.",
		},
		WINNER = {
			"Only {winner} remains. The séance is over... for now.",
			"{winner} walks out alive. Remember this night.",
		},
		NO_WINNER = {
			"No one leaves. The house keeps them all.",
		},
	},

	-- Rituale (Name + Anweisung fuer das HUD)
	RITUALS = {
		chamber = {
			name = "The Chamber",
			instruction_actor = "Choose your target",
			instruction_others = "{name} holds the revolver",
		},
	},

	-- Chat-Feedback fuer Debug-Befehle
	NOT_YOUR_TURN = "It is not your turn.",
}

local function Pick(list)
	if (type(list) == "table") then
		return list[math.random(#list)]
	end
	return list
end

-- Ersetzt {schluessel} im Text durch Werte aus values. Bei Listen wird ein zufaelliger Satz gewaehlt.
function DeathBox.Text.Format(text_or_list, values)
	local text = Pick(text_or_list) or ""
	return (string.gsub(text, "{(%w+)}", function(key)
		local value = values and values[key]
		return value ~= nil and tostring(value) or ("{" .. key .. "}")
	end))
end
