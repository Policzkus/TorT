--!strict
-- The seller's window (Config/Items; ItemService sells). Knock at his door and the server says he's
-- coming (DoorService: SellerOpen, with when he'll be out): you step back and watch him come, as at
-- any door, his door takes no more knocks, and once he's out his window opens. It sits on the right
-- of the screen so you still see him and what he says. At its top, your banked candy and health; then
-- a row a thing: what it is and does, how many you've got of how many you can carry, its price on
-- this street, Buy, and Fill (as many as you can carry and pay for). The bandage's row stands out
-- while you're hurt. Close it (its X, E, Ⓑ), walk off, or let him go back in (SellerShut: the server
-- ended it), and he says goodbye and goes in (SellerDone).
-- And on a street with a seller tonight, you're told so as you come onto it.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Health = require(Shared.Config.Health)
local Items = require(Shared.Config.Items)
local Format = require(Shared.Modules.Format)
local Houses = require(Shared.Modules.Houses)
local Net = require(Shared.Modules.Net)
local DoorController = require(script.Parent.DoorController)
local Homeowner = require(script.Parent.HomeownerController)
local NotificationController = require(script.Parent.NotificationController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local SellerController = {}

local CLOSE_ACTION = "SellerClose"
local SIZE = Vector2.new(470, 540)
local ROW = 92

type Row = {
	frame: Frame,
	stroke: UIStroke,
	owned: TextLabel,
	buy: TextButton,
	fill: TextButton,
	note: TextLabel,
	canFill: number, -- how many Fill would buy now (0: not shown)
}

local panel: Panel.Panel
local wallet: TextLabel
local rows: { [string]: Row } = {}
local door: BasePart? = nil
local house: Model? = nil
local houseId: string? = nil
local street: string = ""
local visit = 0 -- counts visits (a wait for him to come out checks it's still its own)
local buying = false
local told: { [string]: string } = {} -- per street: the seller's house we last told you about

local function health(): number
	local value = Players.LocalPlayer:GetAttribute("Health")
	return if type(value) == "number" then value else Health.MAX
end

local function paintButton(button: TextButton, on: boolean, color: Color3?)
	-- HUD style: what you can do is green text and a green outline, not a filled button.
	local tint = color or Theme.Colors.Success
	button.TextColor3 = if on then tint else Theme.Colors.TextDim
	local outline = button:FindFirstChild("Outline") :: UIStroke?
	if outline then
		outline.Color = if on then tint else Theme.Colors.Hairline
		outline.Transparency = if on then 0.2 else 0.75
	end
end

local function refresh()
	local candy = StateController.get("candy") or 0
	local consumables = StateController.get("consumables") or {}
	local hp = health()
	wallet.Text = `🍬 {Format.commas(candy)} banked     ❤ {math.ceil(hp)} / {Health.MAX}`
	for itemId, row in rows do
		local item = (Items :: any)[itemId] :: Items.Item
		local have = consumables[itemId] or 0
		local price = Items.price(itemId, street)
		local room = item.most - have
		local affordable = math.floor(candy / price)
		row.owned.Text = `{have} / {item.most}`
		row.owned.TextColor3 = if room <= 0 then Theme.Colors.OrangeLight else Theme.Colors.TextDim
		row.buy.Text = if room <= 0 then "FULL" else `🍬 {Format.number(price)}`
		paintButton(row.buy, room > 0 and affordable >= 1)
		row.canFill = math.min(room, affordable)
		row.fill.Visible = row.canFill >= 2
		row.fill.Text = `Fill ×{row.canFill} · {Format.number(price * row.canFill)}`
		paintButton(row.fill, true, Theme.Colors.OrangeLight)
		row.note.Visible = room > 0 and affordable < 1
		row.note.Text = `need {Format.number(price - candy)} more`
		-- Hurt: the bandage is what you want.
		local wanted = itemId == "Bandage" and hp < Health.MAX and room > 0
		row.stroke.Color = if wanted then Theme.Colors.Danger else Theme.Colors.Stroke
		row.stroke.Transparency = if wanted then 0.15 else 0.45
	end
end

-- A row lights up for a moment: you bought it.
local function flash(row: Row)
	local glow = create("UIStroke", {
		Name = "Bought",
		Color = Theme.Colors.Success,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = row.frame,
	})
	local fade = TweenService:Create(glow, TweenInfo.new(0.6), { Transparency = 1 })
	fade.Completed:Once(function()
		glow:Destroy()
	end)
	fade:Play()
end

local function buy(itemId: string, count: number)
	if buying or houseId == nil then
		return
	end
	buying = true
	local ok, message = Net.func("BuyItem"):InvokeServer(houseId, itemId, count)
	buying = false
	Sound.play(if ok then "Purchase" else "Error")
	NotificationController.show(message or "Couldn't buy that", if ok then "success" else "error")
	if not ok and house then
		Homeowner.react(house, "headShake") -- he shakes his head at you
	end
	local row = rows[itemId]
	if ok and row then
		flash(row)
	end
	refresh()
end

local function buildRow(itemId: string, order: number, parent: Instance): Row
	local item = (Items :: any)[itemId] :: Items.Item
	local stroke = create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 })
	local frame = create("Frame", {
		Name = itemId,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, ROW),
		BackgroundColor3 = Theme.Colors.PanelLight,
		create("UICorner", { CornerRadius = Theme.Corner }),
		stroke,
		create("TextLabel", {
			Name = "Icon",
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(44, ROW),
			BackgroundTransparency = 1,
			Text = item.icon,
			TextSize = 30,
		}),
		create("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(54, 8),
			Size = UDim2.new(1, -230, 0, 24),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = item.name,
			TextColor3 = Theme.Colors.Text,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		create("TextLabel", {
			Name = "Blurb",
			Position = UDim2.fromOffset(54, 32),
			Size = UDim2.new(1, -184, 0, 54),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Body,
			Text = item.blurb,
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Parent = parent,
	})
	local owned = create("TextLabel", {
		Name = "Owned",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -128, 0, 10),
		Size = UDim2.fromOffset(46, 20),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	local buyButton = Button.new({
		name = "Buy",
		text = "",
		size = UDim2.fromOffset(112, 38),
		position = UDim2.new(1, -10, 0, 10),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.PanelDark,
		textSize = 18,
		parent = frame,
		onClick = function()
			buy(itemId, 1)
		end,
	})
	local fill = Button.new({
		name = "Fill",
		text = "",
		size = UDim2.fromOffset(112, 28),
		position = UDim2.new(1, -10, 0, 54),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.PanelDark,
		textSize = 13,
		parent = frame,
		onClick = function()
			local row = rows[itemId]
			if row and row.canFill >= 2 then
				buy(itemId, row.canFill)
			end
		end,
	})
	local note = create("TextLabel", {
		Name = "Note",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 56),
		Size = UDim2.fromOffset(112, 24),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.Danger,
		TextSize = 13,
		Visible = false,
		Parent = frame,
	})
	return { frame = frame, stroke = stroke, owned = owned, buy = buyButton, fill = fill, note = note, canFill = 0 }
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

-- The visit's over (you closed it, walked off, the server ended it): your view and his door are
-- yours again, and he can go back in.
local function finish()
	local id = houseId
	door, house, houseId = nil, nil, nil
	visit += 1
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel.frame) then
		GuiService.SelectedObject = nil
	end
	if id then
		Net.event("SellerDone"):FireServer(id)
		DoorController.release(id)
	end
end

local function showWindow()
	refresh()
	panel:open()
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			panel:close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = rows[Items.ORDER[1]].buy
	end
end

-- The server took your knock: he's coming. You step back and watch; his window opens once he's out.
local function onOpen(id: any, info: any)
	if type(id) ~= "string" then
		return
	end
	local part, model = doorOf(id)
	if part == nil or model == nil then
		Net.event("SellerDone"):FireServer(id)
		return
	end
	if houseId and houseId ~= id then
		panel:close()
		finish()
	end
	door, house, houseId = part, model, id
	street = if type(info) == "table" and type(info.street) == "string" then info.street else ""
	visit += 1
	local mine = visit
	DoorController.faceHouse(id)
	local outIn = if type(info) == "table" and type(info.outIn) == "number" then info.outIn else 0
	task.delay(math.max(0, outIn), function()
		if visit == mine and houseId == id then
			showWindow()
		end
	end)
end

-- The server ended it (you walked off, a new night).
local function onShut(id: any)
	if id ~= houseId then
		return
	end
	if panel:isOpen() then
		panel:close() -- (finish() follows from it)
	else
		finish()
	end
end

-- Walked off, or he's gone back in: the window goes (the server says so too: this is just sooner).
local function watch()
	local at = door
	if at == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local far = root == nil or (root.Position - at.Position).Magnitude > Economy.DOOR_LEAVE
	local gone = panel:isOpen() and house ~= nil and house:GetAttribute("OwnerOut") ~= true
	if at.Parent == nil or far or gone then
		onShut(houseId)
	end
end

-- Onto a street with a seller tonight: you're told (once a night a street).
local function tellOfSeller()
	local zone = Players.LocalPlayer:GetAttribute("Zone")
	if type(zone) ~= "string" then
		return
	end
	for _, part in CollectionService:GetTagged("Door") do
		local model = if part:IsA("BasePart") and part:GetAttribute("Neighborhood") == zone
			then Houses.of(part)
			else nil
		local id = part:GetAttribute("HouseId")
		if model and type(id) == "string" and model:GetAttribute("HouseType") == "Seller" then
			if told[zone] ~= id then
				told[zone] = id
				NotificationController.show("🏮 The seller's on this street tonight. Look for his lantern.", "info")
			end
			return
		end
	end
end

function SellerController.Start()
	panel = Panel.new({ name = "SellerPanel", title = "🏮 Seller", size = SIZE })
	-- On the right, so you still see him and what he says.
	panel.frame.AnchorPoint = Vector2.new(1, 0.5)
	panel.frame.Position = UDim2.new(1, -24, 0.52, 0)
	wallet = create("TextLabel", {
		Name = "Wallet",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel.content,
	})
	create("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		Text = "Use your things with 1-4, the flashlight with F (the d-pad and R3 on a controller).",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel.content,
	})
	local list = create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
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
	Players.LocalPlayer:GetAttributeChangedSignal("Health"):Connect(function()
		if panel:isOpen() then
			refresh()
		end
	end)
	Net.event("SellerOpen").OnClientEvent:Connect(onOpen)
	Net.event("SellerShut").OnClientEvent:Connect(onShut)
	panel.Closed:Connect(finish)
	RunService.Heartbeat:Connect(watch)
	Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(tellOfSeller)
	tellOfSeller()
end

return SellerController
