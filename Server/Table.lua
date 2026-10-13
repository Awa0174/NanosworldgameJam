-- Server/Table.lua
-- Der Tisch: wer sitzt wo, wer lebt noch, wer hat welche Karten.
-- Ein Sitzplatz ("seat") ist eine Tabelle:
--   { name = "Awa", player = <Player> oder nil, is_bot = false, alive = true, cards = { "shield" } }
-- Bots haben kein Player-Objekt; sie sind nur zum Testen mit wenigen Spielern da.

DeathBox.Table = {
	seats = {},
}

local DBTable = DeathBox.Table

-- Fisher-Yates-Shuffle: mischt eine Liste zufaellig (veraendert die Liste selbst)
local function Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Kopiert die Startkarten, damit nicht alle Sitzplaetze dieselbe Tabelle teilen
local function CopyStartCards()
	local cards = {}
	for _, card_id in ipairs(DeathBox.Config.START_CARDS) do
		if (DeathBox.IsValidCard(card_id)) then
			table.insert(cards, card_id)
		else
			Console.Warn("[DeathBox] Unbekannte Startkarte '%s' in Config.START_CARDS", tostring(card_id))
		end
	end
	return cards
end

-- Baut den Tisch fuer eine neue Partie: echte Spieler + Bots, zufaellig gemischt
function DBTable.Build(players, bot_count)
	local seats = {}

	for _, player in ipairs(players) do
		table.insert(seats, {
			name = player:GetName(),
			player = player,
			is_bot = false,
			alive = true,
			cards = CopyStartCards(),
		})
	end

	for i = 1, bot_count do
		table.insert(seats, {
			name = "Bot " .. i,
			player = nil,
			is_bot = true,
			alive = true,
			cards = CopyStartCards(),
		})
	end

	Shuffle(seats)
	DBTable.seats = seats
	return seats
end

function DBTable.Clear()
	DBTable.seats = {}
end

-- Sucht den Sitzplatz eines Spielers (nil, wenn er nicht mitspielt)
function DBTable.FindSeatByPlayer(player)
	for index, seat in ipairs(DBTable.seats) do
		if (seat.player == player) then
			return seat, index
		end
	end
	return nil, nil
end

-- Naechster lebender Platz im Uhrzeigersinn (= aufsteigender Index, am Ende wieder vorne).
-- from_index = 0 bedeutet: beim ersten Platz anfangen.
function DBTable.NextAliveIndex(from_index)
	local count = #DBTable.seats
	if (count == 0) then return nil end

	for step = 1, count do
		local index = ((from_index + step - 1) % count) + 1
		if (DBTable.seats[index].alive) then
			return index
		end
	end
	return nil
end

function DBTable.CountAlive()
	local alive = 0
	for _, seat in ipairs(DBTable.seats) do
		if (seat.alive) then alive = alive + 1 end
	end
	return alive
end

-- Gibt den einzigen Ueberlebenden zurueck (nil, wenn es nicht genau einen gibt)
function DBTable.GetLastAlive()
	local last = nil
	for _, seat in ipairs(DBTable.seats) do
		if (seat.alive) then
			if (last) then return nil end
			last = seat
		end
	end
	return last
end

-- Prueft, ob ein Sitzplatz eine Karte hat, und entfernt sie. Gibt true zurueck, wenn verbraucht.
function DBTable.ConsumeCard(seat, card_id)
	for i, id in ipairs(seat.cards) do
		if (id == card_id) then
			table.remove(seat.cards, i)
			return true
		end
	end
	return false
end

-- Sitzordnung als lesbarer Text, z. B. "1. Awa  2. Bot 1  3. Max"
function DBTable.OrderAsText()
	local parts = {}
	for index, seat in ipairs(DBTable.seats) do
		table.insert(parts, index .. ". " .. seat.name)
	end
	return table.concat(parts, "  ")
end
