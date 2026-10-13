-- Server/GameState.lua
-- Der Ablauf einer Partie als Zustandsautomat:
--
--   WAITING ──(genug Spieler)──> COUNTDOWN ──(Zeit um)──> PLAYING ──(1 uebrig)──> ENDED ──(Zeit um)──> WAITING
--
-- Es laeuft immer hoechstens EIN Timer gleichzeitig (Game.timer_id). Jeder Zustandswechsel
-- loescht den alten Timer zuerst. Dadurch koennen keine zwei Zuege gleichzeitig ablaufen.

local Config = DeathBox.Config
local DBTable = DeathBox.Table
local Characters = DeathBox.Characters

local STATE = {
	WAITING = "WAITING",
	COUNTDOWN = "COUNTDOWN",
	PLAYING = "PLAYING",
	ENDED = "ENDED",
}

DeathBox.Game = {
	STATE = STATE,
	state = STATE.WAITING,
	current_index = 0,   -- Platz, der gerade dran ist (0 = noch niemand)
	timer_id = nil,
	bot_count = 0,       -- Anzahl Test-Bots fuer die naechste Partie (nur Debug)
}

local Game = DeathBox.Game

-- ===================================================================
-- Hilfsfunktionen
-- ===================================================================

local function Say(text)
	Chat.BroadcastMessage(text)
end

local function Highlight(name)
	return "<cyan>" .. name .. "</>"
end

local function Log(text, ...)
	Console.Log("[DeathBox] " .. text, ...)
end

-- Ersetzt den laufenden Timer durch einen neuen
local function SetTimer(callback, seconds)
	Game.ClearTimer()
	Game.timer_id = Timer.SetTimeout(function()
		Game.timer_id = nil
		callback()
	end, seconds * 1000)
end

function Game.ClearTimer()
	if (Game.timer_id and Timer.IsValid(Game.timer_id)) then
		Timer.ClearTimeout(Game.timer_id)
	end
	Game.timer_id = nil
end

local function SetState(new_state)
	Log("Zustand: %s -> %s", Game.state, new_state)
	Game.state = new_state
end

-- Alle verbundenen Spieler, optional ohne einen bestimmten (z. B. den, der gerade geht)
local function GetConnectedPlayers(excluded_player)
	local players = {}
	for _, player in pairs(Player.GetPairs()) do
		if (player ~= excluded_player and player:IsValid()) then
			table.insert(players, player)
		end
	end
	return players
end

