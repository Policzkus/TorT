--!strict
-- Door mini-game tuning (PROMPT §3.6). Difficulty = neighborhood tier (+1 decorated, +1 Witching Hour).
return {
	DIFFICULTY_MIN = 1,
	DIFFICULTY_MAX = 8,

	-- Anti-cheat limits on submitted input (seconds).
	MIN_REACTION = 0.12, -- no human taps faster than this after the challenge starts
	MIN_TAP_GAP = 0.08, -- between two taps
	LATENCY_GRACE = 0.15, -- a tap can't be claimed later than the server says time has passed
	EXPIRE_GRACE = 4, -- an unanswered challenge is dropped this long after its timeout

	TimingBar = {
		-- Full zone widths as a fraction of the bar, at difficulty 1 (easy) and 8 (hard).
		easyWidths = { GOOD = 0.30, GREAT = 0.14, PERFECT = 0.06 },
		hardWidths = { GOOD = 0.16, GREAT = 0.07, PERFECT = 0.025 },
		-- Seconds for one pass of the needle across the bar.
		easySweep = 1.6,
		hardSweep = 0.7,
		twoHitsFrom = 4,
		reverseFrom = 6,
		-- Zone centres are rolled in this range so there's always time to react.
		zoneMin = 0.35,
		zoneMax = 0.85,
		-- Passes the needle makes per hit before the hit counts as a MISS.
		passesPerHit = 2.5,
	},
}
