--!strict
-- Stiff PSX-style procedural animation for the game's own characters (Modules/CharacterRig): arms
-- and legs swing with speed, a little idle breathing and head sway, arms up while airborne. Poses
-- update at a low frame rate like a 1990s console game. Every client animates every rig itself.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CharacterRig = require(game:GetService("ReplicatedStorage").Shared.Modules.CharacterRig)

local CharacterAnimController = {}

local POSE_FPS = 14
local LEG_SWING = math.rad(34)
local ARM_SWING = math.rad(26)
local STRIDE = 0.62 -- swing radians per stud travelled
local FULL_SPEED = 12 -- studs/s at which the swing reaches full size

type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	joints: { [string]: Motor6D },
	phase: number,
	weight: number,
	clock: number,
	seed: number,
}

local rigs: { [Model]: Rig } = {}

local function add(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	if root == nil or humanoid == nil or model.Parent == nil then
		return
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
	}
end

local function set(rig: Rig, name: string, value: CFrame)
	local motor = rig.joints[name]
	if motor then
		motor.Transform = value
	end
end

local function step(dt: number)
	local now = os.clock()
	for model, rig in rigs do
		if model.Parent == nil then
			rigs[model] = nil
			continue
		end
		local velocity = rig.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local airborne = rig.humanoid.FloorMaterial == Enum.Material.Air
		local dead = rig.humanoid.Health <= 0
		local target = if airborne or dead then 0 else math.clamp(speed / FULL_SPEED, 0, 1)
		rig.weight += (target - rig.weight) * math.min(1, dt * 10)
		rig.phase += speed * dt * STRIDE
		rig.clock += dt
		if rig.clock < 1 / POSE_FPS then
			continue -- hold the last pose: choppy on purpose
		end
		rig.clock = 0

		local swing = math.sin(rig.phase)
		local w = rig.weight
		local t = now + rig.seed
		local breathe = math.sin(t * 1.6) * 0.035 * (1 - w)
		local air = if airborne and not dead then 1 else 0
		set(rig, "Left Hip", CFrame.Angles(swing * LEG_SWING * w + air * 0.35, 0, 0))
		set(rig, "Right Hip", CFrame.Angles(-swing * LEG_SWING * w - air * 0.1, 0, 0))
		set(rig, "Left Shoulder", CFrame.Angles(-swing * ARM_SWING * w + breathe + air * 1.1, 0, -0.06 - air * 0.3))
		set(rig, "Right Shoulder", CFrame.Angles(swing * ARM_SWING * w + breathe + air * 1.1, 0, 0.06 + air * 0.3))
		-- A slow, slightly wrong head sway, plus a bounce with each step.
		local tilt = math.sin(t * 0.37) * 0.07 + math.sin(t * 1.9) * 0.015
		set(rig, "Neck", CFrame.Angles(math.sin(t * 0.53) * 0.04, math.sin(t * 0.29) * 0.12, tilt))
		set(rig, "RootJoint", CFrame.new(0, math.abs(swing) * 0.12 * w, 0) * CFrame.Angles(breathe * 0.5, 0, 0))
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
