--!strict
-- Everything the homeowners (and the seller) do with their bodies at the door, beyond walking out
-- and back (the user: "more interactions with houseowners and seller (new animations) (things they do
-- should vary)"). Pure: HomeownerController poses the rig from these, DoorService picks goodbyes from
-- them, tests/ownermoves.spec checks them.
--
-- Who they are decides what they do (TEMPERAMENTS, by the house's Dialogue personality, or the
-- seller): which things they do while you play (ACTS) and how often, how they gesture as they talk
-- (TALKS: a hello, a pleased line, a displeased one), how they hand you your candy (GIVES), what
-- they do when a flashlight's shone in their face, and their goodbyes. Every house also has a
-- favourite act of its own (from its seed), so two of the same sort still differ.
--
-- A pose (Move) is radians on the rig's six joints (CharacterRig: no elbows or knees, so it's all
-- stiff arms and a bending body; it suits them). The near arm is the one on their slapping side
-- (the door's hinge side), the far one the other; `both` is both arms, mirrored. An arm's `pitch`
-- swings it forward and up (0 hanging, ~1.5 straight out at you, ~2.6 up by the head), `roll` out to
-- the side (negative: in across the body), `yaw` round. `fold` bends the body forward, `twist` turns
-- it, `sway` leans it sideways; `nod` lifts the head (negative: down), `tilt` tips it over, `turn`
-- turns it away from you. `step` swings the near leg (a foot tapped), `lunge` moves them at you
-- (studs). Every pose is a function of `t`, seconds into it; HomeownerController eases it in and out.

export type Arm = { pitch: number, roll: number?, yaw: number? }
export type Move = {
	near: Arm?,
	far: Arm?,
	both: Arm?,
	fold: number?,
	twist: number?,
	sway: number?,
	nod: number?,
	tilt: number?,
	turn: number?,
	step: number?,
	lunge: number?,
}
-- A sound partway through a move: `at` seconds in.
export type Cue = { at: number, sound: string, volume: number?, speed: number? }
export type Def = { time: number, pose: (t: number) -> Move, sounds: { Cue }? }
-- A line's gestures: `t` seconds into it, `length` its whole length.
export type Talk = { pose: (t: number, length: number) -> Move }
-- Handing something over: the pose, the thing leaving the hand at `release` and arriving `fly`
-- later, rising `arc` studs on the way (0: dropped straight in).
export type Give = {
	time: number,
	release: number,
	fly: number,
	arc: number,
	pose: (t: number) -> Move,
	sounds: { Cue }?,
}
export type Bye = { time: number, slam: boolean, sound: string?, pose: (t: number) -> Move }
export type Weighted = { { name: string, weight: number } }
export type Temperament = {
	every: number, -- seconds: a chance of an act this often...
	chance: number, -- ...this likely
	acts: Weighted,
	hello: string, -- TALKS
	pleased: string,
	displeased: string,
	gives: Weighted, -- GIVES
	glare: string, -- REACTIONS: a flashlight in their face
	byes: { pleased: Weighted, displeased: Weighted }, -- GOODBYES
}

local Rng = require(script.Parent.Rng)

local OwnerMoves = {}

local function pulse(x: number): number
	return math.max(0, math.sin(x))
end

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- What they do while you play, now and then.
local ACTS: { [string]: Def } = {
	-- A look back over the shoulder into the dark house, as if someone in there said something.
	lookBack = {
		time = 1.9,
		pose = function()
			return { turn = 1.45, twist = 0.3, nod = 0.05 }
		end,
	},
	-- The head slowly cocked right over, too far, and held there.
	cock = {
		time = 2.2,
		pose = function()
			return { tilt = 0.75, nod = -0.06 }
		end,
	},
	-- A hand up to the side of the head, scratching.
	scratch = {
		time = 1.7,
		pose = function(t)
			return { far = { pitch = 2.45, roll = 0.55 + 0.12 * math.sin(t * 24) }, tilt = -0.15 }
		end,
	},
	-- Fingers drumming on the leg: impatient.
	drum = {
		time = 1.9,
		pose = function(t)
			return { near = { pitch = 0.16 + 0.07 * math.sin(t * 26), roll = 0.12 } }
		end,
	},
	-- Weight from one foot to the other, slowly.
	shift = {
		time = 2.6,
		pose = function(t)
			return { sway = 0.11 * math.sin(t * 2.4), tilt = 0.06 * math.sin(t * 2.4) }
		end,
	},
	-- Leaning in closer, for a better look at you.
	lean = {
		time = 2.0,
		pose = function()
			return { fold = 0.32, nod = 0.16 }
		end,
	},
	-- Sniffing the air: little lifts of the chin.
	sniff = {
		time = 1.5,
		pose = function(t)
			return { nod = 0.24 + 0.08 * pulse(t * 18), tilt = 0.06 }
		end,
	},
	-- Hands together in front, wringing them.
	wring = {
		time = 2.0,
		pose = function(t)
			return {
				both = { pitch = 0.62 + 0.06 * math.sin(t * 14), roll = -0.3 + 0.05 * math.sin(t * 14 + 1.5) },
				nod = -0.08,
				fold = 0.06,
			}
		end,
	},
	-- Leaning to one side to look past you, out at the street: who's that behind you?
	peerPast = {
		time = 2.2,
		pose = function()
			return { sway = 0.14, tilt = -0.18, turn = -0.38, nod = 0.06, twist = -0.12 }
		end,
	},
	-- A slow yawn, the head tipped back, a hand up to the mouth.
	yawn = {
		time = 2.2,
		pose = function(t)
			local open = smooth(t / 0.6) * (1 - smooth((t - 1.5) / 0.6))
			return { nod = 0.5 * open, far = { pitch = 2.55, roll = -0.35 }, fold = -0.08 * open }
		end,
		sounds = { { at = 0.2, sound = "Breath", volume = 0.5, speed = 0.6 } },
	},
	-- The head rolled slowly round on the neck... and a crack.
	crack = {
		time = 1.7,
		pose = function(t)
			if t < 1.1 then
				return { tilt = 0.5 * math.sin(t * 5.7), nod = 0.3 * math.cos(t * 5.7) - 0.1 }
			end
			return { tilt = 0.62 * (1 - smooth((t - 1.15) / 0.5)), nod = -0.05 }
		end,
		sounds = { { at = 1.12, sound = "Tick", volume = 0.9, speed = 0.55 } },
	},
	-- Swaying to a tune only they can hear.
	hum = {
		time = 3.0,
		pose = function(t)
			return {
				sway = 0.08 * math.sin(t * 3),
				tilt = 0.18 * math.sin(t * 3),
				nod = 0.06 * math.sin(t * 6),
				twist = 0.05 * math.sin(t * 3),
			}
		end,
	},
	-- A look at the watch they aren't wearing.
	watch = {
		time = 1.8,
		pose = function()
			return { near = { pitch = 1.25, roll = -0.75 }, nod = -0.42, turn = -0.12 }
		end,
	},
	-- A finger to the lips: shh.
	shush = {
		time = 1.6,
		pose = function()
			return { far = { pitch = 2.7, roll = -0.2 }, fold = 0.12, nod = -0.05 }
		end,
		sounds = { { at = 0.3, sound = "Whispers", volume = 0.35 } },
	},
	-- Beckoning you closer, the hand flicking up.
	beckon = {
		time = 1.9,
		pose = function(t)
			return { near = { pitch = 1.35 + 0.22 * pulse(t * 9) }, fold = 0.1, tilt = 0.2 }
		end,
	},
	-- A giggle behind a hand, the shoulders shaking.
	giggle = {
		time = 1.5,
		pose = function(t)
			return {
				far = { pitch = 2.45, roll = -0.3 },
				fold = 0.06 + 0.05 * math.abs(math.sin(t * 22)),
				nod = -0.12 + 0.06 * math.sin(t * 22),
				sway = 0.03 * math.sin(t * 11),
			}
		end,
		sounds = { { at = 0.1, sound = "Breath", volume = 0.4, speed = 1.6 } },
	},
	-- The head snapped up at the floor above, as something creaks up there.
	lookUp = {
		time = 2.0,
		pose = function()
			return { nod = 0.75, tilt = 0.12, fold = -0.06 }
		end,
		sounds = { { at = 0, sound = "FloorCreak", volume = 0.7 } },
	},
	-- Rocking on their heels, back and forth.
	rock = {
		time = 3.0,
		pose = function(t)
			return { fold = 0.13 * math.sin(t * 2.6), nod = -0.06 * math.sin(t * 2.6) }
		end,
	},
	-- Brushing something off their front.
	dust = {
		time = 1.4,
		pose = function(t)
			return { near = { pitch = 0.75 + 0.18 * math.sin(t * 20), roll = -0.55 }, nod = -0.3, fold = 0.08 }
		end,
		sounds = { { at = 0.2, sound = "Cloth", volume = 0.5 } },
	},
	-- A foot tapping on the boards.
	tapFoot = {
		time = 2.1,
		pose = function(t)
			return { step = 0.14 * pulse(t * 12), nod = -0.04 }
		end,
		-- (on each tap: sin(t * 12) peaks at these)
		sounds = {
			{ at = 0.13, sound = "OwnerStep", volume = 0.25, speed = 1.3 },
			{ at = 0.65, sound = "OwnerStep", volume = 0.25, speed = 1.3 },
			{ at = 1.18, sound = "OwnerStep", volume = 0.25, speed = 1.3 },
			{ at = 1.7, sound = "OwnerStep", volume = 0.25, speed = 1.3 },
		},
	},
	-- The seller's: counting his takings, coin by coin, from one hand to the other.
	countCoins = {
		time = 2.0,
		pose = function(t)
			return {
				both = { pitch = 0.5, roll = -0.28 },
				near = { pitch = 0.5 + 0.08 * pulse(t * 12), roll = -0.28 },
				nod = -0.45,
				fold = 0.05,
			}
		end,
		sounds = {
			{ at = 0.4, sound = "Coin", volume = 0.18, speed = 1.3 },
			{ at = 1.0, sound = "Coin", volume = 0.18, speed = 1.4 },
			{ at = 1.5, sound = "Coin", volume = 0.18, speed = 1.2 },
		},
	},
	-- The seller's: a look up the street, then down it. Watching for him.
	lookOut = {
		time = 2.6,
		pose = function(t)
			return { turn = 1.1 * math.sin(t * 2.4), nod = 0.05, twist = 0.12 * math.sin(t * 2.4) }
		end,
	},
	-- The seller's: patting his pockets, has he got it?
	patPockets = {
		time = 1.5,
		pose = function(t)
			return {
				near = { pitch = -0.05 + 0.12 * pulse(t * 14), roll = 0.12 },
				far = { pitch = -0.05 + 0.12 * pulse(t * 14 + 1.6), roll = 0.12 },
				nod = -0.25,
				fold = 0.05,
			}
		end,
		sounds = { { at = 0.15, sound = "Cloth", volume = 0.5 } },
	},
}

-- How they gesture as they talk.
local function beat(t: number): number
	return math.sin(t * 5.5)
end

local TALKS: { [string]: Talk } = {
	-- The far hand beating with the words, the head nodding on them.
	beat = {
		pose = function(t)
			return { far = { pitch = 0.8 + 0.28 * beat(t), roll = 0.3 }, nod = 0.09 * beat(t) }
		end,
	},
	-- A little bow first, then a hand on the heart as they speak.
	greet = {
		pose = function(t)
			local bow = 1 - smooth((t - 0.45) / 0.35)
			return {
				far = { pitch = 1.0, roll = -0.55 },
				fold = 0.42 * bow + 0.04,
				nod = -0.3 * bow + 0.05 * beat(t),
			}
		end,
	},
	-- A hand on the heart.
	chest = {
		pose = function(t)
			return { far = { pitch = 1.0, roll = -0.55 }, nod = 0.06 * beat(t) - 0.04, fold = 0.05 }
		end,
	},
	-- A finger raised and wagged at you.
	wag = {
		pose = function(t)
			return {
				near = { pitch = 2.0, roll = 0.15 + 0.25 * math.sin(t * 10) },
				nod = -0.1,
				fold = 0.12,
				tilt = 0.1 * math.sin(t * 5),
			}
		end,
	},
	-- A hand by the mouth, leaning in: a secret.
	cup = {
		pose = function(t)
			return { far = { pitch = 2.35, roll = -0.15 }, fold = 0.25, nod = -0.1 + 0.04 * beat(t), tilt = 0.2 }
		end,
	},
	-- Bouncing on the spot with it, arms swinging.
	bounce = {
		pose = function(t)
			local b = math.sin(t * 7)
			return {
				both = { pitch = 0.35 + 0.15 * math.abs(b), roll = 0.2 },
				sway = 0.06 * b,
				nod = 0.08 * b,
			}
		end,
	},
	-- Both hands out wide: welcome, behold.
	spread = {
		pose = function(t)
			local open = smooth(t / 0.4)
			return {
				both = { pitch = 0.7 * open, roll = 0.75 * open + 0.1 * beat(t) },
				nod = 0.07 * beat(t),
				fold = -0.04,
			}
		end,
	},
	-- Rubbing the hands together: lovely, lovely.
	rub = {
		pose = function(t)
			return {
				both = { pitch = 0.6 + 0.05 * math.sin(t * 16), roll = -0.32 + 0.06 * math.sin(t * 16 + 1) },
				nod = 0.05 * beat(t),
				fold = 0.08,
			}
		end,
	},
	-- Stiff with anger, trembling, the head down.
	fist = {
		pose = function(t)
			return {
				near = { pitch = 0.12, roll = 0.02 },
				far = { pitch = 0.2, roll = 0.02 },
				fold = 0.2 + 0.03 * math.sin(t * 30),
				nod = -0.2,
			}
		end,
	},
	-- A shrug, then on with it.
	shrug = {
		pose = function(t)
			local up = smooth(t / 0.25) * (1 - smooth((t - 0.7) / 0.3))
			return {
				both = { pitch = 0.45 * up + 0.1, roll = 0.55 * up + 0.1 },
				tilt = 0.25 * up,
				nod = 0.05 * beat(t),
			}
		end,
	},
	-- A finger jabbed at you on the words.
	point = {
		pose = function(t)
			return { near = { pitch = 1.55 + 0.1 * pulse(t * 9) ^ 3 }, fold = 0.15, nod = -0.05 }
		end,
	},
	-- A finger to the lips as they say it.
	shush = {
		pose = function(t)
			return { far = { pitch = 2.7, roll = -0.2 }, fold = 0.15, nod = -0.05 + 0.03 * beat(t) }
		end,
	},
	-- Leaning in, a hand cupped to the ear: eh? Speak up.
	ear = {
		pose = function(t)
			return { near = { pitch = 2.3, roll = 0.95 }, fold = 0.35, nod = -0.22 + 0.04 * beat(t), tilt = 0.15 }
		end,
	},
}

-- Handing over your candy (or what you bought).
local GIVES: { [string]: Give } = {
	-- The arm out to you, the candy dropped in.
	hand = {
		time = 0.95,
		release = 0.45,
		fly = 0.35,
		arc = 1.2,
		pose = function()
			return { near = { pitch = 1.35, roll = 0.05 }, fold = 0.08 }
		end,
	},
	-- Held out in both hands with a little bow.
	offer = {
		time = 1.1,
		release = 0.55,
		fly = 0.4,
		arc = 0.8,
		pose = function()
			return { both = { pitch = 1.15, roll = -0.12 }, fold = 0.28, nod = -0.15 }
		end,
	},
	-- Held up high over you and dropped, the head bent to watch it go in.
	drop = {
		time = 1.25,
		release = 0.7,
		fly = 0.45,
		arc = 0,
		pose = function()
			return { near = { pitch = 1.8 }, fold = 0.18, nod = -0.35 }
		end,
	},
	-- The arm swung back and the candy tossed, high.
	toss = {
		time = 1.0,
		release = 0.38,
		fly = 0.6,
		arc = 3,
		pose = function(t)
			return { near = { pitch = -0.45 + 2.0 * smooth((t - 0.2) / 0.18) }, fold = 0.05, nod = 0.08 }
		end,
		sounds = { { at = 0.3, sound = "Whoosh", volume = 0.3, speed = 1.4 } },
	},
	-- Held out... pulled back, the head on one side... then given.
	tease = {
		time = 1.55,
		release = 1.05,
		fly = 0.35,
		arc = 1.0,
		pose = function(t)
			local back = smooth((t - 0.4) / 0.15) * (1 - smooth((t - 0.75) / 0.2))
			return { near = { pitch = 1.3 - 0.9 * back }, fold = 0.1 - 0.15 * back, tilt = 0.35 * back }
		end,
		sounds = { { at = 0.45, sound = "Breath", volume = 0.45, speed = 1.3 } },
	},
	-- An old, shaking hand, slowly out.
	pinch = {
		time = 1.3,
		release = 0.75,
		fly = 0.35,
		arc = 0.9,
		pose = function(t)
			return { near = { pitch = 1.25 * smooth(t / 0.5) + 0.04 * math.sin(t * 40) }, fold = 0.16, nod = -0.1 }
		end,
	},
}

-- What they do when something happens to them: held for as long as it lasts (glare) or once
-- (the rest).
local REACTIONS: { [string]: Def } = {
	-- A flashlight in their face: an arm up to shield their eyes, the head turned from it.
	shield = {
		time = math.huge,
		pose = function()
			return { far = { pitch = 2.55, roll = -0.45 }, turn = 0.45, nod = -0.15, fold = -0.08, twist = 0.15 }
		end,
	},
	-- Both hands over their eyes.
	cover = {
		time = math.huge,
		pose = function()
			return { both = { pitch = 2.6, roll = -0.25 }, nod = -0.2, fold = 0.1, turn = 0.2 }
		end,
	},
	-- A flat hand out at you: get that out of my face.
	palm = {
		time = math.huge,
		pose = function()
			return { near = { pitch = 1.65, roll = 0.05 }, turn = 0.5, nod = -0.1, fold = -0.12 }
		end,
	},
	-- The power cut: a jolt, the head snapped up at the dead light, then a look out into the
	-- street, hands drawn in.
	startle = {
		time = 2.2,
		pose = function(t)
			if t < 0.7 then
				return { fold = -0.15, nod = 0.5, both = { pitch = 0.5, roll = 0.25 } }
			end
			return { turn = -0.7 * smooth((t - 0.7) / 0.4), nod = 0.05, both = { pitch = 0.6, roll = -0.3 } }
		end,
		sounds = { { at = 0, sound = "Breath", volume = 0.7, speed = 1.4 } },
	},
	-- A slow shake of the head: no.
	headShake = {
		time = 1.1,
		pose = function(t)
			return { turn = 0.32 * math.sin(t * 9), nod = -0.1 }
		end,
	},
}

-- Their goodbye going back in, still facing you (the displeased ones end with the door slammed).
local GOODBYES: { [string]: Bye } = {
	-- A slow wave, the hand up by their head, the head on one side.
	wave = {
		time = 1.4,
		slam = false,
		pose = function(t)
			return { near = { pitch = 0.45, roll = 2.0 + 0.3 * math.sin(t * 8) }, tilt = 0.25 }
		end,
	},
	-- A deep bow, slow, held a little too long.
	bow = {
		time = 1.5,
		slam = false,
		sound = "Breath",
		pose = function()
			return { fold = 0.75, nod = -0.35 }
		end,
	},
	-- Two nods and a little hand raised to you.
	nod = {
		time = 1.1,
		slam = false,
		pose = function(t)
			return { near = { pitch = 0.35, roll = 1.0 + 0.15 * math.sin(t * 10) }, nod = -0.32 * pulse(t * 7) }
		end,
	},
	-- A sweeping bow, one arm flung out wide.
	flourish = {
		time = 1.6,
		slam = false,
		sound = "Whoosh",
		pose = function(t)
			local down = smooth(t / 0.5)
			return {
				near = { pitch = 0.6, roll = 1.4 * down },
				far = { pitch = 0.9, roll = -0.5 },
				fold = 0.6 * down,
				nod = -0.3,
			}
		end,
	},
	-- A quick little wave down low, the head bobbing.
	fingerWave = {
		time = 1.2,
		slam = false,
		pose = function(t)
			return {
				near = { pitch = 1.1, roll = 0.35 + 0.35 * math.sin(t * 16) },
				nod = 0.1 * math.sin(t * 8),
				tilt = 0.2,
			}
		end,
	},
	-- A finger to the lips as they back away: not a word.
	shushBye = {
		time = 1.4,
		slam = false,
		sound = "Whispers",
		pose = function()
			return { far = { pitch = 2.7, roll = -0.2 }, fold = 0.18, nod = -0.08, tilt = 0.25 }
		end,
	},
	-- A kiss blown at you from the fingertips.
	blowKiss = {
		time = 1.4,
		slam = false,
		pose = function(t)
			local out = smooth((t - 0.5) / 0.3)
			return { far = { pitch = 2.55 - 1.0 * out, roll = -0.3 + 0.4 * out }, tilt = 0.3, nod = -0.05 }
		end,
	},
	-- A stiff salute.
	salute = {
		time = 1.3,
		slam = false,
		pose = function()
			return { near = { pitch = 2.55, roll = 0.5 }, nod = 0.1, fold = -0.05 }
		end,
	},
	-- The seller's: two fingers to the brow and a nod.
	tip = {
		time = 1.2,
		slam = false,
		pose = function(t)
			return { near = { pitch = 2.6, roll = 0.35 }, nod = -0.25 * pulse(t * 5) }
		end,
	},
	-- A finger jabbed at you, twice, leaning in.
	point = {
		time = 1.0,
		slam = true,
		pose = function(t)
			return { near = { pitch = 1.55 + 0.18 * pulse(t * 9) ^ 3 }, fold = 0.15 }
		end,
	},
	-- The back of the hand flicked at you (go away), the head turned from you.
	shoo = {
		time = 1.0,
		slam = true,
		sound = "Whoosh",
		pose = function(t)
			return { near = { pitch = 0.8, roll = 0.3 + 0.6 * pulse(t * 11) }, turn = 0.45, fold = -0.06 }
		end,
	},
	-- Just a long stare, the head tipping over, leaning in.
	stare = {
		time = 1.5,
		slam = true,
		sound = "Breath",
		pose = function()
			return { tilt = 0.55, fold = 0.18, nod = -0.12 }
		end,
	},
	-- A slow shake of the head.
	headShake = {
		time = 1.3,
		slam = true,
		pose = function(t)
			return { turn = 0.35 * math.sin(t * 7), nod = -0.15, fold = 0.05 }
		end,
	},
	-- A foot stamped on the boards.
	stomp = {
		time = 1.0,
		slam = true,
		sound = "Thud",
		pose = function(t)
			local up = smooth(t / 0.2) * (1 - smooth((t - 0.3) / 0.08))
			return { step = 0.45 * up, both = { pitch = 0.15, roll = 0.15 }, fold = 0.15, nod = -0.2 }
		end,
	},
}

local function weighted(list: { [number]: any }): Weighted
	local out: Weighted = {}
	for i = 1, #list, 2 do
		table.insert(out, { name = list[i], weight = list[i + 1] })
	end
	return out
end

-- Which sort they are: by the house's Dialogue personality (its "Owner"), or the seller.
local TEMPERAMENTS: { [string]: Temperament } = {
	-- Manners: tidy, stiff, a bow.
	Host = {
		every = 4.5,
		chance = 0.55,
		acts = weighted({ "dust", 3, "watch", 2, "lookBack", 2, "shift", 1, "lean", 1, "cock", 1 }),
		hello = "greet",
		pleased = "chest",
		displeased = "wag",
		gives = weighted({ "offer", 3, "hand", 1 }),
		glare = "palm",
		byes = {
			pleased = weighted({ "bow", 3, "nod", 1 }),
			displeased = weighted({ "stare", 1, "point", 1, "shoo", 1 }),
		},
	},
	-- Rhymes: theatrical, a tune in their head.
	Rhymer = {
		every = 4,
		chance = 0.6,
		acts = weighted({ "hum", 3, "drum", 2, "cock", 2, "tapFoot", 2, "shift", 1, "sniff", 1 }),
		hello = "spread",
		pleased = "spread",
		displeased = "shrug",
		gives = weighted({ "toss", 2, "hand", 1 }),
		glare = "shield",
		byes = {
			pleased = weighted({ "flourish", 3, "wave", 2 }),
			displeased = weighted({ "shoo", 2, "headShake", 1 }),
		},
	},
	-- Playing along: fidgety, giggly, a tantrum when you get it wrong.
	Child = {
		every = 3.2,
		chance = 0.75,
		acts = weighted({ "giggle", 3, "rock", 2, "beckon", 2, "cock", 1, "sniff", 1, "wring", 1 }),
		hello = "bounce",
		pleased = "bounce",
		displeased = "fist",
		gives = weighted({ "toss", 2, "tease", 2 }),
		glare = "cover",
		byes = {
			pleased = weighted({ "fingerWave", 3, "wave", 1 }),
			displeased = weighted({ "stomp", 2, "stare", 2 }),
		},
	},
	-- Whispering: secrets, listening to the house.
	Whisperer = {
		every = 5,
		chance = 0.5,
		acts = weighted({ "shush", 2, "peerPast", 2, "lookUp", 2, "cock", 2, "lean", 2, "lookBack", 1 }),
		hello = "cup",
		pleased = "cup",
		displeased = "shush",
		gives = weighted({ "hand", 2, "tease", 1 }),
		glare = "shield",
		byes = {
			pleased = weighted({ "shushBye", 2, "nod", 1 }),
			displeased = weighted({ "stare", 3, "point", 1 }),
		},
	},
	-- Compliments: greedy, close, hands rubbing.
	Collector = {
		every = 4,
		chance = 0.6,
		acts = weighted({ "wring", 3, "beckon", 2, "lean", 2, "sniff", 2, "scratch", 1 }),
		hello = "rub",
		pleased = "rub",
		displeased = "point",
		gives = weighted({ "tease", 3, "drop", 1 }),
		glare = "shield",
		byes = {
			pleased = weighted({ "blowKiss", 2, "wave", 1 }),
			displeased = weighted({ "stare", 2, "shoo", 1 }),
		},
	},
	-- Bravery: an old soldier, hard of hearing, stiff in the neck.
	OldMan = {
		every = 5.5,
		chance = 0.5,
		acts = weighted({ "rock", 2, "tapFoot", 2, "crack", 2, "yawn", 2, "watch", 1, "shift", 1, "scratch", 1 }),
		hello = "ear",
		pleased = "beat",
		displeased = "wag",
		gives = weighted({ "pinch", 3, "drop", 1 }),
		glare = "palm",
		byes = {
			pleased = weighted({ "salute", 3, "nod", 1 }),
			displeased = weighted({ "shoo", 2, "headShake", 2 }),
		},
	},
	-- The seller: counting his takings, watching the street for him, handing over what you buy.
	Seller = {
		every = 3.6,
		chance = 0.7,
		acts = weighted({ "countCoins", 3, "lookOut", 3, "patPockets", 2, "lean", 1, "drum", 1 }),
		hello = "spread",
		pleased = "rub",
		displeased = "shrug",
		gives = weighted({ "hand", 3, "offer", 1 }),
		glare = "palm",
		byes = {
			pleased = weighted({ "tip", 3, "nod", 1 }),
			displeased = weighted({ "headShake", 2, "shoo", 1, "stare", 1 }),
		},
	},
	-- Anyone else (a personality this doesn't know): a bit of everything.
	Default = {
		every = 4.5,
		chance = 0.55,
		acts = weighted({ "lookBack", 1, "cock", 1, "scratch", 1, "drum", 1, "shift", 1, "lean", 1, "sniff", 1 }),
		hello = "beat",
		pleased = "beat",
		displeased = "point",
		gives = weighted({ "hand", 1 }),
		glare = "shield",
		byes = {
			pleased = weighted({ "wave", 1, "bow", 1, "nod", 1 }),
			displeased = weighted({ "point", 1, "shoo", 1, "stare", 1 }),
		},
	},
}

OwnerMoves.ACTS = ACTS
OwnerMoves.TALKS = TALKS
OwnerMoves.GIVES = GIVES
OwnerMoves.REACTIONS = REACTIONS
OwnerMoves.GOODBYES = GOODBYES
OwnerMoves.TEMPERAMENTS = TEMPERAMENTS
OwnerMoves.FAVOURITE = 3 -- a house's favourite act is this many times as likely as it'd be

-- The temperament of a homeowner: `owner` the house's Dialogue personality, `seller` whether it's
-- the seller's house.
function OwnerMoves.temperament(owner: any, seller: boolean?): Temperament
	if seller then
		return TEMPERAMENTS.Seller
	end
	return (if type(owner) == "string" then TEMPERAMENTS[owner] else nil) or TEMPERAMENTS.Default
end

-- One of `list` by weight, with `roll` (0..1).
function OwnerMoves.pick(list: Weighted, roll: number): string
	local total = 0
	for _, entry in list do
		total += entry.weight
	end
	local at = roll * total
	for _, entry in list do
		at -= entry.weight
		if at < 0 then
			return entry.name
		end
	end
	return list[#list].name
end

-- Their acts, with this house's favourite (from `seed`) made more likely.
function OwnerMoves.acts(temper: Temperament, seed: number): Weighted
	local favourite = Rng.new(seed + 71):int(1, #temper.acts)
	local out: Weighted = {}
	for i, entry in temper.acts do
		table.insert(out, {
			name = entry.name,
			weight = if i == favourite then entry.weight * OwnerMoves.FAVOURITE else entry.weight,
		})
	end
	return out
end

-- What they're doing at server time `now` (nil when nothing), and how far into it: the same on every
-- screen (the house's `seed`). `acts` is OwnerMoves.acts(temper, seed).
function OwnerMoves.actAt(temper: Temperament, acts: Weighted, seed: number, now: number): (string?, number, number)
	local window = math.floor(now / temper.every)
	local roll = Rng.new(seed + window * 13)
	if roll:next() >= temper.chance then
		return nil, 0, window
	end
	local name = OwnerMoves.pick(acts, roll:next())
	local t = now - window * temper.every - roll:range(0, 0.8)
	local def = ACTS[name]
	if def == nil or t < 0 or t >= math.min(def.time, temper.every - 0.05) then
		return nil, 0, window
	end
	return name, t, window
end

-- A goodbye for a visit that went `mood` ("pleased"/"displeased"), with `roll` (0..1): DoorService.
function OwnerMoves.bye(owner: any, seller: boolean?, mood: string, roll: number): string
	local temper = OwnerMoves.temperament(owner, seller)
	return OwnerMoves.pick(if mood == "pleased" then temper.byes.pleased else temper.byes.displeased, roll)
end

-- How they talk: their hello before anything's happened, then by how it went (OwnerMood), or
-- pleased once they've handed you something.
function OwnerMoves.talk(temper: Temperament, mood: any, answered: boolean): string
	if mood == "displeased" then
		return temper.displeased
	elseif mood == "pleased" or answered then
		return temper.pleased
	end
	return temper.hello
end

return OwnerMoves
