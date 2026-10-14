-- Server/Events/Gallery.lua
-- Event "Shooting Gallery": Jack spielt Schiessbude. Er schiesst nacheinander auf den Gewaehlten und dessen
-- linken und rechten lebenden Nachbarn, wie auf drei Enten in einer Reihe.
--
-- Regeln:
--   - Drei Ziele in Sitzreihenfolge: linker Nachbar, Gewaehlter, rechter Nachbar. Jack legt auf jedes einzeln an.
--   - Kein Ausweichen, keine Wahl. Nur Karten helfen: Ricochet lenkt die Kugel ab, Safety rettet (Context:Shoot).
--   - Kommt nur an grossen Tischen, solange 17 oder mehr leben (Config.EVENT_WEIGHTS): Mit 32 Plaetzen wuerde
--     die Show sonst doppelt so lange dauern wie mit 16, weil jede Runde ihre Spannungszeit braucht.
--   - Lebt nur noch einer, hoert Jack auf (nie alle auf einmal erschiessen).
-- Darstellung wie beim Angry Clown, nur mehrmals: "angry_aim" -> "revolver_shot" (ohne shooter) -> Folgen.
--
-- Jeder geplante Schritt traegt eine Nummer (data.step). Geht das Ziel, auf das Jack gerade anlegt,
-- wird die Nummer erhoeht, der alte Schuss verfaellt und Jack schwenkt sofort zum naechsten.

local Config = DeathBox.Config
local Text = DeathBox.Text

local CFG = Config.GALLERY

local Gallery = {
	id = "gallery",
	min_alive = 4,   -- drei Ziele und mindestens ein Zuschauer, der uebrig bleiben kann
}

function Gallery.GetPublic(ctx)
	return { targets = ctx.data.targets, aim = ctx.data.aim }
end

-- Plant einen Schritt, der verfaellt, sobald sich die Lage aendert (siehe Kopf)
local function Later(ctx, seconds, callback)
	local data = ctx.data
	data.step = data.step + 1
	local step = data.step
	ctx:After(seconds, function()
		if (data.step == step) then callback() end
	end)
end

local AimNext

local function Fire(ctx, target)
	local data = ctx.data
	data.aim = nil
	ctx.match:SetTimer(nil)
	ctx:Shoot(target, {}, function(result, hit)
		if (result == "safety") then
			ctx:Show("survive", { seat = hit, name = ctx:Name(hit) })
			ctx:Say(Text.JACK.SAFETY_SAVE, { target = ctx:Name(hit) })
		elseif (result == "dead") then
			ctx:Say(hit == target and Text.JACK.GALLERY_HIT or Text.JACK.RICOCHET_HIT, { target = ctx:Name(hit) })
			ctx:Stage("bang", { target = ctx:Name(hit) })
		end
		ctx:Push()
		Later(ctx, CFG.GAP, function() AimNext(ctx) end)
	end)
end

-- Naechstes lebendes Ziel anvisieren. Keins mehr da (oder nur noch ein Lebender am Tisch): Ende.
AimNext = function(ctx)
	local data = ctx.data
	local target
	while (data.next <= #data.targets) do
		local candidate = data.targets[data.next]
		data.next = data.next + 1
		if (ctx:IsAlive(candidate)) then
			target = candidate
			break
		end
	end
	if (not target or #ctx:AliveSeats() <= 1) then
		data.aim, data.focus = nil, nil
		data.step = data.step + 1   -- geplante Schuesse verfallen
		ctx:Stage("done")
		ctx:Conclude(CFG.RESULT_TIME)
		return
	end

	local aim_time = (data.aims == 0) and CFG.FIRST_AIM or CFG.AIM_TIME
	data.aims = data.aims + 1
	data.aim = target
	data.focus = target
	ctx:Show("angry_aim", { seat = target, aim_time = aim_time })
	ctx:Stage("aim", { target = ctx:Name(target) })
	ctx:Fx("aim", target)
	ctx.match:SetTimer(aim_time)
	ctx:Push()
	Later(ctx, aim_time, function() Fire(ctx, target) end)
end

function Gallery.Start(ctx)
	local data = ctx.data
	local chosen = ctx.actor_index
	local left, right = ctx:NextAlive(chosen, -1), ctx:NextAlive(chosen, 1)
	data.targets = { left, chosen, right }
	data.next = 1     -- naechster Eintrag in targets
	data.aims = 0     -- wie oft Jack schon angelegt hat (das erste Mal dauert laenger)
	data.step = 0
	data.focus = chosen

	ctx:Say(Text.JACK.GALLERY_START, { name = ctx:Name(chosen), left = ctx:Name(left), right = ctx:Name(right) })
	ctx:Push()
	AimNext(ctx)
end

function Gallery.OnInput()
	-- Keine Eingaben: Jack schiesst allein
end

-- Geht das Ziel, auf das Jack gerade anlegt, schwenkt er sofort weiter. Andere Abgaenge erledigt AimNext
-- (Weggegangene werden uebersprungen). Der Gewaehlte darf gehen, ohne dass die Schiessbude schliesst.
function Gallery.OnSeatLeft(ctx, index, was_alive)
	if (was_alive and index == ctx.data.aim) then
		ctx.data.aim = nil
		ctx.match:SetTimer(nil)
		AimNext(ctx)
	end
end

DeathBox.Events.Register(Gallery)
