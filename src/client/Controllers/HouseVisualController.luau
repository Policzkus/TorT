--!strict
-- Draws each house's "tells" from the attributes HouseService sets (PROMPT §3.5), all locally:
--   homeowner + preference badge over the door, dark windows for Lights Off, a flickering porch
--   light for Trick houses, string lights + extra pumpkins for Decorated houses, and the gold
--   beam over the Full-Size Bar house (from ReplicatedStorage.WorldState). Jack-o'-lantern candles
--   on the Blender houses flicker.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Houses = require(Shared.Modules.Houses)
local Dialogue = require(Shared.Config.Dialogue)
local Events = require(Shared.Config.Events)
local HouseTypes = require(Shared.Config.HouseTypes)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local HouseVisualController = {}

type Tracked = {
	door: BasePart,
	model: Model,
	decor: Folder?,
	badge: BillboardGui?,
	saved: { [Instance]: { [string]: any } }, -- original properties of things we changed
}

local tracked: { [Model]: Tracked } = {}
local tricky: { [Model]: boolean } = {}
local candles: { [PointLight]: number } = {} -- jack-o'-lantern candles and their steady brightness
local beam: Model? = nil

local function save(entry: Tracked, instance: Instance, property: string)
	local list = entry.saved[instance]
	if list == nil then
		list = {}
		entry.saved[instance] = list
	end
	if list[property] == nil then
		list[property] = (instance :: any)[property]
	end
end

local function restore(entry: Tracked)
	for instance, properties in entry.saved do
		for property, value in properties do
			(instance :: any)[property] = value
		end
	end
	table.clear(entry.saved)
end

local function porchLights(model: Model): { PointLight }
	local lights = {}
	local porch = model:FindFirstChild("PorchLight", true)
	if porch then
		for _, child in porch:GetChildren() do
			if child:IsA("PointLight") then
				table.insert(lights, child)
			end
		end
	end
	return lights
end

local function lightsOff(entry: Tracked)
	for _, descendant in entry.model:GetDescendants() do
		if descendant:IsA("BasePart") and (descendant.Name == "Window" or descendant.Name == "PorchLight") then
			save(entry, descendant, "Color")
			save(entry, descendant, "Material")
			descendant.Color = Color3.fromHex("161A26")
			descendant.Material = Enum.Material.Glass
		elseif
			descendant:IsA("BasePart") and (descendant.Name == "LanternGlow" or descendant.Name == "PumpkinGlow")
		then
			-- The Blender house's lantern and jack-o'-lantern candles go out.
			save(entry, descendant, "Color")
			save(entry, descendant, "Material")
			descendant.Color = Color3.fromHex("1A1612")
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("SurfaceGui") and descendant.Parent and descendant.Parent:GetAttribute("Lit") then
			-- A lit window room (Victorian.windowRooms) turns into a dark one.
			save(entry, descendant, "LightInfluence")
			descendant.LightInfluence = 1
			local image = descendant:FindFirstChildWhichIsA("ImageLabel")
			if image then
				save(entry, image, "ImageColor3")
				image.ImageColor3 = Color3.fromRGB(70, 70, 76)
			end
		elseif descendant:IsA("PointLight") then
			save(entry, descendant, "Enabled")
			descendant.Enabled = false
		end
	end
end

-- The Blender decorations (Assets.Decor, art/scripts/decor.py) hung at the anchors a house model
-- brings (DecorAnchors: attachments named after the piece). False if either is missing.
local function blenderDecor(entry: Tracked, folder: Folder): boolean
	local anchors = entry.model:FindFirstChild("DecorAnchors")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local set = assets and assets:FindFirstChild("Decor")
	if anchors == nil or set == nil then
		return false
	end
	local placed = false
	for _, anchor in anchors:GetChildren() do
		local piece = if anchor:IsA("Attachment") then set:FindFirstChild(anchor.Name) else nil
		if piece and piece:IsA("Model") then
			local copy = piece:Clone()
			copy:PivotTo(anchor.WorldCFrame)
			copy.Parent = folder
			placed = true
		end
	end
	return placed
