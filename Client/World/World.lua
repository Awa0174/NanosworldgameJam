-- Client/World/World.lua
-- Welcher Ort ist gerade lokal gebaut? Der Server sagt per "DeathBox:Place", wo der Spieler ist.
-- Beim Wechsel wird der alte Ort abgerissen und der neue gebaut (hinter einer kurzen Schwarzblende).

DeathBox.World = {
	kind = nil,         -- "hub" | "match"
	match_id = nil,
	hub = nil,
	tent = nil,
	light_scale = 1,    -- Konsole: db_light <faktor>
	light_dim = 1,
	head_light = nil,
}

local World = DeathBox.World
local Builder = DeathBox.Builder

local function Clear()
	if (World.hub) then Builder.Destroy(World.hub.list) end
	if (World.tent) then Builder.Destroy(World.tent.list) end
	World.hub, World.tent = nil, nil
	if (World.head_light and World.head_light:IsValid()) then World.head_light:Destroy() end
	World.head_light = nil
end

-- Schwaches Licht am eigenen Kopf, damit man im dunklen Friedhof den Weg sieht (wie im offiziellen Halloween-Modus)
local function AttachHeadLight()
	if (World.kind ~= "hub" or (World.head_light and World.head_light:IsValid())) then return end
	local player = Client.GetLocalPlayer()
	local character = player and player:GetControlledCharacter()
	if (not character or not character:IsValid()) then return end
	World.head_light = Light(character:GetLocation(), Rotator(), Color(1, 0.85, 0.7), LightType.Point, 0.8, 380,
		44, 0, 2000, true, false, true, 2)
	World.head_light:AttachTo(character, AttachmentRule.SnapToTarget, "head", -1, false)
end

function World.Enter(kind, info)
	info = info or {}
	if (kind == World.kind and (kind == "hub" or info.match == World.match_id)) then return end
	Clear()
	World.kind = kind
	World.match_id = info.match
	World.light_dim = 1

	DeathBox.Atmosphere.FadeIn(1.4)
	DeathBox.Presentation.Reset()

	if (DeathBox.Diag) then DeathBox.Diag.OnEnter(kind) end   -- Selbstdiagnose (nur Testmodus, einmal)

	if (kind == "hub") then
		World.hub = DeathBox.Hub.Build()
		DeathBox.Atmosphere.Apply("hub")
		DeathBox.Audio.SetAmbience("hub")
		Timer.SetTimeout(AttachHeadLight, 600)
	else
		World.tent = DeathBox.Tent.Build(info.seat_count or DeathBox.Config.TABLE_SEATS, info.jack_yaw or 0)
		DeathBox.Atmosphere.Apply("tent")
		DeathBox.Audio.SetAmbience("tent")
	end
end

function World.Leave()
	Clear()
	World.kind, World.match_id = nil, nil
end
