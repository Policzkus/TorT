--!strict
-- Server-side cache of MeshParts built from Config/Meshes (AssetService:CreateMeshPartAsync).
-- MeshIds can't be set from scripts, so each mesh is created once at boot and cloned after that.
-- get() returns nil for a mesh that failed to load: callers fall back to their part-built version.

local AssetService = game:GetService("AssetService")

local Meshes = require(script.Parent.Parent.Config.Meshes)

local MeshLibrary = {}

local templates: { [string]: MeshPart } = {}
local pending = 0
local started = false

function MeshLibrary.preload()
	if started then
		return
	end
	started = true
	for name, cfg in Meshes do
		pending += 1
		task.spawn(function()
			local ok, part = pcall(function()
				return AssetService:CreateMeshPartAsync(`rbxassetid://{cfg.mesh}`)
			end)
			if ok and part then
				part.Name = name
				part.TextureID = `rbxassetid://{cfg.texture}`
				part.Size = Vector3.new(cfg.size[1], cfg.size[2], cfg.size[3])
				templates[name] = part
			else
				warn(`[Meshes] '{name}' failed to load, using the part-built fallback: {part}`)
			end
			pending -= 1
		end)
	end
end

-- Yields until every mesh has finished loading (or `timeout` seconds pass).
function MeshLibrary.waitReady(timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- A fresh copy of the named mesh, or nil.
function MeshLibrary.get(name: string): MeshPart?
	local template = templates[name]
	return if template then template:Clone() else nil
end

return MeshLibrary
