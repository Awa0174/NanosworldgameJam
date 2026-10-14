-- Server/Events/AngryClown.lua
-- Event "Angry Clown": Jack verliert die Geduld und schiesst selbst auf den gewaehlten Spieler.
--
-- Regeln:
--   - Kein Ausweichen, keine Wahl. Nur Karten helfen: Ricochet lenkt die Kugel ab, Safety rettet.
--   - Kommt haeufiger, solange viele leben (Config.EVENT_WEIGHTS): so bleibt eine Show mit 16-32 Spielern
--     im Tempo, ohne die Spannung (Spieluhr, Stille, POP) zu kuerzen.

local Config = DeathBox.Config
local Text = DeathBox.Text

local AngryClown = {
	id = "angry",
	min_alive = 3,
}

function AngryClown.Start(ctx)
	local victim = ctx.actor_index
	local values = { name = ctx:Name(victim) }
	ctx:Say(Text.JACK.ANGRY_START, values)
	ctx:Show("angry_aim", { seat = victim, aim_time = Config.ANGRY.AIM_TIME })
	ctx:Fx("aim", victim)
	ctx:Stage("aim")
	ctx.match:SetTimer(Config.ANGRY.AIM_TIME)
	ctx:Push()

	ctx:After(Config.ANGRY.AIM_TIME, function()
		ctx.match:SetTimer(nil)
		ctx.data.fired = true
		-- Jack schiesst selbst: "revolver_shot" ohne shooter
		ctx:Shoot(victim, {}, function(result, hit)
			if (result == "safety") then
				ctx:Show("survive", { seat = hit, name = ctx:Name(hit) })
				ctx:Say(Text.JACK.SAFETY_SAVE, { target = ctx:Name(hit) })
			elseif (result == "dead") then
				if (hit == victim) then
					ctx:Say(Text.JACK.ANGRY_BANG, values)
				else
					ctx:Say(Text.JACK.RICOCHET_HIT, { target = ctx:Name(hit) })
				end
				ctx:Stage("bang", { target = ctx:Name(hit) })
			end
			ctx:Conclude(Config.ANGRY.RESULT_TIME)
		end)
	end)
end

function AngryClown.OnInput()
	-- Keine Eingaben: Jack entscheidet allein
end

-- Das Ziel geht, bevor Jack schiesst: Event endet. Ist der Schuss schon gefallen (abgelenkte Kugel unterwegs),
-- laeuft es zu Ende, damit der Querschlaeger sein neues Opfer trotzdem trifft.
function AngryClown.OnSeatLeft(ctx, index, was_alive)
	if (was_alive and index == ctx.actor_index and not ctx.data.fired) then ctx:Finish() end
end

DeathBox.Events.Register(AngryClown)
