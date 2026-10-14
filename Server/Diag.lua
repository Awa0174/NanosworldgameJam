-- Server/Diag.lua
-- Nimmt die Selbstdiagnose der Clients an (Client/Diag.lua) und haengt sie an "deathbox_diag.txt" im Server-Ordner.
-- Nur mit DEBUG_COMMANDS; pro Spieler hoechstens 80 Teile pro Verbindung, Text wird gekuerzt.

local Config = DeathBox.Config

local FILE = "deathbox_diag.txt"
local MAX_PARTS = 80
local received = {}

local function Append(text)
	local file = File(FILE, false)
	if (not file:IsGood()) then
		file:Close()
		file = File(FILE, true)
	end
	file:Seek(file:Size())
	file:Write(text)
	file:Close()
end

Events.SubscribeRemote("DeathBox:Diag", function(player, index, total, text)
	if (not Config.DEBUG_COMMANDS) then return end
	if (type(index) ~= "number" or type(total) ~= "number" or type(text) ~= "string") then return end
	local id = player:GetID()
	received[id] = (received[id] or 0) + 1
	if (received[id] > MAX_PARTS) then return end

	local out = string.sub(text, 1, 2000)
	if (index == 1) then
		local stamp = (os and os.date) and os.date("%Y-%m-%d %H:%M:%S") or ""
		out = string.format("\n===== Diagnose von %s %s =====\n", player:GetName(), stamp) .. out
		Console.Log("[DeathBox] Diagnose von %s empfangen (%d Teile) -> %s", player:GetName(), total, FILE)
	end
	if (index >= total) then out = out .. "\n" end
	local ok, err = pcall(Append, out)
	if (not ok) then Console.Warn("[DeathBox] Diagnose nicht geschrieben: %s", tostring(err)) end
end)

Player.Subscribe("Destroy", function(player)
	received[player:GetID()] = nil
end)
