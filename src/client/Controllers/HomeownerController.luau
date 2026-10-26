--!strict
-- The homeowners who answer the door (PROMPT §V2.1/V2.3), built and animated on every client from
-- the attributes HomeownerService sets on each house (OwnerModel, OwnerSeed, OwnerOut, OwnerStyle).
-- Every knock plays one of five entrances (Config/Homeowners.STYLES): the bolt drawn back, the door
-- swinging open on the dark hall (on a painted door, darkness growing from the hinge), footsteps in
-- the dark, and then they walk out: real steps, legs and arms swinging, every footfall a heavy board.
-- Nothing passes through the house or the door: when they come out the doorway is measured (how
-- far back the hall goes, the ceilings inside and on the porch, where the door swings), they wait
-- deep in the hall out of the door's way until it has swung past them (nothing of them is there to
-- see before it moves), fold forward under a frame or ceiling too low for them and turn sideways
-- through a door too narrow. They stop on the porch, shuffle round to face you, settle, and watch
-- you while you play: breathing, head following you, twitching, sometimes slowly reaching for you,
-- and now and then doing something (ACTS: a look back into the dark house, the head cocked over too
-- far, a scratch, fingers drumming, leaning in for a closer look...; the same on every screen: server
-- time and the house's seed). They gesture as they talk (talk), clap slowly at a PERFECT (clap).
-- Then they turn back to the door, back into the dark step by step, and the door shuts on them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Houses = require(Shared.Modules.Houses)
local Characters = require(Shared.Config.Characters)
local Homeowners = require(Shared.Config.Homeowners)
local CandyPiece = require(Shared.Modules.CandyPiece)
local CharacterRig = require(Shared.Modules.CharacterRig)
local Sound = require(script.Parent.SoundController)

local HomeownerController = {}

-- What they do standing at the door while you play, now and then (every `ACT_EVERY` s there's an
-- `ACT_CHANCE` one starts, picked from the house's seed and server time, so every player sees the
-- same). `time` seconds of it; `pose(t)` what it does `t` seconds in (radians): the near (`arm` =
-- "near", their slapping side) or far arm swung up (`pitch`) and out (`roll`); a bend forward
-- (`fold`); a turn of the body (`twist`) and a sway (`sway`); the head nodding up (`nod`), tilted
-- (`tilt`) and turned (`turn`, away from you toward the house behind them).
type Act = {
	arm: string?,
	pitch: number?,
	roll: number?,
	fold: number?,
	twist: number?,
	sway: number?,
	nod: number?,
	tilt: number?,
	turn: number?,
}
local ACT_EVERY = 4.5
local ACT_CHANCE = 0.55
local ACTS: { { name: string, time: number, pose: (t: number) -> Act } } = {
	-- A look back over the shoulder into the dark house, as if someone in there said something.
	{
		name = "lookBack",
		time = 1.9,
		pose = function()
			return { turn = 1.45, twist = 0.3, nod = 0.05 }
		end,
	},
	-- The head slowly cocked right over, too far, and held there.
	{
		name = "cock",
		time = 2.2,
		pose = function()
			return { tilt = 0.75, nod = -0.06 }
		end,
	},
	-- A hand up to the side of the head, scratching.
	{
		name = "scratch",
		time = 1.7,
		pose = function(t)
			return { arm = "far", pitch = 2.45, roll = 0.55 + 0.12 * math.sin(t * 24), tilt = -0.15 }
		end,
	},
	-- Fingers drumming on the leg: impatient.
	{
		name = "drum",
		time = 1.9,
		pose = function(t)
			return { arm = "near", pitch = 0.16 + 0.07 * math.sin(t * 26), roll = 0.12 }
		end,
	},
	-- Weight from one foot to the other, slowly.
	{
		name = "shift",
		time = 2.6,
		pose = function(t)
			return { sway = 0.11 * math.sin(t * 2.4), tilt = 0.06 * math.sin(t * 2.4) }
		end,
	},
	-- Leaning in closer, for a better look at you.
	{
		name = "lean",
		time = 2.0,
		pose = function()
			return { fold = 0.32, nod = 0.16 }
		end,
	},
	-- Sniffing the air: little lifts of the chin.
	{
		name = "sniff",
		time = 1.5,
		pose = function(t)
			return { nod = 0.24 + 0.08 * math.max(0, math.sin(t * 18)), tilt = 0.06 }
		end,
	},
}
-- Talking (talk): the far hand beats in time with the words, the head nods on them.
local TALK = { pitch = 0.8, beat = 0.28, roll = 0.3, nod = 0.09, ease = 0.25 }
-- A slow clap at a PERFECT (clap): both hands out in front, meeting `claps` times over `time` s.
local CLAP = { time = 1.15, claps = 3, pitch = 1.3, apart = 0.08, together = 0.42 }

local POSE_FPS = 30
local DOOR_FRONT = 0.47 -- the door part's front face, in front of its centre
local VIEW_DISTANCE = 220
local DEEPEST = 2.8 -- studs into the hall they start from, at least (more to fold or keep clear of the door)
local HEADROOM = 0.3 -- kept between their head and any frame or ceiling
local MAX_BEND = 1.3 -- radians they'll fold forward to get under something
local FOLD_PER_STUD = 1.1 -- radians of fold per stud walked straightening up, at most
local FOLD_DOWN = 0.7 -- and folding down (before the frame)
local PLAN_STEP = 0.05 -- studs between the fold plan's samples
local WALL = 0.9 -- how deep the wall around the door is, behind its front face (studs)
local SIDEWAYS = 1.3 -- radians they turn to pass a door narrower than they are
local TURN = 0.7 -- radians they turn their body toward you, at most, once out (the head does the rest)
local TURN_RATE = 1.6 -- radians a second they turn (back to the door: twice that)
local TURN_STEP = 0.7 -- studs of stepping per radian turned: they shuffle round, they don't spin
local LEAF_MARGIN = 0.3 -- kept between them and the middle of a door swinging open (it is 0.4 thick)
local GATE_STEPS = 20 -- samples of the door's swing (or a painted door's darkness growing)
local FADE = 0.5 -- seconds to come out of the dark, where a hall's too short to wait clear of the door
-- How far the head nods and turns on the way out (more once they're standing on the porch).
local HEAD_WALK = { down = -0.5, up = 0.3, turn = 0.4 }
local LEAVE_TURN = 0.25 -- seconds turning back to the door before they back in (at least)
local LEAVE_PACE = 5.5 -- studs a second backing into the dark (on average)
local LEAVE_WALK = 2.2 -- seconds at most
local CLOSE_TIME = 0.5 -- then the door shuts
local GLOW_COLOR = Color3.fromRGB(214, 168, 120)
local LATE = 1 -- seconds after they came out (OwnerOutAt) past which we show them already out
-- A wrong answer and they slap you (strike; the user: "they slap, not hit"): the hand drawn back out
-- to the side as the body turns away, then swung flat across at your face as they lunge and turn
-- through, then back. Seconds for each; radians: `out` the arm raised out sideways, `back` how far
-- behind it starts, `across` how far round it ends (past straight at you), `lift` the hand up to
-- face height, `twist` the body's turn, `lean` forward into it; studs `lunge`. The blow lands `hit`
-- of the way through the swing.
-- A peek at someone going by (Glance, HomeownerService): the door cracked this far over `open`
-- seconds, their head leaning out into the gap, held till the server says; slammed if you come close.
local GLANCE = { crack = 0.4, open = 0.5, lean = 0.45, slam = 0.35, aside = 0.28, nearer = 0.6 } -- aside: of the door's width, to the gap's side; nearer: studs in from their start
-- Goodbyes before they go back in (OwnerBye: the server picks one that fits how the visit went):
-- `time` seconds of it, still facing you, before they turn to the door; the displeased ones end with
-- the door slammed. `pose(t)` is what it does `t` seconds in (radians): the near arm swung up
-- (`pitch`) and out (`roll`), if it uses the arm; a bend forward (`fold`); a nod (`nod`, down is
-- negative), a tilt of the head (`tilt`) and a turn of it away from you (`turn`).
type Bye = { pitch: number?, roll: number?, fold: number?, nod: number?, tilt: number?, turn: number? }
local GOODBYES: { [string]: { time: number, slam: boolean, sound: string?, pose: (t: number) -> Bye } } = {
	-- A slow wave, the hand up by their head, the head on one side.
	wave = {
		time = 1.4,
		slam = false,
		pose = function(t)
			return { pitch = 0.45, roll = 2.0 + 0.3 * math.sin(t * 8), tilt = 0.25 }
		end,
	},
	-- A deep bow, slow, held a little too long.
	bow = {
		time = 1.5,
		slam = false,
		sound = "Breath",
		pose = function()
			return { fold = 0.75, nod = -0.35 }
		end,
	},
	-- Two nods and a little hand raised to you.
	nod = {
		time = 1.1,
		slam = false,
		pose = function(t)
			return { pitch = 0.35, roll = 1.0 + 0.15 * math.sin(t * 10), nod = -0.32 * math.max(0, math.sin(t * 7)) }
		end,
	},
	-- A finger jabbed at you, twice, leaning in.
	point = {
		time = 1.0,
		slam = true,
		pose = function(t)
			return { pitch = 1.55 + 0.18 * math.max(0, math.sin(t * 9)) ^ 3, fold = 0.15 }
		end,
	},
	-- The back of the hand flicked at you (go away), the head turned from you.
	shoo = {
		time = 1.0,
		slam = true,
		sound = "Whoosh",
		pose = function(t)
			return { pitch = 0.8, roll = 0.3 + 0.6 * math.max(0, math.sin(t * 11)), turn = 0.45, fold = -0.06 }
		end,
	},
	-- Just a long stare, the head tipping over, leaning in.
	stare = {
		time = 1.5,
		slam = true,
		sound = "Breath",
		pose = function()
			return { tilt = 0.55, fold = 0.18, nod = -0.12 }
		end,
	},
}
-- Handing you your candy (HomeownerGive): the arm out to you over `reach`, the candy leaving the
-- hand at `release` and in your bucket `fly` later, the arm back by `back`.
local GIVE = { reach = 0.25, release = 0.45, fly = 0.35, back = 0.95, raise = 1.35 }
-- Someone else's scare (a trick house's Nerve Hold): they lunge out at them, both hands up, hold it,
-- then settle. Seconds; radians the arms come up and the body leans; studs the lunge.
local SCARE = { rush = 0.12, hold = 0.5, recover = 0.45, reach = 1.7, lean = 0.4, lunge = 1.5 }
local SLAP = {
	windup = 0.24,
	swing = 0.11,
	recover = 0.5,
	out = 1.45,
	back = -0.45,
	across = 1.85,
	lift = 0.35,
	twist = 0.4,
	lean = 0.2,
	lunge = 0.7,
	hit = 0.85,
}

