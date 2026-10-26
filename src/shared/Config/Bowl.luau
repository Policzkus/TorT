--!strict
-- The candy bowl (HouseTypes "Bowl": Services/HouseService puts it out, DoorService, OwnerChaseService).
-- A rare house that doesn't answer the door but leaves a bowl on the porch: PLEASE TAKE ONE. All you
-- can do is take the lot (hold the prompt), for a big haul. The moment you do, the porch lamp bursts
-- and the porch goes dark (everyone sees it), and maybe the homeowner comes out after you. They hunt
-- you the way the Knifer does (AI/Hunter): they see you in front of them with nothing in the way,
-- hear you walk close by and run from further off (creeping, only right by them). Lose them and they
-- go to where they last saw you, look round it, and go back in. Catch you and they take back every
-- piece of candy in your bucket. (The user's design; the numbers are mine.)

return {
	CANDY = { 100, 300 }, -- what taking it all gives you (as much of it as your bucket holds)
	HOLD = 3, -- seconds to hold the prompt
	CHASE_CHANCE = 0.5, -- that the homeowner comes out after you
	-- The homeowner's hunt (the same shape as Config/Knifer, for AI/Hunter).
	CHASE = {
		WAIT = 1.6, -- seconds from the lamp bursting to the door flying open
		BURST = 1.1, -- seconds they stand in the doorway shouting before they come for you
		SPEED = { chase = 19, investigate = 13, search = 10, home = 9 }, -- studs/s (you walk ~11, sprint ~26)
		SIGHT = { range = 70, fov = 140, near = 8 }, -- studs, degrees; within `near` they know you're there anyway
		HIDDEN_NEAR = 6, -- in a HideSpot they only see you closer than this
		HEAR = { creep = 6, walk = 18, run = 45, walking = 4, running = 20 }, -- studs they hear you within; your speed that counts
		LOSE = 3, -- seconds out of sight before they give up running at you and go to where they last saw you
		SEARCH = { points = 3, radius = 26, pause = { 1.2, 2 } }, -- the hiding places they look in round there
		SWEEP = 0.6, -- radians their gaze sweeps either way while they stand looking
		CATCH = 4, -- studs: this close (and seeing you) and they've got you
		MOST = 50, -- seconds out at most, whatever's happening; then they go home
		THROW = { away = 18, up = 12 }, -- studs/s they throw you down with, away from them
		DOWN = 2.5, -- seconds you're down (a ragdoll)
		STAND_OVER = 1.2, -- seconds they stand over you before going home with their candy
	},
	-- What they shout coming out of the door, and when they've got you.
	SHOUTS = {
		"HEY! ONE PER KID!",
		"THOSE ARE FOR THE TRICK-OR-TREATERS!",
		"I SAW THAT, YOU LITTLE GOBLIN!",
		"GIMME BACK MY CANDY!",
	},
	GOTCHA = { "GOTCHA.", "MINE.", "GREEDY LITTLE THING.", "ONE. PER. KID." },
}
