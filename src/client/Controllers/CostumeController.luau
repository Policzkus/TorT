--!strict
-- The wardrobe (PROMPT §V2.3): every costume and starter kid is a whole character, shown turning
-- in a 3D preview. Buy costumes with candy (kept forever, rebirth too), wear one, or pick which kid
-- you are underneath. Without a costume, homeowners barely give you anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Costumes = require(Shared.Config.Costumes)
local CharacterRig = require(Shared.Modules.CharacterRig)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local NotificationController = require(script.Parent.NotificationController)
local RadialMenuController = require(script.Parent.RadialMenuController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local CostumeController = {}

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Theme.Colors.TextDim,
	Rare = Theme.Rarity.MilSpec,
	Epic = Theme.Rarity.Classified,
	Legendary = Theme.Rarity.Gold,
}
local TURN_SPEED = 0.6 -- radians per second in the big preview

type Entry = { kind: "costume" | "kid", id: string, character: string, order: number }
type Card = { entry: Entry, frame: TextButton, status: TextLabel, stroke: UIStroke }

local panel: Panel.Panel
local cards: { Card } = {}
local selected: Entry? = nil
local tab: "costume" | "kid" = "costume"
local busy = false

local preview: ViewportFrame
local previewModel: Model? = nil
local nameLabel: TextLabel
local infoLabel: TextLabel
local blurbLabel: TextLabel
local actionButton: TextButton
local tabButtons: { [string]: TextButton } = {}
local grid: ScrollingFrame
local warning: TextLabel

local function entries(kind: "costume" | "kid"): { Entry }
	local list: { Entry } = {}
	if kind == "costume" then
		for id, costume in Costumes.costumes do
			table.insert(list, { kind = "costume", id = id, character = costume.character, order = costume.order })
		end
	else
		for order, id in Costumes.STARTER_ORDER do
			table.insert(list, { kind = "kid", id = id, character = Costumes.starters[id].character, order = order })
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- Puts a static copy of a character in a viewport, framed head to toe.
local function show(viewport: ViewportFrame, characterId: string): Model?
	viewport:ClearAllChildren()
	local model = CharacterRig.build(characterId, true)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if model == nil then
		return nil
	end
	local _, size = model:GetBoundingBox()
	local height = math.max(size.Y, 1)
	local distance = height / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.25
	camera.CFrame = CFrame.lookAt(Vector3.new(0, height * 0.52, -distance), Vector3.new(0, height * 0.5, 0))
	model.Parent = viewport
	return model
end

local function owned(entry: Entry): boolean
	if entry.kind == "kid" then
		return true
	end
	local costumes = StateController.get("costumes") or {}
	return costumes[entry.id] == true
end

local function wearing(entry: Entry): boolean
	local equipped = StateController.get("equipped") or {}
	if entry.kind == "kid" then
		return StateController.get("starter") == entry.id
	end
	return equipped.costume == entry.id
end

local function refreshDetails()
	local entry = selected
	if entry == nil then
		return
	end
	local candy = StateController.get("candy") or 0
	if entry.kind == "kid" then
		local starter = Costumes.starters[entry.id]
		nameLabel.Text = string.upper(starter.name)
		infoLabel.Text = "STARTER KID  ·  under every costume"
		infoLabel.TextColor3 = Theme.Colors.TextDim
		blurbLabel.Text = starter.blurb
		actionButton.Text = if wearing(entry) then "THIS IS YOU" else "BE " .. string.upper(starter.name)
		actionButton.BackgroundColor3 = if wearing(entry) then Theme.Colors.PanelDark else Theme.Colors.PanelLight
	else
		local costume = Costumes.costumes[entry.id]
		nameLabel.Text = string.upper(costume.name)
		infoLabel.Text = `{string.upper(costume.rarity)}  ·  {string.upper(costume.tag)}  ·  +{math.round(
			costume.bonus * 100
		)}% CANDY`
		infoLabel.TextColor3 = RARITY_COLORS[costume.rarity] or Theme.Colors.TextDim
		blurbLabel.Text = `Homeowners who like {costume.tag} costumes give +40% more.`
		if wearing(entry) then
			actionButton.Text = "TAKE OFF"
			actionButton.BackgroundColor3 = Theme.Colors.PanelDark
		elseif owned(entry) then
			actionButton.Text = "WEAR"
			actionButton.BackgroundColor3 = Theme.Colors.PanelLight
		else
			actionButton.Text = `BUY  ·  {Format.number(costume.price)} CANDY`
			actionButton.BackgroundColor3 = if candy >= costume.price
				then Color3.fromHex("2E4A24")
				else Theme.Colors.PanelDark
		end
	end
end

local function refreshCards()
	local candy = StateController.get("candy") or 0
	for _, card in cards do
		local entry = card.entry
		local isSelected = selected ~= nil and selected.id == entry.id and selected.kind == entry.kind
		card.stroke.Transparency = if isSelected then 0.1 else 0.8
		if wearing(entry) then
			card.status.Text = "● WEARING"
			card.status.TextColor3 = Theme.Colors.Slime
		elseif owned(entry) then
			card.status.Text = if entry.kind == "kid" then "" else "OWNED"
			card.status.TextColor3 = Theme.Colors.TextDim
		else
			local price = Costumes.costumes[entry.id].price
			card.status.Text = `{Format.number(price)}`
			card.status.TextColor3 = if candy >= price then Theme.Colors.Text else Theme.Colors.TextDim
		end
	end
	local equipped = StateController.get("equipped") or {}
	warning.Visible = equipped.costume == nil
