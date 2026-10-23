-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/decor/Decor.fbx with
-- File > Import 3D (into Workspace). Files the Halloween decorations (art/scripts/decor.py) under
-- ReplicatedStorage.Assets.Decor, where HouseVisualController hangs them on Decorated houses at the
-- house's DecorAnchors (tools/setup_victorian.luau). Save the place afterwards.
--
-- Every piece was modelled at one Blender origin; each model's pivot goes back there, facing the
-- street (-Z), so that, like the house and the yard, Blender (x, y, z) is (-x, z, y) in its frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Decor")
assert(imported and imported:IsA("Model"), "Import Decor.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end

-- The garland's wire runs between hooks at x = ±1.7, z = 0 (its top is the wire's radius above),
-- and it's symmetric across the wire, so its box centre sits right under the origin.
local wire = mesh("Garland")
local cf, size = wire.CFrame, wire.Size
assert(cf.Rotation:FuzzyEq(CFrame.identity, 1e-3), "expected the import to keep the meshes unrotated")
assert(math.abs(size.X - 3.47) < 0.1, "the garland should run along X")
local origin = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 - 0.035, 0))

local function file(part: MeshPart, props: { [string]: any })
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	for key, value in props do
		(part :: any)[key] = value
	end
	part.PivotOffset = part.CFrame:ToObjectSpace(origin)
end
local function group(name: string, parts: { MeshPart }): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, part in parts do
		part.Parent = model
	end
	model.WorldPivot = origin
	return model
end

local folder = Instance.new("Folder")
folder.Name = "Decor"

file(wire, { Material = Enum.Material.Metal, Color = Color3.fromRGB(20, 20, 22), CastShadow = false })
local bulbs = {
	BulbsA = Color3.fromRGB(255, 120, 20), -- orange
	BulbsB = Color3.fromRGB(150, 70, 255), -- purple
	BulbsC = Color3.fromRGB(110, 255, 70), -- green
}
local garlandParts = { wire }
for name, color in bulbs do
	local part = mesh(name)
	file(part, { Material = Enum.Material.Neon, Color = color, CastShadow = false })
	table.insert(garlandParts, part)
end
local glow = Instance.new("PointLight")
glow.Range, glow.Brightness, glow.Color, glow.Shadows = 9, 0.5, Color3.fromRGB(255, 150, 90), false
glow.Parent = wire
group("Garland", garlandParts).Parent = folder

local pile = mesh("PumpkinPile")
file(pile, { CastShadow = true })
local inner = mesh("PumpkinPileGlow")
file(inner, { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 130, 40), Transparency = 0.1, CastShadow = false })
-- HouseVisualController flickers lights held by something named "PumpkinLight".
local candle = Instance.new("Attachment")
candle.Name = "PumpkinLight"
candle.Parent = inner
local light = Instance.new("PointLight")
light.Range, light.Brightness, light.Color, light.Shadows = 12, 1.2, Color3.fromRGB(255, 130, 50), false
light.Parent = candle
group("PumpkinPile", { pile, inner }).Parent = folder

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local old = assets:FindFirstChild("Decor")
if old then
	old:Destroy()
end
folder.Parent = assets
imported:Destroy()
print("[setup_decor] decorations ready at ReplicatedStorage.Assets.Decor")
