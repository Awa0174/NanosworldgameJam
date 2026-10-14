-- Server/Rescue.lua
-- Sicherheitsnetz: Niemand soll je wieder "wegfliegen" und verloren gehen.
-- Einmal pro Sekunde:
--   * Sitzende Figuren (Spieler und Bots), die sich mehr als SEAT_TOLERANCE von ihrem Platz entfernt haben,
--     werden zurueckgesetzt.
--   * Wer im Hub oder als Zuschauer unter den Boden faellt (die Welt wird nur beim Client gebaut, die Map
--     darunter ist leer), wird zurueck an seinen Spawn bzw. Zuschauerplatz geholt.

local Config = DeathBox.Config
local Layout = DeathBox.Layout
local Characters = DeathBox.Characters
local Lobby = DeathBox.Lobby

local CHECK_INTERVAL = 1.0
local SEAT_TOLERANCE = 120   -- cm
local WATCHDOG_TIME = 60     -- s ohne Fortschritt -> Show gilt als haengend

DeathBox.Rescue = { rescued = 0 }

local function TooLow(character, floor_z)
	return character:GetLocation().Z < floor_z - Config.WORLD.RESCUE_DEPTH
end

local function Check()

	for player, place in pairs(Lobby.where) do
		local character = player:IsValid() and player:GetControlledCharacter() or nil
		if (character and character:IsValid() and not character:IsDead()) then
			if (place.hub) then
				if (TooLow(character, Config.WORLD.HUB_CENTER.Z)) then
					local location, rotation = Layout.HubSpawn()
					Characters.Place(player, place.hub.dimension, location, rotation)
					DeathBox.Rescue.rescued = DeathBox.Rescue.rescued + 1
				end
			elseif (place.match) then
				local match = place.match
				local seat = match:FindSeatByPlayer(player)
				if (seat and seat.alive) then
					if (Characters.ReseatIfDrifted(character, SEAT_TOLERANCE)) then
						DeathBox.Rescue.rescued = DeathBox.Rescue.rescued + 1
					end
				elseif (TooLow(character, Config.WORLD.SHOW_CENTER.Z)) then
					local location, rotation = Layout.SpectatorTransform(seat and seat.chair or 1, match.seat_count)
					Characters.Place(player, match.dimension, location, rotation)
					DeathBox.Rescue.rescued = DeathBox.Rescue.rescued + 1
				end
			end
		end
	end

	-- Watchdog: Eine Show, in der sich zu lange nichts mehr bewegt (kein Timer-Schritt, keine Eingabe), haengt.
	-- Dann ordentlich beenden, statt Spieler eingefroren sitzen zu lassen. Laengster regulaerer Abstand zwischen
	-- zwei Schritten ist eine Abfrage-Zeit (wenige Sekunden), WATCHDOG_TIME ist grosszuegig darueber.
	local now = Server.GetTime()
	local matches = {}
	for i, match in ipairs(Lobby.matches) do matches[i] = match end   -- Abort kann Lobby.matches veraendern
	for _, match in ipairs(matches) do
		if (not match.disposed and match.last_progress > 0 and now - match.last_progress > WATCHDOG_TIME * 1000) then
			DeathBox.Rescue.watchdog = (DeathBox.Rescue.watchdog or 0) + 1
			match.last_progress = now
			match:Abort("watchdog")
		end
	end

	-- Bots am Platz halten
	for _, match in ipairs(Lobby.matches) do
		for _, seat in ipairs(match.seats) do
			if (seat.alive and seat.bot_character and seat.bot_character:IsValid()) then
				Characters.ReseatIfDrifted(seat.bot_character, SEAT_TOLERANCE)
			end
		end
	end
end

Timer.SetInterval(Check, CHECK_INTERVAL * 1000)
