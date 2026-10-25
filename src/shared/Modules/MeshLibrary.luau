--!strict
-- MeshParts built from Config/Meshes and Config/Characters. MeshIds can't be set from scripts, so
-- the server creates each one once at boot (AssetService:CreateMeshPartAsync) and parks the
-- templates in ReplicatedStorage.MeshTemplates, where the server and the clients clone them.
-- get() returns nil for a mesh that isn't (yet) available: callers fall back to a part-built version.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Characters = require(script.Parent.Parent.Config.Characters)
local Meshes = require(script.Parent.Parent.Config.Meshes)

local FOLDER_NAME = "MeshTemplates"

export type Group = "World" | "Characters"

-- Every mesh to load, by group: "World" is Config/Meshes (needed before the streets are built),
-- "Characters" is each character segment (as Char_<id>_<segment>, the name Modules/CharacterRig
-- asks for; needed before anyone spawns).
local function allMeshes(): { [Group]: { [string]: Meshes.Mesh } }
	local characters: { [string]: Meshes.Mesh } = {}
	for characterId, character in Characters do
		if character.pivots then
			continue -- a Blender homeowner: its meshes are imported assets (Assets.Characters)
		end
		for segment, seg in character.segments do
			local mesh, texture = seg.mesh, seg.texture
			if mesh and texture then
				characters[`Char_{characterId}_{segment}`] =
					{ mesh = mesh, texture = texture, size = seg.size, collision = "Box" }
			end
		end
	end
	return { World = Meshes, Characters = characters }
end

local MeshLibrary = {}

local pending: { [Group]: number } = { World = 0, Characters = 0 }
local started = false

local function folder(): Folder?
	return ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
end

local function load(templates: Folder, group: Group, name: string, cfg: Meshes.Mesh)
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(`rbxassetid://{cfg.mesh}`, {
			CollisionFidelity = (Enum.CollisionFidelity :: any)[cfg.collision or "Default"],
		})
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
	pending[group] -= 1
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
	for group, meshes in allMeshes() do
		for name, cfg in meshes do
			pending[group] += 1
			task.spawn(load, templates, group, name, cfg)
		end
	end
end

-- Yields until the templates are ready (server: that group, or everything, finished loading;
-- client: the folder exists).
function MeshLibrary.waitReady(timeout: number?, group: Group?)
	local deadline = os.clock() + (timeout or 10)
	if RunService:IsServer() then
		local function loading(): boolean
			if group then
				return pending[group] > 0
			end
			return pending.World + pending.Characters > 0
		end
		while loading() and os.clock() < deadline do
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
