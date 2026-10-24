--!strict
-- Gates you own become passable for you only (local CanCollide), their prompt disappears and the
-- sign says UNLOCKED. The server still pushes anyone back who gets past a gate they don't own.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Celebrate = require(script.Parent.CelebrationController)
local Neighborhoods = require(ReplicatedStorage:WaitForChild("Shared").Config.Neighborhoods)
local StateController = require(script.Parent.StateController)

local GateController = {}

local function owned(neighborhoodId: any): boolean
	local list = StateController.get("neighborhoods")
	return type(neighborhoodId) == "string" and list ~= nil and list[neighborhoodId] == true
end

local function applyBarrier(barrier: Instance)
	if not barrier:IsA("BasePart") then
		return
	end
	local open = owned(barrier:GetAttribute("Neighborhood"))
	if barrier:GetAttribute("BaseTransparency") == nil then
		barrier:SetAttribute("BaseTransparency", barrier.Transparency)
	end
	barrier.CanCollide = not open
	barrier.Transparency = if open then 1 else barrier:GetAttribute("BaseTransparency") :: number
end

local function applyPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Enabled = not owned(prompt:GetAttribute("Neighborhood"))
	end
end

local function applyInfo(board: Instance)
	local id = board:GetAttribute("Neighborhood")
	if not board:IsA("BillboardGui") or not owned(id) then
		return
	end
	local neighborhood = Neighborhoods.byId[id :: string]
	local line1 = board:FindFirstChild("Line1") :: TextLabel?
	local line2 = board:FindFirstChild("Line2") :: TextLabel?
	local line3 = board:FindFirstChild("Line3") :: TextLabel?
	if line1 and neighborhood then
		line1.Text = string.upper(neighborhood.name) .. "  UNLOCKED"
	end
	if line2 then
		line2.Text = "UNLOCKED"
	end
	if line3 then
		line3.Visible = false
	end
end

local TAGS: { [string]: (Instance) -> () } = {
	GateBarrier = applyBarrier,
	GatePrompt = applyPrompt,
	GateInfo = applyInfo,
}

local function refreshAll()
	for tag, apply in TAGS do
		for _, instance in CollectionService:GetTagged(tag) do
			apply(instance)
		end
	end
end

function GateController.Start()
	for tag, apply in TAGS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(apply)
	end
	StateController.observe("neighborhoods", refreshAll)
	refreshAll()
	Celebrate.on("unlock", function()
		refreshAll()
	end)
end

return GateController
