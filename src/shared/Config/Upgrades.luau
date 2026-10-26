--!strict
-- Candy shop upgrade tracks (PROMPT §3.12). Levels reset on rebirth.
-- "tiers" tracks have an explicit list; "levels" tracks use cost = baseCost × growth^level and
-- maxLevel = maxLevel + maxPerRebirth × rebirths.
-- Rule: every price in life R must be ≤ 50% of that life's Candy Box capacity (Economy.BOX_CAPACITY).

export type Tier = {
	name: string,
	capacity: number,
	cost: number, -- price to reach this tier from the previous one
	rebirths: number, -- rebirths needed before it can be bought
	model: string, -- Shared/Models/Buckets builder name
}

export type Track = {
	name: string,
	icon: string,
	kind: "tiers" | "levels",
	description: string,
	tiers: { Tier }?,
	perLevel: number?,
	baseValue: number?,
	baseCost: number?,
	growth: number?,
	maxLevel: number?,
	maxPerRebirth: number?,
}

local tracks: { [string]: Track } = {
	bucketTier = {
		name = "Bucket",
		icon = "🎃",
		kind = "tiers",
		description = "Carry more candy per trip",
		tiers = {
			{ name = "Paper Bag", capacity = 15, cost = 0, rebirths = 0, model = "PaperBag" },
			{ name = "Plastic Pumpkin", capacity = 50, cost = 20, rebirths = 0, model = "PlasticPumpkin" },
			{ name = "Pillowcase", capacity = 120, cost = 90, rebirths = 0, model = "Pillowcase" },
			{ name = "Trick Sack", capacity = 300, cost = 350, rebirths = 0, model = "TrickSack" },
			{ name = "Trash Bag", capacity = 750, cost = 1200, rebirths = 0, model = "TrashBag" },
			{ name = "Laundry Basket", capacity = 2000, cost = 3500, rebirths = 0, model = "LaundryBasket" },
			{ name = "Wheelbarrow", capacity = 5000, cost = 10000, rebirths = 0, model = "Wheelbarrow" },
			{ name = "Wagon", capacity = 12500, cost = 35000, rebirths = 1, model = "Wagon" },
			{ name = "Coffin", capacity = 30000, cost = 70000, rebirths = 1, model = "Coffin" },
			{ name = "Cauldron", capacity = 80000, cost = 250000, rebirths = 2, model = "Cauldron" },
			{ name = "Haunted Wardrobe", capacity = 200000, cost = 1000000, rebirths = 3, model = "Wardrobe" },
			{ name = "Black Hole Bucket", capacity = 1000000, cost = 4500000, rebirths = 4, model = "BlackHole" },
		},
	},
	charm = {
		name = "Charm",
		icon = "😇",
		kind = "levels",
		description = "+10% candy from every door",
		perLevel = 0.10,
		baseCost = 30,
		growth = 1.45,
		maxLevel = 10,
		maxPerRebirth = 5,
	},
	sneakers = {
		name = "Sneakers",
		icon = "👟",
		kind = "levels",
		description = "Walk faster between houses",
		perLevel = 1,
		baseValue = 16,
		baseCost = 40,
		growth = 1.85,
		maxLevel = 10,
		maxPerRebirth = 0,
	},
}

return {
	-- Shop display order. Stealth and Luck arrive with their systems (Phases 3–4). There's no flashlight.
	ORDER = { "bucketTier", "charm", "sneakers" },
	tracks = tracks,
}
