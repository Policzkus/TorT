--!strict
-- Puts the player's current bucket tier on their character (everyone sees it) and fills it with
-- candy pieces as the bucket fills (PROMPT §3.8).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local MeshLibrary = require(ReplicatedStorage.Shared.Modules.MeshLibrary)
local Buckets = require(ReplicatedStorage.Shared.Models.Buckets)
local DataService = require(script.Parent.DataService)

local BucketService = {}

type Equipped = { model: Model, tier: number }
local equipped: { [Player]: Equipped } = {}

local function mountFrame(character: Model, mount: string): (BasePart?, CFrame?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		return nil, nil
	end
	if mount == "hand" then
		local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
		if hand == nil then
			return nil, nil
		end
		local bottom = hand.Position - root.CFrame.UpVector * (hand.Size.Y / 2)
		return hand, root.CFrame.Rotation + bottom
	elseif mount == "back" then
		local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
		if torso == nil then
			return nil, nil
		end
		return torso, torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2)
	end
	-- tow / float: on the ground behind the character.
	local ground = root.Size.Y / 2 + humanoid.HipHeight
	return root, root.CFrame * CFrame.new(0, -ground, 1.2)
end

local function detach(player: Player)
	local current = equipped[player]
	equipped[player] = nil
	if current then
		current.model:Destroy()
	end
end

local function updateFill(player: Player)
	local current = equipped[player]
	local data = DataService.get(player)
	if current and data then
		local capacity = Formulas.bucketCapacity(data.upgrades.bucketTier)
		Buckets.setFill(current.model, if capacity > 0 then data.bucket / capacity else 0)
	end
end

local function attach(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	if data == nil or character == nil then
		return
	end
	MeshLibrary.waitReady(8, "World")
	local tier = data.upgrades.bucketTier
	local current = equipped[player]
	if current and current.tier == tier and current.model.Parent == character then
		return
	end
	detach(player)
	local model = Buckets.build(Formulas.bucketTier(tier).model)
	model.Name = "Bucket" -- swapped-in assets keep their own name otherwise
	local mount = model:GetAttribute("Mount") :: string
	local anchor, frame = mountFrame(character, mount)
	if anchor == nil or frame == nil then
		model:Destroy()
		return
	end
	model:PivotTo(frame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Parent = character
	equipped[player] = { model = model, tier = tier }
	updateFill(player)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		detach(player)
		-- Wait for the rig so the hand/torso exist and the pose is the default one.
		character:WaitForChild("HumanoidRootPart", 10)
		character:WaitForChild("Humanoid", 10)
		task.wait(0.2)
		if player.Character == character then
			attach(player)
		end
	end)
	if player.Character then
		attach(player)
	end
end

function BucketService.Init()
	MeshLibrary.preload()
end

function BucketService.Start()
	DataService.Loaded:Connect(watch)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			watch(player)
		end
	end
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "upgrades" then
			attach(player)
		elseif key == "bucket" then
			updateFill(player)
		end
	end)
	Players.PlayerRemoving:Connect(detach)
end

return BucketService
