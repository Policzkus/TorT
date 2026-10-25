-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/characters/Homeowners.fbx
-- with File > Import 3D (into Workspace). Files the Blender homeowners' meshes (art/scripts/characters.py)
-- under ReplicatedStorage.Assets.Characters, where Modules/CharacterRig finds them; Config/CharacterModels
-- has their part sizes, offsets and joints. Save the place afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterModels = require(ReplicatedStorage.Shared.Config.CharacterModels) :: any

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

local imported = workspace:FindFirstChild("Homeowners")
assert(imported and imported:IsA("Model"), "Import Homeowners.fbx into Workspace first")

local folder = Instance.new("Folder")
folder.Name = "Characters"
local count = 0
local problems = {}
for id, def in CharacterModels do
	for segment, seg in def.segments do
		local name = `Char_{id}_{segment}`
		local part = imported:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			table.insert(problems, "missing " .. name)
			continue
		end
		-- The rig sizes every part from Config/CharacterModels: the import should already match.
		local want = Vector3.new(seg.size[1], seg.size[2], seg.size[3])
		if (part.Size - want).Magnitude > 0.1 then
			table.insert(problems, `{name} is {part.Size}, expected {want}`)
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = true
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		part.RenderFidelity = Enum.RenderFidelity.Precise -- always the full mesh: they're seen up close
		noteMaps(part)
		part.Parent = folder
		count += 1
	end
end

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local old = assets:FindFirstChild("Characters")
if old then
	old:Destroy()
end
folder.Parent = assets
imported:Destroy()
print(("[setup_characters] %d meshes ready at ReplicatedStorage.Assets.Characters"):format(count))
for _, problem in problems do
	warn("[setup_characters] " .. problem)
end
