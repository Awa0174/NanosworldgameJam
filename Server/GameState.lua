-- Server/GameState.lua
-- Der Ablauf einer Séance als Zustandsautomat:
--
--   WAITING ──(genug Spieler)──> COUNTDOWN ──(Zeit um)──> PLAYING ──(1 uebrig)──> ENDED ──(Zeit um)──> WAITING
--
-- Innerhalb von PLAYING wiederholt sich:
--   NextTurn: naechster Lebender im Uhrzeigersinn + Ritual auswaehlen, Madame verkuendet
--   -> Rituals.Run(...)  (das Ritual steuert sich selbst)
--   -> OnRitualFinished: Sieger pruefen, dann naechster Zug
--
-- Timer-Regel: GameState hat genau EINEN eigenen Timer (zwischen den Ritualen),
-- das laufende Ritual hat seinen eigenen (Rituals.timer_id). Die beiden laufen nie gleichzeitig.

local Config = DeathBox.Config
local Text = DeathBox.Text
local DBTable = DeathBox.Table
local Characters = DeathBox.Characters
local Net = DeathBox.Net
local Rituals = DeathBox.Rituals

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
	winner_index = 0,    -- Sieger der letzten Partie (fuers HUD)
	timer_id = nil,
	bot_count = 0,       -- Anzahl Test-Bots fuer die naechste Partie (nur Debug)
}

local Game = DeathBox.Game

