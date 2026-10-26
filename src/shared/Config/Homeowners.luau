--!strict
-- The uncanny PSX homeowners who answer the door (PROMPT §V2.1/V2.3).
-- Each house rolls a homeowner from its neighbourhood's pool every Night, plus a seed that every
-- client turns into the same body (stretched legs, arms hanging too low, a head too small or too
-- big, a thin frame, a crooked tilt). Later neighbourhoods push those further. Every knock also picks
-- how they come out (STYLES), so the same door never plays out the same way twice.
-- Owners are Config/Characters ids: the Blender homeowners (art/scripts/characters.py), rigged, so
-- they move, duck and track you with their head. Ids whose meshes aren't in the place are skipped.

export type Range = { min: number, max: number }

-- The whole cast (art/scripts/characters.py). Every street deals from all of it, like a shuffled
-- deck (HomeownerService.roll): no homeowner shows up twice on a street until all of them have.
local CAST = {
	"Owner_Curlers",
	"Owner_Lanky",
	"Owner_Nightgown",
	-- (Owner_SackMask is the Knifer now: Config/Knifer.CHARACTER. Never at a door.)
	"Owner_TankTop",
	"Owner_Cardigan",
	"Owner_SweaterVest",
	"Owner_Porcelain",
	"Owner_Grinner",
	"Owner_PumpkinSuit",
	"Owner_Widow",
	"Owner_RavenMan",
	"Owner_Bathrobe",
	"Owner_Butler",
	"Owner_MaskedLady",
	"Owner_Gown",
	"Owner_BagMan",
}

local POOLS: { [string]: { string } } = {
	CardboardCourt = CAST,
	MapleLane = CAST,
	PumpkinHollow = CAST,
	RavenRidge = CAST,
	MansionHill = CAST,
	BlackwoodEstates = CAST,
}

-- How unsettling each neighbourhood's homeowners get (0..1): biases the morphs toward the extremes.
local CREEP: { [string]: number } = {
	CardboardCourt = 0.15,
	MapleLane = 0.3,
	PumpkinHollow = 0.5,
	RavenRidge = 0.65,
	MansionHill = 0.8,
	BlackwoodEstates = 1,
}

return {
	POOLS = POOLS,
	CREEP = CREEP,
	-- Base height of a homeowner in studs (doors are HouseModels.DOOR_HEIGHT = 7.5; taller ones duck).
	HEIGHT = 7.2,

	-- Body morph ranges (CharacterRig.Morph). Low CREEP rolls near the first value, high CREEP near
	-- the second.
	MORPH = {
		scale = { min = 0.9, max = 1.1 } :: Range,
		stretch = { min = 1, max = 1.28 } :: Range,
		arms = { min = 1, max = 1.6 } :: Range,
		head = { min = 0.68, max = 1.3 } :: Range, -- either end is wrong; the middle is normal
		thin = { min = 0.72, max = 1 } :: Range,
		neck = { min = 0, max = 0.45 } :: Range,
	},
	TILT = 16, -- max head/body tilt in degrees

	-- How they come out of the door (HomeownerController plays them; they always walk, step by step):
	--   Creep   - the door eases open on darkness, footsteps up the hall, they walk out slowly
	--   Waiting - the door opens and they were already standing in the dark, head bowed; two steps
	--   Peek    - the door opens a crack, their head leans out sideways first; then they come
	--   Rush    - the door is yanked open and they stride straight out at you, and stop dead
	--   Flicker - the porch light stutters while something comes up the hall; it steadies as they stop
	STYLES = { "Creep", "Waiting", "Peek", "Rush", "Flicker" },

	-- Seconds from the knock being answered until they've stopped on the porch, per style (the
	-- walk's start + length in HomeownerController's WALK; a long hall can make it a little later,
	-- and their hello waits for them).
	OUT_AFTER = { Creep = 2.4, Waiting = 2.5, Peek = 2.7, Rush = 1.3, Flicker = 2.4 } :: { [string]: number },
	HELLO_TIME = 2.4, -- seconds they have for their hello before the mini-game starts (skippable: MinigameSkip)
	LEAVE_DELAY = 2.0, -- seconds they linger after the mini-game at least (longer if they're still talking)
	AFTER_LINE = 0.3, -- seconds between their last line fading and them turning back in
	-- Seconds from them starting back in to the door shut on them, about (HomeownerController's turn,
	-- walk back and close; a little under, so a door's cooldown never reads more than its full time).
	SHUT_AFTER = 2.2,
	-- Seconds from a slap starting to it landing (HomeownerController's SLAP): what they say after it
	-- waits for this.
	SLAP_LANDS = 0.33,
	TWITCH_EVERY = { min = 0.6, max = 2.2 } :: Range,
	STAND_OFF = 0.2, -- studs between the wall round the door and the back of them, once they've turned to you
}
