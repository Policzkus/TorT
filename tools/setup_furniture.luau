-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/furniture/Furniture.fbx
-- with File > Import 3D (into Workspace). Files the furniture (art/scripts/furniture.py) under
-- ReplicatedStorage.Assets.Furniture, where World/BlenderLot.furnish puts a layout of it in every
-- room of the Blender houses (Config/RoomLayouts). Save the place afterwards.
--
-- Every piece was modelled at one Blender origin, standing on the floor and facing -Y (the room's
-- window); each piece's pivot goes back there, facing the street (-Z), so that, like the houses,
-- Blender (x, y, z) is (-x, z, y) in its frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Furniture")
assert(imported and imported:IsA("Model"), "Import Furniture.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end

-- The rug is a flat slab centred on the origin, lying on the floor.
local rug = mesh("Rug")
assert(rug.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), "expected the import to keep the meshes unrotated")
local origin = CFrame.new(rug.Position - Vector3.new(0, rug.Size.Y / 2, 0))
-- The table is centred on it too, its legs on the floor.
local table_ = mesh("Table")
local off = table_.Position - origin.Position
assert(math.abs(off.X) < 0.05 and math.abs(off.Z) < 0.05, "the table should stand on the rug's centre")
assert(math.abs(table_.Position.Y - table_.Size.Y / 2 - origin.Y) < 0.05, "the table should stand on the floor")

-- The SurfaceAppearance's texture ids, written on the part as "Maps": a game script can't read them
-- and PreloadAsync skips them, so the loading screen (LoadingController) downloads them from this.
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

local folder = Instance.new("Folder")
folder.Name = "Furniture"
local count = 0
for _, part in imported:GetDescendants() do
	if not part:IsA("MeshPart") then
		continue
	end
	assert(part.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), part.Name .. " came in rotated")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.CollisionFidelity = Enum.CollisionFidelity.Box
	part.PivotOffset = part.CFrame:ToObjectSpace(origin)
	noteMaps(part)
	part.Parent = folder
	count += 1
end

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local old = assets:FindFirstChild("Furniture")
if old then
	old:Destroy()
end
folder.Parent = assets
imported:Destroy()
print(("[setup_furniture] %d pieces ready at ReplicatedStorage.Assets.Furniture"):format(count))