end

local function decorate(entry: Tracked)
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	if blenderDecor(entry, folder) then
		folder.Parent = entry.model
		entry.decor = folder
		return
	end
	local door = entry.door
	local colors = { Color3.fromHex("FF8A00"), Color3.fromHex("8A3AFF"), Color3.fromHex("7CFF4F") }
	-- String lights along the top of the front wall, either side of the door.
	for i = -7, 7 do
		if math.abs(i) > 1 then
			local bulb = Instance.new("Part")
			bulb.Shape = Enum.PartType.Ball
			bulb.Size = Vector3.one * 0.5
			bulb.Material = Enum.Material.Neon
			bulb.Color = colors[(i % 3) + 1]
			bulb.Anchored = true
			bulb.CanCollide = false
			bulb.CanQuery = false
			bulb.CastShadow = false
			bulb.CFrame = door.CFrame * CFrame.new(i * 1.4, door.Size.Y / 2 + 1.6 + (i % 2) * 0.25, -0.4)
			bulb.Parent = folder
		end
	end
	-- A big glowing pumpkin by the door.
	local pumpkin = Instance.new("Part")
	pumpkin.Shape = Enum.PartType.Ball
	pumpkin.Size = Vector3.new(2.6, 2.1, 2.6)
	pumpkin.Color = Color3.fromHex("FF7A1A")
	pumpkin.Anchored = true
	pumpkin.CanCollide = false
	pumpkin.CFrame = door.CFrame * CFrame.new(3.2, -door.Size.Y / 2 + 1, -2.4)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex("FF8A00")
	glow.Range = 10
	glow.Brightness = 1.2
	glow.Parent = pumpkin
	pumpkin.Parent = folder
	folder.Parent = entry.model
	entry.decor = folder
end

local function badgeText(model: Model): (string, string)
	local houseType = model:GetAttribute("HouseType")
	local owner = Dialogue.personalities[model:GetAttribute("Owner") :: string]
	local preference = model:GetAttribute("Preference") :: string?
	local icon = if preference then HouseTypes.PREFERENCE_ICONS[preference] or "" else ""
	if houseType == "LightsOff" then
		return "💤", "Lights off"
	elseif houseType == "Bowl" then
		return "🍬", "Please take one"
	end
	local name = if owner then `{owner.emoji} {owner.name}` else ""
	local tag = if houseType == "Decorated" then "  ✨" else ""
	return icon .. tag, name
end

local function updateBadge(entry: Tracked)
	local top, bottom = badgeText(entry.model)
	local badge = entry.badge
	if badge == nil then
		badge = create("BillboardGui", {
			Name = "HouseBadge",
			Size = UDim2.fromOffset(150, 52),
			StudsOffsetWorldSpace = Vector3.new(0, entry.door.Size.Y / 2 + 2.6, 0),
			MaxDistance = 48,
			LightInfluence = 0,
			Adornee = entry.door,
			create("TextLabel", {
				Name = "Icon",
				Size = UDim2.fromScale(1, 0.6),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Heading,
				TextScaled = true,
				TextColor3 = Theme.Colors.Text,
			}),
			create("TextLabel", {
				Name = "Owner",
				Position = UDim2.fromScale(0, 0.6),
				Size = UDim2.fromScale(1, 0.4),
				BackgroundTransparency = 1,
				FontFace = Theme.Fonts.Heading,
				TextScaled = true,
				TextColor3 = Theme.Colors.OrangeLight,
				create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
			}),
			Parent = entry.door,
		})
		entry.badge = badge
	end
	local gui = badge :: BillboardGui
	local icon = gui:FindFirstChild("Icon") :: TextLabel
	local owner = gui:FindFirstChild("Owner") :: TextLabel
	icon.Text = top
	owner.Text = bottom
end

local function apply(entry: Tracked)
	restore(entry)
	if entry.decor then
		entry.decor:Destroy()
		entry.decor = nil
	end
	tricky[entry.model] = nil
	for _, light in porchLights(entry.model) do
		light.Enabled = true -- undo any trick-house flicker
	end
	local houseType = entry.model:GetAttribute("HouseType")
	if houseType == "LightsOff" then
		lightsOff(entry)
	elseif houseType == "Decorated" then
		decorate(entry)
	elseif houseType == "Trick" then
		tricky[entry.model] = true
	end
	updateBadge(entry)
