-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/car/Car.fbx with
-- File > Import 3D (into Workspace). Files the car (art/scripts/car.py) under
-- ReplicatedStorage.Assets.Vehicles.Car for TrafficController to copy down the streets. Save the
-- place afterwards.
--
-- The car was modelled on the ground under its middle (Mark_Origin), its front toward -Y in Blender:
-- here its pivot goes back there, facing -Z. Each wheel's pieces (CarTire/CarWall/CarRim/CarHub +
-- FL, FR, RL, RR) become a model pivoting on its axle, with its radius as a "Radius" attribute, so
-- the game can roll it. The headlights get lights where Mark_HeadL/R are, the tail lights a glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Car")
assert(imported and imported:IsA("Model"), "Import Car.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end
local function bottomOf(marker: MeshPart): CFrame
	assert(marker.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), "expected the import to keep the meshes unrotated")
	return CFrame.new(marker.Position - Vector3.new(0, marker.Size.Y / 2, 0))
end
local origin = bottomOf(mesh("Mark_Origin"))

-- The SurfaceAppearance's texture ids as a "Maps" attribute, for the loading screen to download.
local function noteMaps(part: MeshPart)
	local look = part:FindFirstChildOfClass("SurfaceAppearance")
	if look == nil then
		return
	end
	local ids = {}
	for _, map in { look.ColorMap, look.NormalMap, look.RoughnessMap, look.MetalnessMap } do
		if map ~= "" then
			table.insert(ids, map)
		end
	end
	part:SetAttribute("Maps", table.concat(ids, ","))
end

-- The pieces Blender left plain: their look is set here.
local FLAT: { [string]: { [string]: any } } = {
	CarGlass = {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(20, 24, 26),
		Transparency = 0.35,
		CastShadow = false,
	},
	CarTrim = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(10, 10, 11) },
	CarInside = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(18, 13, 11) },
	CarPlate = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(176, 166, 132) },
	LightWhite = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 226, 170), CastShadow = false },
	LightRed = { Material = Enum.Material.Neon, Color = Color3.fromRGB(200, 22, 16), CastShadow = false },
}
local WHEEL: { [string]: { [string]: any } } = {
	Tire = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(12, 12, 13) },
	Wall = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(184, 174, 150) }, -- an old, yellowed whitewall
	Rim = { Material = Enum.Material.Metal, Color = Color3.fromRGB(74, 20, 20) }, -- steel painted like the body (and the cap's badge)
	Hub = { Material = Enum.Material.Metal, Color = Color3.fromRGB(176, 176, 182) }, -- the chrome trim ring, cap and spinner
}

local function file(part: MeshPart, look: { [string]: any }?, parent: Instance)
	assert(part.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), part.Name .. " came in rotated")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.CollisionFidelity = Enum.CollisionFidelity.Box
	for key, value in look or {} do
		(part :: any)[key] = value
	end
	-- The importer leaves each mesh a rotated pivot (Blender's Z-up); the car's main part's pivot is
	-- the car's, so every one goes back to the car's origin, unrotated (it stood the car on end).
	part.PivotOffset = part.CFrame:ToObjectSpace(origin)
	noteMaps(part)
	part.Parent = parent
end

local function light(parent: BasePart, at: Vector3, kind: string, props: { [string]: any })
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = at
	attachment.Parent = parent
	local l = Instance.new(kind)
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = attachment
	return l
end

local car = Instance.new("Model")
car.Name = "Car"
-- The wheels: a model each, on its axle (the tyre's middle).
for _, key in { "FL", "FR", "RL", "RR" } do
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel" .. key
	local tire = mesh("CarTire" .. key)
	for piece, look in WHEEL do
		file(mesh("Car" .. piece .. key), look, wheel)
	end
	wheel.WorldPivot = CFrame.new(tire.Position)
	wheel:SetAttribute("Radius", tire.Size.Y / 2)
	wheel.Parent = car
end
for _, part in imported:GetDescendants() do
	if
		part:IsA("MeshPart")
		and part.Name:sub(1, 5) ~= "Mark_"
		and part.Parent ~= nil
		and not part:IsDescendantOf(car)
	then
		file(part, FLAT[part.Name], car)
	end
end
car.PrimaryPart = car:FindFirstChild("CarPaint") :: BasePart
-- Its lights: the headlights down the road (and a glow round them), the tail lights' red.
local white = car:FindFirstChild("LightWhite") :: BasePart
local red = car:FindFirstChild("LightRed") :: BasePart
for _, side in { "L", "R" } do
	local head = mesh("Mark_Head" .. side).Position
	local beam = light(white, head, "SpotLight", {
		Range = 60,
		Brightness = 2.4,
		Angle = 55,
		Color = Color3.fromRGB(255, 226, 170),
		Face = Enum.NormalId.Front,
		Shadows = true,
	})
	beam.Parent.Name = "Headlight"
	light(
		white,
		head,
		"PointLight",
		{ Range = 7, Brightness = 1.2, Color = Color3.fromRGB(255, 220, 160), Shadows = false }
	)
	light(red, mesh("Mark_Tail" .. side).Position, "PointLight", {
		Range = 6,
		Brightness = 1.4,
		Color = Color3.fromRGB(255, 40, 30),
		Shadows = false,
	})
end
for _, name in { "Mark_Origin", "Mark_HeadL", "Mark_HeadR", "Mark_TailL", "Mark_TailR" } do
	mesh(name):Destroy()
end
car.WorldPivot = origin

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local vehicles = assets:FindFirstChild("Vehicles") or Instance.new("Folder")
vehicles.Name = "Vehicles"
vehicles.Parent = assets
local old = vehicles:FindFirstChild("Car")
if old then
	old:Destroy()
end
car.Parent = vehicles
imported:Destroy()
print("[setup_car] the car is ready at ReplicatedStorage.Assets.Vehicles.Car")
