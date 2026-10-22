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

	-- The door knocks a pattern; repeat it in time. Graded by the average timing error.
	KnockRhythm = {
		easyKnocks = 3,
		hardKnocks = 7,
		easyBpm = 90,
		hardBpm = 140,
		syncopationFrom = 3, -- half-beat gaps
		longGapFrom = 4, -- 1.5-beat gaps
		fakesFrom = 5, -- creaks to ignore while listening
		leadIn = 0.6, -- seconds before the first knock
		gapBeforeTurn = 0.7, -- after the last knock, before "YOUR TURN"
		answerTime = 3, -- extra seconds after the pattern length to finish repeating
		-- Average error (s) per grade.
		perfect = 0.07,
		great = 0.12,
		good = 0.2,
		missingTapError = 0.5,
	},

	-- Hold through the scares; letting go early is a flinch.
	NerveHold = {
		easyDuration = 3,
		hardDuration = 7,
		pressWindow = 1.5, -- seconds to start holding
		trapsFrom = 5, -- fake "LET GO!" whispers
		-- Share of the hold completed per grade.
		perfect = 1,
		great = 0.75,
		good = 0.45,
	},

	-- Pick the answer the homeowner would like. Faster correct answers grade higher.
	CostumeLine = {
		easyOptions = 2,
		hardOptions = 4,
		easyTimer = 8,
		hardTimer = 4,
		perfectShare = 0.35, -- answered within this share of the timer
		greatShare = 0.65,
	},
}
