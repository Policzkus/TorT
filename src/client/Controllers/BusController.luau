--!strict
-- The Spooky School Bus destination picker. Opens from any bus or bus stop prompt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Neighborhoods = require(Shared.Config.Neighborhoods)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local StateController = require(script.Parent.StateController)
local TransitionController = require(script.Parent.TransitionController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local BusController = {}

local panel: Panel.Panel
local list: ScrollingFrame
local traveling = false

type Destination = { id: string, name: string, emoji: string, neighborhood: Neighborhoods.Neighborhood? }

local function destinations(): { Destination }
	local result: { Destination } = { { id = "Hub", name = "Home Street", emoji = "🏠", neighborhood = nil } }
	for _, neighborhood in Neighborhoods.list do
		table.insert(
			result,
			{ id = neighborhood.id, name = neighborhood.name, emoji = "🏘", neighborhood = neighborhood }
		)
	end
	return result
end

local function travel(destinationId: string)
	if traveling then
		return
	end
	traveling = true
	panel:close()
	TransitionController.fadeOut(0.3)
	local arrived = false
	local connection = Net.event("Teleported").OnClientEvent:Once(function()
		arrived = true
	end)
	Net.event("BusTravel"):FireServer(destinationId)
	local deadline = os.clock() + 4
	while not arrived and os.clock() < deadline do
		task.wait()
	end
	connection:Disconnect()
	task.wait(0.15)
	TransitionController.fadeIn(0.4)
	traveling = false
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local owned = StateController.get("neighborhoods") or {}
	local here = Players.LocalPlayer:GetAttribute("Zone")
	for index, destination in destinations() do
		local neighborhood = destination.neighborhood
		local unlocked = neighborhood == nil or owned[destination.id] == true
		local status: string
		if neighborhood and not neighborhood.enabled then
			status = "🚧 Coming soon"
		elseif not unlocked and neighborhood then
			local needs = if neighborhood.unlock.rebirths > 0 then ` + Rebirth {neighborhood.unlock.rebirths}` else ""
			status = `🔒 Unlock at its gate: {Format.number(neighborhood.unlock.price)} 🍬{needs}`
		elseif here == destination.id then
			status = "📍 You are here"
		else
			status = if neighborhood
				then `Tier {neighborhood.tier} • {neighborhood.candy.min}-{neighborhood.candy.max} 🍬 per door`
				else "Shop, bus and the big Candy Box"
		end
		local row = create("Frame", {
			Name = destination.id,
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, 64),
			BackgroundColor3 = if unlocked then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
			create("UICorner", { CornerRadius = Theme.Corner }),
			create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
			create("TextLabel", {
				Name = "Name",
				Position = UDim2.fromOffset(14, 6),
				Size = UDim2.new(1, -150, 0, 30),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Heading,
				Text = `{destination.emoji} {destination.name}`,
				TextColor3 = if unlocked then Theme.Colors.Text else Theme.Colors.TextDim,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
				create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
			}),
			create("TextLabel", {
				Name = "Status",
				Position = UDim2.fromOffset(14, 36),
				Size = UDim2.new(1, -150, 0, 20),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Body,
				Text = status,
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Parent = list,
		})
		local canGo = unlocked and (neighborhood == nil or neighborhood.enabled) and here ~= destination.id
		if canGo then
			Button.new({
				name = "Go",
				text = "GO 🚌",
				size = UDim2.fromOffset(112, 44),
				position = UDim2.new(1, -12, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				color = Theme.Colors.Slime,
				textSize = 22,
				parent = row,
				onClick = function()
					travel(destination.id)
				end,
			})
		end
	end
end

function BusController.open()
	render()
	panel:open()
end

function BusController.Start()
	panel = Panel.new({ name = "BusPanel", title = "🚌 Spooky School Bus", size = Vector2.new(560, 470) })
	list = create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
		Parent = panel.content,
	})
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "BusStop") then
			BusController.open()
		end
	end)
	StateController.observe("neighborhoods", function()
		if panel:isOpen() then
			render()
		end
	end)
end

return BusController
