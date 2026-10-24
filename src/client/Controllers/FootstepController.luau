--!strict
-- Footsteps you can hear: a step every stride on whatever is underfoot (porch boards, the dead
-- lawns, pavement), for you and everyone near you, the strides longer and the steps harder when
-- running; a thump when you land from a fall. Roblox's own plastic footstep loop is silenced.
-- Stride length follows the camera bob (CameraController), so the steps keep time with your view.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent.SoundController)

local FootstepController = {}

local STRIDE = 5.6 -- studs per step at walking speed 16; longer as you go faster (with sqrt of speed)
local HEAR = 70 -- other characters' steps farther than this aren't played
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
			local speed = (moved / math.max(dt, 1e-3)) / 16
			local stride = STRIDE * math.sqrt(math.max(speed, 0.5))
			if walker.travelled >= stride then
				walker.travelled = math.min(walker.travelled - stride, stride)
				local running = speed > 2
				Sound.play(name, {
					volume = (if running then 1.25 else 0.9) * (if mine then 1 else 1.4),
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

function FootstepController.Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.Heartbeat:Connect(step)
end

return FootstepController
