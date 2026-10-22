--!strict
-- Helpers for procedural geometry. Every part is anchored and smooth; Parent is set last.

local Parts = {}

export type Props = { [string]: any }

local colorCache: { [string]: Color3 } = {}

function Parts.hex(hex: string): Color3
	local cached = colorCache[hex]
	if cached == nil then
		cached = Color3.fromHex(hex)
		colorCache[hex] = cached
	end
	return cached
end

local function resolveColor(color: Color3 | string): Color3
	return if type(color) == "string" then Parts.hex(color) else color
end

function Parts.new(
	className: string,
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = resolveColor(color)
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			(part :: any)[key] = value
		end
	end
	part.Parent = parent
	return part
end

function Parts.block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	return Parts.new("Part", parent, name, size, cframe, color, material, props)
end

function Parts.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	return Parts.new("WedgePart", parent, name, size, cframe, color, material, props)
end

function Parts.ball(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	local part = Parts.new("Part", parent, name, size, cframe, color, material, props) :: Part
	part.Shape = Enum.PartType.Ball
	return part
end

-- A cylinder whose axis runs along `cframe`'s X axis (Roblox's convention).
function Parts.cylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	cframe: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	local part =
		Parts.new("Part", parent, name, Vector3.new(length, diameter, diameter), cframe, color, material, props) :: Part
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- An upright cylinder standing on `base` (a point on the ground).
function Parts.pole(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	base: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	return Parts.cylinder(
		parent,
		name,
		height,
		diameter,
		base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		props
	)
end

-- A flat disc lying on the ground, centred on `base`.
function Parts.disc(
	parent: Instance,
	name: string,
	diameter: number,
	thickness: number,
	base: CFrame,
	color: Color3 | string,
	material: Enum.Material?,
	props: Props?
): BasePart
	return Parts.cylinder(
		parent,
		name,
		thickness,
		diameter,
		base * CFrame.new(0, thickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		props
	)
end

-- Purely visual: no collisions, raycasts, touches or shadows.
function Parts.decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

function Parts.invisibleWall(parent: Instance, size: Vector3, cframe: CFrame): BasePart
	local wall = Parts.block(parent, "Boundary", size, cframe, "000000", Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	return wall
end

-- A wall segment between two ground points (used for boundaries at road bends).
function Parts.wallBetween(parent: Instance, a: Vector3, b: Vector3, height: number): BasePart?
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	if flat.Magnitude < 0.5 then
		return nil
	end
	local middle = (a + b) / 2
	local frame = CFrame.lookAt(Vector3.new(middle.X, height / 2, middle.Z), Vector3.new(b.X, height / 2, b.Z))
	return Parts.invisibleWall(parent, Vector3.new(2, height, flat.Magnitude + 2), frame)
end

function Parts.light(parent: BasePart, range: number, brightness: number, color: Color3 | string): PointLight
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = resolveColor(color)
	light.Shadows = false
	light.Parent = parent
	return light
end

export type TextOptions = {
	color: Color3?,
	stroke: Color3?,
	font: Font?,
	background: Color3?,
}

local HEADING_FONT = Font.fromEnum(Enum.Font.FredokaOne)

local function label(text: string, options: TextOptions?): TextLabel
	local opts: TextOptions = options or {}
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = if opts.background then 0 else 1
	textLabel.BackgroundColor3 = opts.background or Color3.new()
	textLabel.FontFace = opts.font or HEADING_FONT
	textLabel.Text = text
	textLabel.TextScaled = true
	textLabel.TextColor3 = opts.color or Color3.new(1, 1, 1)
	textLabel.RichText = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = opts.stroke or Color3.fromHex("120A1C")
	stroke.Thickness = 3
	stroke.Parent = textLabel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.Parent = textLabel
	return textLabel
end

-- Text painted on one face of a part.
function Parts.sign(part: BasePart, face: Enum.NormalId, text: string, options: TextOptions?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	label(text, options).Parent = gui
	gui.Parent = part
	return gui
end

-- Floating text above a part. `size` is in studs.
function Parts.billboard(
	adornee: BasePart,
	name: string,
	text: string,
	size: Vector2,
	offset: Vector3,
	maxDistance: number?,
	options: TextOptions?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 150
	gui.AlwaysOnTop = false
	label(text, options).Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

export type Line = { text: string, height: number, color: Color3? }

-- Floating text with several lines of different sizes. Line heights are fractions of `size.Y`.
-- Each line's TextLabel is named Line1, Line2… so the client can change one.
function Parts.billboardLines(
	adornee: BasePart,
	name: string,
	lines: { Line },
	size: Vector2,
	offset: Vector3,
	maxDistance: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 150
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = gui
	for index, line in lines do
		local textLabel = label(line.text, { color = line.color })
		textLabel.Name = "Line" .. index
		textLabel.LayoutOrder = index
		textLabel.Size = UDim2.fromScale(1, line.height)
		textLabel.Parent = gui
	end
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

function Parts.prompt(
	parent: BasePart,
	actionText: string,
	objectText: string,
	distance: number,
	holdDuration: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance
	prompt.HoldDuration = holdDuration or 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

return Parts
