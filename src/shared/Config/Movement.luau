--!strict
-- How kids move (Controllers/MovementController; the server reads the crouch numbers to check what a
-- client says, AI/Hunter). Speeds are shares of the Humanoid's BaseSpeed (16; the Sneakers upgrade
-- raises it: the server's), so everything scales with it. Rates are in walking speeds per second:
-- ACCEL.start = 7 is from standing to a walk in 1/7 s.

return {
	-- A walk (slow, the user asked: a horror pace), a run (straight ahead; less the further you turn
	-- from it: as fast as before, so the Knifer and the homeowners are as easy to outrun), a creep.
	WALK = 0.7,
	SPRINT = 1.6,
	CROUCH = 0.4,
	-- Sprinting counts only moving forward: fully within FORWARD.full of where you look (the dot of
	-- your direction and your view), not at all under FORWARD.none (sideways, backwards).
	FORWARD = { none = 0.35, full = 0.8 },
	-- Picking up speed, slowing down, and changing direction. `sprint` is above a walk (a run builds up
	-- over a moment). In the air you steer at `air` of all that, and with nothing pressed you carry on
	-- (slowing at only `drift` of it): let go mid-jump and your momentum takes you.
	ACCEL = { start = 7, sprint = 3.4, stop = 9, turn = 8, air = 0.55, drift = 0.04 },
	AIR_GRACE = 0.12, -- seconds off the ground before you count as in the air (steps and kerbs aren't)
	-- Jumping: `height` studs up (Roblox's default 7.2 was a superhero's; 4 was too little to be any
	-- use, the user said), costing `cost` stamina, the same jump however tired you are. After landing
	-- you find your feet for `rest` seconds first (no bouncing along). A press up to `buffer` seconds
	-- too soon (just before landing, or while finding your feet) isn't lost: you jump as soon as you
	-- can. And `coyote` seconds after walking off an edge you can still jump (it felt like a bug that
	-- you couldn't).
	JUMP = { height = 6, cost = 4, rest = 0.1, buffer = 0.2, coyote = 0.1 },
	-- Landing from a fall faster than `felt` studs/s jolts the view (fully at `hardest`; a jump comes
	-- down at about 48). Faster than `from` it slows you for `time` seconds, to `slow` at `full`: not
	-- a jump's landing, a drop off a roof a lot.
	LANDING = { felt = 10, hardest = 120, from = 55, full = 110, slow = 0.6, time = 0.4 },
	STAMINA = {
		drain = 17, -- per second sprinting flat out
		regen = 26, -- per second, `delay` seconds after you stop sprinting
		delay = 0.9,
		recover = 30, -- run dry and you can't sprint again until it's back to this
		winded = 25, -- under this you're out of breath
	},
	-- Crouched, your eyes are at CROUCH_EYE of their standing height (and the rest of you goes down
	-- with them for everyone else). The server takes a client's word that it's crouching only while it
	-- moves no faster than a creep (times CROUCH_GRACE for lag).
	CROUCH_EYE = 0.68,
	CROUCH_GRACE = 1.3,
	STRIDE = 5.6, -- studs per step at speed 16; longer the faster you go (with the square root of speed)
}
