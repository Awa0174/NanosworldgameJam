-- Shared/Text.lua
-- Alle Texte, die Spieler sehen, an einer Stelle (Englisch).
-- Platzhalter wie {name}, {target}, {winner} werden mit DeathBox.Text.Format ersetzt.
-- Jack hat pro Situation mehrere Saetze, damit er sich nicht staendig wiederholt.

DeathBox = DeathBox or {}

-- Zeilen, die von der Config abhaengen (Shared/Index.lua laedt Config.lua vor dieser Datei)
local Cfg = DeathBox.Config or {}
local LOAD_EXTRA = not Cfg.REVOLVER or Cfg.REVOLVER.LOAD_EXTRA ~= false
local REVOLVER_RULES = LOAD_EXTRA
	and "Aim at someone and pull the trigger. Click: they get the gun. Jack loads another bullet after every click."
	or "Aim at someone and pull the trigger. Click: they get the gun. One bullet - the odds get worse with every click."
local REVOLVER_LOAD_LINE = LOAD_EXTRA and "After every click Jack loads one more bullet."
	or "One bullet in six chambers - every click makes it worse."
local KNIFE_KEYS_LINE = string.format("%d keys in a row, each one faster.", Cfg.KNIFE and #Cfg.KNIFE.WINDOWS or 3)
local FIRE_CLICKS_LINE = string.format("Click it %d times before the time runs out.", Cfg.FIRE and Cfg.FIRE.CLICKS or 10)

DeathBox.Text = {
	TITLE = "Jack's Last Show",
	HOST = "Jack",

	HUB_JOIN = "Welcome to the fairground, {name}. The show is about to begin...",
	QUEUE_WAITING = "Waiting for more victims ({count}/{needed})",
	QUEUE_COUNTDOWN = "Next show starts in",
	MATCH_SPECTATING = "You are out. Watch the show... or press NEXT SHOW to play again.",
	JOIN_WAIT = {
		"A show is already running! Watch for a moment - you take over a puppet's seat when the next round starts.",
	},
	JOIN_MOVED = "No puppet seat left at this table - off to the next show!",

	-- Jack (Untertitel)
	JACK = {
		GAME_START = {
			"Ladies and gentlemen... welcome to my LAST SHOW!",
			"Hello, hello, my little friends! Who wants to play?",
			"The box is open. Nobody leaves... except one.",
		},
		CHOSEN = {
			"Round and round it goes... and stops on {name}!",
			"Eeny, meeny, miny... {name}!",
			"Oh, {name}. I've been looking at you.",
			"{name}! Come on, don't be shy.",
		},
		SKIPPED = {
			"A BODY DOUBLE! {name} slips away... Jack spins on to {new}!",
			"Not you, {name}? Fine. {new}, then!",
			"{name} sends a body double. Lucky you, {new}!",
		},
		SEAT_TAKEN = {
			"Fresh meat! {name} takes {old}'s seat.",
			"{old} is out of a job. Welcome to the show, {name}!",
			"Look who crawled in! {name} replaces {old}.",
		},
		REVOLVER_HAND = {
			"{name}, {blanks} blanks and one bullet. Pick someone special.",
			"A gift for you, {name}! Who's your favourite?",
			"Here, {name}, hold this. Point it at a friend.",
		},
		REVOLVER_AIM = {
			"{name} points the revolver at {target}...",
			"{name} chose {target}. How sweet.",
			"{target}, look down the barrel. {odds}.",
		},
		REVOLVER_HESITATE = {
			"Too slow, {name}! Jack will help you... aim at YOURSELF.",
			"Tick tock, {name}. Jack chooses for you!",
		},
		REVOLVER_CLICK = {
			"*click* ... Awww. The gun is yours now, {target}.",
			"*click*. Not yet, not yet! Your turn, {target}.",
			"*click*. Breathe, {target}. Then pull.",
		},
		REVOLVER_SELF_CLICK = {
			"*click*! {name} lives. The gun moves on to {next}.",
			"Lucky, {name}. Your turn, {next}!",
		},
		REVOLVER_PASS = {
			"The gun passes to {name}. {odds}.",
			"{name}, your turn. {odds}.",
		},
		REVOLVER_RELOAD = {
			"One more bullet for luck! {name}, your turn. {odds}.",
			"Jack slips in another bullet... {name}, {odds}.",
			"More bullets, more fun! Over to you, {name}. {odds}.",
		},
		REVOLVER_ODDS = "{left} chambers left, one bullet",
		REVOLVER_ODDS_LAST = "The last chamber. No more luck",
		REVOLVER_ODDS_LOADED = "{bullets} of {chambers} chambers loaded",
		REVOLVER_ODDS_FULL = "Every chamber is loaded. No more luck",
		REVOLVER_ODDS_SHORT = "{bullets} IN {chambers}",     -- Stage-Zeile beim Zielen (Nachladen)
		REVOLVER_ODDS_SHORT_CLASSIC = "1 IN {left}",         -- ... klassisch
		REVOLVER_BANG = {
			"BANG! Bye-bye, {target}! Big round of applause!",
			"{target} has left the show. HAHAHA!",
			"BANG! Somebody clean up {target}, please.",
		},
		REVOLVER_HOLDER_FLED = {
			"{name} ran away with sweaty hands. {next}, catch!",
		},
		SAFETY_SAVE = {
			"A Lucky Charm! {target} cheats death... this time.",
			"Lucky Charm? Boring! {target} lives.",
		},
		RICOCHET = {
			"RICOCHET! The bullet bounces off {target}...",
			"{target} had a FUNHOUSE MIRROR! Where will it land?",
		},
		RICOCHET_HIT = {
			"...and finds {target}! Oopsie!",
			"...straight into {target}. What a shot!",
		},
		TARGET_FLED = {
			"{target} ran away. Cowards never win. Choose again!",
		},
		KNIFE_START = {
			"Catch, {name}! Dodge my knives!",
			"Hold still, {name}... or dodge!",
		},
		KNIFE_DODGED = {
			"{name} dodged it! Boooring.",
			"Missed! You're quick, {name}.",
		},
		KNIFE_HIT = {
			"Bullseye! Bye-bye, {name}!",
			"Right between the eyes. Sorry, {name}!",
		},
		FIRE_START = {
			"Feeling cold, {name}? Let Jack warm you up!",
			"FWOOSH! Oops. Sorry, {name}.",
		},
		FIRE_OUT = {
			"{name} put out the fire. Spoilsport!",
		},
		FIRE_BURN = {
			"Crispy {name}! Smells delicious.",
			"{name} is toast. Literally!",
		},
		STAB_HAND = {
			"A knife for you, {name}! Pick a neighbour.",
			"{name}, your neighbours look tasty...",
		},
		STAB_CHOSE = {
			"{name} turns to {target}...",
			"{name} raises the knife over {target}!",
		},
		STAB_HESITATE = {
			"Too slow, {name}. Jack stabs YOU instead!",
		},
		STAB_BLOCKED = {
			"{target} blocked it! Lucky, lucky.",
		},
		STAB_HIT = {
			"Stab, stab! {target} is out!",
			"{target} won't need that seat anymore.",
		},
		ANGRY_START = {
			"Enough games. Jack does it HIMSELF.",
			"Jack is getting bored, {name}...",
			"No more toys. Just Jack and you, {name}.",
		},
		ANGRY_BANG = {
			"BANG! Jack never misses.",
			"Shh, {name}. Sleep now.",
		},
		GALLERY_START = {
			"Step right up! {left}, {name} and {right}... sitting ducks!",
			"Three little ducks in a row: {left}, {name}, {right}. Jack LOVES this game!",
			"The shooting gallery is open! {name}, you're the big prize. {left}, {right}, you're the bonus.",
		},
		GALLERY_HIT = {
			"Pop goes {target}!",
			"Ding, ding, ding! Down goes {target}!",
			"One duck less. Bye-bye, {target}!",
		},
		VOTE_START = {
			"{name} will live or die. Cast your votes!",
			"Spare {name}... or eliminate? YOU decide!",
			"Thumbs up or thumbs down for {name}?",
		},
		VOTE_SPARE = {
			"The majority wishes to spare {name}. ({spare} - {kill}) Boooo!",
			"{name} lives! ({spare} - {kill}) You softies.",
		},
		VOTE_KILL = {
			"The people have spoken. Goodbye, {name}! ({kill} - {spare})",
			"Eliminate! ({kill} - {spare}) Sorry, {name}. Democracy!",
		},
		VOTE_TIE = {
			"A tie! ({spare} - {kill}) Jack flips a coin...",
		},
		VOTE_COIN_SPARE = {
			"Heads! {name} lives.",
		},
		VOTE_COIN_KILL = {
			"Tails! Goodbye, {name}!",
		},
		VOTE_FLED = {
			"{name} ran from the vote. Guilty!",
		},
		PUMPKIN_START = {
			"Catch, {name}! It's lit!",
			"A present for {name}! Don't hold it too long...",
			"Hot pumpkin! Pass it on, {name}!",
		},
		PUMPKIN_BOOM = {
			"BOOM! {name} is pumpkin pie!",
			"KABOOM! Who ordered roasted {name}?",
		},
		PUMPKIN_FLED = {
			"{name} ran off. The pumpkin goes off on an empty chair. Boring!",
		},
		BOMB_START = {
			"A present for you, {name}! Don't shake it.",
			"Tick, tock, {name}. Read the manual!",
		},
		BOMB_DEFUSED = {
			"{name} defused it?! Jack is... impressed. Barely.",
			"Click. Nothing. How disappointing, {name}.",
		},
		BOMB_BOOM = {
			"BOOM! There goes {name}!",
			"Wrong wire, {name}. Wrong, wrong, WRONG!",
		},
		DUEL_START = {
			"{name} and {target}... back to back. Don't blink!",
			"A duel! {name} versus {target}. Jack LOVES duels.",
		},
		DUEL_WIN = {
			"{name} was faster. Bye-bye, {target}!",
			"Quick hands, {name}. {target} wasn't so lucky.",
		},
		DUEL_MISFIRE = {
			"{name} shot their own foot. HAHAHA!",
			"Wrong key, {name}. Oops.",
		},
		DUEL_BOTH = {
			"Too slow, BOTH of you. Jack hates waiting.",
			"Nobody fired? Then Jack does it for you!",
		},
		DUEL_FLED = {
			"{name} ran from the duel. {target} wins without a shot.",
		},
		SPLITSTEAL_START = {
			"{name} and {name2}. Split... or steal?",
			"Trust each other, {name} and {name2}? Hehehe.",
		},
		SPLITSTEAL_SPLIT = {
			"Both split! A card for each of you. How sweet.",
			"Split and split. Friendship wins... for now.",
		},
		SPLITSTEAL_STEAL = {
			"{stealer} STEALS everything from {victim}! Jack approves.",
			"{victim} trusted {stealer}. Big mistake! HAHAHA!",
		},
		SPLITSTEAL_BOTH = {
			"Both steal! Greedy, greedy. Nobody gets anything.",
		},
		SPLITSTEAL_FLED = {
			"{name} ran away. No deal!",
		},
		DEAL_ONE = "1 PLAYER WILL NOW BE GIVEN A CARD",
		DEAL_MANY = "{count} PLAYERS WILL NOW BE GIVEN CARDS",
		DEAL_NONE = "Everybody's hands are full. Greedy little things!",
		CHOOSECARD_START = {
			"{name}, pick a card. Any card!",
			"Three cards for {name}. Choose wisely.",
		},
		CHOOSECARD_DONE = {
			"{name} takes a card. Wise choice... maybe.",
			"{name} made a choice. Jack is curious.",
		},
		CHOOSECARD_TIMEOUT = {
			"Too slow, {name}. Jack picks for you.",
		},
		CHOOSECARD_FULL = {
			"Your hands are full, {name}. Greedy little thing!",
		},
		LEFT_TABLE = {
			"{name} left the show. How rude!",
		},
		WINNER = {
			"Only {winner} remains! The show is over... for now.",
			"{winner} survives! Jack is SO proud of you.",
		},
		NO_WINNER = {
			"Nobody survived. Jack wins again!",
		},
	},

	-- Events: Name, Event-Karte und Stage-Zeilen fuer das HUD (docs/PROTOCOL.md, "Klarheit").
	--   name / tagline / rules   Karte (rules = ein Satz, fuer aeltere HUDs)
	--   who                      Karte: wer ist dran ({name}, {name2} = Gewaehlte)
	--   how                      Karte: 2-3 Stichpunkte "so geht's"
	--   you_actor / you_others   Karte: "YOU: ..." fuer die Gewaehlten bzw. alle anderen
	--   instruction_actor/_others  Stage-Zeile, solange das Event keine Phase gesetzt hat
	--   stage                    Stage-Zeilen je Phase (Context:Stage): Text fuer alle oder { actor = ..., others = ... }
	--                            (actor = fuer die Plaetze in State.event.involved, others = fuer alle anderen)
	-- Platzhalter: {name} {name2} Gewaehlte, {target} Ziel/Opfer, {next} naechster Halter, {odds} "2 IN 6",
	-- {step}/{steps} Taste x von y, {left}/{done} Flammen, {count} Karten, {spare}/{kill} Stimmen, {winner}/{loser}, {stealer}/{victim}
	EVENTS = {
		revolver = {
			name = "Clown Roulette",
			tagline = "One gun. One bullet... for now.",
			rules = REVOLVER_RULES,
			who = "{name} gets the revolver",
			how = {
				"The holder aims at a player and pulls the trigger.",
				"*Click*: the target gets the gun and shoots next.",
				REVOLVER_LOAD_LINE,
			},
			you_actor = "YOU: aim with the mouse, click to shoot.",
			you_others = "YOU: watch out - if the gun clicks on you, you shoot next.",
			instruction_actor = "YOUR TURN - aim with the mouse, click to SHOOT",
			instruction_others = "{name} must shoot someone...",
			stage = {
				give = { actor = "GET READY - aim with the mouse, click to shoot", others = "Jack hands {name} the revolver..." },
				choose = { actor = "YOUR TURN - aim with the mouse, click to SHOOT", others = "{name} must shoot someone..." },
				aim = "{name} pulls the trigger on {target}... ({odds})",
				aim_self = "Too slow! {name} must shoot THEMSELVES... ({odds})",
				-- actor = der naechste Halter (involved): er bekommt den Revolver und muss gleich zielen
				click = {
					actor = "*click* - YOU get the gun next! Aim with the mouse, click to shoot",
					others = "*click* - the gun passes to {next}",
				},
				click_reload = {
					actor = "*click* - YOU get the gun next, +1 bullet! Aim with the mouse, click to shoot",
					others = "*click* - the gun passes to {next}. Jack loads another bullet!",
				},
				bang = "BANG! {target} is OUT",
			},
		},
		angry = {
			name = "Jack Snaps",
			tagline = "Jack has run out of patience.",
			rules = "Jack shoots. Only a Lucky Charm or a Funhouse Mirror can help you.",
			who = "Jack shoots {name} himself",
			how = {
				"No choice, no dodging - Jack aims and shoots.",
				"Only a LUCKY CHARM or FUNHOUSE MIRROR card saves you.",
			},
			you_actor = "YOU: pray - only a LUCKY CHARM or MIRROR card helps.",
			you_others = "YOU: just watch.",
			instruction_actor = "Pray.",
			instruction_others = "Jack aims at {name}...",
			stage = {
				aim = "Jack aims at {name}...",
				bang = "BANG! {target} is OUT",
			},
		},
		gallery = {
			name = "Shooting Gallery",
			tagline = "Step right up! Three ducks, one clown.",
			rules = "Jack shoots the chosen one and both neighbours, one after another. Only a Lucky Charm or a Funhouse Mirror can help.",
			who = "{name} and both neighbours are the ducks",
			how = {
				"Jack shoots the chosen one and both neighbours.",
				"One after another - nobody can dodge.",
				"Only a LUCKY CHARM or FUNHOUSE MIRROR card saves you.",
			},
			you_actor = "YOU: are the big prize. Pray.",
			you_others = "YOU: sitting next to {name}? You are a target too.",
			instruction_actor = "Pray.",
			instruction_others = "Jack takes aim at {name}...",
			stage = {
				aim = "Jack aims at {target}...",
				bang = "BANG! {target} is OUT",
				done = "The shooting gallery is closed.",
			},
		},
		knife = {
			name = "The Knife Act",
			tagline = "Jack never misses. Usually.",
			rules = "Press the keys that appear - fast. One mistake and it sticks.",
			who = "Jack throws knives at {name}",
			how = {
				"A key (W, A, S or D) pops up - press it fast.",
				KNIFE_KEYS_LINE,
				"Wrong key or too slow: the knife hits.",
			},
			you_actor = "YOU: press each key that pops up to DODGE.",
			you_others = "YOU: just watch.",
			instruction_actor = "Press the key to DODGE!",
			instruction_others = "{name} tries to dodge Jack's knife",
			stage = {
				ready = { actor = "GET READY - press the keys that pop up!", others = "Jack takes aim at {name} with a knife..." },
				dodge = { actor = "DODGE! Press the key! ({step}/{steps})", others = "{name} dodges Jack's knives... ({step}/{steps})" },
				dodged = "{name} dodged the knives!",
				hit = "The knife hits {name}. OUT!",
			},
		},
		fire = {
			name = "Fire Eater",
			tagline = "Feeling cold? Jack will warm you up.",
			rules = "Click the jumping flame before you burn.",
			who = "Jack sets {name} on fire",
			how = {
				"A flame jumps around the screen.",
				FIRE_CLICKS_LINE,
				"Too slow and you burn.",
			},
			you_actor = "YOU: click the jumping flame - fast!",
			you_others = "YOU: just watch.",
			instruction_actor = "Click the flames to put yourself out!",
			instruction_others = "{name} is on fire!",
			stage = {
				ready = { actor = "GET READY - click the flame when it appears!", others = "Jack breathes fire at {name}..." },
				click = { actor = "CLICK THE FLAME! {left} more", others = "{name} is on fire! {done}/{clicks} flames out" },
				out = "{name} put out the fire!",
				burn = "{name} burned. OUT!",
			},
		},
		stab = {
			name = "Chop Chop",
			tagline = "Love thy neighbour. Then stab them.",
			rules = "Pick the left or right neighbour. The victim may block with one key.",
			who = "{name} must stab a neighbour",
			how = {
				"The holder picks the left or right neighbour.",
				"The victim can BLOCK with one key - fast!",
				"Too slow to choose? Jack stabs the holder.",
			},
			you_actor = "YOU: click your left or right neighbour.",
			you_others = "YOU: sitting next to {name}? Get ready to BLOCK.",
			instruction_actor = "Choose a neighbour to stab",
			instruction_others = "{name} holds the knife",
			stage = {
				ready = { actor = "GET READY - you stab your left or right neighbour", others = "Jack hands {name} a knife..." },
				choose = { actor = "YOUR TURN - click the neighbour you want to stab", others = "{name} picks a neighbour to stab..." },
				strike = { actor = "GET READY TO BLOCK - a key will pop up!", others = "{name} raises the knife over {target}..." },
				hesitate = { actor = "GET READY TO BLOCK - a key will pop up!", others = "Too slow! Jack stabs {target} instead..." },
				block = { actor = "BLOCK! Press the key!", others = "{target} tries to block the knife..." },
				blocked = "{target} blocked the knife!",
				hit = "The knife hits {target}. OUT!",
			},
		},
		vote = {
			name = "Cheer or Jeer",
			tagline = "The audience decides.",
			rules = "Everyone votes, even the dead. Majority wins, a tie is a coin flip. No card can save you.",
			who = "The table votes on {name}",
			how = {
				"Everyone votes - even players who are out.",
				"SPARE or ELIMINATE: the majority wins.",
				"A tie is a coin flip. No card can save you.",
			},
			you_actor = "YOU: can't vote. Hope they like you.",
			you_others = "YOU: vote SPARE or ELIMINATE when the buttons appear.",
			instruction_actor = "Spare or eliminate {name}?",
			instruction_others = "The table votes on {name}",
			stage = {
				ready = { actor = "GET READY TO VOTE - spare or eliminate {name}?", others = "The table is about to vote on {name}..." },
				voting = { actor = "VOTE NOW - spare or eliminate {name}?", others = "The table votes on {name}..." },
				tie = "A tie ({spare} - {kill})! Jack flips a coin...",
				spare = "{name} is SPARED ({spare} - {kill})",
				kill = "{name} is ELIMINATED ({kill} - {spare})",
				fled = "{name} ran from the vote",
			},
		},
		pumpkin = {
			name = "Pass the Pumpkin",
			tagline = "It's lit. Don't be the one holding it.",
			rules = "Throw the pumpkin left or right. The fuse is secret. Whoever holds it at the end explodes.",
			who = "{name} gets the lit pumpkin",
			how = {
				"Throw it to your left or right neighbour - click them.",
				"The fuse is secret. It can blow any second.",
				"Whoever holds it when it blows is OUT.",
			},
			you_actor = "YOU: throw it left or right - FAST!",
			you_others = "YOU: if it lands on you, throw it on at once.",
			instruction_actor = "PASS THE PUMPKIN!",
			instruction_others = "{name} holds the pumpkin",
			stage = {
				catch = { actor = "CATCH! Then throw it on - left or right", others = "Jack throws a lit pumpkin to {name}..." },
				hold = { actor = "THROW IT! Click your left or right neighbour", others = "{name} has the pumpkin!" },
				boom = "BOOM! {name} is OUT",
				fled = "{name} ran off - the pumpkin blows up an empty chair",
			},
		},
		bomb = {
			name = "Snip the Wire",
			tagline = "Jack built it himself. With love.",
			rules = "Read Jack's manual and cut the right wire before the timer hits zero.",
			who = "Jack gives {name} a bomb",
			how = {
				"Three numbered wires and one rule from Jack's manual.",
				"Cut the right wire before the timer runs out.",
				"Wrong wire or too slow: BOOM.",
			},
			you_actor = "YOU: read the rule, then click the right wire.",
			you_others = "YOU: just watch.",
			instruction_actor = "Cut the right wire!",
			instruction_others = "{name} is defusing Jack's bomb",
			stage = {
				ready = { actor = "GET READY - read the rule, then cut the right wire", others = "Jack puts a bomb at {name}'s feet..." },
				cut = { actor = "CUT THE RIGHT WIRE!", others = "{name} is defusing the bomb..." },
				defused = "{name} defused the bomb!",
				boom = "BOOM! {name} is OUT",
			},
		},
		duel = {
			name = "Quick Draw",
			tagline = "Two players. One bullet each. No second chances.",
			rules = "Wait for DRAW!, then press the key faster than your opponent.",
			who = "{name} vs {name2}",
			how = {
				"Wait for DRAW! - then press the key that appears.",
				"The faster one shoots, the other one is hit.",
				"Wrong key: you shoot yourself. Nobody fires: Jack shoots both.",
			},
			you_actor = "YOU: wait for DRAW!, then press the key FAST.",
			you_others = "YOU: just watch.",
			instruction_actor = "Wait for it...",
			instruction_others = "{name} and {name2} face each other",
			stage = {
				wait = { actor = "WAIT FOR IT... press the key only after DRAW!", others = "{name} and {name2} wait for the signal..." },
				draw = { actor = "DRAW! Press the key!", others = "DRAW!" },
				win = "{winner} wins the duel - {loser} is hit",
				misfire = "{loser} pressed the wrong key...",
				both = "Too slow - Jack shoots BOTH!",
				fled = "{loser} ran - {winner} wins without a shot",
			},
		},
		splitsteal = {
			name = "Share or Snatch",
			tagline = "Trust is a funny thing.",
			rules = "Both split: one card each. One steals: they take all the other's cards plus one. Both steal: nothing.",
			who = "{name} and {name2} make a deal",
			how = {
				"Both SPLIT: one card each.",
				"One STEALS: they take all the other's cards.",
				"Both STEAL: nobody gets anything.",
			},
			you_actor = "YOU: choose SPLIT or STEAL in secret.",
			you_others = "YOU: just watch. Nobody dies this round.",
			instruction_actor = "Split or steal? Nobody sees your choice.",
			instruction_others = "{name} and {name2} make a deal",
			stage = {
				ready = { actor = "GET READY - SPLIT or STEAL, in secret", others = "{name} and {name2} make a deal..." },
				choose = { actor = "SPLIT or STEAL? Nobody sees your choice", others = "{name} and {name2} decide: split or steal..." },
				reveal = "Both have chosen... drum roll!",
				split = "Both SPLIT - a card for each!",
				steal = "{stealer} STEALS from {victim}!",
				both = "Both STEAL - nobody gets anything",
				fled = "{name} ran away - no deal",
			},
		},
		deal = {
			name = "Party Favors",
			tagline = "Jack is feeling generous.",
			rules = "Jack hands out free cards. Nobody dies... this time.",
			who = "Jack hands out cards",
			how = {
				"Jack gives free cards to some players.",
				"{name} gets one for sure.",
				"Nobody dies this round.",
			},
			you_actor = "YOU: get a card for sure.",
			you_others = "YOU: maybe you get a card too.",
			instruction_actor = "Jack deals you a card",
			instruction_others = "Jack deals cards",
			stage = {
				one = "Jack deals 1 card...",
				many = "Jack deals {count} cards...",
				none = "Everybody's hands are full - no cards",
			},
		},
		choosecard = {
			name = "Fortune Teller",
			tagline = "Pick a card. Any card.",
			rules = "Keep one of three cards. Choose wisely.",
			who = "{name} picks a card",
			how = {
				"Keep one of three cards.",
				"Too slow? Jack picks for you.",
				"Nobody dies this round.",
			},
			you_actor = "YOU: click the card you want to keep.",
			you_others = "YOU: just watch. Nobody dies this round.",
			instruction_actor = "Pick one card",
			instruction_others = "{name} picks a card",
			stage = {
				pick = { actor = "PICK A CARD - click the one you want", others = "{name} picks a card..." },
				done = "{name} took a card",
				full = "{name}'s hands are full - no card",
			},
		},
	},

	-- Stage-Zeilen, die in mehreren Events vorkommen (Treffer mit Karten, Abgaenge)
	STAGE = {
		RICOCHET = "RICOCHET! The bullet bounces off {target}'s mirror...",
		SAFETY = "BANG! A LUCKY CHARM saves {target}!",
		OUT = "BANG! {target} is OUT",
	},

	NOT_YOUR_TURN = "It is not your turn.",
}

local function Pick(list)
	if (type(list) == "table") then
		return list[math.random(#list)]
	end
	return list
end

-- Ersetzt {schluessel} im Text durch Werte aus values. Bei Listen wird ein zufaelliger Satz gewaehlt.
function DeathBox.Text.Format(text_or_list, values)
	local text = Pick(text_or_list) or ""
	return (string.gsub(text, "{(%w+)}", function(key)
		local value = values and values[key]
		return value ~= nil and tostring(value) or ("{" .. key .. "}")
	end))
end