end

local function track(door: Instance)
	if not door:IsA("BasePart") then
		return
	end
	local model = Houses.of(door)
	if model == nil or tracked[model] then
		return
	end
	local entry: Tracked = { door = door, model = model, saved = {} }
	tracked[model] = entry
	for _, attribute in { "HouseType", "Owner", "Preference" } do
		model:GetAttributeChangedSignal(attribute):Connect(function()
			if tracked[model] == entry then
				apply(entry)
			end
		end)
	end
	apply(entry)
end

local function untrack(door: Instance)
	local model = Houses.of(door)
	if model and tracked[model] then
		tracked[model] = nil
		tricky[model] = nil
	end
end

-- Full-Size Bar beam ----------------------------------------------------------------------------

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
end

local function showBeam(position: Vector3)
	clearBeam()
	local m = Instance.new("Model")
	m.Name = "FullSizeBeam"
	local column = Instance.new("Part")
	column.Shape = Enum.PartType.Cylinder
	column.Size = Vector3.new(220, 5, 5)
	column.CFrame = CFrame.new(position.X, position.Y + 108, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	column.Color = Color3.fromHex("FFD23F")
	column.Material = Enum.Material.Neon
	column.Transparency = 0.45
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CastShadow = false
	column.Parent = m
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FFD23F")
	light.Range = 40
	light.Brightness = 3
	light.Parent = column
	create("BillboardGui", {
		Name = "Label",
		Size = UDim2.fromOffset(260, 70),
		StudsOffsetWorldSpace = Vector3.new(0, -96, 0),
		AlwaysOnTop = true,
		MaxDistance = 2000,
		LightInfluence = 0,
		Adornee = column,
		create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = `🍫 FULL-SIZE BAR ×{Events.FULL_SIZE_MULTIPLIER}`,
			TextColor3 = Color3.fromHex("FFD23F"),
			TextScaled = true,
			create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
		}),
		Parent = column,
	})
	m.Parent = Workspace
	beam = m
end

local function watchFullSize(state: Instance)
	local function refresh()
		local houseId = state:GetAttribute("FullSizeHouse")
		local position = state:GetAttribute("FullSizePosition")
		if type(houseId) == "string" and houseId ~= "" and typeof(position) == "Vector3" then
			showBeam(position)
		else
			clearBeam()
		end
	end
	state:GetAttributeChangedSignal("FullSizeHouse"):Connect(refresh)
	refresh()
end

function HouseVisualController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Door"):Connect(untrack)
	for _, door in CollectionService:GetTagged("Door") do
		track(door)
	end
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("WorldState", 120)
		if state then
			watchFullSize(state)
		end
	end)

	-- Candles in the Blender house's jack-o'-lanterns (lights in a part named "PumpkinLight").
	local function watchCandle(instance: Instance)
		local holder = instance.Parent
		if instance:IsA("PointLight") and holder and holder.Name == "PumpkinLight" then
			candles[instance] = instance.Brightness
		end
	end
	Workspace.DescendantAdded:Connect(watchCandle)
	for _, instance in Workspace:GetDescendants() do
		watchCandle(instance)
	end

	-- Trick houses: a porch light that can't make up its mind. Candles gutter everywhere.
	while true do
		task.wait(0.12)
		for light, steady in candles do
			if light.Parent == nil then
				candles[light] = nil
			else
				light.Brightness = steady * (0.65 + math.random() * 0.45)
			end
		end
		for model in tricky do
			for _, light in porchLights(model) do
				if math.random() < 0.3 then
					light.Enabled = not light.Enabled
				end
			end
		end
		if beam then
			local column = beam:FindFirstChildOfClass("Part")
			if column then
				column.Transparency = 0.4 + math.sin(os.clock() * 4) * 0.12
			end
		end
	end
end

return HouseVisualController
