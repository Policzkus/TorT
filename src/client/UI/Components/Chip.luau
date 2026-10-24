--!strict
-- A HUD chip: a near-black translucent tile with a hairline outline that hugs one line of text,
-- like the HUD's own (HUDController). For labels anywhere, including billboards in the world.

local Theme = require(script.Parent.Parent.Theme)
local create = require(script.Parent.Parent.create)

export type Options = {
	name: string?,
	text: string?,
	textSize: number?,
	color: Color3?, -- the text's
	height: number?,
	anchor: Vector2?,
	position: UDim2?,
	parent: Instance?,
}

local Chip = {}

-- Returns the tile and its label.
function Chip.new(options: Options): (Frame, TextLabel)
	local height = options.height or 26
	local label = create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = options.text or "",
		TextColor3 = options.color or Theme.Colors.Text,
		TextSize = options.textSize or 16,
	})
	local frame = create("Frame", {
		Name = options.name or "Chip",
		AnchorPoint = options.anchor or Vector2.new(0.5, 0.5),
		Position = options.position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = Theme.HairlineTransparency,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		label,
		Parent = options.parent,
	})
	return frame, label
end

return Chip
