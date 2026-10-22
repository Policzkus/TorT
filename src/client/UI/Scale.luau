--!strict
-- UI is designed at REFERENCE pixels; a UIScale keeps it the same relative size from phones to
-- big monitors (clamped so phone buttons stay tappable and desktop UI doesn't get huge).

local Workspace = game:GetService("Workspace")

local REFERENCE = Vector2.new(1100, 620)
local MIN_SCALE, MAX_SCALE = 0.6, 1.15

local Scale = {}

local scales: { UIScale } = {}

local function current(): number
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else REFERENCE
	return math.clamp(math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y), MIN_SCALE, MAX_SCALE)
end

local function refresh()
	local value = current()
	for _, scale in scales do
		scale.Scale = value
	end
end

function Scale.attach(gui: LayerCollector): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Scale = current()
	scale.Parent = gui
	table.insert(scales, scale)
	return scale
end

function Scale.get(): number
	return current()
end

local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return Scale
