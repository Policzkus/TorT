--!strict
-- HUD progress bar: a translucent track with a hairline, a near-white fill, an optional label.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)
local create = require(script.Parent.Parent.create)

export type Options = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	background: Color3?,
	textSize: number?,
	layoutOrder: number?,
	parent: Instance?,
}

export type ProgressBar = {
	frame: Frame,
	fill: Frame,
	label: TextLabel,
	set: (self: ProgressBar, fraction: number, animate: boolean?) -> (),
	setColor: (self: ProgressBar, color: Color3) -> (),
	setText: (self: ProgressBar, text: string) -> (),
}

local ProgressBar = {}
ProgressBar.__index = ProgressBar

local TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function ProgressBar.new(options: Options): ProgressBar
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = options.color or Theme.Colors.Orange,
		BackgroundTransparency = 0.2,
		create("UICorner", { CornerRadius = UDim.new(0, 2) }),
	})
	local label = create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.BodyHeavy,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = options.textSize or 14,
		ZIndex = 2,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.3 }),
	})
	local frame = create("Frame", {
		Name = options.name or "ProgressBar",
		Size = options.size,
		Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.zero,
		BackgroundColor3 = options.background or Theme.Colors.PanelDark,
		LayoutOrder = options.layoutOrder or 0,
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		create("UICorner", { CornerRadius = UDim.new(0, 2) }),
		create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = 0.8, Thickness = 1 }),
		fill,
		label,
		Parent = options.parent,
	})
	local self = setmetatable({ frame = frame, fill = fill, label = label }, ProgressBar)
	return self :: any
end

function ProgressBar.set(self: any, fraction: number, animate: boolean?)
	local goal = UDim2.fromScale(math.clamp(if fraction == fraction then fraction else 0, 0, 1), 1)
	if animate then
		TweenService:Create(self.fill, TWEEN, { Size = goal }):Play()
	else
		self.fill.Size = goal
	end
end

function ProgressBar.setColor(self: any, color: Color3)
	self.fill.BackgroundColor3 = color
end

function ProgressBar.setText(self: any, text: string)
	self.label.Text = text
end

return ProgressBar
