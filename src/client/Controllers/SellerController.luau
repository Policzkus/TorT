--!strict
-- The seller's window (Config/Items; his stall: HouseService; ItemService sells): his crate's prompt
-- opens it. A line from him at the top, then a row a thing: what it is and does, how many you've got
-- of how many you can carry, and its price on this street in banked candy. Walk off
-- (Items.SELLER.RANGE) and it closes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local NotificationController = require(script.Parent.NotificationController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local SellerController = {}

type Row = { owned: TextLabel, buy: TextButton }

local panel: Panel.Panel
local line: TextLabel
local rows: { [string]: Row } = {}
local crate: BasePart? = nil
local houseId: string? = nil
local street: string? = nil
local buying = false

local function refresh()
	local candy = StateController.get("candy") or 0
	local consumables = StateController.get("consumables") or {}
	for itemId, row in rows do
		local item = (Items :: any)[itemId] :: Items.Item
		local have = consumables[itemId] or 0
		local price = Items.price(itemId, street or "")
		local full = have >= item.most
		local afford = candy >= price
		row.owned.Text = `{have} / {item.most}`
		row.buy.Text = if full then "FULL" else `🍬 {Format.number(price)}`
		-- HUD style: affordable is green text and a green outline, not a filled button.
		row.buy.TextColor3 = if not full and afford then Theme.Colors.Success else Theme.Colors.TextDim
		local outline = row.buy:FindFirstChild("Outline") :: UIStroke?
		if outline then
			outline.Color = if not full and afford then Theme.Colors.Success else Theme.Colors.Hairline
			outline.Transparency = if not full and afford then 0.2 else 0.75
		end
	end
end

local function buy(itemId: string)
	if buying or houseId == nil then
		return
	end
	buying = true
	local ok, message = Net.func("BuyItem"):InvokeServer(houseId, itemId)
	buying = false
	Sound.play(if ok then "Purchase" else "Error")
	NotificationController.show(message or "Couldn't buy that", if ok then "success" else "error")
	refresh()
end

local function buildRow(itemId: string, order: number, parent: Instance): Row
	local item = (Items :: any)[itemId] :: Items.Item
	local frame = create("Frame", {
		Name = itemId,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 78),
		BackgroundColor3 = Theme.Colors.PanelLight,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
		create("TextLabel", {
			Name = "Icon",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(52, 78),
			BackgroundTransparency = 1,
			Text = item.icon,
			TextSize = 34,
		}),
		create("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(68, 8),
			Size = UDim2.new(1, -230, 0, 28),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = item.name,
			TextColor3 = Theme.Colors.Text,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		create("TextLabel", {
			Name = "Blurb",
			Position = UDim2.fromOffset(68, 36),
			Size = UDim2.new(1, -230, 0, 36),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Body,
			Text = item.blurb,
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Parent = parent,
	})
	local owned = create("TextLabel", {
		Name = "Owned",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -148, 0.5, 0),
		Size = UDim2.fromOffset(56, 24),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	local buyButton = Button.new({
		name = "Buy",
		text = "",
		size = UDim2.fromOffset(124, 50),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.PanelDark,
		textSize = 20,
		parent = frame,
		onClick = function()
			buy(itemId)
		end,
	})
	return { owned = owned, buy = buyButton }
end

local function open(stall: BasePart)
	local model = stall.Parent
	if model == nil then
		return
	end
	crate = stall
	houseId = model:GetAttribute("House") :: string?
	street = model:GetAttribute("Street") :: string?
	local lines = Items.SELLER.LINES
	line.Text = `“{lines[math.random(1, #lines)]}”`
	refresh()
	panel:open()
end

-- Walked off, or he's gone (a new night): the window goes.
local function watch()
	local stall = crate
	if stall == nil or not panel:isOpen() then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if stall.Parent == nil or root == nil or (root.Position - stall.Position).Magnitude > Items.SELLER.RANGE + 2 then
		panel:close()
	end
end

function SellerController.Start()
	panel = Panel.new({ name = "SellerPanel", title = "🏮 Seller", size = Vector2.new(600, 470) })
	line = create("TextLabel", {
		Name = "Line",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.OrangeLight,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel.content,
	})
	local list = create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
		Parent = panel.content,
	})
	for order, itemId in Items.ORDER do
		rows[itemId] = buildRow(itemId, order, list)
	end
	for _, key in { "candy", "consumables" } do
		StateController.observe(key, function()
			if panel:isOpen() then
				refresh()
			end
		end)
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and parent:IsA("BasePart") and CollectionService:HasTag(parent, "SellerStall") then
			open(parent)
		end
	end)
	RunService.Heartbeat:Connect(watch)
end

return SellerController