-- When they start walking out and for how long (they arrive at walkAt + walkFor, which is
-- Homeowners.OUT_AFTER for the style, so their hello lands as they stop; waiting for the door to
-- swing past them can make them later, and DoorController's hello waits).
-- maxSpeed caps their pace (studs a second on average): a long way to come, they set off sooner.
local WALK: { [string]: { walkAt: number, walkFor: number, maxSpeed: number } } = {
	Creep = { walkAt = 0.5, walkFor = 1.9, maxSpeed = 5.5 },
	Waiting = { walkAt = 1.0, walkFor = 1.5, maxSpeed = 5.5 },
	Peek = { walkAt = 1.3, walkFor = 1.4, maxSpeed = 5.5 },
	Rush = { walkAt = 0.2, walkFor = 1.1, maxSpeed = 9 },
	Flicker = { walkAt = 0.5, walkFor = 1.9, maxSpeed = 5.5 },
}

export type Look = {
	morph: CharacterRig.Morph,
	tilt: number,
	hinge: number, -- -1 / 1: which side of the door the hinge is on
	reach: boolean, -- slowly reaches for you while you play
	snapAt: number, -- kept for the jumpscare's timing
}

-- What a doorway allows: measured once, when they come out.
type Fit = {
	startZ: number, -- how far into the hall they start (door frame space: +Z is inside)
	startX: number, -- and how far to the side (a short hall: out of the door's sweep)
	joinZ: number, -- where their path out has come round onto the line through the door
	standZ: number, -- where they stop, out on the porch
	doorTop: number, -- the opening's height above the sill
	doorWidth: number,
	ceilingIn: number, -- the hall's ceiling above the sill
	ceilingOut: number, -- the porch's
	hipY: number, -- their hips above their feet
	pivotY: number, -- where they fold (the root joint): above their feet, and back from them
	pivotZ: number,
	front: number, -- how far in front of their feet any of them reaches, standing straight
	turn: number, -- how far they can turn toward you where they stand without touching the wall
	outline: { Vector2 }, -- their head's and torso's top, side on, nodding too: from the fold's pivot (y, z: + back)
	halfDepth: number,
	halfWidth: number, -- how far to either side any of them reaches (body)
	back: number, -- and behind their feet
	body: { Vector3 }, -- everywhere their parts reach on the way out (reachOf): feet at the origin, facing -Z
	radius: number, -- round them, seen from above (their path is on the door's line this far behind the wall)
	wide: boolean, -- wider than the door: turn sideways through it
	stepLength: number,
	folds: { number }, -- how far forward they fold at each PLAN_STEP from startZ out to standZ
	folding: boolean, -- too tall for the door: they come from deeper in the hall, folding as they come
	leaf: { { Vector2 } }?, -- a real door's two edges (door frame x, z) at each GATE_STEPS of its swing
	gate: { number }, -- the nearest z the door lets them come at each GATE_STEPS of its opening
	swept: boolean, -- nowhere in the hall to wait clear of the door: out of the dark once it's past
}

type Figure = {
	house: Model,
	door: BasePart,
	doorFrame: CFrame, -- the door where it hangs closed (a real door swings; this doesn't)
	hinge: Model?, -- a real hinged front door (World/HouseStyles) the homeowner opens
	hingeClosed: CFrame,
	hingeAngle: number,
	side: number, -- -1 / 1: the hinge's side of the doorway (door frame x)
	model: Model,
	root: BasePart,
	rootOffset: CFrame, -- root relative to the feet
	joints: { [string]: Motor6D },
	height: number,
	look: Look,
	style: string,
	fit: Fit,
	walkAt: number, -- when they set off, and for how long (WALK, stretched for a long way to come)
	walkFor: number,
	leaving: boolean,
	clock: number, -- seconds since the entrance started
	leaveClock: number,
	leaveFrom: number, -- where they were when they started back in
	leaveOpen: number, -- how open the door was then
	leaveTurn: number, -- seconds turning back to the door, then backing in
	leaveWalk: number,
	poseClock: number,
	open: number, -- how open the door is (0..1)
	z: number, -- where they are on the way out (door frame space)
	lastZ: number,
	speed: number, -- studs a second, smoothed (drives how big the steps are)
	travel: number, -- ground their feet have covered, walking and turning (drives the walk cycle)
	stepIndex: number, -- footfalls so far (a step sounds when it changes)
	bend: number,
	yaw: number,
	shown: boolean, -- in the world (not before the door moves, nor while it swings through them)
	fade: number, -- how much of them shows (1: all), coming out of the dark
	void: Part,
	glow: PointLight,
	porch: { PointLight },
	headYaw: number,
	headPitch: number,
	twitchAt: number,
	twitchNeck: number,
	twitchArm: number,
	twitchArmSide: string,
	twitchBody: number,
	strikeAt: number?, -- when they started slapping you (figure clock)
	scareAt: number?, -- when they lunged at someone (figure clock)
	glance: boolean, -- only peeking out at someone going by: they never come out
	slam: boolean, -- the door's slammed on the way in (a peek someone came too close to)
	gesture: string?, -- their goodbye, going back in (a GOODBYES key)
	gestureFor: number, -- seconds of it before they turn back to the door
	giveAt: number?, -- when they reached out with your candy (figure clock)
	talkAt: number?, -- when they started saying a line (figure clock), and for how long
	talkFor: number,
	clapAt: number?, -- when they started clapping (figure clock)
	claps: number, -- claps heard so far
	seed: number, -- the house's OwnerSeed: their acts and twitches, the same on every screen
	cues: { [string]: boolean },
	rng: Random,
	shut: boolean,
}

local figures: { [Model]: Figure } = {}
local hiddenHouses: { [Model]: boolean } = {}

local function ease(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function approach(value: number, target: number, rate: number): number
	if value < target then
		return math.min(target, value + rate)
	end
	return math.max(target, value - rate)
end

-- The body, tilt and quirks of a house's homeowner: the same on every client.
function HomeownerController.look(seed: number, creep: number): Look
	local rng = Random.new(seed)
	local M = Homeowners.MORPH
	local power = 1.8 - 1.4 * creep -- creepier neighbourhoods roll toward the extremes
	local function biased(range: Homeowners.Range): number
		return range.min + (range.max - range.min) * rng:NextNumber() ^ power
	end
	local headAmount = rng:NextNumber() ^ power
	local head = if rng:NextNumber() < 0.55
		then 1 - (1 - M.head.min) * headAmount
		else 1 + (M.head.max - 1) * headAmount
	local morph: CharacterRig.Morph = {
		scale = lerp(M.scale.min, M.scale.max, rng:NextNumber()),
		stretch = biased(M.stretch),
		arms = biased(M.arms),
		head = head,
		thin = M.thin.max - (biased(M.thin) - M.thin.min),
		neck = biased(M.neck),
	}
	return {
		morph = morph,
		tilt = math.rad(rng:NextNumber(-1, 1) * Homeowners.TILT * (0.3 + 0.7 * creep)),
		hinge = if rng:NextNumber() < 0.5 then -1 else 1,
		reach = rng:NextNumber() < 0.3 + 0.5 * creep,
		snapAt = rng:NextNumber(0.8, 1.6),
	}
end

local function houseLook(house: Model, door: BasePart): Look?
	local seed = house:GetAttribute("OwnerSeed")
	if type(seed) ~= "number" then
		return nil
	end
	local neighborhood = door:GetAttribute("Neighborhood")
	local creep = if type(neighborhood) == "string" then Homeowners.CREEP[neighborhood] or 0.5 else 0.5
	return HomeownerController.look(seed, creep)
end

-- A standalone copy of a house's homeowner with its feet at the origin (also used by the
-- jumpscare). Returns the model, the part to move and the root's offset from the feet.
function HomeownerController.build(house: Model): (Model?, BasePart?, CFrame?)
	local id = house:GetAttribute("OwnerModel")
	local door = house:FindFirstChild("Door", true)
	if type(id) ~= "string" or door == nil or not door:IsA("BasePart") then
		return nil, nil, nil
	end
	local look = houseLook(house, door) or HomeownerController.look(1, 0.5)
	local rig = if Characters[id] then CharacterRig.build(id, "puppet", look.morph) else nil
	if rig and rig.PrimaryPart then
		return rig, rig.PrimaryPart, rig.PrimaryPart.CFrame
	end
	return nil, nil, nil
end

-- How tall a homeowner is (feet to the top of the head), before it's built.
function HomeownerController.heightOf(id: string): number
	local def = Characters[id]
	local headSeg = def and def.segments.Head
	if headSeg == nil then
		return Homeowners.HEIGHT
	end
	return headSeg.offset[2] + headSeg.size[2] / 2
end

local function porchLights(house: Model): { PointLight }
	local lights = {}
	local porch = house:FindFirstChild("PorchLight", true)
	if porch then
		for _, child in porch:GetChildren() do
			if child:IsA("PointLight") then
				table.insert(lights, child)
			end
		end
	end
	return lights
end

-- The lowest thing over a point at `z` (door frame space) of radius `r`: the wall above the door
-- while it's in the doorway, else the hall's ceiling or the porch roof.
local function overhead(fit: Fit, z: number, r: number): number
	local ceiling = if z > 0 then fit.ceilingIn else fit.ceilingOut
	if z + r > -DOOR_FRONT and z - r < -DOOR_FRONT + WALL then
		return math.min(fit.doorTop, ceiling)
	end
	return ceiling
end

-- Whether their head and spine clear everything over them, standing at `z` folded `fold` forward.
local function clears(fit: Fit, z: number, fold: number): boolean
	local c, sn = math.cos(fold), math.sin(fold)
	for _, corner in fit.outline do
		-- Folding forward turns the body about the hips: up becomes forward (out, -z).
		local py = fit.pivotY + corner.X * c + corner.Y * sn
		local pz = z + fit.pivotZ - corner.X * sn + corner.Y * c
		if py > overhead(fit, pz, 0.1) - HEADROOM then
			return false
		end
	end
	return true
end

-- The least fold that brings every point of them under the door's top (wherever they stand).
local function underFrame(fit: Fit): number
	for fold = 0, MAX_BEND, 0.02 do
		local c, sn = math.cos(fold), math.sin(fold)
		local fits = true
		for _, corner in fit.outline do
			if fit.pivotY + corner.X * c + corner.Y * sn > fit.doorTop - HEADROOM then
				fits = false
				break
			end
		end
		if fits then
			return fold
		end
	end
	return MAX_BEND
end

-- Whether every point of them is out in front of the wall, standing at `z` folded `fold`.
local function pastWall(fit: Fit, z: number, fold: number): boolean
	local c, sn = math.cos(fold), math.sin(fold)
	for _, corner in fit.outline do
		if z + fit.pivotZ - corner.X * sn + corner.Y * c > -DOOR_FRONT - 0.1 then
			return false
		end
	end
	return true
end

-- Whether every point of them is still behind the wall (in the hall), at `z` folded `fold`.
local function behindWall(fit: Fit, z: number, fold: number): boolean
	local c, sn = math.cos(fold), math.sin(fold)
	for _, corner in fit.outline do
		if z + fit.pivotZ - corner.X * sn + corner.Y * c < -DOOR_FRONT + WALL + 0.15 then
			return false
		end
	end
	return true
end

-- The fold all the way out, planned ahead. Folding swings the head far forward, so folding at the
-- door would sweep it through the wall over the frame. Someone too tall for the door folds down
-- under it gradually while all of them is still in the hall, stays folded until all of them is
-- out past the wall, then straightens gradually to what the porch allows. Anyone else only bends
-- for a low ceiling, starting early enough to clear it.
local function planFolds(fit: Fit): { number }
	local count = math.max(1, math.ceil((fit.startZ - fit.standZ) / PLAN_STEP))
	local need = {}
	for i = 0, count do
		local z = fit.startZ - i * PLAN_STEP
		local fold = 0
		while fold < MAX_BEND and not clears(fit, z, fold) do
			fold += 0.02
		end
		need[i + 1] = math.min(fold, MAX_BEND)
	end
	local folds = {}
	local unfold = FOLD_PER_STUD * PLAN_STEP
	if fit.folding then
		local under = underFrame(fit)
		local full = #need -- where they have to be folded right under it
		for i = 1, #need do
			if not behindWall(fit, fit.startZ - (i - 1) * PLAN_STEP, under) then
				full = i
				break
			end
		end
		local through = true
		for i = 1, #need do
			local z = fit.startZ - (i - 1) * PLAN_STEP
			if i < full then
				folds[i] = math.max(need[i], under - (full - i) * FOLD_DOWN * PLAN_STEP)
			elseif through then
				folds[i] = math.max(under, need[i])
				through = not pastWall(fit, z, folds[i])
			else
				folds[i] = math.max(need[i], folds[i - 1] - unfold)
			end
		end
		return folds
	end
	for i = 1, #need do
		folds[i] = need[i]
	end
	for i = #folds - 1, 1, -1 do -- be bent before getting under it
		folds[i] = math.max(folds[i], folds[i + 1] - unfold)
	end
	for i = 2, #folds do -- and straighten gradually after
		folds[i] = math.max(folds[i], folds[i - 1] - unfold)
	end
	return folds
end

local function foldAt(fit: Fit, z: number): number
	local i = (fit.startZ - z) / PLAN_STEP + 1
	local lo = math.clamp(math.floor(i), 1, #fit.folds)
	local hi = math.clamp(lo + 1, 1, #fit.folds)
	return lerp(fit.folds[lo], fit.folds[hi], math.clamp(i - lo, 0, 1))
end

-- How far in front of their feet the front of them is, folded `fold` forward.
local function frontAt(fit: Fit, fold: number): number
	local f = fold + 0.1 -- and a bow, a breath
	local c, sn = math.cos(f), math.sin(f)
	local front = 0
	for _, point in fit.body do
		local up = point.Y - fit.pivotY
		local back = point.Z - fit.pivotZ
		front = math.max(front, if up > 0 then up * sn - back * c - fit.pivotZ else -point.Z)
	end
	return front
end

-- Everywhere their parts reach on the way out (the rig standing unposed at the origin): each part
-- as a rounded box (they're rounded: a box's corners would be far outside a head), at rest, the
-- head also nodding and turning as far as HEAD_WALK, the arms and legs swinging.
local function reachOf(model: Model, joints: { [string]: Motor6D }): { Vector3 }
	local points = {}
	local ROUND = { 1, 0.85, 0.75 } -- how far out along one, two or three axes
	local function corners(cf: CFrame, size: Vector3)
		for _, sx in { -1, 0, 1 } do
			for _, sy in { -1, 0, 1 } do
				for _, sz in { -1, 0, 1 } do
					local axes = math.abs(sx) + math.abs(sy) + math.abs(sz)
					if axes > 0 then
						local k = ROUND[axes] / 2
						table.insert(points, cf * Vector3.new(sx * size.X * k, sy * size.Y * k, sz * size.Z * k))
					end
				end
			end
		end
	end
	local function swinging(name: string, motor: string, turns: { CFrame })
		local part = model:FindFirstChild(name)
		if part == nil or not part:IsA("BasePart") then
			return
		end
		local joint = joints[motor]
		if joint == nil or joint.Part0 == nil then
			corners(part.CFrame, part.Size)
			return
		end
		for _, turn in turns do
			corners(joint.Part0.CFrame * joint.C0 * turn * joint.C1:Inverse(), part.Size)
		end
	end
	local nods = {}
	for _, pitch in { HEAD_WALK.down, 0, HEAD_WALK.up } do
		for _, yaw in { -HEAD_WALK.turn, 0, HEAD_WALK.turn } do
			table.insert(nods, CFrame.fromEulerAnglesYXZ(pitch, yaw, 0))
		end
	end
	local arms = { CFrame.Angles(-0.4, 0, 0), CFrame.identity, CFrame.Angles(0.4, 0, 0) }
	local legs = { CFrame.Angles(-0.5, 0, 0), CFrame.identity, CFrame.Angles(0.5, 0, 0) }
	swinging("Head", "Neck", nods)
	swinging("Torso", "", {})
	for _, side in { "Left", "Right" } do
		swinging(side .. " Arm", side .. " Shoulder", arms)
		swinging(side .. " Leg", side .. " Hip", legs)
	end
	return points
end

-- Their path out (door frame x at `z`): from where they wait round onto the line through the door
-- before any of them reaches the wall.
local function pathX(fit: Fit, z: number): number
	if fit.startX == 0 then
		return 0
	end
	local u = math.clamp((z - fit.joinZ) / (fit.startZ - fit.joinZ), 0, 1)
	return fit.startX * u * u * (3 - 2 * u)
end

-- Which way the path heads, walking out (a turn about the vertical, 0 straight out).
local function pathYaw(fit: Fit, z: number): number
	return math.atan((pathX(fit, z + 0.05) - pathX(fit, z - 0.05)) / 0.1)
end

-- Whether a door swung to `leaf` (its two edges) is in the way of them standing at (x, z), their
-- front `front` ahead of their feet.
local function hitsLeaf(fit: Fit, leaf: { Vector2 }, x: number, z: number, front: number): boolean
	local near, far = z - front - LEAF_MARGIN, z + fit.back + LEAF_MARGIN
	local half = fit.halfWidth + LEAF_MARGIN
	for i = 0, 16 do
		local point = leaf[1]:Lerp(leaf[2], i / 16)
		if math.abs(point.X - x) < half and point.Y > near and point.Y < far then
			return true
		end
	end
	return false
end

-- Whether the door swinging open (to just short of wide open: it's against the wall then) passes
-- through them, standing at (x, z).
local function swept(fit: Fit, leaf: { { Vector2 } }, x: number, z: number, front: number): boolean
	for k = 1, GATE_STEPS do
		if hitsLeaf(fit, leaf[k], x, z, front) then
			return true
		end
	end
	return false
end

-- The nearest the door lets them come at each GATE_STEPS of its opening, on their way out: a real
-- door swings in through the hall, so they keep behind its sweep; a painted one's darkness has to
-- cover the doorway before any of them comes through it.
local function planGate(fit: Fit): { number }
	local count = #fit.folds - 1
	local fronts = {}
	for i = 0, count do
		fronts[i + 1] = frontAt(fit, fit.folds[i + 1])
	end
	local gate = {}
	for k = 0, GATE_STEPS do
		local nearest = -math.huge
		-- Wide open, the door's against the wall (the frame and turning sideways see them through).
		for i = 0, if k == GATE_STEPS then -1 else count do
			local z = fit.startZ - i * PLAN_STEP
			local blocked = if fit.leaf
				then hitsLeaf(fit, fit.leaf[k + 1], pathX(fit, z), z, fronts[i + 1])
				else k < GATE_STEPS and z - fronts[i + 1] < -DOOR_FRONT + 0.06
			if blocked then
				nearest = if i == 0 then fit.startZ else z + PLAN_STEP
				break
			end
		end
		gate[k + 1] = nearest
	end
	return gate
end

local function gateAt(fit: Fit, open: number): number
	local lo = math.floor(math.clamp(open, 0, 1) * GATE_STEPS) + 1
	return math.max(fit.gate[lo], fit.gate[math.min(lo + 1, #fit.gate)])
end

-- Where a hall's figures stand (World/BlenderLot), on its floor: door frame (x, z). Somewhere a
-- body can stand, and how deep the hall goes (the house's collision is a solid box, no use for
-- measuring it).
local function hallSpots(house: Model, door: BasePart, doorFrame: CFrame): { Vector2 }
	local spots = {}
	for k = 1, 9 do
		local spot = house:FindFirstChild(if k == 1 then "HallFigure" else "HallFigure" .. k)
		if spot == nil then
			break
		end
		if spot:IsA("BasePart") then
			local at = doorFrame:PointToObjectSpace(spot.Position)
			if math.abs(at.Y + door.Size.Y / 2) < 1.2 then -- not up the stairs
				table.insert(spots, Vector2.new(at.X, at.Z))
			end
		end
	end
	return spots
end

-- Measures the doorway for this body (the rig still standing at the origin, unposed): where they
-- can start in the hall without being inside a wall or in the way of the door, the ceilings,
-- whether they fit the door, and how they'll have to fold to get out. `spots` are where the hall's
-- figures stand (none: measure it); a painted door has no hall to see (nothing behind its darkness
-- shows). `side` is the hinge's.
local function measure(
	door: BasePart,
	doorFrame: CFrame,
	model: Model,
	joints: { [string]: Motor6D },
	ignore: { Instance },
	leaf: { { Vector2 } }?,
	spots: { Vector2 },
	side: number
): Fit
	local _, size = model:GetBoundingBox()
	local top = 0
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			top = math.max(top, part.Position.Y + part.Size.Y / 2)
		end
	end
	local hip = joints["Left Hip"]
	local hipY = if hip and hip.Part0 then (hip.Part0.CFrame * hip.C0).Position.Y else top * 0.35
	local rootJoint = joints.RootJoint
	local pivot = if rootJoint and rootJoint.Part0
		then (rootJoint.Part0.CFrame * rootJoint.C0).Position
		else Vector3.new(0, hipY, 0)
	local halfDepth = math.max(0.5, size.Z / 2)
	local body = reachOf(model, joints)
	local halfWidth, back, front = 0.5, 0.3, 0.3
	for _, point in body do
		halfWidth = math.max(halfWidth, math.abs(point.X))
		back = math.max(back, point.Z)
		front = math.max(front, -point.Z)
	end
	local radius = math.sqrt(halfWidth * halfWidth + halfDepth * halfDepth)
	-- How far behind their feet any of them gets, turned up to `turn` either way (seen from above).
	local function backTurned(turn: number): number
		local most = back
		for k = -4, 4 do
			local c, sn = math.cos(turn * k / 4), math.sin(turn * k / 4)
			for _, point in body do
				most = math.max(most, -point.X * sn + point.Z * c)
			end
		end
		return most
	end
	-- Wider than the door: they turn sideways through it, if turning makes them narrower (and they
	-- aren't folding: folded, turning would swing their head into the wall).
	local turnedWidth = 0
	for _, point in body do
		turnedWidth = math.max(turnedWidth, math.abs(point.X * math.cos(SIDEWAYS) + point.Z * math.sin(SIDEWAYS)))
	end
	-- What could catch on something overhead: their real side silhouette (Config/CharacterModels),
	-- or failing that the high corners of the head's and torso's boxes; the head's also nodding.
	local high: { Vector3 } = {}
	local def = Characters[model.Name]
	for _, point in (def and def.outline) or {} do
		if point[1] > pivot.Y + 0.5 then
			table.insert(high, Vector3.new(0, point[1], point[2]))
		end
	end
	for _, name in if #high > 0 then {} else { "Head", "Torso" } do
		local part = model:FindFirstChild(name) :: BasePart?
		if part then
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = part.CFrame * Vector3.new(0, sy * part.Size.Y / 2, sz * part.Size.Z / 2)
					if corner.Y > pivot.Y + 0.5 then
						table.insert(high, corner)
					end
				end
			end
		end
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	local neckJoint = joints.Neck
	local neck = if neckJoint and neckJoint.Part0 then (neckJoint.Part0.CFrame * neckJoint.C0).Position else nil
	local outline: { Vector2 } = {}
	for _, point in high do
		local nods = if head
				and neck
				and point.Y > head.Position.Y - head.Size.Y / 2
			then { 0, HEAD_WALK.down, HEAD_WALK.up }
			else { 0 }
		for _, nod in nods do
			local at = point
			if nod ~= 0 and neck then
				local y, z = point.Y - neck.Y, point.Z - neck.Z
				at = Vector3.new(
					0,
					neck.Y + y * math.cos(nod) - z * math.sin(nod),
					neck.Z + y * math.sin(nod) + z * math.cos(nod)
				)
			end
			table.insert(outline, Vector2.new(at.Y - pivot.Y, at.Z - pivot.Z))
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local bottom = doorFrame * CFrame.new(0, -door.Size.Y / 2, 0)
	local function cast(from: Vector3, direction: Vector3): number
		local hit = Workspace:Raycast(from, direction, params)
		return if hit then (hit.Position - from).Magnitude else direction.Magnitude
	end
	-- How far back the hall is clear: to its figures' spots in line with the door, or at shin, chest
	-- and head height across their width. Behind a painted door it doesn't matter (nothing shows).
	local hall: number? = nil
	for _, spot in spots do
		if math.abs(spot.X) < door.Size.X / 2 + 1 then
			hall = math.max(hall or 0, spot.Y)
		end
	end
	local room = if leaf then hall or 9 else math.huge
	if leaf and hall == nil then
		local inward = bottom.LookVector * -1
		for _, h in { 1, 3.5, math.min(6, top - 0.5) } do
			for _, x in { -0.7, 0, 0.7 } do
				room = math.min(room, cast((bottom * CFrame.new(x, h, 0.3)).Position, inward * 9) + 0.3)
			end
		end
	elseif hall then
		room = hall + halfDepth + 0.35 -- a figure's spot is somewhere a body stands
	end
	local folding = false
	for _, point in outline do
		folding = folding or pivot.Y + point.X > door.Size.Y - HEADROOM
	end
	local wide = not folding and halfWidth > door.Size.X / 2 - 0.3 and turnedWidth < halfWidth - 0.15
	-- Out on the porch far enough to turn round toward you (from sideways, if they came that way),
	-- unless something's in the way there (a railing, a chair); then as far as they can turn there.
	local standZ = -(DOOR_FRONT + Homeowners.STAND_OFF + backTurned(if wide then SIDEWAYS else TURN))
	local ahead = cast((bottom * CFrame.new(0, 3, -DOOR_FRONT)).Position, bottom.LookVector * 6)
	standZ = math.min(math.max(standZ, -(DOOR_FRONT + ahead - front - 0.3)), -(DOOR_FRONT + 0.1 + back))
	local turn = 0
	while turn < TURN and standZ + backTurned(turn + 0.05) < -DOOR_FRONT - 0.05 do
		turn += 0.05
	end
	local function ceiling(z: number): number
		return 1 + cast((bottom * CFrame.new(0, 1, z)).Position, Vector3.new(0, 16, 0))
	end
	local fit: Fit = {
		startZ = 0.6,
		startX = 0,
		joinZ = -DOOR_FRONT + WALL + radius + 0.3,
		standZ = standZ,
		doorTop = door.Size.Y,
		doorWidth = door.Size.X,
		ceilingIn = 0,
		ceilingOut = math.min(ceiling(standZ), ceiling(standZ - 0.8)),
		hipY = hipY,
		pivotY = pivot.Y,
		pivotZ = pivot.Z,
		front = front,
		turn = turn,
		outline = outline,
		halfDepth = halfDepth,
		halfWidth = halfWidth,
		back = back,
		body = body,
		radius = radius,
		wide = wide,
		folding = folding,
		stepLength = math.max(0.7, hipY * 0.55),
		folds = {},
		leaf = leaf,
		gate = {},
		swept = false,
	}
	-- Where they wait: deep enough to fold down under the frame before reaching the wall, and for the
	-- door to swing open in front of them; in a hall too short for that, off to the side at one of
	-- its figures' spots (away from the hinge), out of the door's sweep.
	local under = if folding then underFrame(fit) else 0
	local behindAt = 0.6 -- where, folded under the frame, all of them is just behind the wall
	while folding and behindAt < 12 and not behindWall(fit, behindAt, under) do
		behindAt += PLAN_STEP
	end
	local function frontFrom(z: number): number -- their front, waiting at `z` (the plan's fold there)
		return frontAt(fit, math.max(0, under - math.max(0, z - behindAt) * FOLD_DOWN))
	end
	local deepest = math.max(DEEPEST, if folding then behindAt + under / FOLD_DOWN else 0)
	if leaf then
		local z = 0.6
		while z < 12 and swept(fit, leaf, 0, z, frontFrom(z)) do
			z += PLAN_STEP
		end
		deepest = math.max(deepest, z)
	end
	fit.startZ = math.clamp(room - halfDepth - 0.35, 0.6, deepest)
	if leaf and swept(fit, leaf, 0, fit.startZ, frontFrom(fit.startZ)) then
		local aside = {}
		for _, spot in spots do
			if spot.X * side < 0.3 and math.min(spot.Y, deepest) > fit.joinZ + 1.5 then
				table.insert(aside, spot)
			end
		end
		table.sort(aside, function(a: Vector2, b: Vector2): boolean
			return math.abs(a.X) < math.abs(b.X)
		end)
		local found = false
		for _, spot in aside do
			local z = math.min(spot.Y, deepest)
			for push = 0, 0.75, 0.25 do
				local x = spot.X - side * push
				if not found and not swept(fit, leaf, x, z, frontFrom(z)) then
					found = true
					fit.startX, fit.startZ = x, z
				end
			end
		end
	end
	fit.swept = leaf ~= nil and swept(fit, leaf, fit.startX, fit.startZ, frontFrom(fit.startZ))
	fit.ceilingIn = math.min(ceiling(math.max(1, fit.startZ)), ceiling(math.max(1, fit.startZ * 0.5)))
	fit.folds = planFolds(fit)
	fit.gate = planGate(fit)
	return fit
end

local function cue(figure: Figure, key: string, at: number, play: () -> ())
	if figure.clock >= at and not figure.cues[key] then
		figure.cues[key] = true
		play()
	end
end

-- One footfall: a heavy board under them, the step, now and then the floor complaining.
local function footstep(figure: Figure, weight: number)
	local size = math.clamp(figure.height / 7, 0.8, 1.5)
	Sound.play("OwnerStep", {
		at = figure.root,
		volume = weight * size,
		speed = figure.rng:NextNumber(0.8, 0.92) / math.sqrt(size),
	})
	Sound.play("StepWood", { at = figure.root, volume = 0.8, speed = 0.72 })
	if figure.rng:NextNumber() < 0.35 then
		Sound.play("BoardCreak", { at = figure.root, volume = 0.8, speed = figure.rng:NextNumber(0.75, 1) })
	end
end

-- How open the door is (0..1) `c` seconds into an entrance of this style.
local function doorOpen(style: string, c: number): number
	if style == "Rush" then
		return ease(c / 0.3) -- yanked open
	elseif style == "Peek" then
		-- A crack of door, held while they look out, then opened the rest of the way.
		return if c < 0.3 then 0.35 * ease(c / 0.3) elseif c < 1.2 then 0.35 else 0.35 + 0.65 * ease((c - 1.2) / 0.35)
	elseif style == "Waiting" then
		return ease(c / 0.7)
	elseif style == "Flicker" then
		return ease((c - 0.2) / 0.9)
	end
	return ease(c / 1.0) -- Creep: eased open on the dark
end

-- Where they are (door frame z) `c` seconds into their entrance: an easy walk, or for Rush hard at
-- you and a sudden stop.
local function walkZ(figure: Figure, c: number): number
	local t = math.clamp((c - figure.walkAt) / figure.walkFor, 0, 1)
	local e = if figure.style == "Rush" then 1 - (1 - t) ^ 2 else (1 - math.cos(math.pi * t)) / 2
	return lerp(figure.fit.startZ, figure.fit.standZ, e)
end

-- Whether, walking out as timed, they'd get ahead of the door at some point.
local function aheadOfDoor(figure: Figure): boolean
	for c = 0, figure.walkAt + figure.walkFor, 1 / 30 do
		if walkZ(figure, c) < gateAt(figure.fit, doorOpen(figure.style, c)) - 0.02 then
			return true
		end
	end
	return false
end

-- In the world or not: see Figure.shown (and HomeownerController.hide).
local function place(figure: Figure)
	local parent = if figure.shown and not hiddenHouses[figure.house] then Workspace else nil
	if figure.model.Parent ~= parent then
		figure.model.Parent = parent
	end
end

local function create(house: Model, door: BasePart, skipEntrance: boolean, glance: boolean?)
	if figures[house] then
		return
	end
	local look = houseLook(house, door)
	local model, root, rootOffset = HomeownerController.build(house)
	if look == nil or model == nil or root == nil or rootOffset == nil then
		return
	end
	local joints: { [string]: Motor6D } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			joints[descendant.Name] = descendant
		end
	end
	local void = Instance.new("Part")
	void.Name = "DoorVoid"
	void.Anchored = true
	void.CanCollide = false
	void.CanQuery = false
	void.CanTouch = false
	void.CastShadow = false
	void.Material = Enum.Material.SmoothPlastic
	void.Color = Color3.new(0, 0, 0)
	void.Size = Vector3.new(0.05, door.Size.Y, 0.05)
	void.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = GLOW_COLOR
	glow.Range = 11
	glow.Brightness = 0
	glow.Shadows = true
	glow.Parent = void
	void.Parent = Workspace -- not in the model: it stays while they're out of the world
	local style = house:GetAttribute("OwnerStyle")
	local hingeModel = door.Parent
	local hinge = if hingeModel
			and hingeModel:IsA("Model")
			and CollectionService:HasTag(hingeModel, "Hinged")
			and hingeModel:GetAttribute("Kind") == "FrontDoor"
		then hingeModel
		else nil
	local ignore: { Instance } = { model }
	if hinge then
		table.insert(ignore, hinge)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local hingeAngle = if hinge then (hinge:GetAttribute("OpenAngle") :: number?) or 100 else 0
	-- A real door's two edges at each step of its swing (it swings in through the hall).
	local leaf: { { Vector2 } }? = nil
	local side = look.hinge
	if hinge then
		local pivot = hinge:GetPivot()
		side = if door.CFrame:PointToObjectSpace(pivot.Position).X < 0 then -1 else 1
		local swung = {}
		for k = 0, GATE_STEPS do
			local turn = pivot * CFrame.Angles(0, math.rad(hingeAngle * k / GATE_STEPS), 0) * pivot:Inverse()
			local edges = {}
			for _, sx in { -1, 1 } do
				local at =
					door.CFrame:PointToObjectSpace(turn * (door.CFrame * Vector3.new(sx * door.Size.X / 2, 0, 0)))
				table.insert(edges, Vector2.new(at.X, at.Z))
			end
			swung[k + 1] = edges
		end
		leaf = swung
	end
	local spots = if hinge then hallSpots(house, door, door.CFrame) else {}
	local fit = measure(door, door.CFrame, model, joints, ignore, leaf, spots, side)
	local figure: Figure = {
		house = house,
		door = door,
		doorFrame = door.CFrame,
		hinge = hinge,
		hingeClosed = if hinge then hinge:GetPivot() else CFrame.identity,
		hingeAngle = hingeAngle,
		side = side,
		model = model,
		root = root,
		rootOffset = rootOffset,
		joints = joints,
		height = (model:GetAttribute("Height") :: number?) or root.Size.Y,
		look = look,
		-- Too tall for the door, there's no peeking round it: they come folded from deep in the hall
		-- (and in a hall too short to wait clear of the door, it's open before they're there to see).
		style = if type(style) ~= "string"
				or WALK[style] == nil
				or (style == "Peek" and (fit.folding or fit.swept))
			then "Creep"
			else style,
		fit = fit,
		walkAt = 0,
		walkFor = 1,
		leaving = false,
		clock = if skipEntrance then 30 else 0,
		leaveClock = 0,
		leaveFrom = fit.standZ,
		leaveOpen = 1,
		leaveTurn = LEAVE_TURN,
		leaveWalk = LEAVE_WALK,
		poseClock = 1,
		open = 0,
		z = if skipEntrance then fit.standZ else fit.startZ,
		lastZ = if skipEntrance then fit.standZ else fit.startZ,
		speed = 0,
		travel = 0,
		stepIndex = 0,
		bend = foldAt(fit, if skipEntrance then fit.standZ else fit.startZ),
		yaw = 0,
		shown = false,
		fade = if skipEntrance then 1 else 0,
		void = void,
		glow = glow,
		porch = porchLights(house),
		headYaw = 0,
		headPitch = 0,
		twitchAt = 30,
		twitchNeck = 0,
		twitchArm = 0,
		twitchArmSide = "Left",
		twitchBody = 0,
		strikeAt = nil,
		scareAt = nil,
		glance = glance == true,
		slam = false,
		gesture = nil,
		gestureFor = 0,
		giveAt = nil,
		talkAt = nil,
		talkFor = 0,
		clapAt = nil,
		claps = 0,
		seed = if type(house:GetAttribute("OwnerSeed")) == "number"
			then house:GetAttribute("OwnerSeed") :: number
			else 0,
		cues = {},
		rng = Random.new(
			if type(house:GetAttribute("OwnerSeed")) == "number" then house:GetAttribute("OwnerSeed") :: number else nil
		),
		shut = false,
	}
	if glance then
		-- Just a look out at someone going by: the crack of door, never further.
		figure.style = if fit.folding or fit.swept then "Creep" else "Peek"
		figure.walkAt, figure.walkFor = math.huge, 1
		figure.twitchAt = math.huge
		figures[house] = figure
		return
	end
	local walk = WALK[figure.style]
	local arrive = walk.walkAt + walk.walkFor
	local distance = fit.startZ - fit.standZ
	figure.walkFor = math.max(walk.walkFor, distance / walk.maxSpeed)
	figure.walkAt = math.max(0.15, arrive - figure.walkFor)
	figure.walkFor = arrive - figure.walkAt
	-- Never ahead of the door: while it would be in their way, they set off later (and come faster).
	for _ = 1, 80 do
		if skipEntrance or not aheadOfDoor(figure) then
			break
		end
		figure.walkAt += 0.05
		figure.walkFor = math.max(arrive - figure.walkAt, distance / (walk.maxSpeed * 1.25))
	end
	figure.twitchAt = (if skipEntrance then 30 else figure.walkAt + figure.walkFor + 1) + figure.rng:NextNumber(0.5, 2)
	figures[house] = figure
	if not skipEntrance then
		Sound.play("Latch", { at = door }) -- the bolt drawn back before the door moves
	end
	-- Into the world once the door moves (pose).
end

local function destroy(house: Model)
	local figure = figures[house]
	if figure then
		figures[house] = nil
		for _, light in figure.porch do
			light.Enabled = true
		end
		if figure.hinge then
			figure.hinge:PivotTo(figure.hingeClosed)
		end
		figure.void:Destroy()
		figure.model:Destroy()
	end
end

-- The entrance at `clock`: how open the door is (0..1), where they are (door frame z), sideways
-- lean (Peek), head bow, the light inside, the porch light.
type Pose = { open: number, z: number, roll: number, bow: number, glow: number, porch: boolean }

local function entrance(figure: Figure): Pose
	local c = figure.clock
	local door = figure.door
	local style = figure.style
	if figure.glance then
		-- The door eased open a crack and their head leaning out into it, watching someone go by.
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 1.3, volume = 0.5, at = door })
		end)
		local open = GLANCE.crack * ease(c / GLANCE.open)
		local roll = if style == "Peek" then figure.side * 0.6 * ease((c - 0.35) / GLANCE.lean) else 0
		-- A little in from where they'd start, off to the side the door opens on, so their face is
		-- in the gap (pose puts them there).
		return {
			open = open,
			z = figure.fit.startZ - GLANCE.nearer,
			roll = roll,
			bow = 0,
			glow = open * 0.6,
			porch = true,
		}
	end
	local walk = { walkAt = figure.walkAt, walkFor = figure.walkFor }
	local t = (c - walk.walkAt) / walk.walkFor
	local open = doorOpen(style, c)
	local pose: Pose = { open = open, z = walkZ(figure, c), roll = 0, bow = 0, glow = 0.6, porch = true }

	if style == "Rush" then
		-- The door yanked open and they come straight at you, hard, and stop dead.
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 1.6, volume = 1.2, at = door })
		end)
		cue(figure, "cloth", walk.walkAt, function()
			Sound.play("Cloth", { at = figure.root })
		end)
		cue(figure, "stop", walk.walkAt + walk.walkFor, function()
			Sound.play("Thud", { at = door, volume = 0.8 })
		end)
		pose.glow = ease(c / 0.5) * 0.7
		local after = c - (walk.walkAt + walk.walkFor)
		pose.bow = if after > 0 then -0.5 * math.max(0, 1 - after / 0.6) else 0 -- the jolt as they stop
	elseif style == "Peek" then
		-- A crack of door, their head leaning out from behind it, gone again; then the door opens.
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 1.2, volume = 0.6, at = door })
		end)
		cue(figure, "creak2", 1.2, function()
			Sound.play("Creak", { speed = 0.85, at = door })
		end)
		cue(figure, "cloth", 1.2, function()
			Sound.play("Cloth", { at = figure.root, volume = 0.8 })
		end)
		local lean = if c < 0.3 then 0 elseif c < 1.2 then ease((c - 0.3) / 0.3) else 1 - ease((c - 1.2) / 0.35)
		pose.roll = figure.side * 0.6 * lean -- toward the gap
		pose.glow = pose.open * 0.6
	elseif style == "Waiting" then
		-- The door opens and they're already standing there in the dark hall, head bowed.
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 0.7, at = door })
		end)
		cue(figure, "breath", 0.9, function()
			Sound.play("Breath", { at = figure.root })
		end)
		cue(figure, "cloth", walk.walkAt - 0.3, function()
			Sound.play("Cloth", { at = figure.root, volume = 0.8 })
		end)
		pose.bow = -0.4 * (1 - ease((c - 0.9) / 0.6))
		pose.glow = open * 0.5
	elseif style == "Flicker" then
		-- The porch light stutters while something comes up the hall; it steadies as they stop.
		cue(figure, "whisper", 0.15, function()
			Sound.play("Whispers", { at = door, volume = 1.4 })
		end)
		cue(figure, "creak", 0.2, function()
			Sound.play("Creak", { speed = 0.6, at = door })
		end)
		pose.glow = pose.open * 0.4
		local arrive = walk.walkAt + walk.walkFor
		if c < arrive - 0.2 then
			pose.porch = figure.rng:NextNumber() < (if c < 0.8 then 0.5 else 0.75)
		end
	else
		-- Creep: the door eases open on the dark, steps come up the hall, they walk out slowly.
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 0.75, at = door })
		end)
		cue(figure, "whisper", 0.4, function()
			Sound.play("Whispers", { at = door, volume = 0.9 })
		end)
		pose.glow = open * 0.6
		pose.bow = -0.25 * (1 - ease(t))
	end
	cue(figure, "settle", walk.walkAt + walk.walkFor + 0.15, function()
		Sound.play("Cloth", { at = figure.root, volume = 0.6 })
		if style ~= "Rush" then
			Sound.play("Breath", { at = figure.root, volume = 0.8 })
		end
	end)
	return pose
