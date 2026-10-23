-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/yard/Yard.fbx with
-- File > Import 3D (into Workspace). Files the yard set (art/scripts/yard.py) under
-- ReplicatedStorage.Assets.Yard, where World/HouseStyles/Victorian.dressLot places it per lot.
-- Save the place afterwards (Assets aren't in Rojo).
--
-- Every piece was modelled at the same Blender origin (on the ground, fence line along X, street
-- toward -Y). Each piece's pivot is put back on that origin, facing the street (-Z), so that, like
-- the house, Blender (x, y, z) is (-x, z, y) in the pivot's frame. FencePanel pivots on its middle
-- instead (Blender x = 2), so the game can stretch it to fit a run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Yard")
assert(imported and imported:IsA("Model"), "Import Yard.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end

-- The fence post stands centred on the origin, 5.45 studs tall from the ground.
local post = mesh("FencePost")
local up = post.CFrame:VectorToWorldSpace(Vector3.yAxis)
assert(math.abs(up.Y) > 0.99, "expected the import to keep Y up")
local origin = CFrame.new(post.Position - Vector3.new(0, post.Size.Y / 2, 0))

-- Which way is Blender +X in the world? The fence panel runs from x = 0 to 4, centred on the
-- fence line.
local panel = mesh("FencePanel")
local blenderX = (panel.Position - origin.Position) * Vector3.new(1, 0, 1)
assert(math.abs(blenderX.Magnitude - 2) < 0.05, "fence panel should sit 2 studs from the post")
blenderX = blenderX.Unit
-- Pivot frame: RightVector = Blender -X, UpVector = Y, LookVector (street) = Blender -Y.
local right = -blenderX
local look = Vector3.yAxis:Cross(right) -- right = look x up  =>  look = up x right
origin = CFrame.fromMatrix(origin.Position, right, Vector3.yAxis, -look)

local folder = Instance.new("Folder")
folder.Name = "Yard"

local function file(part: MeshPart, pivot: CFrame, collide: boolean)
	part.Anchored = true
	part.CanCollide = collide
	part.CanTouch = false
	part.CanQuery = collide
	part.CastShadow = true
	part.CollisionFidelity = Enum.CollisionFidelity.Box
	part.PivotOffset = part.CFrame:ToObjectSpace(pivot)
end

-- The panel: pivot in its middle, and which of its own axes runs along the fence.
file(panel, origin * CFrame.new(-2, 0, 0), false)
local along = panel.CFrame:VectorToObjectSpace(blenderX)
panel:SetAttribute("StretchAxis", Vector3.new(math.abs(along.X), math.abs(along.Y), math.abs(along.Z)))
panel:SetAttribute("Length", 4)
panel.Parent = folder

for _, name in { "FencePost", "Gate", "Tree", "Tree2", "Flag1", "Flag2" } do
	local part = mesh(name)
	file(part, origin, false)
	part.Parent = folder
end
for _, name in { "Pillar", "Grave1", "Grave2" } do
	local part = mesh(name)
	file(part, origin, true)
	part.Parent = folder
end

-- The mailbox and its post travel together.
local mailbox = Instance.new("Model")
mailbox.Name = "Mailbox"
local box, mailPost = mesh("Mailbox"), mesh("MailboxPost")
file(box, origin, false)
file(mailPost, origin, true)
box.Parent = mailbox
mailPost.Parent = mailbox
mailbox.WorldPivot = origin
mailbox.Parent = folder

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local old = assets:FindFirstChild("Yard")
if old then
	old:Destroy()
end
folder.Parent = assets
imported:Destroy()
print("[setup_yard] yard set ready at ReplicatedStorage.Assets.Yard")
