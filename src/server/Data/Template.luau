--!strict
-- Default data for a brand-new player. Adding a key here is safe (Reconcile fills it in for
-- existing players). Renaming, removing or changing the shape of a key needs a migration.
local Types = require(game:GetService("ReplicatedStorage").Shared.Modules.Types)

local Template: Types.PlayerData = {
	version = 1,

	candy = 0,
	bucket = 0,
	souls = 0,
	rebirths = 0,

	upgrades = {
		bucketTier = 1,
		sneakers = 0,
		charm = 0,
		stealth = 0,
		luck = 0,
		flashlight = 0,
	},
	soulPerks = {},
	neighborhoods = { CardboardCourt = true },

	rareCandy = {},
	inventory = {},
	equipped = { familiars = {} },
	index = {},
	pity = {},

	boosts = {},
	consumables = {},
	codes = {},
	purchases = {},

	daily = { streak = 0, lastDay = 0 },
	quests = {},
	tutorial = { step = 1, done = false },

	stats = {
		lifetimeCandy = 0,
		doors = 0,
		perfects = 0,
		bestStreak = 0,
		loots = 0,
		caught = 0,
		escapes = 0,
		cases = 0,
		playtime = 0,
	},
	settings = {
		music = 0.5,
		sfx = 1,
		jumpscare = "Full",
		reduceFlash = false,
		psx = true,
	},

	firstJoin = 0,
	lastJoin = 0,
}

return Template
