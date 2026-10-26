--!strict
-- Footsteps you can hear: a step every stride on whatever is underfoot (porch boards, the dead
-- lawns, pavement), for you and everyone near you, the strides longer and the steps harder when
-- running, soft when creeping (crouched); a thump when you land from a fall. Roblox's own plastic
-- footstep loop is silenced.
-- Your own steps come from your gait (MovementController.footfall), each one as the view dips
-- (CameraController), so what you hear keeps time with what you see, and a jump pushes off with one.
-- Everyone else's go by the ground they cover, with the same stride (Modules/Motion).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(ReplicatedStorage:WaitForChild("Shared").Modules.Motion)
local MovementController = require(script.Parent.MovementController)
local Sound = require(script.Parent.SoundController)

local FootstepController = {}

local HEAR = 70 -- other characters' steps farther than this aren't played
local OTHERS = { walk = 1.26, run = 1.75, creep = 0.5, running = 1.3 } -- their steps' loudness (3D, so louder); `running` above 1.3 walking speeds
local LAND_SPEED = 14 -- studs a second of falling before landing makes a sound

local M = Enum.Material
local STEP: { [Enum.Material]: string } = {
	[M.Wood] = "StepWood",
	[M.WoodPlanks] = "StepWood",
	-- The houses' invisible colliders (porches, steps, stoops) are plastic: mostly boards underneath.
	[M.SmoothPlastic] = "StepWood",
	[M.Plastic] = "StepWood",
	[M.Grass] = "StepGrass",
	[M.LeafyGrass] = "StepGrass",
	[M.Ground] = "StepGrass",
	[M.Mud] = "StepGrass",
	[M.Sand] = "StepDirt",
	[M.Pebble] = "StepDirt",
	[M.Snow] = "StepDirt",
	[M.Fabric] = "StepCarpet",
	[M.Carpet] = "StepCarpet",
}
local SOFT: { [string]: boolean } = { StepGrass = true, StepDirt = true, StepCarpet = true }

type Walker = { travelled: number, last: Vector3?, airborne: boolean, fall: number }
local walkers: { [Model]: Walker } = {}
local underfoot: Enum.Material = M.Concrete -- what your feet were last on (a jump pushes off it)

-- RbxCharacterSounds plays a plastic "Running" loop and its own "Landing"; ours replace them.
local function silence(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil then
		return
	end
	local function mute(child: Instance)
		if child:IsA("Sound") and (child.Name == "Running" or child.Name == "Landing") then
			child.Volume = 0
			child:GetPropertyChangedSignal("Volume"):Connect(function()
				if child.Volume ~= 0 then
					child.Volume = 0
				end
			end)
		end
	end
	for _, child in root:GetChildren() do
		mute(child)
	end
	root.ChildAdded:Connect(mute)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(silence)
	if player.Character then
		task.spawn(silence, player.Character)
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local me = Players.LocalPlayer.Character
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character == nil or humanoid == nil or root == nil or humanoid.Health <= 0 then
			continue
		end
		local mine = character == me
		if not mine and (root.Position - camera.CFrame.Position).Magnitude > HEAR then
			continue
		end
		seen[character] = true
		local walker = walkers[character]
		if walker == nil then
			walker = { travelled = 0, last = nil, airborne = false, fall = 0 }
			walkers[character] = walker
		end
		local position = root.Position
		local grounded = humanoid.FloorMaterial ~= M.Air
		local name = STEP[humanoid.FloorMaterial] or "StepConcrete"
		local at = if mine then nil else root
		if mine and grounded then
			underfoot = humanoid.FloorMaterial
		end
		if grounded then
			if walker.airborne and walker.fall > LAND_SPEED then
				Sound.play(if SOFT[name] then "LandSoft" else "LandWood", {
					volume = math.clamp(walker.fall / 50, 0.35, 1),
					speed = 0.95 + math.random() * 0.1,
					at = at,
				})
				walker.travelled = 0
			end
			walker.fall = 0
			local last = walker.last
			local moved = if last then ((position - last) * Vector3.new(1, 0, 1)).Magnitude else 0
			if moved < 8 then -- more than that in a frame is a teleport, not a walk
				walker.travelled += moved
			end
			local speed = moved / math.max(dt, 1e-3)
			local creeping = character:GetAttribute("Crouching") == true
			local stride = Motion.stride(speed, if creeping then 1 else 0)
			-- Your own steps come from your gait (onFootfall).
			if not mine and walker.travelled >= stride then
				walker.travelled = math.min(walker.travelled - stride, stride)
				Sound.play(name, {
					volume = if creeping
						then OTHERS.creep
						elseif speed > 16 * OTHERS.running then OTHERS.run
						else OTHERS.walk,
					speed = 0.9 + math.random() * 0.2,
					at = at,
				})
			end
		else
			walker.fall = math.max(walker.fall, -root.AssemblyLinearVelocity.Y)
		end
		walker.airborne = not grounded
		walker.last = position
	end
	for character in walkers do
		if not seen[character] then
			walkers[character] = nil
		end
	end
end

-- One of your own feet landed (MovementController's gait): `loudness` from a creep to a run.
local function onFootfall(loudness: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.FloorMaterial == M.Air or humanoid.Health <= 0 then
		return
	end
	Sound.play(STEP[humanoid.FloorMaterial] or "StepConcrete", {
		volume = loudness,
		speed = 0.9 + math.random() * 0.2,
	})
end

function FootstepController.Start()
	MovementController.footfall:Connect(onFootfall)
	MovementController.jumped:Connect(function()
		Sound.play(STEP[underfoot] or "StepConcrete", { volume = 1.1, speed = 0.85 + math.random() * 0.1 }) -- pushing off
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.Heartbeat:Connect(step)
end

return FootstepController