end

local function choose(entry: Entry)
	selected = entry
	previewModel = show(preview, entry.character)
	refreshDetails()
	refreshCards()
end

local function buildCard(entry: Entry): Card
	local viewport = create("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.new(1, 0, 1, -22),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 150),
		LightColor = Color3.fromRGB(255, 244, 228),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
	})
	local status = create("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -2),
		Size = UDim2.new(1, -12, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.TextDim,
	})
	local stroke = create("UIStroke", {
		Color = Theme.Colors.Hairline,
		Transparency = 0.8,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local frame: TextButton = create("TextButton", {
		Name = entry.id,
		LayoutOrder = entry.order,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.2,
		AutoButtonColor = false,
		Text = "",
		create("UICorner", { CornerRadius = Theme.Corner }),
		stroke,
		viewport,
		status,
		Parent = grid,
	})
	frame.Activated:Connect(function()
		Sound.play("Click")
		choose(entry)
	end)
	task.defer(show, viewport, entry.character)
	return { entry = entry, frame = frame, status = status, stroke = stroke }
end

local function showTab(kind: "costume" | "kid")
	tab = kind
	for _, card in cards do
		card.frame:Destroy()
	end
	table.clear(cards)
	for _, entry in entries(kind) do
		table.insert(cards, buildCard(entry))
	end
	for id, button in tabButtons do
		local active = id == kind
		button.TextColor3 = if active then Theme.Colors.Text else Theme.Colors.TextDim
		button.BackgroundColor3 = if active then Theme.Colors.PanelLight else Theme.Colors.PanelDark
	end
	-- Select what you're wearing (or the first one).
	local list = entries(kind)
	local pick = list[1]
	for _, entry in list do
		if wearing(entry) then
			pick = entry
		end
	end
	if pick then
		choose(pick)
	end
end

local function act()
	local entry = selected
	if entry == nil or busy then
		return
	end
	busy = true
	local ok, message
	if entry.kind == "kid" then
		ok, message = Net.func("ChooseStarter"):InvokeServer(entry.id)
	elseif wearing(entry) then
		ok, message = Net.func("EquipCostume"):InvokeServer("")
	elseif owned(entry) then
		ok, message = Net.func("EquipCostume"):InvokeServer(entry.id)
	else
		ok, message = Net.func("BuyCostume"):InvokeServer(entry.id)
		if ok then
			Sound.play("Purchase")
		end
	end
	busy = false
	if not ok then
		Sound.play("Error")
	end
	NotificationController.show(message or "Couldn't do that", if ok then "success" else "error")
end

function CostumeController.open()
	panel:open()
	showTab(tab)
end

function CostumeController.Start()
	panel = Panel.new({ name = "CostumePanel", title = "Costumes", size = Vector2.new(780, 500) })
	local content = panel.content

	-- Left: big turning preview + details.
	preview = create("ViewportFrame", {
		Name = "BigPreview",
		Size = UDim2.new(0, 280, 1, -150),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(140, 140, 140),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
		create("UICorner", { CornerRadius = Theme.Corner }),
		Parent = content,
	})
	nameLabel = create("TextLabel", {
		Name = "CostumeName",
		Position = UDim2.new(0, 0, 1, -144),
		Size = UDim2.fromOffset(280, 30),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	infoLabel = create("TextLabel", {
		Name = "Info",
		Position = UDim2.new(0, 0, 1, -114),
		Size = UDim2.fromOffset(280, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	blurbLabel = create("TextLabel", {
		Name = "Blurb",
		Position = UDim2.new(0, 0, 1, -94),
		Size = UDim2.fromOffset(280, 36),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = content,
	})
	actionButton = Button.new({
		name = "Action",
		text = "",
		size = UDim2.fromOffset(280, 46),
		position = UDim2.new(0, 0, 1, -50),
		textSize = 18,
		parent = content,
		onClick = act,
	})

	-- Right: tabs + grid of cards.
	local right = create("Frame", {
		Name = "Right",
		Position = UDim2.fromOffset(296, 0),
		Size = UDim2.new(1, -296, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
	})
	for index, info in { { id = "costume", label = "COSTUMES" }, { id = "kid", label = "YOUR KID" } } do
		tabButtons[info.id] = Button.new({
			name = info.id,
			text = info.label,
			size = UDim2.fromOffset(130, 32),
			position = UDim2.fromOffset((index - 1) * 138, 0),
			textSize = 16,
			parent = right,
			onClick = function()
				showTab(info.id :: any)
			end,
		})
	end
	grid = create("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -72),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(106, 140),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }),
		Parent = right,
	})
	warning = create("TextLabel", {
		Name = "NoCostume",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = `NO COSTUME: HOMEOWNERS ONLY GIVE {math.round(Costumes.NO_COSTUME_CANDY * 100)}% CANDY`,
		TextColor3 = Theme.Colors.Danger,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = right,
	})

	-- Slow turn of the big preview while the window is open.
	RunService.RenderStepped:Connect(function(dt)
		local model = previewModel
		if model and model.Parent and panel:isOpen() then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * TURN_SPEED, 0))
		end
	end)

	for _, key in { "candy", "costumes", "equipped", "starter" } do
		StateController.observe(key, function()
			if panel:isOpen() then
				refreshDetails()
				refreshCards()
			end
		end)
	end
	RadialMenuController.register({
		id = "Costumes",
		label = "COSTUMES",
		order = 2,
		glyph = "👻",
		onSelect = CostumeController.open,
	})
end

return CostumeController
