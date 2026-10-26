--!strict
-- Shared type definitions. Keep PlayerData in sync with src/server/Data/Template.luau.

export type InventoryItem = {
	id: string,
	golden: boolean,
	locked: boolean,
	t: number, -- os.time() when obtained
}

export type PlayerData = {
	version: number,

	candy: number, -- banked in the Candy Box (never lost)
	bucket: number, -- carried (lost by half when caught)
	souls: number,
	rebirths: number,
	lives: number, -- PROMPT §V2.3: die inside a house → -1; at 0 → lose half the banked candy
	livesRefillAt: number,

	upgrades: {
		bucketTier: number,
		sneakers: number,
		charm: number,
		stealth: number,
		luck: number,
	},
	soulPerks: { [string]: number },
	neighborhoods: { [string]: boolean },

	starter: string, -- Config/Costumes starter kid ("" until picked)
	costumes: { [string]: boolean }, -- owned costumes (kept through rebirth)
	rareCandy: { [string]: number }, -- [caseId] = count
	inventory: { [string]: InventoryItem }, -- [uid] = item
	equipped: {
		bucketSkin: string?,
		costume: string?,
		familiars: { string },
	},
	index: { [string]: boolean },
	pity: { [string]: { sincePink: number, sinceRed: number } },

	boosts: { [string]: number }, -- [boostId] = remaining play-seconds
	consumables: { [string]: number },
	codes: { [string]: boolean },
	purchases: { string }, -- recent developer-product PurchaseIds (receipt idempotency)

	daily: { streak: number, lastDay: number },
	quests: { [string]: any },
	tutorial: { step: number, done: boolean },

	stats: {
		lifetimeCandy: number,
		doors: number,
		perfects: number,
		bestStreak: number,
		loots: number,
		caught: number,
		escapes: number,
		cases: number,
		playtime: number,
	},
	settings: {
		music: number,
		sfx: number,
		jumpscare: string, -- "Full" | "Reduced" | "Off"
		reduceFlash: boolean,
		psx: boolean, -- PSX camera grade, blur and grain
	},

	firstJoin: number,
	lastJoin: number,
}

return {}
