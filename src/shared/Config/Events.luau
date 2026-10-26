--!strict
-- Live events (PROMPT §3.4). Times in seconds; timestamps in Unix UTC. There are no Nights (the
-- user had them taken out): it's always night, and the Witching Hour comes round on its own clock.
return {
	-- Witching Hour: WITCHING_EVERY calm seconds, then WITCHING_LENGTH red ones; when it's over the
	-- town changes (house types reroll).
	WITCHING_EVERY = 10 * 60,
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
