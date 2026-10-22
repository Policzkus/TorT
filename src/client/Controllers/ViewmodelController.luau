--!strict
-- First-person view of the bucket you're carrying (bottom right of the screen), swaying as you
-- walk. It's a local copy of the bucket BucketService welds to your character (which first
-- person hides), with the candy pieces mirrored so you watch it fill up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local source: Model? = nil
local copy: Model? = nil
local copyParts: { [string]: BasePart } = {}
local sourceParts: { [string]: BasePart } = {}
local swayTime = 0

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
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
	swayTime += dt * (if moving then 8 else 1.5)
	local amount = if moving then 0.05 else 0.015
	local sway = CFrame.new(math.sin(swayTime) * amount, math.abs(math.cos(swayTime)) * amount, 0)
	local mount = (model:GetAttribute("Mount") :: string?) or "hand"
	model:PivotTo(camera.CFrame * (OFFSETS[mount] or OFFSETS.hand) * sway)
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
	RunService:BindToRenderStep("BucketViewmodel", Enum.RenderPriority.Camera.Value + 2, onRender)
end

return ViewmodelController