end

-- Who they're looking at: whoever knocked (OwnerVisitor), so everyone sees them face the same kid;
-- you, if nobody's knocked or they're not about.
local function watching(figure: Figure, camera: Camera): Vector3
	local userId = figure.house:GetAttribute("OwnerVisitor")
	local visitor = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if visitor and visitor ~= Players.LocalPlayer then
		local character = visitor.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head and (head.Position - figure.root.Position).Magnitude < 40 then
			return head.Position
		end
	end
	return camera.CFrame.Position
end

local function setJoint(figure: Figure, name: string, value: CFrame)
	local motor = figure.joints[name]
	if motor then
		motor.Transform = value
	end
end

local function pose(figure: Figure, dt: number, camera: Camera)
	local door = figure.door
	local fit = figure.fit
	local p = entrance(figure)
	local z = math.max(p.z, gateAt(fit, p.open)) -- never ahead of the door (create times it so)
	if figure.leaving then
		-- Turned back to the door, they back into the dark step by step; then the door shuts on them.
		local t = figure.leaveClock
		local back = (t - figure.leaveTurn) / figure.leaveWalk
		z = lerp(figure.leaveFrom, fit.startZ, (1 - math.cos(math.pi * math.clamp(back, 0, 1))) / 2)
		local closing = t - figure.leaveTurn - figure.leaveWalk
		local closeTime = if figure.slam then GLANCE.slam else CLOSE_TIME
		p.open = figure.leaveOpen * (1 - ease(closing / closeTime))
		p.glow = 0.6 * figure.leaveOpen * (1 - ease(t / (figure.leaveTurn + figure.leaveWalk + CLOSE_TIME)))
		p.porch = true
		p.roll, p.bow = 0, 0
		if closing >= closeTime and not figure.shut then
			figure.shut = true
			if figure.leaveOpen > 0.2 then
				Sound.play(if figure.style == "Rush" or figure.slam then "DoorSlam" else "DoorShut", { at = door })
			end
		end
	end
	figure.z = z
	figure.open = p.open

	local doorFrame = figure.doorFrame
	if figure.hinge then
		-- A real door: it swings open onto the dark hall, where the light comes from.
		figure.hinge:PivotTo(
			figure.hingeClosed * CFrame.Angles(0, math.rad(figure.hingeAngle * math.clamp(p.open, 0, 1)), 0)
		)
		figure.void.Transparency = 1
		figure.void.CFrame = doorFrame * CFrame.new(0, 1, 2.5)
	else
		-- A painted-on door: darkness grows from the hinge side instead.
		local width = door.Size.X * math.clamp(p.open, 0, 1)
		local hingeX = figure.side * door.Size.X / 2
		figure.void.Size = Vector3.new(math.max(width, 0.05), door.Size.Y, 0.05)
		figure.void.Transparency = if width < 0.06 then 1 else 0
		figure.void.CFrame = doorFrame * CFrame.new(hingeX - figure.side * width / 2, 0, -DOOR_FRONT + 0.03)
	end
	figure.glow.Brightness = p.glow
	for _, light in figure.porch do
		light.Enabled = p.porch
	end

	figure.poseClock += dt
	if figure.poseClock < 1 / POSE_FPS then
		return
	end
	local step = figure.poseClock
	figure.poseClock = 0

	-- Fold forward under whatever's low (planned ahead, so the head never goes through a wall).
	figure.bend = foldAt(fit, z)
	-- How far all of them is from the wall round the door: in front of it, or behind it in the hall
	-- (negative: in the doorway).
	local outside = -DOOR_FRONT - 0.1 - (z + fit.back)
	local behind = z - frontAt(fit, figure.bend) - (-DOOR_FRONT + WALL)
	-- Turning: sideways through a door narrower than they are, straight through any other; out on
	-- the porch, round to face you (the head turns the rest of the way); back to the door to go in.
	local x = pathX(fit, z) - (if figure.glance then figure.side * door.Size.X * GLANCE.aside else 0)
	local focus = watching(figure, camera)
	local eye = doorFrame:PointToObjectSpace(focus)
	local turningIn = figure.leaving and figure.leaveClock >= figure.gestureFor -- (after any goodbye)
	local target, rate = pathYaw(fit, z), if turningIn then 2 * TURN_RATE else TURN_RATE
	local standing = z < fit.standZ + 0.1
	if fit.wide and (turningIn or not standing) and behind < 0.8 and z < fit.startZ - 0.05 then
		target, rate = SIDEWAYS * figure.side, 3
	elseif standing and not turningIn then
		target = math.clamp(math.atan2(-(eye.X - x), -(eye.Z - z)), -fit.turn, fit.turn)
	end
	local turned = approach(figure.yaw, target, rate * step) - figure.yaw
	figure.yaw += turned
	-- In the doorway they hold themselves straight: no tilt, sway or twitch to catch on the frame.
	local loose = math.clamp(1 + math.max(outside, behind) / 0.5, 0, 1)

	-- How fast their feet are going, and the walk cycle: one footfall every stepLength of ground
	-- covered (turning round on the spot is a shuffle of small steps).
	local moved = math.abs(figure.z - figure.lastZ) * math.sqrt(1 + math.tan(pathYaw(fit, z)) ^ 2)
		+ math.abs(turned) * TURN_STEP
	figure.lastZ = figure.z
	figure.travel += moved
	figure.speed = lerp(figure.speed, moved / step, math.min(1, step * 10))
	local phase = figure.travel / fit.stepLength
	local index = math.floor(phase + 0.5)
	if index ~= figure.stepIndex then
		figure.stepIndex = index
		if figure.speed > 0.3 then
			footstep(figure, if figure.style == "Rush" and not figure.leaving then 1.3 else 1)
		end
	end
	local stride = math.clamp(figure.speed / 2.2, 0, 1)
	local swing = math.sin(math.pi * phase) * stride

	-- Twitches once they've stopped: something jerks, then settles.
	local arrived = figure.clock >= figure.walkAt + figure.walkFor
	if arrived and figure.clock >= figure.twitchAt and not figure.leaving then
		figure.twitchAt = figure.clock + figure.rng:NextNumber(Homeowners.TWITCH_EVERY.min, Homeowners.TWITCH_EVERY.max)
		local kind = figure.rng:NextInteger(1, 3)
		if kind == 1 then
			figure.twitchNeck = figure.rng:NextNumber(-0.6, 0.6)
		elseif kind == 2 then
			figure.twitchArm = figure.rng:NextNumber(0.3, 0.9)
			figure.twitchArmSide = if figure.rng:NextNumber() < 0.5 then "Left" else "Right"
		else
			figure.twitchBody = figure.rng:NextNumber(-0.18, 0.18)
		end
	end
	local decay = math.exp(-step * 7)
	figure.twitchNeck *= decay
	figure.twitchArm *= decay
	figure.twitchBody *= decay

	local now = os.clock()
	local breathe = math.sin(now * 1.4) * 0.025
	local tilt = figure.look.tilt
	local idle = if arrived and not figure.leaving then figure.clock - figure.walkAt - figure.walkFor else 0
	local lean = math.min(idle / 30, 0.12) -- they slowly lean in toward you while you play
	local bob = -math.abs(swing) * 0.06 * fit.hipY -- lowest with the legs apart

	-- Slapping you: the hand drawn back out to the side as they turn away, swung flat across at your
	-- face as they lunge and turn through, then back. `slap` 0..1 is how much the slap has the arm
	-- (the rest of its pose fades out under it); the angles are for a right hand (a left one mirrors).
	local slap, slapYaw, slapRoll, slapTwist, slapLean, slapLunge = 0, 0, 0, 0, 0, 0
	if figure.strikeAt then
		local s = figure.clock - (figure.strikeAt :: number)
		local through = SLAP.windup + SLAP.swing
		if s < SLAP.windup then
			local w = ease(s / SLAP.windup)
			slap = w
			slapYaw, slapRoll, slapTwist = SLAP.back, SLAP.out * w, -SLAP.twist * w
		elseif s < through then
			local k = (s - SLAP.windup) / SLAP.swing
			slap = 1
			slapYaw, slapRoll = lerp(SLAP.back, SLAP.across, k), SLAP.out
			slapTwist, slapLean, slapLunge = lerp(-SLAP.twist, SLAP.twist * 0.75, k), SLAP.lean * k, SLAP.lunge * k
		elseif s < through + SLAP.recover then
			local r = 1 - ease((s - through) / SLAP.recover)
			slap = r
			slapYaw, slapRoll = SLAP.across, SLAP.out * r
			slapTwist, slapLean, slapLunge = SLAP.twist * 0.75 * r, SLAP.lean * r, SLAP.lunge * r
		else
			figure.strikeAt = nil
		end
	end
	-- Lunging at someone (their scare): both hands up and out at them, held, then back.
	local scare = 0
	if figure.scareAt then
		local s = figure.clock - (figure.scareAt :: number)
		if s < SCARE.rush then
			scare = ease(s / SCARE.rush)
		elseif s < SCARE.rush + SCARE.hold then
			scare = 1
		elseif s < SCARE.rush + SCARE.hold + SCARE.recover then
			scare = 1 - ease((s - SCARE.rush - SCARE.hold) / SCARE.recover)
		else
			figure.scareAt = nil
		end
	end
	local slapSide = if figure.look.hinge > 0 then "Right" else "Left"
	local mirror = if slapSide == "Right" then 1 else -1
	-- Something they do while you play (ACTS), when nothing else has them: the same on every screen.
	local act: Act = {}
	local actWeight = 0
	local busy = figure.strikeAt or figure.scareAt or figure.giveAt or figure.clapAt or figure.talkAt
	if arrived and not figure.leaving and not figure.glance and not busy then
		local serverNow = Workspace:GetServerTimeNow()
		local window = math.floor(serverNow / ACT_EVERY)
		local roll = Random.new(figure.seed + window * 13)
		if roll:NextNumber() < ACT_CHANCE then
			local chosen = ACTS[roll:NextInteger(1, #ACTS)]
			local t = serverNow - window * ACT_EVERY - roll:NextNumber(0, 0.8)
			if t >= 0 and t < chosen.time then
				act = chosen.pose(t)
				actWeight = math.min(ease(t / 0.35), 1 - ease((t - (chosen.time - 0.4)) / 0.4))
			end
		end
	end
	-- Talking: the far hand beating with the words, the head nodding on them.
	local talk = 0
	if figure.talkAt then
		local t = figure.clock - (figure.talkAt :: number)
		if t > figure.talkFor then
			figure.talkAt = nil
		else
			talk = math.min(ease(t / TALK.ease), 1 - ease((t - (figure.talkFor - TALK.ease)) / TALK.ease))
		end
	end
	-- Clapping: both hands out, meeting CLAP.claps times.
	local clap, clapIn = 0, 0
	if figure.clapAt then
		local t = figure.clock - (figure.clapAt :: number)
		if t > CLAP.time then
			figure.clapAt = nil
		else
			clap = math.min(ease(t / 0.15), 1 - ease((t - (CLAP.time - 0.2)) / 0.2))
			local beat = t / CLAP.time * CLAP.claps
			clapIn = 0.5 - 0.5 * math.cos(beat * 2 * math.pi) -- 0 apart .. 1 together
			if math.floor(beat + 0.5) > figure.claps and beat < CLAP.claps then
				figure.claps = math.floor(beat + 0.5)
				Sound.play("Clap", { at = figure.root })
			end
		end
	end
	local talkBeat = figure.talkAt and math.sin((figure.clock - (figure.talkAt :: number)) * 5.5) or 0
	-- Their goodbye (going back in, before they turn to the door), eased in and out.
	local bye: Bye = {}
	local byeWeight = 0
	local goodbye = if figure.gesture then GOODBYES[figure.gesture :: string] else nil
	if goodbye and figure.leaving and figure.leaveClock < figure.gestureFor then
		local t = figure.leaveClock
		bye = goodbye.pose(t)
		byeWeight = math.min(ease(t / 0.2), 1 - ease((t - (goodbye.time - 0.25)) / 0.25))
	end

	figure.root.CFrame = doorFrame
		* CFrame.new(x, -door.Size.Y / 2 + bob, z - slapLunge - SCARE.lunge * scare)
		* CFrame.Angles(0, figure.yaw, 0)
		* figure.rootOffset
	local fold = figure.bend
		+ lean
		+ slapLean
		+ SCARE.lean * scare
		+ (bye.fold or 0) * byeWeight
		+ (act.fold or 0) * actWeight
	setJoint(
		figure,
		"RootJoint",
		CFrame.Angles(
			-fold + breathe + p.bow * 0.25,
			slapTwist * mirror + (act.twist or 0) * mirror * actWeight,
			(p.roll + tilt * 0.3 + figure.twitchBody + swing * 0.035 + (act.sway or 0) * actWeight) * loose
		)
	)

	-- Head: watches you (slowly, with snaps when it twitches); while walking it mostly looks ahead.
	local torso = figure.model:FindFirstChild("Torso") :: BasePart?
	local head = figure.model:FindFirstChild("Head") :: BasePart?
	if torso and head and figure.shown then
		local dir = torso.CFrame:VectorToObjectSpace(focus - head.Position)
		local watchful = arrived or figure.glance
		local turn = if watchful then 1.2 else HEAD_WALK.turn
		local yaw = math.clamp(math.atan2(-dir.X, -dir.Z), -turn, turn)
		local pitch = math.clamp(
			math.atan2(dir.Y, math.sqrt(dir.X * dir.X + dir.Z * dir.Z)),
			if watchful then -0.6 else HEAD_WALK.down,
			if arrived then 0.9 else HEAD_WALK.up
		)
		local follow =
			math.min(1, step * (if math.abs(figure.twitchNeck) > 0.3 then 12 elseif watchful then 2.2 else 1.2))
		figure.headYaw = lerp(figure.headYaw, yaw, follow)
		figure.headPitch = lerp(figure.headPitch, pitch, follow)
	end
	setJoint(
		figure,
		"Neck",
		CFrame.fromEulerAnglesYXZ(
			(if arrived then figure.headPitch + p.bow else math.max(figure.headPitch + p.bow, HEAD_WALK.down))
				+ (bye.nod or 0) * byeWeight
				+ (act.nod or 0) * actWeight
				+ TALK.nod * talkBeat * talk
				- 0.15 * clap,
			figure.headYaw * loose + (bye.turn or 0) * mirror * byeWeight + (act.turn or 0) * mirror * actWeight,
			(tilt + figure.twitchNeck) * loose
				+ (bye.tilt or 0) * mirror * byeWeight
				+ (act.tilt or 0) * mirror * actWeight
		)
	)

	-- In the world once the door moves; out of it while a door swinging past would be in their way
	-- (a hall too short for them to wait clear of it), and once it's shut on them.
	-- Where they couldn't wait clear of the door they come out of the dark once it's past them, and
	-- fade back into it before it closes again.
	local shown = p.open > 0.03 and not figure.shut
	local leaf = fit.leaf
	if shown and leaf and p.open < 1 and not figure.glance then -- (a peek stands clear of the door's swing)
		local k = math.floor(math.clamp(p.open, 0, 1) * GATE_STEPS) + 1
		local front = frontAt(fit, figure.bend)
		shown = not hitsLeaf(fit, leaf[k], x, z, front)
			and not hitsLeaf(fit, leaf[math.min(k + 1, GATE_STEPS)], x, z, front)
	end
	local closing = figure.leaving and figure.leaveClock > figure.leaveTurn + figure.leaveWalk
	local fadeTo = if shown and not (fit.swept and closing) then 1 else 0
	figure.fade = if shown then approach(figure.fade, fadeTo, step / FADE) else 0
	shown = shown and (figure.fade > 0 or fadeTo > 0)
	if shown ~= figure.shown then
		figure.shown = shown
		place(figure)
	end
	if shown then
		for _, part in figure.model:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1 - figure.fade
			end
		end
	end

	-- Legs: the stride, kept upright however far the body folds over them. Arms swing against the
	-- legs and hang down as the body folds; some homeowners slowly reach for you while you play.
	local reach = if figure.look.reach and arrived and not figure.leaving then ease((idle - 2) / 4) * 1.25 else 0
	local reachSide = slapSide
	-- Handing you your candy: the arm out to you, then back.
	if figure.giveAt then
		local g = figure.clock - (figure.giveAt :: number)
		if g > GIVE.back then
			figure.giveAt = nil
		else
			local out =
				math.min(ease(g / GIVE.reach), 1 - ease((g - GIVE.release - 0.1) / (GIVE.back - GIVE.release - 0.1)))
			reach = math.max(reach, GIVE.raise * out)
		end
	end

	for _, side in { "Left", "Right" } do
		local sign = if side == "Left" then 1 else -1
		-- The legs stay put while the body turns over them.
		setJoint(figure, side .. " Hip", CFrame.Angles(fold + sign * swing * 0.5, -slapTwist * mirror, 0))
		local lift = if side == reachSide then reach else 0
		local jerk = if side == figure.twitchArmSide then figure.twitchArm else 0
		local sway = math.sin(now * 0.9 + (if side == "Left" then 0 else 1.7)) * 0.04
		local splay = if side == "Left" then -0.05 else 0.05 :: number
		local pitch = lerp(fold * 0.8 - sign * swing * 0.35 + lift + jerk + sway, SCARE.reach, scare)
		if side == reachSide and byeWeight > 0 and bye.pitch then
			pitch = lerp(pitch, bye.pitch :: number, byeWeight)
			splay = lerp(splay, (bye.roll or 0) * mirror, byeWeight)
		end
		-- An act that uses an arm (near: their slapping side; far: the other).
		local actSide = if act.arm == "near"
			then reachSide
			elseif act.arm == "far" then (if reachSide == "Left" then "Right" else "Left")
			else nil
		if side == actSide and act.pitch then
			local out = if side == "Right" then 1 else -1
			pitch = lerp(pitch, act.pitch :: number, actWeight)
			splay = lerp(splay, (act.roll or 0) * out, actWeight)
		end
		-- Talking: the far hand.
		if talk > 0 and side ~= reachSide then
			local out = if side == "Right" then 1 else -1
			pitch = lerp(pitch, TALK.pitch + TALK.beat * talkBeat, talk)
			splay = lerp(splay, TALK.roll * out, talk)
		end
		-- Clapping: both hands out in front, swung in to meet.
		if clap > 0 then
			local inward = if side == "Right" then -1 else 1
			pitch = lerp(pitch, CLAP.pitch, clap)
			splay = lerp(splay, inward * lerp(CLAP.apart, CLAP.together, clapIn), clap)
		end
		if side == slapSide and slap > 0 then
			-- Out to the side (roll), round across the front (yaw), up to face height (pitch).
			setJoint(
				figure,
				side .. " Shoulder",
				CFrame.Angles(lerp(pitch, SLAP.lift, slap), slapYaw * mirror * slap, splay + slapRoll * mirror)
			)
		else
			setJoint(figure, side .. " Shoulder", CFrame.Angles(pitch, 0, splay))
		end
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	for house, figure in figures do
		if house.Parent == nil or figure.door.Parent == nil then
			destroy(house)
			continue
		end
		figure.clock += dt
		if figure.leaving then
			figure.leaveClock += dt
			if figure.leaveClock > figure.leaveTurn + figure.leaveWalk + CLOSE_TIME + 0.2 then
				destroy(house)
				continue
			end
		end
		pose(figure, dt, camera)
	end
end

-- Seconds since this house's homeowner came out (huge if we don't know).
local function outFor(house: Model): number
	local at = house:GetAttribute("OwnerOutAt")
	return if type(at) == "number" then Workspace:GetServerTimeNow() - at else math.huge
end

-- Back the way they came: as long as it takes from where they got to (still in the hall, the door
-- just closes again). A visit ends with a goodbye first (OwnerMood); a peek someone came too close
-- to ends in a slammed door.
local function goBackIn(figure: Figure, slam: boolean)
	figure.leaving = true
	figure.leaveClock = 0
	figure.leaveFrom = figure.z
	figure.leaveOpen = figure.open
	figure.slam = slam
	local chosen = if figure.glance or not figure.shown then nil else figure.house:GetAttribute("OwnerBye")
	local goodbye = if type(chosen) == "string" then GOODBYES[chosen] else nil
	figure.gesture = if goodbye then chosen :: string else nil
	figure.gestureFor = if goodbye then goodbye.time else 0
	if goodbye then
		figure.slam = slam or goodbye.slam
		if goodbye.sound then
			Sound.play(goodbye.sound, { at = figure.root, volume = 0.5 })
		end
	end
	local turnTo = if figure.fit.wide then SIDEWAYS * figure.side else 0
	local turning = math.abs(turnTo - figure.yaw) / (if figure.fit.wide then 3 else 2 * TURN_RATE)
	figure.leaveTurn = figure.gestureFor + (if turning > 0.03 then math.max(LEAVE_TURN, turning + 0.1) else 0)
	local back = figure.fit.startZ - figure.z
	figure.leaveWalk = if back < 0.05 then 0 else math.clamp(back / LEAVE_PACE, 0.6, LEAVE_WALK)
	if figure.glance then
		-- A peek: they pull back from the gap at once, the door shutting as they go.
		figure.leaveTurn, figure.leaveWalk = 0, 0.3
	end
	if figure.shown then
		Sound.play("Cloth", { at = figure.root, volume = 0.7 })
	end
end

local function onOutChanged(house: Model, door: BasePart)
	local out = house:GetAttribute("OwnerOut") == true
	local figure = figures[house]
	if out then
		if figure and (figure.leaving or figure.glance) then
			destroy(house) -- knocked again while they were going back in (or peeking): start over
			figure = nil
		end
		if figure == nil then
			local camera = Workspace.CurrentCamera
			if camera and (camera.CFrame.Position - door.Position).Magnitude <= VIEW_DISTANCE then
				create(house, door, outFor(house) > LATE)
			end
		end
	elseif figure and not figure.leaving and not figure.glance then
		goBackIn(figure, false)
	end
end

-- Someone peeks out at a kid going by (Glance, HomeownerService), and shuts the door again (slams
-- it, GlanceSlam, if they came close).
local function onGlanceChanged(house: Model, door: BasePart)
	local figure = figures[house]
	if house:GetAttribute("Glance") == true then
		local camera = Workspace.CurrentCamera
		if figure == nil and house:GetAttribute("OwnerOut") ~= true and camera then
			if (camera.CFrame.Position - door.Position).Magnitude <= VIEW_DISTANCE then
				create(house, door, false, true)
			end
		end
	elseif figure and figure.glance and not figure.leaving then
		goBackIn(figure, house:GetAttribute("GlanceSlam") == true)
	end
end

local function watch(door: Instance)
	if not door:IsA("BasePart") then
		return
	end
	local house = Houses.of(door)
	if house == nil or house:GetAttribute("HouseId") == nil then
		return
	end
	house:GetAttributeChangedSignal("OwnerOut"):Connect(function()
		onOutChanged(house, door)
	end)
	house:GetAttributeChangedSignal("Glance"):Connect(function()
		onGlanceChanged(house, door)
	end)
end

-- Hides a house's homeowner (the jumpscare uses its own copy) or shows it again.
function HomeownerController.hide(house: Model, hidden: boolean)
	hiddenHouses[house] = if hidden then true else nil
	local figure = figures[house]
	if figure then
		place(figure)
	end
end

-- Where a house's front door hangs when closed (a real door may be swung open right now).
function HomeownerController.doorFrame(door: BasePart): CFrame
	local house = Houses.of(door)
	local figure = house and figures[house]
	return if figure then figure.doorFrame else door.CFrame
end

-- Seconds until whoever answered a house's door stops on the porch (0: they have; nil: nobody's
-- coming out here).
function HomeownerController.arrivesIn(house: Model): number?
	local figure = figures[house]
	if figure == nil or figure.leaving then
		return nil
	end
	return math.max(0, figure.walkAt + figure.walkFor - figure.clock)
end

-- They slap you (a wrong answer): returns seconds until the slap lands and the hand it's with
-- ("Left"/"Right", theirs), or nil if nobody's out on the porch to do it.
function HomeownerController.strike(house: Model): (number?, string?)
	local figure = figures[house]
	if figure == nil or figure.leaving or not figure.shown or figure.clock < figure.walkAt + figure.walkFor then
		return nil, nil
	end
	figure.strikeAt = figure.clock
	figure.twitchArm = 0
	Sound.play("Cloth", { at = figure.root, volume = 0.8 })
	Sound.play("Breath", { at = figure.root, volume = 0.9, speed = 1.2 })
	task.delay(SLAP.windup, function()
		Sound.play("Whoosh", { at = figure.root, volume = 0.5, speed = 1.3 })
	end)
	return SLAP.windup + SLAP.swing * SLAP.hit, if figure.look.hinge > 0 then "Right" else "Left"
end

-- Whether someone's at a house's door: out, or going back in until the door has shut on them.
function HomeownerController.atDoor(house: Model): boolean
	return figures[house] ~= nil or house:GetAttribute("OwnerOut") == true
end

-- They hand someone their candy: the arm out, a piece of candy (like those in `bucket`, the
-- receiver's) leaving the hand and flying to `target()` (where it's going, asked as it flies), a pop
-- as it lands. Nothing if nobody's out.
function HomeownerController.give(house: Model, target: () -> Vector3?, bucket: Model?)
	local figure = figures[house]
	if figure == nil or figure.leaving or not figure.shown then
		return
	end
	figure.giveAt = figure.clock
	local side = if figure.look.hinge > 0 then "Right" else "Left"
	local shoulder = figure.joints[side .. " Shoulder"]
	local arm = shoulder and shoulder.Part1
	if arm == nil then
		return
	end
	local source = bucket and bucket:FindFirstChild("Candy1")
	local candy =
		CandyPiece.make(0.45, if source and source:IsA("BasePart") then source.Color else Color3.fromHex("E8513C"))
	candy.Name = "GivenCandy"
	candy.Transparency = 0
	candy.Anchored = true
	candy.CanCollide = false
	candy.CanQuery = false
	candy.CanTouch = false
	candy:ClearAllChildren()
	candy.Parent = Workspace
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local hand = (arm.CFrame * CFrame.new(0, -arm.Size.Y / 2, 0)).Position
		if t < GIVE.release then
			candy.Position = hand
			return
		end
		local k = (t - GIVE.release) / GIVE.fly
		local to = target()
		if k >= 1 or to == nil or figures[house] ~= figure then
			connection:Disconnect()
			if to then
				Sound.play("Pop", { at = candy, volume = 0.7 })
			end
			candy:Destroy()
			return
		end
		-- An arc from the hand to them.
		local at = hand:Lerp(to :: Vector3, k) + Vector3.new(0, math.sin(math.pi * k) * 1.2, 0)
		candy.Position = at
	end)
