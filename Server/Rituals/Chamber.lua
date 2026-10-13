-- Server/Rituals/Chamber.lua
-- Ritual "The Chamber": Revolver mit gemeinsamer Trommel.
--
-- Regeln:
--   - 6 Kammern, 1 Kugel. Die Trommel bleibt zwischen den Zuegen bestehen,
--     die Chance steigt sichtbar: 1/6 -> 1/5 -> ... -> 1/1.
--   - Der gewaehlte Spieler waehlt ein Ziel (einen anderen lebenden Spieler).
--   - Waehlt er nicht rechtzeitig, zielt er auf sich selbst.
--   - Nach einem Schuss wird neu geladen.
--
-- Fairness: Die Position der Kugel wird beim Laden zufaellig bestimmt und bleibt geheim.
-- Weil die Kugel gleichverteilt liegt, ist die Chance fuer den naechsten Abzug
-- exakt 1 / (verbleibende Kammern) – genau das zeigt das HUD an.

local Config = DeathBox.Config
local Text = DeathBox.Text

local Chamber = {
	id = "chamber",
	weight = 3,
	min_alive = 2,
}

-- Gemeinsame Trommel fuer die ganze Partie
local cylinder = { size = 6, fired = 0, bullet = 1 }

local function Reload()
	cylinder.size = Config.CHAMBER.CHAMBERS
	cylinder.fired = 0
	cylinder.bullet = math.random(cylinder.size)
end

function Chamber.OnGameStart()
	Reload()
end

-- Oeffentliche Daten fuers HUD (die Kugelposition bleibt geheim!)
function Chamber.GetPublic(ctx)
	return {
		chambers = cylinder.size,
		spent = cylinder.fired,
		target = ctx.data.target,
	}
end

-- Ablauf -------------------------------------------------------------

local Pull   -- vorwaerts deklariert

local function Aim(ctx, target, hesitated)
	ctx.data.target = target
	local values = { name = ctx:Name(ctx.actor_index), target = ctx:Name(target) }

	if (hesitated) then
		ctx:Say(Text.MADAME.CHAMBER_HESITATE, values)
	else
		ctx:Say(Text.MADAME.CHAMBER_AIM, values)
	end

	DeathBox.Net.Fx("aim", target)
	ctx:Push()
	ctx:After(Config.CHAMBER.AIM_TIME, function() Pull(ctx) end)
end

Pull = function(ctx)
	local target = ctx.data.target
	local values = { name = ctx:Name(ctx.actor_index), target = ctx:Name(target) }

	-- Ziel ist inzwischen weg (Server verlassen): Trommel dreht sich nicht weiter
	if (not ctx:IsAlive(target)) then
		ctx:Say(Text.MADAME.TARGET_FLED, values)
		ctx:After(Config.CHAMBER.RESULT_TIME, function() ctx:Finish() end)
		return
	end

	cylinder.fired = cylinder.fired + 1
	local loaded = (cylinder.fired == cylinder.bullet)

	if (not loaded) then
		DeathBox.Net.Fx("click", target)
		ctx:Say(Text.MADAME.CHAMBER_CLICK, values)
	else
		DeathBox.Net.Fx("bang", target)
		local result = ctx:Kill(target)
		if (result == "ward") then
			ctx:Say(Text.MADAME.WARD_SAVE, values)
		else
			ctx:Say(Text.MADAME.CHAMBER_BANG, values)
		end
		Reload()
	end

	ctx:Push()
	ctx:After(Config.CHAMBER.RESULT_TIME, function() ctx:Finish() end)
end

function Chamber.Start(ctx)
	local actor = ctx.actor_index
	local targets = ctx:AliveSeats(actor)

	-- Sicherheitsnetz: niemand mehr da, auf den man zielen koennte
	if (#targets == 0) then
		ctx:Finish()
		return
	end

	ctx:Say(Text.MADAME.CHAMBER_HAND, { name = ctx:Name(actor) })
	ctx:Ask(actor, "target", targets, Config.CHAMBER.CHOOSE_TIME, function()
		Aim(ctx, actor, true)   -- zu langsam: Waffe zeigt auf den Schuetzen selbst
	end)
end

function Chamber.OnInput(ctx, seat_index, choice)
	if (seat_index ~= ctx.actor_index) then return end
	Aim(ctx, choice, false)
end

-- Schuetze verlaesst den Tisch, bevor er gewaehlt hat: Ritual endet ohne Schuss
function Chamber.OnSeatLeft(ctx, index)
	if (index == ctx.actor_index and not ctx.data.target) then
		ctx:Finish()
	end
	-- Ziel verlaesst den Tisch: wird in Pull() behandelt ("fled")
end

DeathBox.Rituals.Register(Chamber)