-- ===================================================================
-- Hilfsfunktionen
-- ===================================================================

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
function Game.GetConnectedPlayers(excluded_player)
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
	local real = math.min(#Game.GetConnectedPlayers(excluded_player), Config.MAX_PLAYERS)
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
	else
		Net.PushState()   -- Lobby-Anzeige "x/2" aktualisieren
	end
end

function Game.StartCountdown()
	SetState(STATE.COUNTDOWN)
	Net.SetTimer(Config.START_COUNTDOWN)
	Net.PushState()
	SetTimer(Game.StartGame, Config.START_COUNTDOWN)
end

-- Bricht den Countdown ab, falls jemand geht und es nicht mehr reicht
local function CancelCountdownIfTooFew(excluded_player)
	if (Game.state ~= STATE.COUNTDOWN) then return end

	if (CountParticipants(excluded_player) < Config.MIN_PLAYERS) then
		Game.ClearTimer()
		Net.SetTimer(nil)
		SetState(STATE.WAITING)
		Net.PushState()
	end
end

-- ===================================================================
-- Partie
-- ===================================================================

function Game.StartGame()
	-- Erneut pruefen: waehrend des Countdowns koennen Spieler gegangen sein
	if (CountParticipants() < Config.MIN_PLAYERS) then
		Net.SetTimer(nil)
		SetState(STATE.WAITING)
		Net.PushState()
		return
	end

	-- Echte Spieler bis zur Platzgrenze, Rest wird mit Bots aufgefuellt
	local players = Game.GetConnectedPlayers()
	local seated_players = {}
	for i = 1, math.min(#players, Config.MAX_PLAYERS) do
		table.insert(seated_players, players[i])
	end
	local bots = math.min(Game.bot_count, Config.MAX_PLAYERS - #seated_players)

	DBTable.Build(seated_players, bots)
	Characters.ReviveAll()
	Rituals.ResetForGame()

	-- Jeden echten Spieler auf seinen Stuhl setzen
	local seat_count = #DBTable.seats
	for index, seat in ipairs(DBTable.seats) do
		if (seat.player) then
			Characters.SitOnChair(seat.player, DeathBox.Arena.GetChairIndex(index, seat_count))
		end
	end

	SetState(STATE.PLAYING)
	Game.current_index = 0
	Game.winner_index = 0
	Net.SetTimer(nil)

	Net.Say(Text.Format(Text.MADAME.GAME_START))
	Net.Fx("start", 0)
	Net.PushState()

	SetTimer(Game.NextTurn, Config.ANNOUNCE_TIME + Config.BETWEEN_TURNS)
end

-- Der naechste lebende Spieler im Uhrzeigersinn ist dran, Madame waehlt das Ritual
function Game.NextTurn()
	if (Game.state ~= STATE.PLAYING) then return end

	local alive = DBTable.CountAlive()
	if (alive <= 1) then
		Game.EndGame()
		return
	end

	local index = DBTable.NextAliveIndex(Game.current_index)
	local ritual = Rituals.Pick(alive)
	if (not index or not ritual) then
		Game.EndGame()
		return
	end

	Game.current_index = index
	local seat = DBTable.seats[index]

	Net.Say(Text.Format(Text.MADAME.CHOSEN, { name = seat.name }))
	Net.Fx("chosen", index)
	Net.PushState()

	-- Kurze Pause fuer die Spannung, dann beginnt das Ritual
	SetTimer(function()
		local current = DBTable.seats[index]
		if (Game.state ~= STATE.PLAYING) then return end
		if (not current or not current.alive) then
			Game.NextTurn()   -- in der Zwischenzeit gegangen
			return
		end
		Rituals.Run(ritual, index, Game.OnRitualFinished)
	end, Config.ANNOUNCE_TIME)
end

function Game.OnRitualFinished()
	if (Game.state ~= STATE.PLAYING) then return end

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
	Net.PushState()
end

function Game.EndGame()
	if (Game.state ~= STATE.PLAYING) then return end
	Rituals.Cancel()
	SetState(STATE.ENDED)

	local winner, winner_index = nil, 0
	for index, seat in ipairs(DBTable.seats) do
		if (seat.alive) then
			if (winner) then winner = nil break end
			winner, winner_index = seat, index
		end
	end

	if (winner) then
		Game.winner_index = winner_index
		Net.Say(Text.Format(Text.MADAME.WINNER, { winner = winner.name }))
		Net.Fx("winner", winner_index)
	else
		Net.Say(Text.Format(Text.MADAME.NO_WINNER))
	end

	Net.SetTimer(Config.GAME_END_DELAY)
	Net.PushState()
	SetTimer(Game.ReturnToLobby, Config.GAME_END_DELAY)
end

function Game.ReturnToLobby()
	Game.ClearTimer()
	Rituals.Cancel()
	DBTable.Clear()
	Game.current_index = 0
	Net.SetTimer(nil)
	SetState(STATE.WAITING)
	Characters.ReviveAll()

	Net.PushState()
	Game.CheckAutoStart()
end

-- ===================================================================
-- Spieler kommen und gehen
-- ===================================================================

function Game.OnPlayerJoin(player)
	if (Game.state == STATE.PLAYING or Game.state == STATE.ENDED) then
		Chat.SendMessage(player, Text.LOBBY_SPECTATING)
		Net.PushState()
		return
	end
	Game.CheckAutoStart()
end

-- Wer geht, zaehlt als ausgeschieden
function Game.OnPlayerLeave(player)
	CancelCountdownIfTooFew(player)

	if (Game.state ~= STATE.PLAYING) then
		Net.PushState()
		return
	end

	local seat, index = DBTable.FindSeatByPlayer(player)
	if (not seat) then return end   -- war nur Zuschauer

	seat.player = nil               -- keine Referenz auf ein ungueltiges Player-Objekt behalten

	if (not seat.alive) then
		Net.PushState()
		return
	end

	seat.alive = false
	Net.Say(Text.Format(Text.MADAME.LEFT_TABLE, { name = seat.name }))

	if (DBTable.CountAlive() <= 1) then
		Rituals.Cancel()
		Game.ClearTimer()
		Game.EndGame()
		return
	end

	Rituals.OnSeatLeft(index)
	Net.PushState()
end

-- ===================================================================
-- Debug-Befehle (nur wenn Config.DEBUG_COMMANDS = true)
-- ===================================================================

Game.DebugCommands = {
	-- /start  – Partie sofort starten
	start = function(player)
		if (Game.state ~= STATE.WAITING and Game.state ~= STATE.COUNTDOWN) then
			Chat.SendMessage(player, "A séance is already running.")
			return
		end
		if (CountParticipants() < Config.MIN_PLAYERS) then
			Chat.SendMessage(player, "Not enough players. Add test bots with /bots 3")
			return
		end
		Game.ClearTimer()
		Game.StartGame()
	end,

	-- /bots <anzahl>  – Test-Bots fuer die naechste Partie
	bots = function(player, argument)
		local count = tonumber(argument)
		if (not count or count < 0 or count > Config.MAX_BOTS or count % 1 ~= 0) then
			Chat.SendMessage(player, "Usage: /bots <0-" .. Config.MAX_BOTS .. ">")
			return
		end
		Game.bot_count = count
		Chat.SendMessage(player, "Bots for the next séance: " .. count)
		CancelCountdownIfTooFew(nil)
		Game.CheckAutoStart()
	end,

	-- /stop  – laufende Partie abbrechen
	stop = function(player)
		if (Game.state == STATE.WAITING) then
			Chat.SendMessage(player, "No séance is running.")
			return
		end
		Chat.BroadcastMessage("Séance stopped by " .. player:GetName() .. ".")
		Game.ReturnToLobby()
	end,

	-- /ritual <id>  – naechstes Ritual erzwingen
	ritual = function(player, argument)
		local id = string.lower(argument or "")
		if (not Rituals.Exists(id)) then
			Chat.SendMessage(player, "Usage: /ritual <" .. table.concat(Rituals.GetIds(), "|") .. ">")
			return
		end
		Rituals.forced_next = id
		Chat.SendMessage(player, "Next ritual: " .. id)
	end,

	-- /status  – aktuellen Zustand anzeigen
	status = function(player)
		local ritual = Rituals.active and Rituals.active.id or "-"
		Chat.SendMessage(player, string.format("State: %s | Ritual: %s | Bots: %d | Alive: %d",
			Game.state, ritual, Game.bot_count, DBTable.CountAlive()))
		if (#DBTable.seats > 0) then
			Chat.SendMessage(player, "Seats: " .. DBTable.OrderAsText())
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