end

-- They lunge out at someone (someone else's scare; yours is the jumpscare). Nothing if nobody's out.
-- They're saying a line for `seconds`: they gesture and nod with it (DoorController, as it shows).
function HomeownerController.talk(house: Model, seconds: number)
	local figure = figures[house]
	if figure and not figure.leaving then
		figure.talkAt = figure.clock
		figure.talkFor = seconds
	end
end

-- A PERFECT: a slow clap before they hand over the candy (DoorController).
function HomeownerController.clap(house: Model)
	local figure = figures[house]
	if figure and not figure.leaving and figure.shown then
		figure.clapAt = figure.clock
		figure.claps = 0
	end
end

function HomeownerController.lunge(house: Model)
	local figure = figures[house]
	if figure and not figure.leaving and figure.shown then
		figure.scareAt = figure.clock
		figure.strikeAt = nil
	end
end

-- The homeowner's root part at a house right now, if one is out (for the jumpscare to start from).
function HomeownerController.current(house: Model): BasePart?
	local figure = figures[house]
	return if figure and not figure.leaving then figure.root else nil
end

-- Where the face of whoever answered a house's door is right now (DoorController looks up at it).
function HomeownerController.face(house: Model): Vector3?
	local figure = figures[house]
	if figure == nil or figure.leaving or not figure.shown then
		return nil -- (out of the world, the head isn't kept where it would be)
	end
	local head = figure.model:FindFirstChild("Head") :: BasePart?
	local anchor = head and head:FindFirstChild("Face")
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	end
	if head then
		return head.Position
	end
	return (figure.root.CFrame * CFrame.new(0, figure.root.Size.Y * 0.4, 0)).Position
end

function HomeownerController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(watch)
	for _, door in CollectionService:GetTagged("Door") do
		watch(door)
	end
	RunService.RenderStepped:Connect(step)
	-- Someone else's homeowner was already out when we arrived, or we walked into view of one.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local camera = Workspace.CurrentCamera
			if camera then
				for _, door in CollectionService:GetTagged("Door") do
					local house = Houses.of(door)
					if
						house
						and door:IsA("BasePart")
						and figures[house] == nil
						and house:GetAttribute("OwnerOut") == true
						and outFor(house) > LATE -- a fresh one plays its entrance (onOutChanged)
						and (camera.CFrame.Position - door.Position).Magnitude <= VIEW_DISTANCE
					then
						create(house, door, true)
					end
				end
			end
		end
	end)
end

return HomeownerController
