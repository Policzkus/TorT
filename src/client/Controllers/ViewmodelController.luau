--!strict
-- First-person view of the bucket you're carrying (bottom right of the screen). It's a local copy of
-- the bucket BucketService welds to your character (which first person hides), with the candy pieces
-- mirrored so you watch it fill up.
-- It moves like it's in your hand (MovementController's gait): it swings in time with your steps,
-- trails a little behind when you turn and catches up, swings lower and harder when you run, comes
-- in close when you crouch, bounces when you land, and rises and falls with your breathing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(ReplicatedStorage:WaitForChild("Shared").Modules.Motion)
local MovementController = require(script.Parent.MovementController)

local ViewmodelController = {}

-- Where the bucket sits relative to the camera, per mount type.
local OFFSETS: { [string]: CFrame } = {
	hand = CFrame.new(1.05, -1.05, -2.1) * CFrame.Angles(0, math.rad(-12), 0),
	back = CFrame.new(1.6, -1.9, -2.6) * CFrame.Angles(0, math.rad(-25), 0),
	tow = CFrame.new(1.8, -2.8, -3.4) * CFrame.Angles(0, math.rad(-30), 0),
	float = CFrame.new(1.8, -2.4, -4.6) * CFrame.Angles(0, math.rad(-30), 0),
}
-- Big tiers are scaled down so they don't fill the screen.
local MAX_SIZE = 2.2
-- Its swing (studs and radians, in the view): `sway` side to side over two steps, `dip` down at each
-- footfall, `roll` with the sway. Running it's carried lower, further out and tipped (`carry`, `tip`).
local SWING = {
	walk = { sway = 0.045, dip = 0.04, roll = math.rad(2) },
	run = { sway = 0.08, dip = 0.09, roll = math.rad(4.5) },
}
local CARRY = Vector3.new(0.08, -0.22, 0.1) -- where it goes running (times how hard you run)
local TIP = math.rad(-9) -- pitched down running
local CLOSE = Vector3.new(-0.06, -0.1, 0.25) -- crouched: in close
local LAG = { per = 0.03, most = 0.18, frequency = 13, damping = 0.7 } -- trailing your turns: studs per radian/s
local LAND = { frequency = 12, damping = 0.5, drop = 1.2, jump = 0.5 } -- its bounce

local source: Model? = nil
local copy: Model? = nil
local copyParts: { [string]: BasePart } = {}
local sourceParts: { [string]: BasePart } = {}
-- Trailing your turns (x, y studs) and bouncing on landings (y): springs, with their speeds.
local lagX, lagXSpeed, lagY, lagYSpeed = 0, 0, 0, 0
local bounce, bounceSpeed = 0, 0
local lastLook: CFrame? = nil

local function clear()
	if copy then
		copy:Destroy()
	end
	copy, source = nil, nil
	table.clear(copyParts)
	table.clear(sourceParts)
end

local function build(bucket: Model)
	clear()
	source = bucket
	local clone = bucket:Clone()
	clone.Name = "ViewmodelBucket"
	local _, size = clone:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > MAX_SIZE then
		clone:ScaleTo(MAX_SIZE / biggest)
	end
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			copyParts[part.Name] = part
		elseif part:IsA("WeldConstraint") then
			part:Destroy()
		end
	end
	for _, part in bucket:GetDescendants() do
		if part:IsA("BasePart") then
			sourceParts[part.Name] = part
		end
	end
	clone.Parent = Workspace.CurrentCamera
	copy = clone
end

local function watchCharacter(character: Model)
	clear()
	local function check(child: Instance)
		if child.Name == "Bucket" and child:IsA("Model") then
			task.defer(build, child)
		end
	end
	character.ChildAdded:Connect(check)
	character.ChildRemoved:Connect(function(child)
		if child == source then
			clear()
		end
	end)
	for _, child in character:GetChildren() do
		check(child)
	end
end

local function onRender(dt: number)
	local model = copy
	local camera = Workspace.CurrentCamera
	if model == nil or camera == nil or model.PrimaryPart == nil then
		lastLook = nil
		return
	end
	local character = Players.LocalPlayer.Character
	if character and character:GetAttribute("Ragdoll") == true then
		-- Knocked down (RagdollController): your arms are flopping about, no bucket held up in view.
		model:PivotTo(camera.CFrame * CFrame.new(0, -500, 0))
		lastLook = nil
		return
	end
	-- How fast you're turning: it trails behind (turn left and it's left over to the right, look up
	-- and it's left below), then catches up. A jump in the view (a cut) isn't a turn.
	local look = camera.CFrame.Rotation
	local turnX, turnY = 0, 0
	if lastLook and dt > 0 then
		local pitch, yaw = (lastLook :: CFrame):ToObjectSpace(look):ToEulerAnglesYXZ()
		if math.abs(yaw) < 0.5 and math.abs(pitch) < 0.5 then
			turnX = math.clamp(yaw / dt * LAG.per, -LAG.most, LAG.most)
			turnY = math.clamp(-pitch / dt * LAG.per, -LAG.most, LAG.most)
		end
	end
	lastLook = look
	lagX, lagXSpeed = Motion.spring(lagX, lagXSpeed, turnX, LAG.frequency, LAG.damping, dt)
	lagY, lagYSpeed = Motion.spring(lagY, lagYSpeed, turnY, LAG.frequency, LAG.damping, dt)
	bounce, bounceSpeed = Motion.spring(bounce, bounceSpeed, 0, LAND.frequency, LAND.damping, dt)

	local gait = MovementController.gait()
	local run = gait.sprint
	local crouch = math.clamp(gait.crouch, 0, 1)
	local function swing(key: string): number
		local walk, running = (SWING.walk :: any)[key], (SWING.run :: any)[key]
		return walk + (running - walk) * run
	end
	local moving = gait.moving
	local side = math.sin(gait.phase)
	local footfall = Motion.footfall(gait.phase)
	local breath = math.sin(gait.breath) * (0.008 + 0.025 * gait.winded)
	local offset = Vector3.new(lagX, lagY, 0)
		+ Vector3.new(side * swing("sway") * moving, -footfall * swing("dip") * moving + breath + bounce, 0)
		+ CARRY * run
		+ CLOSE * crouch
	-- Still facing a little the way you were.
	local turn = CFrame.Angles(TIP * run + lagY * 0.6, -lagX * 0.8, -side * swing("roll") * moving)
	local mount = (model:GetAttribute("Mount") :: string?) or "hand"
	model:PivotTo(camera.CFrame * CFrame.new(offset) * (OFFSETS[mount] or OFFSETS.hand) * turn)
	-- Mirror the candy fill from the real bucket.
	for name, part in sourceParts do
		local mirror = copyParts[name]
		if mirror and string.sub(name, 1, 5) == "Candy" then
			mirror.Transparency = part.Transparency
		end
	end
end

function ViewmodelController.Start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	MovementController.landed:Connect(function(impact: number)
		bounceSpeed -= LAND.drop * (0.4 + impact)
	end)
	MovementController.jumped:Connect(function()
		bounceSpeed -= LAND.jump
	end)
	RunService:BindToRenderStep("BucketViewmodel", Enum.RenderPriority.Camera.Value + 2, onRender)
end

return ViewmodelController
