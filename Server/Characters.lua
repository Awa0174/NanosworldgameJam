-- Server/Characters.lua
-- Alles rund um die Spielfiguren: in eine Dimension bringen, hinsetzen, aufstehen, ausschalten.
-- Bots bekommen eine eigene Figur ohne Spieler, damit der Kreis auch voll aussieht.
--
-- WARUM SO (Ursachen aus der Analyse der nanos-1.159-Binary und der Doku, siehe docs/DESIGN.md):
--   * SetGravityEnabled(false) ist bei Characters nur "Schwerkraft x 0". Die Figur bleibt im Fall-Zustand,
--     behaelt ihre Restgeschwindigkeit (in der Luft wird nicht gebremst) und rutscht ohne Kollision davon
--     -> "ich fliege weg". Nach 1 s Fallen kommt "HighFalling" -> zappelnde Bots.
--   * Loesung: StopMovement(true) (Geschwindigkeit auf 0) + SetFlyingMode(true) (bremst, keine Schwerkraft,
--     kein HighFalling, wird vom Server gespeichert) + Eingabe aus.
--   * PlayAnimation wird nur einmal an die Clients geschickt, die gerade da sind, und nirgends gespeichert.
--     Deshalb steht die Sitz-Animation als SYNCHRONISIERTER Wert an der Figur ("DB_SitAnim"); jeder Client
--     spielt sie selbst ab (Client/Poses.lua) – auch wer spaeter dazukommt.
--   * Ebenso synchron: "DB_Seat" / "DB_Chair" (Platz- und Stuhlnummer am Tisch, 0 = keiner). Damit findet jeder Client
--     die Figur eines Platzes (Highlights, Revolver in der Hand), docs/PROTOCOL.md "Synchronisierte Werte".

DeathBox.Characters = {}

local Characters = DeathBox.Characters

local SIT_KEY = "DB_SitAnim"
local SPAWN_HOVER_TIME = 1.2   -- so lange schwebt man nach dem Teleport, bis der Client den Ort gebaut hat

-- Figur einfrieren: kein Schwung, kein Fallen, keine Eingabe
local function Freeze(character)
	character:StopMovement(true)
	character:SetInputEnabled(false)
	character:SetFlyingMode(true)
	character:SetHighFallingTime(-1)
end

-- Bringt Spieler + Figur in eine Dimension an eine Position. Erzeugt/belebt die Figur bei Bedarf.
-- Die Figur schwebt kurz eingefroren, bis der Client den Ort (Boden!) lokal gebaut hat.
function Characters.Place(player, dimension, location, rotation)
	if (not player or not player:IsValid()) then return nil end

	local character = player:GetControlledCharacter()
	if (not character or not character:IsValid()) then
		player:SetDimension(dimension)
		character = Character(location, rotation, DeathBox.Asset("player_mesh"))
		character:SetDimension(dimension)
		player:Possess(character)
	else
		Characters.StandUp(character)
		DeathBox.Commands.ResetCheats(character)
		player:SetDimension(dimension)   -- nimmt die Figur mit
		if (character:IsDead()) then
			character:Respawn(location, rotation)
		end
	end

	Freeze(character)
	Characters.ClearSeat(character)   -- woanders hingestellt: gehoert zu keinem Platz mehr (Match.Create markiert neu)
	character:SetCollision(CollisionType.Normal)
	character:SetLocation(location)
	character:SetRotation(rotation)
	player:SetCameraRotation(rotation)

	-- Nach kurzer Zeit freigeben (dann steht der Boden beim Client)
	character:SetValue("DB_PlaceToken", (character:GetValue("DB_PlaceToken") or 0) + 1)
	local token = character:GetValue("DB_PlaceToken")
	Timer.SetTimeout(function()
		if (not character:IsValid() or character:IsDead()) then return end
		if (character:GetValue("DB_PlaceToken") ~= token or character:GetValue(SIT_KEY)) then return end
		character:SetFlyingMode(false)
		character:SetInputEnabled(true)
	end, SPAWN_HOVER_TIME * 1000)

	return character
end

