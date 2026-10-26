-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/lobby/Lobby.fbx with
-- File > Import 3D (into Workspace). Files the lobby's pieces (art/scripts/lobby.py) under
-- ReplicatedStorage.Assets.Lobby: the party bus (World/Lobby parks four of them round the
-- turnaround, Services/PartyService seats the party in them) and the cast-iron street lamp. Save
-- the place afterwards.
--
-- Each piece was modelled at a Blender origin marked by Mark_Origin / Mark_LampOrigin; its pivot
-- goes back there, front toward -Z, so that Blender (x, y, z) is (-x, z, y) in its frame.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Lobby")
assert(imported and imported:IsA("Model"), "Import Lobby.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end
local function bottomOf(marker: MeshPart): CFrame
	assert(marker.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), "expected the import to keep the meshes unrotated")
	return CFrame.new(marker.Position - Vector3.new(0, marker.Size.Y / 2, 0))
end
local busOrigin = bottomOf(mesh("Mark_Origin"))
local lampOrigin = bottomOf(mesh("Mark_LampOrigin"))

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
	BusGlass = { Material = Enum.Material.Glass, Color = Color3.fromRGB(28, 32, 34), Transparency = 0.45, CastShadow = false },
	BusTire = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(14, 14, 15) },
	BusRubber = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(10, 10, 11) },
	BusText = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(16, 14, 12) },
	BusWhite = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(200, 196, 182) },
	BusRib = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(96, 92, 80) },
	BusGauge = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(46, 74, 50), CastShadow = false },
	LightWhite = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 226, 170), CastShadow = false },
	LightAmber = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 140, 30), CastShadow = false },
	LightRed = { Material = Enum.Material.Neon, Color = Color3.fromRGB(220, 24, 18), CastShadow = false },
	LampGlow = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 176, 110), CastShadow = false },
	LampIron = { Material = Enum.Material.Metal, Color = Color3.fromRGB(26, 26, 28) },
}

local function file(part: MeshPart, origin: CFrame, parent: Instance)
	assert(part.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), part.Name .. " came in rotated")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.CollisionFidelity = Enum.CollisionFidelity.Box
	part.RenderFidelity = Enum.RenderFidelity.Precise -- the interior is seen up close: no LOD swaps
	for key, value in FLAT[part.Name] or {} do
		(part :: any)[key] = value
	end
	part.PivotOffset = part.CFrame:ToObjectSpace(origin)
	noteMaps(part)
	part.Parent = parent
end

-- A marker becomes an invisible part of that name (where the game puts something).
local function marker(name: string, as: string, parent: Instance): BasePart
	local mark = mesh(name)
	local part = Instance.new("Part")
	part.Name = as
	part.Size = mark.Size
	part.CFrame = mark.CFrame
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Parent = parent
	mark:Destroy()
	return part
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

-- Blender (x, y, z) from a piece's origin, in Roblox.
local function blender(origin: CFrame, x: number, y: number, z: number): Vector3
	return (origin * CFrame.new(-x, z, y)).Position
end

-- The bus.
local bus = Instance.new("Model")
bus.Name = "Bus"
for _, part in imported:GetDescendants() do
	if part:IsA("MeshPart") and (part.Name:sub(1, 3) == "Bus" or part.Name:sub(1, 5) == "Light") then
		file(part, busOrigin, bus)
	end
end
marker("Mark_Door", "Door", bus)
for k = 1, 4 do
	marker("Mark_Seat" .. k, "Seat" .. k, bus)
end
mesh("Mark_Origin"):Destroy()
-- Something solid to bump into from outside (the meshes don't collide).
local collider = Instance.new("Part")
collider.Name = "Collider"
collider.Size = Vector3.new(10.4, 12, 42.2)
collider.CFrame = busOrigin * CFrame.new(0, 6, -0.7)
collider.Anchored = true
collider.Transparency = 1
collider.CanQuery = false
collider.CanTouch = false
collider.Parent = bus
-- Its lights: the headlights down the road, the bare bulbs inside.
local lightsWhite = bus:FindFirstChild("LightWhite") :: BasePart
for _, x in { -2.75, 2.75 } do
	local beam = light(lightsWhite, blender(busOrigin, x, -21.2, 4.85), "SpotLight", {
		Range = 34,
		Brightness = 1.6,
		Angle = 70,
		Color = Color3.fromRGB(255, 226, 170),
		Face = Enum.NormalId.Front,
		Shadows = true,
	})
	beam.Parent.Name = "Headlight"
end
for _, y in { -6.5, 2.0, 10.5 } do
	local bulb = light(lightsWhite, blender(busOrigin, 0, y, 11.1), "PointLight", {
		Range = 15,
		Brightness = 1.8,
		Color = Color3.fromRGB(255, 214, 150),
		Shadows = false, -- (with shadows, your own body darkens the seat in front of you)
	})
	bulb.Parent.Name = "Bulb"
end
bus.WorldPivot = busOrigin

-- The street lamp.
local lamp = Instance.new("Model")
lamp.Name = "Lamp"
for _, name in { "LampIron", "LampGlow" } do
	file(mesh(name), lampOrigin, lamp)
end
local lit = mesh("Mark_LampLight").Position
mesh("Mark_LampLight"):Destroy()
mesh("Mark_LampOrigin"):Destroy()
local glow = lamp:FindFirstChild("LampGlow") :: BasePart
light(glow, lit, "PointLight", { Range = 32, Brightness = 1.4, Color = Color3.fromRGB(255, 190, 130), Shadows = true })
CollectionService:AddTag(glow, "StreetLamp")
local post = Instance.new("Part")
post.Name = "Post" -- something to bump into
post.Size = Vector3.new(1.4, 14, 1.4)
post.CFrame = lampOrigin * CFrame.new(0, 7, 0)
post.Anchored = true
post.Transparency = 1
post.CanQuery = false
post.CanTouch = false
post.Parent = lamp
lamp.WorldPivot = lampOrigin

local folder = Instance.new("Folder")
folder.Name = "Lobby"
bus.Parent = folder
lamp.Parent = folder
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local old = assets:FindFirstChild("Lobby")
if old then
	old:Destroy()
end
folder.Parent = assets
imported:Destroy()
print("[setup_lobby] the bus and the lamp are ready at ReplicatedStorage.Assets.Lobby")
