-- Client/HUD.lua
-- Verbindet Server, Welt/Regie (Lua) und die WebUI (Client/UI).
--
-- Datenfluss:
--   Server --Remote Event--> HUD.lua --> World / Presentation (3D, Licht, Ton)
--                                   \--CallEvent--> hud.js (WebUI)
--   hud.js --Events.Call--> HUD.lua --CallRemote--> Server
--
-- Die WebUI zeigt nur an. Ob eine Wahl gueltig ist, entscheidet ausschliesslich der Server.

DeathBox.HUD = {
	ui = nil,
	ready = false,       -- WebUI fertig geladen?
	choice_ask = nil,    -- ID der offenen Abfrage oder nil
	choice_kind = nil,   -- "target" / "click" (Maus an), "qte" (Tastatur, Maus aus) oder "aim" (Revolver: Kamera zielt,
	                     -- Linksklick schiesst, Maus bleibt gefangen – Client/Aim.lua)
	cards_open = false,  -- Kartenhand aufgeklappt (Taste C)?
	pending = {},        -- Aufrufe, die vor "Ready" ankamen
	choice_guard = nil,  -- Sicherheitsnetz: schliesst eine Abfrage lokal, falls das ChoiceEnd des Servers ausbleibt
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
HUD.CallUI = CallUI

local function SendLocalPlayer()
	local local_player = Client.GetLocalPlayer()
	if (local_player) then
		CallUI("Init", local_player:GetID(), DeathBox.VERSION)
	end
end

-- Maus/Klicks fuer die WebUI ein- oder ausschalten, je nachdem ob eine Klick-Abfrage oder die Kartenhand offen ist.
-- Tasten-Abfragen (qte) und der Zielmodus (aim) lassen die Maus gefangen: Kamera dreht sich, Klicks gehen ans Spiel.
local function UpdateMouse()
	local enabled = (HUD.choice_ask ~= nil and HUD.choice_kind ~= "qte" and HUD.choice_kind ~= "aim") or HUD.cards_open
	Input.SetMouseEnabled(enabled)
	if (enabled) then
		HUD.ui:SetVisibility(WidgetVisibility.Visible)
		HUD.ui:BringToFront()
	else
		HUD.ui:SetVisibility(WidgetVisibility.VisibleNotHitTestable)
	end
end

-- Abfrage oeffnen/schliessen. Bei Klick-Abfragen faengt die WebUI die Maus ab.
-- Bei Tasten-Abfragen (qte) bleibt die Maus aus, die Taste wird unten per KeyDown gelesen.
local function SetChoiceMode(ask_id, kind)
	if (HUD.choice_guard and Timer.IsValid(HUD.choice_guard)) then Timer.ClearTimeout(HUD.choice_guard) end
	HUD.choice_guard = nil
	local was_aim = (HUD.choice_kind == "aim")
	HUD.choice_ask = ask_id
	HUD.choice_kind = ask_id and kind or nil
	if (ask_id and HUD.cards_open) then HUD.SetCardsOpen(false) end
	if (was_aim and HUD.choice_kind ~= "aim" and DeathBox.Aim) then DeathBox.Aim.End("closed") end
	UpdateMouse()
end

-- Eine Wahl an den Server schicken (Ring/Knoepfe der WebUI und Linksklick im Zielmodus). Nur fuer die offene Abfrage;
-- ob die Wahl gilt, prueft ausschliesslich der Server. Gibt true zurueck, wenn sie gesendet wurde.
function HUD.SubmitChoice(ask_id, value)
	if (not HUD.choice_ask or tonumber(ask_id) ~= HUD.choice_ask) then return false end
	if (type(value) ~= "number" and type(value) ~= "string") then return false end
	Events.CallRemote("DeathBox:Input", Reliability.Reliable, HUD.choice_ask, value)
	SetChoiceMode(nil)
	return true
end

-- Zielmodus (Client/Aim.lua) -> WebUI: Zielzeile { ask, seat, chair, name, label, hint, warn, seconds, total, crosshair }
-- und Ende (reason: "confirm", "closed", "end", "place", "restart", "timeout"). Alle Aufrufe an die WebUI laufen hier.
function HUD.ShowAim(json)
	CallUI("Aim", json)
end

function HUD.EndAim(ask_id, reason)
	CallUI("AimEnd", ask_id or 0, reason or "end")
end

-- Abfrage lokal schliessen, falls das ChoiceEnd des Servers ausbleibt (Sicherheitsnetz des Zielmodus)
function HUD.CloseChoice(ask_id)
	if (HUD.choice_ask and (ask_id == nil or ask_id == HUD.choice_ask)) then
		SetChoiceMode(nil)
		CallUI("ChoiceEnd", ask_id or 0)
	end
end

-- Neue Runde, Showbeginn, Sieg, Ortswechsel: GOLD/ROT-Markierungen und Zielposen der letzten Szene weg
local function ResetMarks()
	if (DeathBox.Highlight) then DeathBox.Highlight.Clear() end
	if (DeathBox.Poses and DeathBox.Poses.StopAllAiming) then DeathBox.Poses.StopAllAiming() end
end

-- Kartenhand auf-/zuklappen (Taste C). Waehrend einer eigenen Abfrage geht das nicht.
function HUD.SetCardsOpen(open)
	if (open and (HUD.choice_ask or DeathBox.World.kind ~= "match")) then return end
	HUD.cards_open = open
	CallUI("CardMode", open)
	UpdateMouse()
end

-- Kurze Sounds zu kleinen Ereignissen. Grosse Momente (Tod, Lachen, Feuer, Spieluhr) macht Presentation.lua.
local FX_SOUNDS = {
	aim     = { "snd_load", 0.8, 1.0 },
	click   = { "snd_dry", 1.0, 1.0 },
	bang    = { "snd_shot", 1.0, 0.9 },
	safety  = { "snd_safety", 0.8, 0.7 },
	qte_ok  = { "snd_qte", 0.8, 1.2 },
	stab    = { "snd_flesh", 1.0, 0.9 },
	block   = { "snd_block", 1.0, 1.1 },
	burn    = { "snd_scream", 0.7, 0.9 },
}

local function PlayFx(kind)
	local sound = FX_SOUNDS[kind]
	if (sound) then DeathBox.Audio.PlayAsset(sound[1], sound[2], sound[3]) end
	if (kind == "dodge") then DeathBox.Audio.Play("whoosh", 0.9, 1.5) end
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
		-- Kartendefinitionen (Name, Beschreibung, Typ, Ziel) aus Shared/Cards.lua – eine Quelle fuer Server und HUD
		local defs = {}
		for id, card in pairs(DeathBox.Cards) do
			defs[id] = { name = card.name, description = card.description, type = card.type, target = card.target, art = card.art }
		end
		HUD.ui:CallEvent("CardDefs", JSON.stringify(defs))
		Events.CallRemote("DeathBox:RequestState", Reliability.Reliable)
	end)

	-- Spieler hat in der WebUI etwas gewaehlt. Zahl oder Text wird unveraendert weitergegeben.
	HUD.ui:Subscribe("Choose", function(ask_id, value)
		HUD.SubmitChoice(ask_id, value)
	end)

	-- Karte ausspielen (aus der aufgeklappten Hand). Ziel 0 = ohne Ziel. Der Server prueft alles.
	HUD.ui:Subscribe("PlayCard", function(uid, target_seat)
		if (not HUD.cards_open) then return end
		Events.CallRemote("DeathBox:PlayCard", Reliability.Reliable, tonumber(uid) or uid, tonumber(target_seat) or 0)
		HUD.SetCardsOpen(false)
	end)

	HUD.ui:Subscribe("CloseCards", function()
		HUD.SetCardsOpen(false)
	end)

	-- Kurze Sounds auf Wunsch der WebUI: nur diese Liste (Stings: Client/sounds/<name>.ogg, siehe synth.py)
	local UI_SOUNDS = {
		hover = { asset = "snd_hover", volume = 0.4 },
		click = { asset = "snd_click", volume = 0.6 },
		your_turn = { file = "your_turn", volume = 0.9 },
		round_out = { file = "round_out", volume = 0.8 },
		round_safe = { file = "round_safe", volume = 0.7 },
	}
	HUD.ui:Subscribe("UiSound", function(kind)
		local sound = UI_SOUNDS[kind]
		if (not sound) then return end
		if (sound.asset) then
			DeathBox.Audio.PlayAsset(sound.asset, sound.volume)
		else
			DeathBox.Audio.Play(sound.file, sound.volume)
		end
	end)

	-- Tasten-Abfrage (Knife Toss, Block): W/A/S/D direkt aus dem Spiel lesen (nicht, solange der Chat offen ist)
	Input.Subscribe("KeyDown", function(key_name)
		if (HUD.choice_kind ~= "qte" or not HUD.choice_ask) then return end
		if (DeathBox.Aim and DeathBox.Aim.chat_open) then return end
		local valid = false
		for _, key in ipairs(DeathBox.Config.QTE_KEYS) do
			if (key == key_name) then valid = true break end
		end
		if (not valid) then return end
		Events.CallRemote("DeathBox:Input", Reliability.Reliable, HUD.choice_ask, key_name)
		CallUI("QtePressed", key_name)
		SetChoiceMode(nil)
		return false
	end)