-- Setzt eine Figur auf ihren Platz (location/rotation aus Shared/Layout.lua)
function Characters.Sit(character, location, rotation)
	if (not character or not character:IsValid() or character:IsDead()) then return end

	DeathBox.Commands.ResetCheats(character)
	-- Reihenfolge ist wichtig: erst Schwung weg und einfrieren, dann versetzen
	Freeze(character)
	character:SetCollision(CollisionType.NoCollision)   -- Nachbarn/Zuschauer schieben niemanden vom Stuhl
	character:SetRagdollOnHitEnabled(false)
	character:SetLocation(location)
	character:SetRotation(rotation)
	character:SetValue("DB_SeatLocation", location)
	character:SetValue(SIT_KEY, DeathBox.Asset("sit_animation"), true)   -- synchron: Clients spielen die Pose

	-- Kurz danach nochmal exakt hinsetzen: faengt Netzwerk-Korrekturen und letzten Restschwung ab (v0.5.3)
	Timer.SetTimeout(function()
		if (not character:IsValid() or character:IsDead() or not character:GetValue(SIT_KEY)) then return end
		character:StopMovement(true)
		character:SetLocation(location)
		character:SetRotation(rotation)
	end, 250)
end

-- Platz-Markierung (synchron): seat_index = Platz in match.seats, chair_index = Stuhl. 0 = an keinem Platz.
function Characters.MarkSeat(character, seat_index, chair_index)
	if (not character or not character:IsValid()) then return end
	character:SetValue("DB_Seat", seat_index or 0, true)
	character:SetValue("DB_Chair", chair_index or 0, true)
end

function Characters.ClearSeat(character)
	if (not character or not character:IsValid()) then return end
	if ((character:GetValue("DB_Seat") or 0) == 0 and (character:GetValue("DB_Chair") or 0) == 0) then return end
	Characters.MarkSeat(character, 0, 0)
end

-- Sitzende Figur um die Hochachse drehen (z. B. Revolver-Halter zeigt aufs Ziel). Nur, solange sie sitzt und lebt.
function Characters.TurnSeated(character, yaw)
	if (not Characters.IsSitting(character) or character:IsDead()) then return end
	character:SetRotation(Rotator(0, yaw, 0))
end

function Characters.IsSitting(character)
	return character ~= nil and character:IsValid() and character:GetValue(SIT_KEY) ~= nil and character:GetValue(SIT_KEY) ~= false
end

function Characters.StandUp(character)
	if (not character or not character:IsValid() or not Characters.IsSitting(character)) then return end
	character:SetValue(SIT_KEY, false, true)
	character:SetValue("DB_SeatLocation", nil)
	character:SetCollision(CollisionType.Normal)
	character:SetRagdollOnHitEnabled(true)
	character:SetFlyingMode(false)
	character:SetInputEnabled(true)
end

-- Schaltet eine Figur aus. Sie faellt (Ragdoll) auf den Boden des Zelts.
function Characters.Kill(character)
	if (not character or not character:IsValid() or character:IsDead()) then return end
	DeathBox.Commands.ResetCheats(character)   -- Godmode wuerde den Treffer sonst abfangen
	if (Characters.IsSitting(character)) then
		character:SetValue(SIT_KEY, false, true)
		character:SetCollision(CollisionType.Normal)
		character:SetFlyingMode(false)
	end
	-- Bewusst mehr Schaden als noetig, damit eventuelle Schadens-Multiplikatoren keine Rolle spielen
	character:ApplyDamage(character:GetMaxHealth() * 10)
end

-- Bot-Figur auf einem Stuhl. Simuliert wird sie vom naechsten Spieler in derselben Dimension.
function Characters.SpawnBot(dimension, location, rotation)
	local previous = Server.GetDefaultEntityDimension()
	Server.SetDefaultEntityDimension(dimension)   -- direkt in der richtigen Dimension erzeugen
	local character = Character(location, rotation, DeathBox.Asset("bot_mesh"))
	Server.SetDefaultEntityDimension(previous)
	character:SetDimension(dimension)
	Characters.Sit(character, location, rotation)
	return character
end

-- Sitzende Figur, die zu weit von ihrem Platz abgekommen ist, zurueckholen (Server/Rescue.lua)
function Characters.ReseatIfDrifted(character, max_distance)
	if (not Characters.IsSitting(character) or character:IsDead()) then return false end
	local seat = character:GetValue("DB_SeatLocation")
	if (not seat) then return false end
	local location = character:GetLocation()
	local dx, dy, dz = location.X - seat.X, location.Y - seat.Y, location.Z - seat.Z
	if (dx * dx + dy * dy + dz * dz <= max_distance * max_distance) then return false end
	character:StopMovement(true)
	character:SetLocation(seat)
	return true
end

function Characters.Remove(player)
	local character = player:GetControlledCharacter()
	if (character and character:IsValid()) then
		character:Destroy()
	end
end
