--!strict
-- House types, rolled per house at every Dawn (PROMPT §3.5), and homeowner preferences.

-- Open: the front door stands open on a lit hall and nobody answers (one day you'll be able to walk
-- in: the heists). Only houses with a real door and a hall can be open (HouseService).
export type HouseType = "Normal" | "Decorated" | "Trick" | "Bowl" | "LightsOff" | "Open"

return {
	-- Candy multiplier and added mini-game difficulty per type.
	CANDY = { Normal = 1, Decorated = 1.5, Trick = 2.5 } :: { [string]: number },
	DIFFICULTY = { Normal = 0, Decorated = 1, Trick = 0 } :: { [string]: number },

	-- Roll weights per neighborhood tier (index = tier). Tier 1 never has trick houses. The candy bowl
	-- (Config/Bowl) is rare: about one house in 30.
	WEIGHTS = {
		{ Normal = 67, Decorated = 10, Trick = 0, Bowl = 3, LightsOff = 10, Open = 8 },
		{ Normal = 60, Decorated = 12, Trick = 5, Bowl = 3, LightsOff = 9, Open = 8 },
		{ Normal = 53, Decorated = 14, Trick = 10, Bowl = 3, LightsOff = 8, Open = 8 },
		{ Normal = 46, Decorated = 16, Trick = 15, Bowl = 3, LightsOff = 7, Open = 8 },
		{ Normal = 39, Decorated = 18, Trick = 20, Bowl = 3, LightsOff = 6, Open = 8 },
		{ Normal = 32, Decorated = 20, Trick = 25, Bowl = 3, LightsOff = 5, Open = 8 },
	} :: { { [string]: number } },

	-- What the homeowner likes. A matching costume tag gives +40% (costumes arrive in Phase 4).
	PREFERENCES = { "Classic", "Spooky", "Cute", "Funny" },
	PREFERENCE_ICONS = { Classic = "🎃", Spooky = "👻", Cute = "🐱", Funny = "🤡" } :: { [string]: string },
	PREFERENCE_BONUS = 0.4,
}