-- Wie viele Teilnehmer eine Partie haette (echte Spieler bis MAX_PLAYERS + Bots)
local function CountParticipants(excluded_player)
	local real = math.min(#GetConnectedPlayers(excluded_player), Config.MAX_PLAYERS)
	return math.min(real + Game.bot_count, Config.MAX_PLAYERS)
end

-- ===================================================================
-- Lobby und Countdown
-- ===================================================================

-- Startet den Countdown, wenn genug Teilnehmer da sind
function Game.CheckAutoStart()
	if (Game.state ~= STATE.WAITING) then return end

	if (CountParticipants() >= Config.MIN_PLAYERS) then
		Game.StartCountdown()
	end
end

function Game.StartCountdown()
	SetState(STATE.COUNTDOWN)
	Say("Die Partie beginnt in " .. Config.START_COUNTDOWN .. " Sekunden ...")
	SetTimer(Game.StartGame, Config.START_COUNTDOWN)
end

-- Bricht den Countdown ab, falls jemand geht und es nicht mehr reicht
local function CancelCountdownIfTooFew(excluded_player)
	if (Game.state ~= STATE.COUNTDOWN) then return end

	if (CountParticipants(excluded_player) < Config.MIN_PLAYERS) then
		Game.ClearTimer()
		SetState(STATE.WAITING)
		Say("Countdown abgebrochen – zu wenige Spieler.")
	end
end

-- ===================================================================
-- Partie
-- ===================================================================

function Game.StartGame()
	-- Erneut pruefen: waehrend des Countdowns koennen Spieler gegangen sein
	if (CountParticipants() < Config.MIN_PLAYERS) then
		SetState(STATE.WAITING)
		Say("Zu wenige Spieler – warte auf weitere.")
		return
	end

	-- Echte Spieler bis zur Platzgrenze, Rest wird mit Bots aufgefuellt
	local players = GetConnectedPlayers()
	local seated_players = {}
	for i = 1, math.min(#players, Config.MAX_PLAYERS) do
		table.insert(seated_players, players[i])
	end
	local bots = math.min(Game.bot_count, Config.MAX_PLAYERS - #seated_players)

	DBTable.Build(seated_players, bots)
	Characters.ReviveAll()

	-- Jeden echten Spieler an seinen Platz am Tisch stellen
	local seat_count = #DBTable.seats
	for index, seat in ipairs(DBTable.seats) do
		if (seat.player) then
			local location, rotation = DeathBox.Arena.GetSeatTransform(index, seat_count)
			Characters.PlaceAtSeat(seat.player, location, rotation)
		end
	end

	SetState(STATE.PLAYING)
	Game.current_index = 0

	Say("Die Partie beginnt! Sitzordnung: " .. DBTable.OrderAsText())
	if (#players > #seated_players) then
		Say("Der Tisch ist voll – weitere Spieler schauen zu.")
	end

	SetTimer(Game.NextTurn, Config.BETWEEN_TURNS)
end

-- Der naechste lebende Spieler im Uhrzeigersinn ist dran
function Game.NextTurn()
	if (Game.state ~= STATE.PLAYING) then return end

	if (DBTable.CountAlive() <= 1) then
		Game.EndGame()
		return
	end

	local index = DBTable.NextAliveIndex(Game.current_index)
	if (not index) then
		Game.EndGame()
		return
	end

	Game.current_index = index
	local seat = DBTable.seats[index]

	Say("[SPIELLEITER] reicht " .. Highlight(seat.name) .. " die Pistole ...")
	SetTimer(Game.ResolveTurn, Config.TURN_SUSPENSE)
end

-- Der Spieler am Zug drueckt ab
function Game.ResolveTurn()
	if (Game.state ~= STATE.PLAYING) then return end

	local seat = DBTable.seats[Game.current_index]

	-- Sicherheitsnetz: Spieler ist in der Zwischenzeit ausgeschieden (z. B. Server verlassen)
	if (not seat or not seat.alive) then
		Game.NextTurn()
		return
	end

	local fired = math.random() < Config.SHOT_CHANCE

	if (not fired) then
		Say("*klick* – " .. Highlight(seat.name) .. " hat Glueck gehabt.")
	elseif (DBTable.ConsumeCard(seat, "shield")) then
		local card = DeathBox.Cards.shield
		Say("PENG! Aber " .. Highlight(seat.name) .. " wird von " .. card.name .. " gerettet!")
	else
		Say("PENG! " .. Highlight(seat.name) .. " ist ausgeschieden.")
		Game.Eliminate(seat)
	end

	if (DBTable.CountAlive() <= 1) then
		SetTimer(Game.EndGame, Config.BETWEEN_TURNS)
	else
		SetTimer(Game.NextTurn, Config.BETWEEN_TURNS)
	end
end

function Game.Eliminate(seat)
	seat.alive = false
	if (seat.player) then
		Characters.Kill(seat.player)
	end
	Log("%s ausgeschieden, noch %d im Spiel", seat.name, DBTable.CountAlive())
end

function Game.EndGame()
	if (Game.state ~= STATE.PLAYING) then return end
	SetState(STATE.ENDED)

	local winner = DBTable.GetLastAlive()
	if (winner) then
		Say(Highlight(winner.name) .. " hat ueberlebt und gewinnt die Partie!")
	else
		Say("Niemand hat ueberlebt.")
	end

	SetTimer(Game.ReturnToLobby, Config.GAME_END_DELAY)
end

function Game.ReturnToLobby()
	Game.ClearTimer()
	DBTable.Clear()
	Game.current_index = 0
	SetState(STATE.WAITING)
	Characters.ReviveAll()

	Say("Zurueck in der Lobby.")
	Game.CheckAutoStart()
end

-- ===================================================================
-- Spieler kommen und gehen
-- ===================================================================

function Game.OnPlayerJoin(player)
	if (Game.state == STATE.PLAYING or Game.state == STATE.ENDED) then
		Chat.SendMessage(player, "Gerade laeuft eine Partie. Du spielst ab der naechsten mit.")
		return
	end
	Game.CheckAutoStart()
end

-- Wer geht, zaehlt als ausgeschieden
function Game.OnPlayerLeave(player)
	CancelCountdownIfTooFew(player)

	if (Game.state ~= STATE.PLAYING) then return end

	local seat, index = DBTable.FindSeatByPlayer(player)
	if (not seat) then return end   -- war nur Zuschauer

	seat.player = nil               -- keine Referenz auf ein ungueltiges Player-Objekt behalten

	if (not seat.alive) then return end

	seat.alive = false
	Say(Highlight(seat.name) .. " hat den Tisch verlassen und scheidet aus.")

	if (DBTable.CountAlive() <= 1) then
		Game.ClearTimer()
		Game.EndGame()
	elseif (index == Game.current_index) then
		-- Er war gerade dran: laufenden Zug abbrechen, naechster ist dran
		SetTimer(Game.NextTurn, Config.BETWEEN_TURNS)
	end
end

-- ===================================================================
-- Debug-Befehle (nur wenn Config.DEBUG_COMMANDS = true)
-- ===================================================================

Game.DebugCommands = {
	-- /start  – Partie sofort starten
	start = function(player)
		if (Game.state ~= STATE.WAITING and Game.state ~= STATE.COUNTDOWN) then
			Chat.SendMessage(player, "Es laeuft bereits eine Partie.")
			return
		end
		if (CountParticipants() < Config.MIN_PLAYERS) then
			Chat.SendMessage(player, "Zu wenige Teilnehmer. Mit /bots 3 kannst du Test-Bots hinzufuegen.")
			return
		end
		Game.ClearTimer()
		Game.StartGame()
	end,

	-- /bots <anzahl>  – Test-Bots fuer die naechste Partie
	bots = function(player, argument)
		local count = tonumber(argument)
		if (not count or count < 0 or count > Config.MAX_BOTS or count % 1 ~= 0) then
			Chat.SendMessage(player, "Benutzung: /bots <0 bis " .. Config.MAX_BOTS .. ">")
			return
		end
		Game.bot_count = count
		Chat.SendMessage(player, "Bots fuer die naechste Partie: " .. count)
		CancelCountdownIfTooFew(nil)
		Game.CheckAutoStart()
	end,

	-- /stop  – laufende Partie abbrechen
	stop = function(player)
		if (Game.state == STATE.WAITING) then
			Chat.SendMessage(player, "Es laeuft keine Partie.")
			return
		end
		Say("Partie abgebrochen von " .. Highlight(player:GetName()) .. ".")
		Game.ReturnToLobby()
	end,

	-- /status  – aktuellen Zustand anzeigen
	status = function(player)
		Chat.SendMessage(player, string.format("Zustand: %s | Bots: %d | Lebend: %d",
			Game.state, Game.bot_count, DBTable.CountAlive()))
		if (#DBTable.seats > 0) then
			Chat.SendMessage(player, "Sitzordnung: " .. DBTable.OrderAsText())
		end
	end,
}

-- Gibt true zurueck, wenn die Nachricht ein Befehl war (dann nicht im Chat anzeigen)
function Game.HandleChatCommand(player, message)
	if (not Config.DEBUG_COMMANDS) then return false end

	local command, argument = string.match(message, "^/(%a+)%s*(.*)$")
	if (not command) then return false end

	local handler = Game.DebugCommands[string.lower(command)]
	if (not handler) then return false end

	handler(player, argument)
	return true
end
