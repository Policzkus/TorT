-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/knife/Knife.fbx with
-- File > Import 3D (into Workspace). Files the knife (art/scripts/knife.py) as
-- ReplicatedStorage.Assets.Props.Knife: a model whose pivot is the middle of the grip (Mark_Grip),
-- the blade up +Y, its edge toward -Z, every piece welded to an invisible "Grip" part, unanchored and
-- weightless, so KniferService can weld a copy into his hand. Save the place afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local imported = workspace:FindFirstChild("Knife")
assert(imported and imported:IsA("Model"), "Import Knife.fbx into Workspace first")
local function mesh(name: string): MeshPart
	return assert(imported:FindFirstChild(name, true) :: MeshPart?, "no " .. name .. " mesh")
end
local mark = mesh("Mark_Grip")
assert(mark.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), "expected the import to keep the meshes unrotated")
local origin = CFrame.new(mark.Position)

-- The pieces Blender left plain: their look is set here.
local FLAT: { [string]: { [string]: any } } = {
	KnifeDark = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(58, 12, 10) }, -- the used edge
	KnifeRivet = { Material = Enum.Material.Metal, Color = Color3.fromRGB(150, 108, 46) },
}

local knife = Instance.new("Model")
knife.Name = "Knife"
local grip = Instance.new("Part")
grip.Name = "Grip"
grip.Size = Vector3.new(0.1, 0.1, 0.1)
grip.CFrame = origin
grip.Transparency = 1
grip.Parent = knife
knife.PrimaryPart = grip
for _, part in imported:GetDescendants() do
	if part:IsA("MeshPart") and part.Name:sub(1, 5) == "Knife" then
		assert(part.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-3), part.Name .. " came in rotated")
		for key, value in FLAT[part.Name] or {} do
			(part :: any)[key] = value
		end
		part.Parent = knife
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = grip
		weld.Part1 = part
		weld.Parent = part
	end
end
for _, part in knife:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = part.Name ~= "Grip"
		part.PivotOffset = part.CFrame:ToObjectSpace(origin)
	end
end
knife.WorldPivot = origin

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local props = assets:FindFirstChild("Props") or Instance.new("Folder")
props.Name = "Props"
props.Parent = assets
local old = props:FindFirstChild("Knife")
if old then
	old:Destroy()
end
knife.Parent = props
imported:Destroy()
print("[setup_knife] the knife is ready at ReplicatedStorage.Assets.Props.Knife")
