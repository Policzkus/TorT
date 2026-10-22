--!strict
-- MeshParts built from Config/Meshes. MeshIds can't be set from scripts, so the server creates
-- each one once at boot (AssetService:CreateMeshPartAsync) and parks the templates in
-- ReplicatedStorage.MeshTemplates, where the server and the clients clone them.
-- get() returns nil for a mesh that isn't (yet) available: callers fall back to a part-built version.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Meshes = require(script.Parent.Parent.Config.Meshes)

local FOLDER_NAME = "MeshTemplates"

local MeshLibrary = {}

local pending = 0
local started = false

local function folder(): Folder?
	return ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
end

-- Server only: create every template.
function MeshLibrary.preload()
	if started or not RunService:IsServer() then
		return
	end
	started = true
	local templates = Instance.new("Folder")
	templates.Name = FOLDER_NAME
	templates.Parent = ReplicatedStorage
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
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Parent = templates
			else
				warn(`[Meshes] '{name}' failed to load, using the part-built fallback: {part}`)
			end
			pending -= 1
		end)
	end
end

-- Yields until the templates are ready (server: loading finished; client: the folder exists).
function MeshLibrary.waitReady(timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	if RunService:IsServer() then
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	else
		ReplicatedStorage:WaitForChild(FOLDER_NAME, math.max(0, deadline - os.clock()))
	end
end

-- A fresh copy of the named mesh, or nil.
function MeshLibrary.get(name: string): MeshPart?
	local templates = folder()
	local template = templates and templates:FindFirstChild(name)
	return if template and template:IsA("MeshPart") then template:Clone() else nil
end

return MeshLibrary
