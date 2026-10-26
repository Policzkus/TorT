--!strict
-- The Knifer (Services/KniferService runs him, Controllers/KniferController is what you hear): a
-- serial killer who roams a street now and then. He comes out of nowhere: out of an open house's
-- doorway or round the back of a house nobody's looking at. All the warning you get is a sting when
-- he appears, his heavy footsteps and, once he's after you, the chase music. Catch you and you're
-- dead: no struggle, no second chance. No black screen either: you drop as a ragdoll where you are
-- (a life and your bucket gone), then wake at the spawn.
-- He isn't hard to outrun (slower than a sprint), and the way to live is to hide: get out of his
-- sight (behind a house, round the back gardens, in a bush: parts tagged HideSpot) and keep quiet.
-- Lose him and he goes to where he last saw you, looks around it, and goes back where he came
-- from. He hears you: walking near him, running a long way off; crouched and creeping, only right
-- by him (and crouched he can't see you over what you'd stand up above).
-- He's the sack-mask homeowner (the user: pick a model we already have), taken out of the
-- homeowners' cast so the killer is never the one at the door. (The user's design; the numbers are
-- mine, overridable.)

return {
	EVERY = { 200, 380 }, -- seconds between his visits to a street someone's on
	FIRST = { 90, 200 }, -- seconds before his first
	RETRY = { 20, 40 }, -- due, but nowhere to come out unseen (or nobody there): look again in this long
	STAY = { 50, 80 }, -- seconds he roams before he heads back to disappear (a chase runs on)
	MOST = 45, -- seconds past STAY he's ever around, whatever he's doing

	SPEED = { roam = 9, search = 11, investigate = 14, chase = 20 }, -- studs/s (you walk ~11, sprint ~26)
	SIGHT = { range = 90, fov = 150, near = 10 }, -- studs, degrees; within `near` he knows you're there anyway
	HIDDEN_NEAR = 7, -- in a HideSpot he only sees you closer than this
	-- Studs he hears you within (creeping: crouched, no faster than a crouch walk), and the speeds that count.
	HEAR = { creep = 6, walk = 20, run = 55, walking = 4, running = 20 },
	LOSE = 2.5, -- seconds out of sight before he gives up chasing and goes to where he last saw you
	SEARCH = { points = 3, radius = 30, pause = { 1.2, 2.2 } }, -- the hiding places he checks round where he lost you (within `radius`)
	-- His patrol (roaming): at each house on his way, the chance he steps into its front yard (to the
	-- foot of the porch, `front` studs out from the door, staring `stare` s), goes down a side gap
	-- (`gapIn` behind the door, `gapOut` to the side) to look into the back gardens (`peek` s), crosses
	-- straight over the road, or stops and looks round (`look` s); his gaze sweeps `sweep` radians
	-- either way while he stands.
	PATROL = {
		yard = 0.2,
		gap = 0.25,
		cross = 0.12,
		halt = 0.35,
		stare = { 1.8, 3.2 },
		peek = { 1.6, 2.6 },
		look = { 1, 2 },
		sweep = 0.7,
		front = 14,
		gapIn = 12,
		gapOut = 19,
		reach = 75, -- studs: a yard or gap further than this to walk to from the pavement in front (round fences) doesn't count
		replan = 70, -- studs: his next step further off than this (something sent him the long way) and he plans again
	},
	CATCH = 4.2, -- studs: this close (and seeing you) and you're dead
	KILL_PAUSE = 1.6, -- seconds he stands over you
	SHOVE = { away = 22, up = 14 }, -- studs/s you're thrown down with, away from him (then a ragdoll)

	SPAWN = { near = 25, far = 75, unseen = 45 }, -- studs from someone; no one closer than `unseen` may see the spot
	CHARACTER = "Owner_SackMask", -- Config/Characters id: burlap sack head, one button eye, a stitched grin, overalls
	BODY = Vector3.new(2.2, 6, 1.6), -- the stand-in block if that character's meshes aren't in the place
	STEP = { walk = 2.8, run = 4.2 }, -- studs between his footsteps
	KNIFE = { grip = 0.3 }, -- studs up from the end of his arm the knife's grip sits (in his fist)
}
