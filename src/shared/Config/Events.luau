--!strict
-- Night cycle and live events (PROMPT §3.4). Times in seconds; timestamps in Unix UTC.
return {
	-- One Night: 6:00 PM to midnight in 18 real minutes (3 minutes per in-game hour).
	NIGHT_LENGTH = 18 * 60,
	START_HOUR = 18,
	END_HOUR = 24,

	-- Witching Hour: the last minutes of each Night.
	WITCHING_LENGTH = 3 * 60,
	WITCHING_WARNING = 60, -- countdown banner this long before it starts
	WITCHING_CANDY = 2, -- event multiplier
	WITCHING_DIFFICULTY = 1, -- added to every mini-game
	WITCHING_TRICK_BOOST = 2, -- trick-house weight multiplier when it starts

	-- Full-Size Bar House: a random occupied-street house glows gold; first visitors get ×10.
	FULL_SIZE_INTERVAL = 240,
	FULL_SIZE_JITTER = 40,
	FULL_SIZE_DURATION = 60,
	FULL_SIZE_VISITORS = 6,
	FULL_SIZE_MULTIPLIER = 10,

	-- Blood Moon (Halloween): Oct 31 00:00 UTC → Nov 1 08:00 UTC. Change here, no republish needed
	-- beyond a server restart.
	BLOOD_MOON_START = 1793404800,
	BLOOD_MOON_END = 1793520000,
	BLOOD_MOON_CANDY = 2,
}
