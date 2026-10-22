--!strict
-- Contextual radial menu (the user's Watch Dogs reference): hold TAB (Q also works; DPad-Up on
-- gamepad; the MENU button on phones). Tiles sit on a thin ring, the highlighted one's name shows
-- in the centre. Release TAB over a tile, or click/tap it, to open it.
-- Other controllers add tiles with RadialMenuController.register.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

export type Entry = {
	id: string,
	label: string,
	order: number,
	icon: number?, -- image id
	glyph: string?, -- short text when there's no icon
	onSelect: () -> (),
}

local ACTION = "RadialMenu"
local RADIUS = 130
local TILE = 70

local RadialMenuController = {}

local entries: { Entry } = {}
local tiles: { [string]: TextButton } = {}
local gui: ScreenGui
local ring: Frame
local centreLabel: TextLabel
local popScale: UIScale
local open = false
local selected: string? = nil

local function layout()
	for _, tile in tiles do
		tile:Destroy()
	end
	table.clear(tiles)
	table.sort(entries, function(a, b)
		return a.order < b.order
	end)
	local count = #entries
	for index, entry in entries do
		local angle = -math.pi / 2 + (index - 1) / count * math.pi * 2
		local tile = create("TextButton", {
			Name = entry.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
			Size = UDim2.fromOffset(TILE, TILE),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.1,
			AutoButtonColor = false,
			Text = "",
			create("UICorner", { CornerRadius = Theme.Corner }),
			create("UIStroke", {
				Name = "Outline",
				Color = Theme.Colors.Hairline,
				Transparency = 0.7,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Parent = ring,
		})
		if entry.icon and entry.icon ~= 0 then
			create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(32, 32),
				BackgroundTransparency = 1,
				Image = "rbxassetid://" .. entry.icon,
				ImageColor3 = Theme.Colors.Text,
				Parent = tile,
			})
		else
			create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Heading,
				Text = entry.glyph or string.sub(entry.label, 1, 1),
				TextColor3 = Theme.Colors.Text,
				TextSize = 26,
				Parent = tile,
			})
		end
		tile.MouseEnter:Connect(function()
			selected = entry.id
		end)
		tile.Activated:Connect(function()
			selected = entry.id
			RadialMenuController.close(true)
		end)
		tiles[entry.id] = tile
	end
end

local function highlight()
	for id, tile in tiles do
		local active = id == selected
		local outline = tile:FindFirstChild("Outline") :: UIStroke
		outline.Transparency = if active then 0 else 0.7
		tile.BackgroundColor3 = if active then Theme.Colors.Text else Theme.Colors.PanelDark
		for _, child in tile:GetChildren() do
			if child:IsA("ImageLabel") then
				child.ImageColor3 = if active then Theme.Colors.PanelDark else Theme.Colors.Text
			elseif child:IsA("TextLabel") then
				child.TextColor3 = if active then Theme.Colors.PanelDark else Theme.Colors.Text
			end
		end
	end
	local entry = nil
	for _, candidate in entries do
		if candidate.id == selected then
			entry = candidate
		end
	end
	centreLabel.Text = if entry then entry.label else ""
end

-- Points at a tile from the mouse direction relative to the centre (no need to touch it).
local function pickFromMouse()
	if not open or #entries == 0 then
		return
	end
	local centre = ring.AbsolutePosition + ring.AbsoluteSize / 2
	local offset = UserInputService:GetMouseLocation() - centre
	if offset.Magnitude < 30 then
		return
	end
	local angle = math.atan2(offset.Y, offset.X)
	local best, bestDiff = nil, math.huge
	for index, entry in entries do
		local tileAngle = -math.pi / 2 + (index - 1) / #entries * math.pi * 2
		local diff = math.abs(math.atan2(math.sin(angle - tileAngle), math.cos(angle - tileAngle)))
		if diff < bestDiff then
			best, bestDiff = entry.id, diff
		end
	end
	if best ~= selected then
		selected = best
		Sound.play("Tick", { volume = 0.6 })
		highlight()
	end
end

function RadialMenuController.register(entry: Entry)
	for index, existing in entries do
		if existing.id == entry.id then
			table.remove(entries, index)
			break
		end
	end
	table.insert(entries, entry)
	if gui then
		layout()
	end
end

function RadialMenuController.isOpen(): boolean
	return open
end

function RadialMenuController.openMenu()
	if open then
		return
	end
	open = true
	selected = nil
	highlight()
	gui.Enabled = true
	popScale.Scale = 0.85
	TweenService:Create(popScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	Sound.play("Whoosh", { volume = 0.5, speed = 1.4 })
end

-- `choose` = run the highlighted entry.
function RadialMenuController.close(choose: boolean?)
	if not open then
		return
	end
	open = false
	gui.Enabled = false
	if choose and selected then
		for _, entry in entries do
			if entry.id == selected then
				Sound.play("Click")
				task.defer(entry.onSelect)
			end
		end
	end
end

function RadialMenuController.toggle()
	if open then
		RadialMenuController.close(false)
	else
		RadialMenuController.openMenu()
	end
end

function RadialMenuController.Init()
	popScale = create("UIScale", {})
	centreLabel = create("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 30),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		FontFace = Theme.Fonts.Heading,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		create("UICorner", { CornerRadius = Theme.Corner }),
	})
	ring = create("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2),
		BackgroundTransparency = 1,
		popScale,
		create("Frame", {
			Name = "Circle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = 0.75, Thickness = 1 }),
		}),
		centreLabel,
	})
	gui = create("ScreenGui", {
		Name = "RadialMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		Enabled = false,
		create("TextButton", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			AutoButtonColor = false,
			Text = "",
			Modal = true, -- frees the mouse in first person while the menu is open
		}),
		ring,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui);
	(gui:FindFirstChild("Backdrop") :: TextButton).Activated:Connect(function()
		RadialMenuController.close(false)
	end)
	layout()
end

function RadialMenuController.Start()
	ContextActionService:BindAction(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			RadialMenuController.openMenu()
		elseif state == Enum.UserInputState.End then
			RadialMenuController.close(true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab, Enum.KeyCode.Q, Enum.KeyCode.DPadUp)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			pickFromMouse()
		end
	end)
end

return RadialMenuController
