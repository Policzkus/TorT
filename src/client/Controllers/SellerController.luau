--!strict
-- The seller's window (Config/Items; ItemService sells): knock at his door and once he's come to it
-- (DoorService: SellerOpen) it opens, your view on him as at any door. A line from him at the top,
-- then a row a thing: what it is and does, how many you've got of how many you can carry, and its
-- price on this street in banked candy. Close it, walk off (Items.SELLER.RANGE) or let him go back
-- in, and it's done (SellerDone: he says goodbye and goes in).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Format = require(Shared.Modules.Format)
local Houses = require(Shared.Modules.Houses)
local Net = require(Shared.Modules.Net)
local DoorController = require(script.Parent.DoorController)
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
local door: BasePart? = nil
local house: Model? = nil
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

-- The front door of `id`, and its house.
local function doorOf(id: string): (BasePart?, Model?)
	for _, part in CollectionService:GetTagged("Door") do
		if part:IsA("BasePart") and part:GetAttribute("HouseId") == id then
			return part, Houses.of(part)
		end
	end
	return nil, nil
end

-- He's at his door for you.
local function open(id: any)
	if type(id) ~= "string" then
		return
	end
	local part, model = doorOf(id)
	if part == nil or model == nil then
		Net.event("SellerDone"):FireServer(id)
		return
	end
	door, house, houseId = part, model, id
	street = part:GetAttribute("Neighborhood") :: string?
	local lines = Items.SELLER.LINES
	line.Text = `“{lines[math.random(1, #lines)]}”`
	refresh()
	panel:open()
	DoorController.faceHouse(id)
end

-- Walked off, or he's gone back in (a new night): the window goes.
local function watch()
	local at = door
	if at == nil or not panel:isOpen() then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if
		at.Parent == nil
		or root == nil
		or (root.Position - at.Position).Magnitude > Items.SELLER.RANGE + 2
		or (house and house:GetAttribute("OwnerOut") ~= true)
	then
		panel:close()
	end
end

-- The window's shut: he can go back in.
local function closed()
	local id = houseId
	door, house, houseId = nil, nil, nil
	if id then
		Net.event("SellerDone"):FireServer(id)
		DoorController.release(id)
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
	Net.event("SellerOpen").OnClientEvent:Connect(open)
	panel.Closed:Connect(closed)
	RunService.Heartbeat:Connect(watch)
end

return SellerController
