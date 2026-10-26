--!strict
-- Knocks a kid down as a ragdoll (the car, TrafficService): the joints at the neck, shoulders and
-- hips go loose (ball sockets with limits, so nothing bends the wrong way), the limbs get weight
-- and collide, and after a few seconds it all locks back and they get up. The thrown body is the
-- player's own physics, so their client does the throw and the falling over (RagdollController,
-- from the character's Ragdoll and RagdollPush attributes); everyone else sees it replicate.

local Players = game:GetService("Players")

local RagdollService = {}

-- How far each joint may swing (degrees): off the limb's line, and twisting round it.
local LIMITS: { [string]: { swing: number, twist: number } } = {
	Neck = { swing = 35, twist = 40 },
	["Left Shoulder"] = { swing = 100, twist = 70 },
	["Right Shoulder"] = { swing = 100, twist = 70 },
	["Left Hip"] = { swing = 70, twist = 30 },
	["Right Hip"] = { swing = 70, twist = 30 },
}

type Down = { character: Model, motors: { Motor6D }, limbs: { BasePart }, made: { Instance } }

local down: { [Player]: Down } = {}

function RagdollService.isDown(player: Player): boolean
	return down[player] ~= nil
end

-- A frame at the joint whose X axis runs down the limb (a ball socket's swing is measured off it).
local function along(motor: Motor6D): CFrame
	local toLimb = motor.C1:Inverse().Position -- the limb's middle, from the joint
	local axis = if toLimb.Magnitude > 1e-3 then toLimb.Unit else Vector3.new(0, -1, 0)
	local other = if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local side = axis:Cross(other).Unit
	return CFrame.fromMatrix(Vector3.zero, axis, side)
end

local function standUp(player: Player, state: Down)
	if down[player] ~= state then
		return
	end
	down[player] = nil
	for _, motor in state.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	for _, instance in state.made do
		instance:Destroy()
	end
	for _, limb in state.limbs do
		if limb.Parent then
			limb.CanCollide = false
			limb.Massless = true
		end
	end
	if state.character.Parent then
		state.character:SetAttribute("Ragdoll", false) -- their client gets them up
	end
end

-- Knocks `player` down for `seconds`, thrown with `push` (studs/s). False if they can't be.
function RagdollService.knock(player: Player, push: Vector3, seconds: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character == nil or root == nil or down[player] then
		return false
	end
	local state: Down = { character = character, motors = {}, limbs = {}, made = {} }
	local limbs: { BasePart } = {}
	for _, motor in character:GetDescendants() do
		if not motor:IsA("Motor6D") or motor.Name == "RootJoint" or not motor.Enabled then
			continue
		end
		local limb, body = motor.Part1, motor.Part0
		local limits = LIMITS[motor.Name] or { swing = 45, twist = 30 }
		if limb == nil or body == nil then
			continue
		end
		local frame = along(motor)
		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollJoint"
		a0.CFrame = motor.C0 * frame
		a0.Parent = body
		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollJoint"
		a1.CFrame = motor.C1 * frame
		a1.Parent = limb
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "RagdollSocket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = limits.swing
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -limits.twist
		socket.TwistUpperAngle = limits.twist
		socket.Parent = limb
		table.insert(state.made, a0)
		table.insert(state.made, a1)
		table.insert(state.made, socket)
		motor.Enabled = false
		table.insert(state.motors, motor)
		limb.Massless = false
		limb.CanCollide = true
		table.insert(limbs, limb)
	end
	-- Loose limbs mustn't fight the body (or each other) where they overlap.
	local function apart(a: BasePart, b: BasePart)
		local ignore = Instance.new("NoCollisionConstraint")
		ignore.Part0 = a
		ignore.Part1 = b
		ignore.Parent = a
		table.insert(state.made, ignore)
	end
	local torso = character:FindFirstChild("Torso")
	for i, limb in limbs do
		apart(limb, root)
		if torso and torso:IsA("BasePart") then
			apart(limb, torso)
		end
		for j = i + 1, #limbs do
			apart(limb, limbs[j])
		end
	end
	state.limbs = limbs
	for _, limb in limbs do
		pcall(limb.SetNetworkOwner, limb, player) -- their physics, like the rest of them
	end
	down[player] = state
	character:SetAttribute("RagdollPush", push)
	character:SetAttribute("Ragdoll", true) -- last: the joints are loose by the time their client hears
	task.delay(seconds, standUp, player, state)
	return true
end

function RagdollService.Start()
	Players.PlayerRemoving:Connect(function(player)
		down[player] = nil
	end)
	-- A new character (a costume swap, a respawn) is never left down.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			down[player] = nil
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			down[player] = nil
		end)
	end
end

return RagdollService
