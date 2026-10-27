--!strict
-- Stiff PSX-style procedural animation for the game's own characters (Modules/CharacterRig): arms
-- and legs swing with speed, a little idle breathing and head sway, arms up while airborne. Poses
-- update at a low frame rate like a 1990s console game. Every client animates every rig itself.
-- Heads look up and down where their players do: each client tells the server how far up or down
-- it's looking (LookPitch), and the server puts it on the character for everyone else. A kid who
-- faints (Fainted, HealthService) drops flat on their back where they stood, for everyone to see.
-- Sat down (a party bus seat), they sit: legs out in front, leaning back a touch, hands in the lap,
-- raised so they sit on the seat rather than in it (a seat holds the middle of the body at its top:
-- each build is lifted until its thighs rest on it and nothing of the body is under it). The bucket
-- they carry is put away while they sit (worn on the back, it went through the seat back).
-- Knocked down (Ragdoll, RagdollService) the joints are left to physics.
-- Crouched (Crouching, from their client through CharacterService; your own straight away), they
-- go down on their haunches: hips low, both legs out in front (the angle that keeps the feet on the
-- ground), hunched over with the head up to look ahead, hands by the knees; creeping, they shuffle,
-- bobbing a little with each step. Running they lean into it, arms and legs pumping harder. In the
-- air one leg's drawn up and the other trails, the arms out a little for balance.
-- With a flashlight on (FlashlightOn on their player) they hold it up in their left hand, the arm
-- out in front along where they look, up and down with it (FlashlightController puts the torch in
-- the hand and the beam along the arm); the bucket stays in the right.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CharacterRig = require(game:GetService("ReplicatedStorage").Shared.Modules.CharacterRig)
local Net = require(game:GetService("ReplicatedStorage").Shared.Modules.Net)
local MovementController = require(script.Parent.MovementController)

local CharacterAnimController = {}

local POSE_FPS = 14
local LEG_SWING = math.rad(34)
local ARM_SWING = math.rad(26)
local STRIDE = 0.62 -- swing radians per stud travelled
local FULL_SPEED = 12 -- studs/s at which the swing reaches full size
local LOOK = { every = 0.12, change = 0.05, head = 0.75 } -- send your look this often if it moved this far; the head takes this share
local SIT = { legs = 1.5, splay = 0.08, arms = 0.55, lean = 0.08 } -- radians: legs forward, apart, arms forward, back
-- Crouched: on their haunches, the hips `hips` of their height lower and both legs out in front at
-- the angle that keeps the feet on the ground, `splay` apart; hunched `lean` radians forward, the
-- head tipped back up `head` of that to look ahead; the arms `arms` further forward, to the knees,
-- `tuck`ed in. Creeping they shuffle: the legs `step` radians either way, the body rising `bob` of
-- their hip height with each step, the arms swinging `armSwing` of the legs.
local CROUCH = {
	hips = 0.5,
	splay = 0.14,
	lean = 0.5,
	head = 0.85,
	arms = 0.6,
	tuck = 0.18,
	step = 0.3,
	bob = 0.08,
	armSwing = 0.6,
}
-- Running (from `from` to `full` studs/s): leaning `lean` radians into it, swinging `swing` times as far.
local RUN = { from = 15, full = 25, lean = 0.2, swing = 1.35 }
-- In the air: the near leg drawn up, the other trailing (`legs`), the arms `arms` forward and `out`.
local AIR = { legs = { 0.55, -0.2 }, arms = 0.45, out = 0.35 }
-- Reaching out to grab someone (Reaching: a homeowner after a bowl thief, OwnerChaseService): both
-- arms `arms` radians up in front, `splay` apart, swinging only `swing` of the usual.
local REACH = { arms = 1.45, splay = 0.12, swing = 0.3 }
-- Holding a flashlight up: the left arm `raise` radians up in front, following `follow` of where
-- they look up or down, turned `inward` toward the middle, swinging only `swing` of the usual.
local TORCH = { raise = 1.45, follow = 0.9, inward = 0.14, swing = 0.15 }

type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	joints: { [string]: Motor6D },
	phase: number,
	weight: number,
	clock: number,
	seed: number,
	pitch: number, -- how far up (or down) its head is tilted, easing toward LookPitch
	faint: number, -- 0..1 how far they've dropped
	sit: number, -- 0..1 how sat down they are
	crouch: number, -- 0..1 how crouched
	run: number, -- 0..1 how hard they're running
	reach: number, -- 0..1 how far their arms are out to grab
	torch: number, -- 0..1 how far up they're holding a flashlight
	player: Player?, -- whose (found once it's theirs)
	lift: number?, -- studs this build is raised sitting down (worked out once)
	bucketHidden: boolean, -- put away while they sit
}

local rigs: { [Model]: Rig } = {}