end

function HUD.Destroy()
	if (DeathBox.Aim) then DeathBox.Aim.End("place") end
	if (HUD.choice_ask) then
		SetChoiceMode(nil)
	end
	if (HUD.choice_guard and Timer.IsValid(HUD.choice_guard)) then Timer.ClearTimeout(HUD.choice_guard) end
	HUD.choice_guard = nil
	HUD.cards_open = false
	Input.SetMouseEnabled(false)   -- nie mit freier Maus zurueckbleiben (Package-Reload)
	if (HUD.ui) then
		HUD.ui:Destroy()
		HUD.ui = nil
	end
	HUD.ready = false
end

-- Taste N: Ausgeschiedene und Nachruecker gehen in die naechste Show (der Server prueft, ob das erlaubt ist)
function HUD.RequestNextShow()
	if (DeathBox.World.kind ~= "match") then return end
	if (DeathBox.Aim and DeathBox.Aim.chat_open) then return end   -- "n" beim Tippen im Chat
	Events.CallRemote("DeathBox:Leave", Reliability.Reliable)
end

-- ===================================================================
-- Nachrichten vom Server
-- ===================================================================

-- Ortswechsel: Welt lokal bauen (Friedhof oder Zelt), HUD umschalten
Events.SubscribeRemote("DeathBox:Place", function(kind, info_json)
	local info = (type(info_json) == "string" and info_json ~= "") and JSON.parse(info_json) or {}
	if (DeathBox.Aim) then DeathBox.Aim.End("place") end
	ResetMarks()
	DeathBox.World.Enter(kind, info)
	CallUI("Place", kind)
	-- Jeder Ortswechsel (auch von Tisch zu Tisch): offene Abfrage und Kartenhand schliessen, Maus wieder fangen
	if (HUD.ui) then
		if (HUD.choice_ask) then SetChoiceMode(nil) end
		if (HUD.cards_open) then HUD.SetCardsOpen(false) end
	end
end)

