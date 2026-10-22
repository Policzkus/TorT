--!strict
-- Starter kids and costumes (PROMPT §V2.1/V2.3). Nobody plays as their Roblox avatar: each starter
-- and each costume is a whole character model from Config/Characters, and wearing a costume swaps
-- your character. Without a costume, homeowners barely give anything (NO_COSTUME_CANDY), so the
-- first costume is cheap. Each costume adds `bonus` to door candy; a costume whose tag matches the
-- homeowner's preference (Classic/Spooky/Cute/Funny) adds HouseTypes.PREFERENCE_BONUS on top.
-- Costumes are kept forever (rebirth too).

export type Starter = { name: string, character: string, blurb: string }

export type Costume = {
	name: string,
	character: string,
	tag: string,
	rarity: string, -- "Common" | "Rare" | "Epic" | "Legendary"
	bonus: number,
	price: number, -- candy
	order: number,
}

local starters: { [string]: Starter } = {
	Milo = { name = "Milo", character = "Kid_Milo", blurb = "Hasn't slept properly in weeks." },
	Ivy = { name = "Ivy", character = "Kid_Ivy", blurb = "Keeps a list of the houses that watch back." },
	Theo = { name = "Theo", character = "Kid_Theo", blurb = "Always ready for the rain. It never rains." },
	Nell = { name = "Nell", character = "Kid_Nell", blurb = "Dared everyone. Nobody dared back." },
}

local costumes: { [string]: Costume } = {
	GhostSheet = {
		name = "Sheet Ghost",
		character = "Costume_GhostSheet",
		tag = "Spooky",
		rarity = "Common",
		bonus = 0.05,
		price = 10,
		order = 1,
	},
	PumpkinHead = {
		name = "Pumpkin Head",
		character = "Costume_PumpkinHead",
		tag = "Classic",
		rarity = "Common",
		bonus = 0.05,
		price = 60,
		order = 2,
	},
	Witch = {
		name = "Little Witch",
		character = "Costume_Witch",
		tag = "Spooky",
		rarity = "Common",
		bonus = 0.06,
		price = 180,
		order = 3,
	},
	BlackCat = {
		name = "Black Cat",
		character = "Costume_BlackCat",
		tag = "Cute",
		rarity = "Rare",
		bonus = 0.08,
		price = 450,
		order = 4,
	},
	Skeleton = {
		name = "Skeleton",
		character = "Costume_Skeleton",
		tag = "Spooky",
		rarity = "Rare",
		bonus = 0.1,
		price = 1500,
		order = 5,
	},
	Vampire = {
		name = "Vampire",
		character = "Costume_Vampire",
		tag = "Classic",
		rarity = "Epic",
		bonus = 0.14,
		price = 6000,
		order = 6,
	},
}

return {
	starters = starters,
	STARTER_ORDER = { "Milo", "Ivy", "Theo", "Nell" },
	costumes = costumes,
	-- Candy multiplier while wearing no costume.
	NO_COSTUME_CANDY = 0.15,
	-- Used when a character's meshes aren't available.
	FALLBACK_CHARACTER = "Kid_Milo",
}
