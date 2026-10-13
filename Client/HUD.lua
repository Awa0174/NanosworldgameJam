-- Client/HUD.lua
-- Verbindet die WebUI (Client/UI) mit dem Server.
--
-- Datenfluss:
--   Server --Remote Event--> HUD.lua --CallEvent--> hud.js (WebUI)
--   hud.js --Events.Call--> HUD.lua --CallRemote--> Server
--
-- Die WebUI zeigt nur an. Ob eine Wahl gueltig ist, entscheidet ausschliesslich der Server.

DeathBox.HUD = {
	ui = nil,
	ready = false,       -- WebUI fertig geladen?
	choice_open = false, -- gerade eine Auswahl offen (Maus an)?
	pending = {},        -- Aufrufe, die vor "Ready" ankamen
}

local HUD = DeathBox.HUD

-- Ruft ein Event in der WebUI auf. Vor "Ready" wird gepuffert, damit nichts verloren geht.
local function CallUI(event_name, ...)
	if (HUD.ready) then
		HUD.ui:CallEvent(event_name, ...)
	else
		table.insert(HUD.pending, { event_name, { ... } })
	end
end

local function SendLocalPlayer()
	local local_player = Client.GetLocalPlayer()
	if (local_player) then
		CallUI("Init", local_player:GetID(), DeathBox.VERSION)
	end
end

-- Maus fuer Auswahl ein-/ausschalten. Waehrend der Auswahl faengt die WebUI Klicks ab.
local function SetChoiceMode(enabled)
	HUD.choice_open = enabled
	Input.SetMouseEnabled(enabled)
	if (enabled) then
		HUD.ui:SetVisibility(WidgetVisibility.Visible)
		HUD.ui:BringToFront()
	else
		HUD.ui:SetVisibility(WidgetVisibility.VisibleNotHitTestable)
	end
end

-- Kurze Sounds zu Ereignissen (2D, also ueberall gleich laut)
local FX_SOUNDS = {
	chosen = { asset = "nanos-world::A_Whoosh", volume = 0.6, pitch = 0.8 },
	aim    = { asset = "nanos-world::A_Pistol_Load", volume = 0.8, pitch = 1.0 },
	click  = { asset = "nanos-world::A_Pistol_Dry", volume = 1.0, pitch = 1.0 },
	bang   = { asset = "nanos-world::A_Pistol_Shot_B", volume = 1.0, pitch = 0.9 },
	ward   = { asset = "nanos-world::A_Teleport_Committed", volume = 0.8, pitch = 0.7 },
	start  = { asset = "nanos-world::A_Female_02_Laugh", volume = 0.5, pitch = 0.75 },
	winner = { asset = "nanos-world::A_Female_01_Laugh", volume = 0.6, pitch = 0.8 },
}

local function PlayFx(kind)
	local sound = FX_SOUNDS[kind]
	if (not sound) then return end
	Sound(Vector(), sound.asset, true, true, SoundType.SFX, sound.volume, sound.pitch)
end

function HUD.Create()
	if (HUD.ui) then return end

	HUD.ui = WebUI("DeathBox HUD", "file://UI/index.html", WidgetVisibility.VisibleNotHitTestable)

	HUD.ui:Subscribe("Ready", function()
		HUD.ready = true
		for _, call in ipairs(HUD.pending) do
			HUD.ui:CallEvent(call[1], table.unpack(call[2]))
		end
		HUD.pending = {}
		SendLocalPlayer()
		Events.CallRemote("DeathBox:RequestState", Reliability.Reliable)
	end)

	-- Spieler hat in der WebUI etwas gewaehlt
	HUD.ui:Subscribe("Choose", function(ritual_id, value)
		if (not HUD.choice_open) then return end
		Events.CallRemote("DeathBox:Input", Reliability.Reliable, tostring(ritual_id), tonumber(value))
		SetChoiceMode(false)
	end)

	-- UI-Klickgeraeusche
	HUD.ui:Subscribe("UiSound", function(kind)
		if (kind == "hover") then
			Sound(Vector(), "nanos-world::A_Button_Hover_Cue", true, true, SoundType.UI, 0.4)
		elseif (kind == "click") then
			Sound(Vector(), "nanos-world::A_Button_Click_Cue", true, true, SoundType.UI, 0.6)
		end
	end)
end

function HUD.Destroy()
	if (HUD.choice_open) then
		SetChoiceMode(false)
	end
	if (HUD.ui) then
		HUD.ui:Destroy()
		HUD.ui = nil
	end
	HUD.ready = false
end

-- ===================================================================
-- Nachrichten vom Server
-- ===================================================================

Events.SubscribeRemote("DeathBox:State", function(json)
	CallUI("State", json)
end)

Events.SubscribeRemote("DeathBox:Say", function(text)
	CallUI("Say", text)
end)

Events.SubscribeRemote("DeathBox:Fx", function(kind, seat)
	PlayFx(kind)
	CallUI("Fx", kind, seat)
end)

Events.SubscribeRemote("DeathBox:Choice", function(json)
	CallUI("Choice", json)
	if (HUD.ui) then SetChoiceMode(true) end
end)

Events.SubscribeRemote("DeathBox:ChoiceEnd", function()
	CallUI("ChoiceEnd")
	if (HUD.ui and HUD.choice_open) then SetChoiceMode(false) end
end)

-- Lokaler Spieler ist da (beim ersten Join kommt er erst nach dem Laden des Packages)
Client.Subscribe("SpawnLocalPlayer", function()
	SendLocalPlayer()
end)