Events.SubscribeRemote("DeathBox:Lobby", function(json)
	local ok, lobby = pcall(JSON.parse, json)
	if (ok and type(lobby) == "table") then DeathBox.Hub.SetLobby(lobby) end
	CallUI("Lobby", json)
end)

Events.SubscribeRemote("DeathBox:State", function(json)
	local state = JSON.parse(json)
	if (state) then DeathBox.Presentation.SetState(state) end
	CallUI("State", json)
end)

Events.SubscribeRemote("DeathBox:Say", function(text)
	CallUI("Say", text)
end)

Events.SubscribeRemote("DeathBox:Fx", function(kind, seat)
	PlayFx(kind)
	CallUI("Fx", kind, seat)
end)

-- Regieanweisung: erst 3D/Ton (Presentation ergaenzt z. B. die Tick-Zeiten), dann ans HUD
Events.SubscribeRemote("DeathBox:Show", function(json)
	local data = JSON.parse(json)
	if (type(data) ~= "table" or type(data.action) ~= "string") then return end
	local action = data.action
	-- Rundenende / neue Runde / Showbeginn / Sieg: Markierungen und Zielposen der letzten Szene weg (bevor die Regie
	-- neue setzt; PROTOCOL: round_end = "Highlights aus")
	if (action == "round_end" or action == "spin" or action == "intro" or action == "winner") then ResetMarks() end
	-- Eigenes Zielen: das lokale Bild ist aktueller als das Echo des Servers (Client/Aim.lua)
	if (action == "revolver_aiming" and DeathBox.Aim) then
		local echo = DeathBox.Aim.FilterEcho(data)
		if (echo == "drop") then return end
		if (echo == "ui") then
			CallUI("Show", json)
			return
		end
	end
	data = DeathBox.Presentation.Handle(data)
	CallUI("Show", JSON.stringify(data))
end)

-- Eigene Kartenhand (privat, nur an diesen Spieler)
Events.SubscribeRemote("DeathBox:Hand", function(json)
	CallUI("Hand", json)
end)

-- Abfrage fuer diesen Spieler. Revolver-Ziel mit aim = true: Zielmodus statt Ring (Client/Aim.lua) – die WebUI bekommt
-- die Abfrage trotzdem (YOUR TURN, Zeitbalken) und dazu die Zielzeile per "Aim"/"AimEnd".
Events.SubscribeRemote("DeathBox:Choice", function(json)
	local data = JSON.parse(json)
	if (not data or type(data.ask) ~= "number") then return end
	local aim = data.kind == "target" and (data.aim == true or data.aim == 1) and DeathBox.Aim ~= nil
	CallUI("Choice", json)
	if (HUD.ui) then
		SetChoiceMode(data.ask, aim and "aim" or data.kind)
		if (aim) then DeathBox.Aim.Begin(data) end
		-- Sicherheitsnetz: Kommt das ChoiceEnd nicht (Verbindung, abgebrochenes Event), Abfrage nach Ablauf selbst
		-- schliessen, damit Maus und Kamera nie haengen bleiben. Der Server hat sie dann laengst entschieden.
		local seconds = tonumber(data.seconds) or 10
		local ask = data.ask
		HUD.choice_guard = Timer.SetTimeout(function()
			HUD.choice_guard = nil
			HUD.CloseChoice(ask)
		end, math.floor((seconds + 3) * 1000))
	end
end)

Events.SubscribeRemote("DeathBox:ChoiceEnd", function(ask_id)
	CallUI("ChoiceEnd", ask_id)
	if (HUD.ui and HUD.choice_ask and (ask_id == 0 or ask_id == HUD.choice_ask)) then
		SetChoiceMode(nil)
	end
end)

-- Lokaler Spieler ist da (beim ersten Join kommt er erst nach dem Laden des Packages)
Client.Subscribe("SpawnLocalPlayer", function()
	SendLocalPlayer()
end)
