--!strict
-- The uncanny PSX homeowners who answer the door (PROMPT §V2.1/V2.3).
-- Each house rolls a homeowner from its neighbourhood's pool every Night, plus a seed that every
-- client turns into the same body (stretched legs, arms hanging too low, a head too small or too
-- big, a thin frame, a crooked tilt). Later neighbourhoods push those further. Every knock also picks
-- how they come out (STYLES), so the same door never plays out the same way twice.
-- Owners are Config/Characters ids (rigged: they move, duck, track you with their head) or
-- Config/Meshes names (older one-piece statues: they slide and twitch). Missing ids are skipped.

export type Range = { min: number, max: number }

local POOLS: { [string]: { string } } = {
	CardboardCourt = { "Owner_TankTop", "Owner_Curlers", "Owner_Cardigan", "Owner_Nightgown" },
	MapleLane = { "Owner_SweaterVest", "Owner_Porcelain", "Owner_Grinner", "Owner_Curlers", "Owner_Cardigan" },
	PumpkinHollow = { "Owner_SackMask", "Owner_PumpkinSuit", "Owner_Lanky", "Owner_Grinner", "Owner_TankTop" },
	RavenRidge = { "Owner_Widow", "Owner_RavenMan", "Owner_Bathrobe", "Owner_Lanky", "Owner_SackMask" },
	MansionHill = { "Owner_Butler", "Owner_MaskedLady", "Owner_Porcelain", "Owner_Bathrobe", "Owner_Widow" },
	BlackwoodEstates = { "Owner_Gown", "Owner_BagMan", "Owner_Butler", "Owner_Lanky", "Owner_PumpkinSuit" },
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

	-- How they come out of the door:
	--   Creep    - the door eases open on darkness; they drift out slowly, stiff
	--   Snap     - the door opens, nothing... then they're just there, inches closer
	--   Peek     - the door opens a crack, the head leans out sideways first
	--   Waiting  - the door opens and they were already standing right behind it, head bowed
	--   Blackout - the porch light dies; when it flickers back they're on the porch
	STYLES = { "Creep", "Snap", "Peek", "Waiting", "Blackout" },

	-- Seconds from the knock being answered until they're out on the threshold, per style.
	OUT_AFTER = { Snap = 1.8, Blackout = 1.7, Peek = 2.7, Waiting = 2.3, Creep = 2.8 } :: { [string]: number },
	HELLO_TIME = 4.2, -- seconds they have for their hello before the mini-game starts (the longest types in ~4.5)
	LEAVE_DELAY = 3.8, -- seconds they linger after the mini-game (long enough to say what they think)
	TWITCH_EVERY = { min = 0.6, max = 2.2 } :: Range,
	STAND_OFF = 0.2, -- studs in front of the door surface they stand: on the threshold, in the doorway
}
