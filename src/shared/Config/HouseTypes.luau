--!strict
-- House types, rolled per house at every Dawn (PROMPT §3.5), and homeowner preferences.

-- Open: the front door stands open on a lit hall and nobody answers (one day you'll be able to walk
-- in: the heists). Only houses with a real door and a hall can be open (HouseService).
export type HouseType = "Normal" | "Decorated" | "Trick" | "Bowl" | "LightsOff" | "Open"

return {
	-- Candy multiplier and added mini-game difficulty per type.
	CANDY = { Normal = 1, Decorated = 1.5, Trick = 2.5 } :: { [string]: number },
	DIFFICULTY = { Normal = 0, Decorated = 1, Trick = 0 } :: { [string]: number },

	-- Roll weights per neighborhood tier (index = tier). Tier 1 never has trick houses.
	WEIGHTS = {
		{ Normal = 60, Decorated = 10, Trick = 0, Bowl = 10, LightsOff = 10, Open = 8 },
		{ Normal = 54, Decorated = 12, Trick = 5, Bowl = 9, LightsOff = 9, Open = 8 },
		{ Normal = 48, Decorated = 14, Trick = 10, Bowl = 8, LightsOff = 8, Open = 8 },
		{ Normal = 42, Decorated = 16, Trick = 15, Bowl = 7, LightsOff = 7, Open = 8 },
		{ Normal = 36, Decorated = 18, Trick = 20, Bowl = 6, LightsOff = 6, Open = 8 },
		{ Normal = 30, Decorated = 20, Trick = 25, Bowl = 5, LightsOff = 5, Open = 8 },
	} :: { { [string]: number } },

	-- Take-One Bowl: take one safely, or hold TAKE ALL for a big haul and a chance to get caught.
	BOWL_TAKE_ONE = 1,
	BOWL_TAKE_ALL = 12,
	BOWL_TAKE_ALL_HOLD = 3, -- seconds
	BOWL_CAUGHT_CHANCE = 0.35,
	-- Share of the carried bucket lost when caught (Candy Insurance pass: 0.25, Phase 6).
	CAUGHT_LOSS = 0.5,

	-- What the homeowner likes. A matching costume tag gives +40% (costumes arrive in Phase 4).
	PREFERENCES = { "Classic", "Spooky", "Cute", "Funny" },
	PREFERENCE_ICONS = { Classic = "🎃", Spooky = "👻", Cute = "🐱", Funny = "🤡" } :: { [string]: string },
	PREFERENCE_BONUS = 0.4,
}