local function add(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	if root == nil or humanoid == nil or model.Parent == nil or model:GetAttribute("OwnAnimator") == true then
		return -- (the Knifer has his own: KniferController)
	end
	local joints: { [string]: Motor6D } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			joints[descendant.Name] = descendant
		end
	end
	rigs[model] = {
		model = model,
		root = root,
		humanoid = humanoid,
		joints = joints,
		phase = 0,
		weight = 0,
		clock = 0,
		seed = math.random() * 100,
		pitch = 0,
		faint = 0,
		sit = 0,
		crouch = 0,
		run = 0,
		reach = 0,
		torch = 0,
		player = Players:GetPlayerFromCharacter(model),
		bucketHidden = false,
	}
end

-- How far up a build has to come, sat down, to be on the seat and not in it: its hips high enough
-- for the legs (out in front) to rest on the seat's top, and the bottom of its body (a ghost sheet
-- goes down past the hips) no lower than that. The seat holds the root's middle at its top.
local function sitLift(rig: Rig): number
	if rig.lift then
		return rig.lift :: number
	end
	local rootJoint, hip = rig.joints.RootJoint, rig.joints["Right Hip"]
	local torso = hip and hip.Part0
	local leg = hip and hip.Part1
	if rootJoint == nil or hip == nil or torso == nil or leg == nil then
		rig.lift = 0
		return 0
	end
	local body = rootJoint.C0 * rootJoint.C1:Inverse() -- the torso, in the root's space, at rest
	local hipHeight = (body * hip.C0).Position.Y
	local lowest = math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				lowest = math.min(lowest, (body * (Vector3.new(x, y, z) * torso.Size / 2)).Y)
			end
		end
	end
	local lift = math.max(leg.Size.Z / 2 - hipHeight, -lowest)
	rig.lift = lift
	return lift
end

local function set(rig: Rig, name: string, value: CFrame)
	local motor = rig.joints[name]
	if motor then
		motor.Transform = value
	end
end

local sentPitch = 0
local sentAt = 0

-- Tells the server how far up or down you're looking, when it's moved enough (a few times a second).
local function sendLook()
	local camera = Workspace.CurrentCamera
	if camera == nil or os.clock() - sentAt < LOOK.every then
		return
	end
	local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
	if math.abs(pitch - sentPitch) >= LOOK.change then
		sentPitch, sentAt = pitch, os.clock()
		Net.event("LookPitch"):FireServer(pitch)
	end
end

