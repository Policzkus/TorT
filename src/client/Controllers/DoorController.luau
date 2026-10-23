--!strict
-- Client side of doors: knock sound, and a 💤 countdown over houses you've already visited
-- (only you see it). Doors stream in and out, so state is kept by house id and reapplied.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Houses = require(ReplicatedStorage:WaitForChild("Shared").Modules.Houses)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Sound = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local DoorController = {}

local doors: { [string]: BasePart } = {}
local readyAt: { [string]: number } = {}
local badges: { [string]: BillboardGui } = {}

local function promptOf(door: BasePart): ProximityPrompt?
	return door:FindFirstChildOfClass("ProximityPrompt")
end

local function setBadge(houseId: string, door: BasePart?, secondsLeft: number?)
	local badge = badges[houseId]
	if secondsLeft == nil or door == nil then
		if badge then
			badge:Destroy()
			badges[houseId] = nil
		end
		return
	end
	if badge == nil or badge.Parent ~= door then
		if badge then
			badge:Destroy()
		end
		badge = create("BillboardGui", {
			Name = "Cooldown",
			Size = UDim2.fromOffset(110, 46),
			StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0),
			MaxDistance = 90,
			LightInfluence = 0,
			Adornee = door,
			create("TextLabel", {
				Name = "Text",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Heading,
				TextColor3 = Theme.Colors.TextDim,
				TextScaled = true,
				create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
			}),
			Parent = door,
		})
		badges[houseId] = badge
	end
	local text = (badge :: BillboardGui):FindFirstChild("Text") :: TextLabel
	text.Text = `💤 {math.ceil(secondsLeft :: number)}s`
end

-- Lights-off and bowl houses never answer the door.
local function answers(door: BasePart): boolean
	local model = Houses.of(door)
	local houseType = model and model:GetAttribute("HouseType")
	return houseType ~= "LightsOff" and houseType ~= "Bowl"
end

local function apply(houseId: string)
	local door = doors[houseId]
	local left = (readyAt[houseId] or 0) - Workspace:GetServerTimeNow()
	local onCooldown = left > 0
	if door then
		local prompt = promptOf(door)
		if prompt then
			prompt.Enabled = not onCooldown and answers(door)
		end
	end
	setBadge(houseId, door, if onCooldown then left else nil)
	if not onCooldown then
		readyAt[houseId] = nil
	end
end

local function track(door: Instance)
	local houseId = door:GetAttribute("HouseId")
	if type(houseId) == "string" and door:IsA("BasePart") then
		doors[houseId] = door
		local model = Houses.of(door)
		if model then
			model:GetAttributeChangedSignal("HouseType"):Connect(function()
				apply(houseId)
			end)
		end
		apply(houseId)
	end
end

local function untrack(door: Instance)
	local houseId = door:GetAttribute("HouseId")
	if type(houseId) == "string" and doors[houseId] == door then
		doors[houseId] = nil
		setBadge(houseId, nil, nil)
	end
end

function DoorController.getDoor(houseId: string): BasePart?
	return doors[houseId]
end

function DoorController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Door"):Connect(untrack)
	for _, door in CollectionService:GetTagged("Door") do
		track(door)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "Door") then
			Sound.play("Knock")
		end
	end)

	Net.event("DoorResult").OnClientEvent:Connect(function(result: any)
		readyAt[result.houseId] = result.cooldownUntil
		apply(result.houseId)
	end)
	-- Dawn: every door is ready again.
	Net.event("CooldownsReset").OnClientEvent:Connect(function()
		local ids = {}
		for houseId in readyAt do
			table.insert(ids, houseId)
		end
		table.clear(readyAt)
		for _, houseId in ids do
			apply(houseId)
		end
	end)

	while true do
		task.wait(0.5)
		for houseId in readyAt do
			apply(houseId)
		end
	end
end

return DoorController
