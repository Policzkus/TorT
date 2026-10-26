--!strict
-- The Knifer as you see and hear him (KniferService runs him, Config/Knifer): the sting the moment he
-- comes onto your street (KniferCame), wherever he is; his heavy boots wherever he walks; the chase
-- music while he's after you (or after someone right by you); for everyone near, the blow and the
-- body hitting the ground when he gets someone (KniferStruck).
-- And how he moves (his own animation, not the kids' walk cycle: CharacterAnimController leaves him
-- alone). A heavy, hunched walk with a limp, the knife hanging by his leg, the other arm dead still;
-- the head low, slowly scanning, now and then snapping round to stare at something; the moment he
-- appears, head down, then up. Running at you, the knife up over his head and his eyes on you.
-- Searching, bent forward, the knife held out, peering. Got you: two stabs down, then he stands over
-- you. Standing still, he breathes, heavily, and you hear it. Posed at the game's choppy PSX rate;
-- what's left to chance (the snaps, the breaths) comes from his seed and server time, so every
-- player sees the same.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Knifer = require(Shared.Config.Knifer)
local Net = require(Shared.Modules.Net)
local MusicController = require(script.Parent.MusicController)
local Sound = require(script.Parent.SoundController)

local KniferController = {}

local CHASE_NEAR = 30 -- studs: this close to him while he's chasing anyone, and it's your chase too
local RUNNING = 14 -- studs/s: faster than this and his strides are long
local POSE_FPS = 14 -- choppy, like everyone else (CharacterAnimController)
-- His walk: radians of leg swing per stud, the swing walking and running (blended over `runFrom`..
-- `runTo` studs/s), the right leg's share of it (he favours it: a limp), how far his hips drop.
local GAIT = { stride = 0.42, walk = 0.5, run = 0.8, limp = 0.65, bob = 0.12, runFrom = 11, runTo = 17 }
local HUNCH = { walk = 0.14, run = 0.38, stand = 0.1, search = 0.3 } -- radians forward he leans
-- The knife arm's pitch: hanging by his leg, held out in front, raised over his head (bobbing as he runs).
local KNIFE_ARM = { hang = 0.12, ready = 0.95, raised = 2.55, bob = 0.15, rate = 8 }
-- His wrist (the knife's "Wrist" joint, KniferService): with the arm low (pitch under `from`) the
-- blade's turned `low` radians to hang point down by his leg (held out in front, it points ahead
-- and down); as the arm comes up past `to` it turns back in line for the blow. (A kill's STAB
-- keyframes turn it themselves.)
local WRIST = { low = 1.6, from = 1.2, to = 2.3, rate = 9 }
-- His head: the slow scan either way (walking, standing), how low he holds it, its tilt; and the
-- snaps (every `every` s there's a `chance` he snaps it round to stare at something for `hold` s).
local HEAD = { scan = 0.55, look = 0.95, down = -0.18, tilt = 0.14, every = 3.5, chance = 0.45, hold = 1.1 }
local SNAP_UP = 0.5 -- seconds of the snap up when he's done appearing (head down till then)
local BREATH = { every = 6.5, chance = 0.6 } -- a heavy breath you hear, now and then (standing, walking)
-- Two stabs down, then over you: { seconds in, knife arm pitch, extra lean, wrist } keyframes. Each
-- blow stops with the arm out in front and the blade straight down (into you, on the ground in front
-- of him); then he pulls it out and stands over you, the knife hanging.
local STAB = {
	{ 0, 2.55, 0, 0 }, -- raised, from the chase
	{ 0.16, 2.95, -0.05, 0 }, -- drawn back
	{ 0.28, 1.6, 0.4, 0.25 }, -- down
	{ 0.5, 2.8, 0, 0 }, -- up again
	{ 0.62, 1.5, 0.42, 0.3 }, -- down
	{ 1.0, 1.4, 0.4, 0.4 }, -- held in
	{ 1.8, 0.5, 0.3, 1.6 }, -- pulled out
}

type Tracked = {
	model: Model,
	root: BasePart,
	joints: { [string]: Motor6D },
	seed: number,
	last: Vector3,
	travelled: number, -- since the last footstep
	phase: number,
	speed: number,
	poseClock: number,
	state: string,
	previous: string, -- the state before
	stateAt: number, -- os.clock his state last changed (as this client heard it)
	armPitch: number,
	wrist: number,
	headYaw: number,
	headPitch: number,
	breath: number, -- the last breath window
}

local tracked: { [Model]: Tracked } = {}
local random = Random.new()

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function stab(t: number): (number, number, number)
	for i = 1, #STAB - 1 do
		local a, b = STAB[i], STAB[i + 1]
		if t < b[1] then
			local k = (t - a[1]) / (b[1] - a[1])
			return lerp(a[2], b[2], k), lerp(a[3], b[3], k), lerp(a[4], b[4], k)
		end
	end
	local last = STAB[#STAB]
	return last[2], last[3], last[4]
end

local function set(him: Tracked, name: string, value: CFrame)
	local motor = him.joints[name]
	if motor then
		motor.Transform = value
	end
end

local function add(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	local root = instance:WaitForChild("HumanoidRootPart", 5)
	if root == nil or not root:IsA("BasePart") or instance.Parent == nil then
		return
	end
	local joints: { [string]: Motor6D } = {}
	for _, item in instance:GetDescendants() do
		if item:IsA("Motor6D") then
			joints[item.Name] = item
		end
	end
	local seed = instance:GetAttribute("Seed")
	local him: Tracked = {
		model = instance,
		root = root,
		joints = joints,
		seed = if type(seed) == "number" then seed else 0,
		last = root.Position,
		travelled = 0,
		phase = 0,
		speed = 0,
		poseClock = 0,
		state = tostring(instance:GetAttribute("State")),
		previous = "",
		stateAt = os.clock(),
		armPitch = KNIFE_ARM.hang,
		wrist = WRIST.low,
		headYaw = 0,
		headPitch = -0.6,
		breath = -1,
	}
	tracked[instance] = him
	instance:GetAttributeChangedSignal("State"):Connect(function()
		him.previous = him.state
		him.state = tostring(instance:GetAttribute("State"))
		him.stateAt = os.clock()
	end)
end

-- Where his head wants to point (yaw, pitch, in the torso's frame) and how fast it gets there.
local function headAim(
	him: Tracked,
	torso: BasePart,
	head: BasePart,
	now: number,
	serverNow: number
): (number, number, number)
	if him.state == "appear" then
		return 0, -0.7, 4 -- just out: head down
	end
	if him.previous == "appear" and os.clock() - him.stateAt < SNAP_UP then
		return 0, 0.05, 20 -- and up: he's seen the street
	end
	if him.state == "kill" then
		return 0, -0.65, 6 -- looking down at you
	end
	if him.state == "chase" then
		-- Eyes on you.
		local userId = him.model:GetAttribute("Target")
		local victim = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		local victimHead = victim and victim.Character and victim.Character:FindFirstChild("Head") :: BasePart?
		if victimHead then
			local dir = torso.CFrame:VectorToObjectSpace(victimHead.Position - head.Position)
			local yaw = math.clamp(math.atan2(-dir.X, -dir.Z), -1.1, 1.1)
			local pitch = math.clamp(math.atan2(dir.Y, math.sqrt(dir.X * dir.X + dir.Z * dir.Z)), -0.5, 0.6)
			return yaw, pitch, 9
		end
	end
	-- The snaps: the same moments, the same way, on every screen.
	local window = math.floor(serverNow / HEAD.every)
	local roll = Random.new(him.seed + window * 31)
	if roll:NextNumber() < HEAD.chance and serverNow - window * HEAD.every < HEAD.hold then
		return roll:NextNumber(-1.2, 1.2), roll:NextNumber(-0.3, 0.2), 16
	end
	local standing = him.speed < 0.6
	local reach = if standing or him.state == "search" then HEAD.look else HEAD.scan
	local yaw = math.sin(now * 0.45 + him.seed) * reach + math.sin(now * 1.7 + him.seed) * 0.06
	local pitch = if him.state == "search" then -0.08 else HEAD.down
	return yaw, pitch, 2.5
end

local function pose(him: Tracked, dt: number, now: number, serverNow: number)
	local torso = him.model:FindFirstChild("Torso") :: BasePart?
	local head = him.model:FindFirstChild("Head") :: BasePart?
	if torso == nil or head == nil then
		return
	end
	local state = him.state
	local w = math.clamp(him.speed / 6, 0, 1) -- how much he's walking
	local run = math.clamp((him.speed - GAIT.runFrom) / (GAIT.runTo - GAIT.runFrom), 0, 1)
	local standing = him.speed < 0.6
	local swing = math.sin(him.phase)
	local amp = lerp(GAIT.walk, GAIT.run, run) * w
	local heave = math.sin(now * 1.3) * (if standing then 0.06 else 0.025)

	-- The knife arm, by what he's doing; the stab overrides it.
	local stabLean = 0
	local armTarget
	if state == "chase" then
		armTarget = KNIFE_ARM.raised + math.abs(swing) * KNIFE_ARM.bob * run
	elseif state == "investigate" then
		armTarget = KNIFE_ARM.ready
	elseif state == "search" then
		armTarget = KNIFE_ARM.ready * 0.8 + math.sin(now * 1.1) * 0.12 -- held out, probing
	else
		armTarget = KNIFE_ARM.hang
	end
	if state == "kill" then
		him.armPitch, stabLean, him.wrist = stab(os.clock() - him.stateAt)
	else
		him.armPitch += (armTarget - him.armPitch) * math.min(1, dt * KNIFE_ARM.rate)
		local wristTarget = WRIST.low * (1 - math.clamp((him.armPitch - WRIST.from) / (WRIST.to - WRIST.from), 0, 1))
		him.wrist += (wristTarget - him.wrist) * math.min(1, dt * WRIST.rate)
	end
	set(him, "Wrist", CFrame.Angles(-him.wrist, 0, 0)) -- (the grip's X runs the other way to the arm's)

	local fold = (
		if state == "search" then HUNCH.search elseif standing then HUNCH.stand else lerp(HUNCH.walk, HUNCH.run, run)
	) + stabLean
	local bob = -math.abs(swing) * GAIT.bob * w - math.max(0, swing) * 0.05 * w -- (lower on the bad leg)
	local roll = swing * 0.06 * w + 0.04 -- swaying with the limp, leaning to the knife side
	set(him, "RootJoint", CFrame.new(0, bob, 0) * CFrame.Angles(-fold + heave * 0.5, 0, roll))
	set(him, "Left Hip", CFrame.Angles(fold + swing * amp, 0, 0))
	set(him, "Right Hip", CFrame.Angles(fold - swing * amp * GAIT.limp, 0, 0))
	-- The free arm hangs dead still walking; pumps when he runs.
	set(him, "Left Shoulder", CFrame.Angles(fold * 0.85 - swing * lerp(0.05, 0.95, run) * w + heave * 0.5, 0, -0.08))
	set(
		him,
		"Right Shoulder",
		CFrame.Angles(
			him.armPitch + (if state == "chase" or state == "kill" then 0 else fold * 0.85 + swing * 0.06 * w),
			0,
			if state == "chase" then 0.18 else 0.1
		)
	)

	-- The head.
	local yaw, pitch, rate = headAim(him, torso, head, now, serverNow)
	local follow = math.min(1, dt * rate)
	him.headYaw = lerp(him.headYaw, yaw, follow)
	him.headPitch = lerp(him.headPitch, pitch, follow)
	set(
		him,
		"Neck",
		CFrame.fromEulerAnglesYXZ(
			him.headPitch + fold * 0.5,
			him.headYaw,
			HEAD.tilt + math.sin(now * 0.3 + him.seed) * 0.08
		)
	)
end

local function step(dt: number)
	local me = Players.LocalPlayer
	local character = me.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local chased = false
	local serverNow = Workspace:GetServerTimeNow()
	for model, him in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			continue
		end
		-- His boots: a heavy step every stride, longer strides when he runs.
		local moved = (him.root.Position - him.last) * Vector3.new(1, 0, 1)
		him.last = him.root.Position
		him.travelled += moved.Magnitude
		him.phase += moved.Magnitude * GAIT.stride
		him.speed = lerp(him.speed, moved.Magnitude / math.max(dt, 1e-3), math.min(1, dt * 8))
		local stride = if him.speed > RUNNING then Knifer.STEP.run else Knifer.STEP.walk
		if him.travelled >= stride then
			him.travelled = 0
			Sound.play("KniferStep", { at = him.root, speed = random:NextNumber(0.9, 1.08) })
		end
		-- His breathing, heard now and then (the same breaths for everyone).
		local window = math.floor(serverNow / BREATH.every)
		if window ~= him.breath then
			him.breath = window
			if him.state ~= "chase" and Random.new(him.seed + window * 7):NextNumber() < BREATH.chance then
				Sound.play("Breath", { at = him.root, volume = 0.8, speed = 0.65 })
			end
		end
		him.poseClock += dt
		if him.poseClock >= 1 / POSE_FPS then
			pose(him, him.poseClock, serverNow, serverNow) -- (server time: his scan and breathing match on every screen)
			him.poseClock = 0
		end
		local target = model:GetAttribute("Target")
		local hunting = type(target) == "number" and target ~= 0
		local close = myRoot ~= nil and (myRoot.Position - him.root.Position).Magnitude < CHASE_NEAR
		if target == me.UserId or (hunting and close) then
			chased = true
		end
	end
	MusicController.setChase("knifer", chased)
end

-- He's come onto a street: everyone on it hears the sting, wherever he is (the only warning).
local function onCame(street: any)
	if Players.LocalPlayer:GetAttribute("Zone") == street then
		Sound.play("Stinger")
	end
end

local function onStruck(userId: any)
	local victim = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local character = victim and victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Sound.play("Thud", { at = root, volume = 0.8, speed = 1.2 })
		Sound.play("KniferKill", { at = root })
	end
end

function KniferController.Start()
	CollectionService:GetInstanceAddedSignal("Knifer"):Connect(function(model)
		task.spawn(add, model)
	end)
	for _, model in CollectionService:GetTagged("Knifer") do
		task.spawn(add, model)
	end
	Net.event("KniferCame").OnClientEvent:Connect(onCame)
	Net.event("KniferStruck").OnClientEvent:Connect(onStruck)
	RunService.Heartbeat:Connect(step)
end

return KniferController