local function step(dt: number)
	sendLook()
	local now = os.clock()
	for model, rig in rigs do
		if model.Parent == nil then
			rigs[model] = nil
			continue
		end
		if model:GetAttribute("Ragdoll") == true then
			-- Knocked down (RagdollService): the loose joints are physics now; the body hangs off the
			-- root as it is, no bob or breathing on it.
			for _, motor in rig.joints do
				motor.Transform = CFrame.identity
			end
			continue
		end
		local velocity = rig.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local airborne = rig.humanoid.FloorMaterial == Enum.Material.Air
		local dead = rig.humanoid.Health <= 0
		local target = if airborne or dead then 0 else math.clamp(speed / FULL_SPEED, 0, 1)
		rig.weight += (target - rig.weight) * math.min(1, dt * 10)
		rig.phase += speed * dt * STRIDE
		local look = (model:GetAttribute("LookPitch") :: number?) or 0
		rig.pitch += (look - rig.pitch) * math.min(1, dt * 8)
		local fainted = if model:GetAttribute("Fainted") == true then 1 else 0
		rig.faint += (fainted - rig.faint) * math.min(1, dt * 7)
		local sitting = if rig.humanoid.Sit and rig.humanoid.SeatPart ~= nil then 1 else 0
		rig.sit += (sitting - rig.sit) * math.min(1, dt * 10)
		local crouching = model:GetAttribute("Crouching") == true
			or (model == Players.LocalPlayer.Character and MovementController.isCrouching())
		rig.crouch += ((if crouching and not dead then 1 else 0) - rig.crouch) * math.min(1, dt * 12)
		local running = math.clamp((speed - RUN.from) / (RUN.full - RUN.from), 0, 1) * (1 - rig.crouch)
		rig.run += ((if airborne then rig.run else running) - rig.run) * math.min(1, dt * 6)
		local reaching = if model:GetAttribute("Reaching") == true then 1 else 0
		rig.reach += (reaching - rig.reach) * math.min(1, dt * 8)
		if rig.player == nil then
			rig.player = Players:GetPlayerFromCharacter(model)
		end
		local owner = rig.player
		local holding = if owner and owner:GetAttribute("FlashlightOn") == true and not dead then 1 else 0
		rig.torch += (holding - rig.torch) * math.min(1, dt * 9)
		if (sitting == 1) ~= rig.bucketHidden then
			local bucket = model:FindFirstChild("Bucket")
			if bucket then
				rig.bucketHidden = sitting == 1
				for _, part in bucket:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = if rig.bucketHidden then 1 else 0
					end
				end
			end
		end
		rig.clock += dt
		if rig.clock < 1 / POSE_FPS then
			continue -- hold the last pose: choppy on purpose
		end
		rig.clock = 0

		local w = rig.weight
		local c = rig.crouch
		local stride = math.sin(rig.phase)
		-- Stood up, the stride (harder running); crouched, a shuffle instead.
		local swing = stride * (1 + (RUN.swing - 1) * rig.run) * (1 - c)
		local shuffle = stride * CROUCH.step * c * w
		local t = now + rig.seed
		local breathe = math.sin(t * 1.6) * 0.035 * (1 - w)
		local air = if airborne and not dead then 1 else 0
		-- Leaning over (crouched, running): the legs are turned back to the ground (they hang off the
		-- body); crouched, the hips go down and both legs reach out in front to the ground.
		local lean = -(CROUCH.lean * c + RUN.lean * rig.run)
		local hips = rig.humanoid.HipHeight
		local drop = hips * CROUCH.hips * c
		local squat = if hips > 0 then math.acos(math.clamp(1 - drop / hips, -1, 1)) else 0
		set(
			rig,
			"Left Hip",
			CFrame.Angles(swing * LEG_SWING * w + shuffle + squat - lean + air * AIR.legs[1], 0, -CROUCH.splay * c)
		)
		set(
			rig,
			"Right Hip",
			CFrame.Angles(-swing * LEG_SWING * w - shuffle + squat - lean + air * AIR.legs[2], 0, CROUCH.splay * c)
		)
		local r = rig.reach
		local arms = CROUCH.arms * c + REACH.arms * r + AIR.arms * air
		local armSwing = (swing * ARM_SWING * w + shuffle * CROUCH.armSwing) * (1 - (1 - REACH.swing) * r)
		local out = 0.06 + AIR.out * air - CROUCH.tuck * c + REACH.splay * r
		set(rig, "Left Shoulder", CFrame.Angles(-armSwing + breathe + arms, 0, -out))
		set(rig, "Right Shoulder", CFrame.Angles(armSwing + breathe + arms, 0, out))
		-- A slow, slightly wrong head sway, plus a bounce with each step.
		local tilt = math.sin(t * 0.37) * 0.07 + math.sin(t * 1.9) * 0.015
		set(
			rig,
			"Neck",
			CFrame.Angles(
				math.sin(t * 0.53) * 0.04 + rig.pitch * LOOK.head - lean * CROUCH.head,
				math.sin(t * 0.29) * 0.12,
				tilt
			)
		)
		-- A bounce with each step: stood up, and (rising off their haunches) crouched.
		local bounce = math.abs(swing) * 0.12 * w + math.abs(stride) * CROUCH.bob * hips * c * w
		set(rig, "RootJoint", CFrame.new(0, bounce - drop, 0) * CFrame.Angles(breathe * 0.5 + lean, 0, 0))
		if rig.sit > 0.01 then
			local s = rig.sit
			set(rig, "Left Hip", CFrame.Angles(SIT.legs * s, 0, -SIT.splay * s))
			set(rig, "Right Hip", CFrame.Angles(SIT.legs * s, 0, SIT.splay * s))
			set(rig, "Left Shoulder", CFrame.Angles(SIT.arms * s + breathe, 0, -0.1 * s))
			set(rig, "Right Shoulder", CFrame.Angles(SIT.arms * s + breathe, 0, 0.1 * s))
			set(
				rig,
				"RootJoint",
				CFrame.new(0, sitLift(rig) * s, 0) * CFrame.Angles(SIT.lean * s + breathe * 0.5, 0, 0)
			)
		end
		if rig.torch > 0.01 then
			-- The flashlight held up in front, along where they look (the body's lean taken out of it).
			local h = rig.torch
			local hanging = -armSwing + breathe + arms + SIT.arms * rig.sit
			local up = TORCH.raise + rig.pitch * TORCH.follow - lean - armSwing * TORCH.swing + breathe
			set(rig, "Left Shoulder", CFrame.Angles(hanging + (up - hanging) * h, 0, -out + (TORCH.inward + out) * h))
		end
		if rig.faint > 0.01 then
			-- Down on their back, arms and legs splayed (from the hips: the body tips over them).
			local f = rig.faint
			set(
				rig,
				"RootJoint",
				CFrame.new(0, -rig.humanoid.HipHeight * 0.9 * f, 0) * CFrame.Angles(1.45 * f, 0, 0.15 * f)
			)
			set(rig, "Left Hip", CFrame.Angles(0.15 * f, 0, -0.25 * f))
			set(rig, "Right Hip", CFrame.Angles(0.25 * f, 0, 0.3 * f))
			set(rig, "Left Shoulder", CFrame.Angles(0.4 * f, 0, -0.9 * f))
			set(rig, "Right Shoulder", CFrame.Angles(0.2 * f, 0, 1.1 * f))
			set(rig, "Neck", CFrame.Angles(-0.2 * f, 0.5 * f, 0))
		end
	end
end

function CharacterAnimController.Start()
	CollectionService:GetInstanceAddedSignal(CharacterRig.TAG):Connect(function(model)
		task.spawn(add, model)
	end)
	CollectionService:GetInstanceRemovedSignal(CharacterRig.TAG):Connect(function(model)
		rigs[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(CharacterRig.TAG) do
		task.spawn(add, model)
	end
	RunService.PreSimulation:Connect(step)
end

return CharacterAnimController
