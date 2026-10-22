--!strict
-- Chunky cartoon button: bouncy hover/press scaling and a click sound (PROMPT §3.18).

local TweenService = game:GetService("TweenService")

local Sound = require(script.Parent.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Parent.Theme)
local create = require(script.Parent.Parent.create)

export type Options = {
	name: string?,
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	textSize: number?,
	layoutOrder: number?,
	parent: Instance?,
	onClick: (() -> ())?,
}

local Button = {}

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function Button.new(options: Options): TextButton
	local scale = create("UIScale", { Scale = 1 })
	local button: TextButton = create("TextButton", {
		Name = options.name or "Button",
		Size = options.size,
		Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.zero,
		BackgroundColor3 = options.color or Theme.Colors.Orange,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Heading,
		Text = options.text,
		TextColor3 = options.textColor or Theme.Colors.Text,
		TextSize = options.textSize or 22,
		TextWrapped = true,
		LayoutOrder = options.layoutOrder or 0,
		scale,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Name = "Outline",
			Color = Theme.Colors.Stroke,
			Thickness = Theme.StrokeThickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIStroke", { Name = "TextStroke", Color = Theme.Colors.Stroke, Thickness = 2 }),
	})
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		TweenService:Create(scale, HOVER, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = if hovering then 1.05 else 1 }):Play()
	end)
	button.Activated:Connect(function()
		Sound.play("Click")
		if options.onClick then
			options.onClick()
		end
	end)
	if options.parent then
		button.Parent = options.parent
	end
	return button
end

return Button
