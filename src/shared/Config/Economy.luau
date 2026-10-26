--!strict
-- Core economy numbers (PROMPT §3.7–3.8). Tuned with tests/economy_sim.luau; see docs/ECONOMY.md.
return {
	GRADES = { "MISS", "GOOD", "GREAT", "PERFECT" },
	GRADE_MULTIPLIER = { MISS = 0.4, GOOD = 1, GREAT = 1.6, PERFECT = 2.5 } :: { [string]: number },
	-- A door never gives less than this, even on a MISS.
	MIN_DOOR_CANDY = 1,

	-- Sweet Streak (Phase 2): +STEP per consecutive GREAT/PERFECT, capped at MAX.
	STREAK_STEP = 0.10,
	STREAK_MAX = 1.0,

	-- Permanent candy bonus per rebirth.
	REBIRTH_BONUS = 0.4,
	-- Witching Hour × Blood Moon etc. multiply together, but never beyond this.
	EVENT_MULTIPLIER_CAP = 4,

	-- Candy Box (bank) capacity per life: index = rebirths + 1. After the list, each rebirth ×BOX_GROWTH.
	BOX_CAPACITY = { 25e3, 150e3, 600e3, 2.5e6, 10e6, 40e6 },
	BOX_GROWTH = 4,

	-- Seconds before a house gives anyone candy again: its cooldown is shared (the user wants it synced),
	-- counted from when its door shuts again.
	-- PROMPT says 4 min; the sim showed players idling on a 16-house street, so 90 s (PROGRESS.md).
	DOOR_COOLDOWN = 90,
	-- Max studs between the player and the door for a knock to count (server check).
	DOOR_RANGE = 12,
	-- While they're coming out or playing you can move about, up to DOOR_LEASH studs from the door
	-- (keep pushing past it and you leave); this far and the visit is off: no mini-game, no candy, no
	-- cooldown (client and server both check).
	DOOR_LEASH = 11,
	DOOR_LEAVE = 16,
	-- Radius of a Candy Box drop-off circle.
	STASH_RADIUS = 10,
}
