--!strict
-- The uncanny PSX homeowners who answer the door (PROMPT §V2.1/V2.3). Each house rolls one per
-- Night plus a random stretch/scale/tilt, so no two doors look alike. Keys are Config/Meshes names.
return {
	ROSTER = {
		"Owner_Cardigan", -- bald, googly eyes, grey cardigan
		"Owner_Nightgown", -- tiny grandma, fixed smile, candy bowl
		"Owner_Lanky", -- round green-grey head, hollow eyes, stick limbs
		"Owner_Bathrobe", -- blank white mask, stained bathrobe
		"Owner_Grinner", -- pear-shaped, enormous grin
	} :: { string },

	-- Per-house variation.
	STRETCH = { min = 1, max = 1.2 }, -- extra height (long and thin), capped so faces stay in view
	SCALE = { min = 0.9, max = 1.12 },
	TILT = 12, -- max head/body tilt in degrees

	APPEAR_TIME = 0.7, -- seconds to slide out of the doorway
	LEAVE_DELAY = 1.4, -- seconds they linger after the mini-game
	TWITCH_EVERY = { min = 0.4, max = 1.3 },
}
