--!strict
-- Builds a character from Config/Characters (PROMPT §V2.3: nobody plays as their Roblox avatar). The
-- six AI mesh segments are the body parts, with R6 names so code looking for "Torso" or "Right Arm"
-- keeps working, joined by Motor6Ds at the neck, shoulders and hips.
-- Modes:
--   "player"  - a Humanoid rig for a player (CharacterAnimController animates it). The Humanoid uses
--               the R15 rig type, so HipHeight puts the feet on the ground whatever the proportions.
--   "preview" - a static, anchored copy for ViewportFrames.
--   "puppet"  - joints but no Humanoid, root anchored: a client-side figure that code poses by
--               moving the root and setting Motor6D.Transform (the homeowners).
-- A Morph (puppets) stretches the body: the uncanny long limbs and wrong-sized heads.
-- The Blender homeowners (Config/CharacterModels) come from ReplicatedStorage.Assets.Characters,
-- joined at the pivots they were modelled with, and never morphed: they look as they were made.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(script.Parent.Parent.Config.Characters)
local MeshLibrary = require(script.Parent.MeshLibrary)

local CharacterRig = {}

CharacterRig.TAG = "TorTRig"

export type Mode = "player" | "preview" | "puppet"

export type Morph = {
	scale: number?, -- everything
	stretch: number?, -- legs and torso taller
	arms: number?, -- arm length (they hang lower)
	head: number?, -- head size
	thin: number?, -- body and limb thickness
	neck: number?, -- studs of extra neck
}

local PART_NAMES: { [string]: string } = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

-- Default Roblox camera: the eye sits this far above the root part's centre (no automatic scaling).
local CAMERA_HEAD_OFFSET = 2
local ROOT_DEPTH = 1

type Shape = { size: Vector3, offset: Vector3 }

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

function CharacterRig.meshName(characterId: string, segment: string): string
	return `Char_{characterId}_{segment}`
end

-- An imported Blender homeowner mesh (tools/setup_characters.luau), or nil.
local function blenderMesh(name: string): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Characters")
	local found = folder and folder:FindFirstChild(name)
	return if found and found:IsA("MeshPart") then found else nil
end

local function fromBlender(characterId: string, def: Characters.Character): boolean
	if def.pivots == nil then
		return false
	end
	for segment in PART_NAMES do
		if blenderMesh(CharacterRig.meshName(characterId, segment)) == nil then
			return false
		end
	end
	return true
end

-- Whether build can make this character now (a Blender one needs its meshes imported).
function CharacterRig.ready(characterId: string): boolean
	local def = Characters[characterId]
	if def == nil then
		return false
	end
	return def.pivots == nil or fromBlender(characterId, def)
end

local function joint(name: string, part0: BasePart, part1: BasePart, pivot: Vector3)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:ToObjectSpace(CFrame.new(pivot))
	motor.C1 = part1.CFrame:ToObjectSpace(CFrame.new(pivot))
	motor.Parent = part0
end

local function top(part: BasePart): number
	return part.Position.Y + part.Size.Y / 2
end

-- Segment sizes and offsets after a morph (feet stay at the origin).
local function morphed(def: Characters.Character, morph: Morph?): { [string]: Shape }
	local shapes: { [string]: Shape } = {}
	for segment, seg in def.segments do
		shapes[segment] = { size = vector(seg.size), offset = vector(seg.offset) }
	end
	if morph == nil then
		return shapes
	end
	local stretch = morph.stretch or 1
	local arms = morph.arms or 1
	local headScale = morph.head or 1
	local thin = morph.thin or 1
	local neck = morph.neck or 0
	local scale = morph.scale or 1
	for segment, shape in shapes do
		local size, offset = shape.size, shape.offset
		if segment == "Head" then
			local bottom = (offset.Y - size.Y / 2) * stretch + neck
			size *= headScale
			offset = Vector3.new(offset.X, bottom + size.Y / 2, offset.Z)
		else
			local topY = (offset.Y + size.Y / 2) * stretch
			local length = size.Y * stretch * (if segment == "LeftArm" or segment == "RightArm" then arms else 1)
			size = Vector3.new(size.X * thin, length, size.Z * thin)
			local x = if segment == "Torso" then offset.X else offset.X * (0.35 + 0.65 * thin)
			offset = Vector3.new(x, topY - length / 2, offset.Z)
			if segment == "LeftLeg" or segment == "RightLeg" then
				offset = Vector3.new(x, length / 2, offset.Z) -- legs always reach the ground
			end
		end
		shape.size = size * scale
		shape.offset = offset * scale
	end
	return shapes
end

-- A new character with its feet at the origin, facing -Z. Nil when the meshes aren't loaded.
function CharacterRig.build(characterId: string, mode: Mode?, morph: Morph?): Model?
	local def = Characters[characterId]
	if def == nil then
		return nil
	end
	local blender = fromBlender(characterId, def)
	if def.pivots and not blender then
		return nil -- its meshes aren't in the place
	end
	if blender then
		morph = nil
	end
	local kind: Mode = mode or "player"
	local shapes = morphed(def, morph)
	local model = Instance.new("Model")
	model.Name = characterId
	local parts: { [string]: BasePart } = {}
	for segment, partName in PART_NAMES do
		local shape = shapes[segment]
		local name = CharacterRig.meshName(characterId, segment)
		local template = if blender then blenderMesh(name) else nil
		local part = if shape == nil then nil elseif template then template:Clone() else MeshLibrary.get(name)
		if shape == nil or part == nil then
			model:Destroy()
			return nil
		end
		part.Name = partName
		part.Size = shape.size
		part.CFrame = CFrame.new(shape.offset)
		part.Anchored = kind == "preview"
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = kind == "player"
		part.CanQuery = kind == "player"
		part.Parent = model
		parts[segment] = part
	end
	if kind == "preview" then
		model.WorldPivot = CFrame.identity -- between the feet, so it turns in place
		return model
	end

	local head, torso = parts.Head, parts.Torso
	local hip = math.max(top(parts.LeftLeg), top(parts.RightLeg))
	local eye = if def.eye and morph == nil then def.eye else head.Position.Y + head.Size.Y * 0.1
	-- The root is the collision box from the hips to just below the eyes.
	local rootHeight = math.max(1, eye - hip - 0.4)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(math.clamp(torso.Size.X, 1.4, 2.6), rootHeight, ROOT_DEPTH)
	root.CFrame = CFrame.new(0, hip + rootHeight / 2, 0)
	root.Transparency = 1
	root.CanCollide = kind == "player"
	root.CanQuery = kind == "player"
	root.CanTouch = false
	root.Anchored = kind == "puppet"
	root.Parent = model
	model.PrimaryPart = root

	-- Where the face is, for whatever looks at it (dialogue, the doorstep camera, the jumpscare).
	if blender and def.face then
		local face = Instance.new("Attachment")
		face.Name = "Face"
		face.Position = head.CFrame:PointToObjectSpace(vector(def.face))
		face.Parent = head
	end
	-- Where the parts bend: the Blender homeowners say; otherwise from the parts' bounds.
	local pivots = if blender then def.pivots else nil
	local function pivot(name: string, default: Vector3): Vector3
		local at = pivots and pivots[name]
		return if at then vector(at) else default
	end
	joint("RootJoint", root, torso, Vector3.new(0, hip, 0))
	joint("Neck", torso, head, pivot("Neck", head.Position - Vector3.new(0, head.Size.Y / 2, 0)))
	for _, side in { "Left", "Right" } do
		local arm = parts[side .. "Arm"]
		local leg = parts[side .. "Leg"]
		local shoulder = top(arm) - math.min(0.3, arm.Size.Y * 0.12)
		joint(
			side .. " Shoulder",
			torso,
			arm,
			pivot(side .. "Shoulder", Vector3.new(arm.Position.X, shoulder, arm.Position.Z))
		)
		joint(side .. " Hip", torso, leg, pivot(side .. "Hip", Vector3.new(leg.Position.X, top(leg), leg.Position.Z)))
	end
	model:SetAttribute("CharacterId", characterId)
	model:SetAttribute("Height", top(head))
	if kind == "puppet" then
		model.WorldPivot = CFrame.identity
		return model
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.HipHeight = hip
	humanoid.CameraOffset = Vector3.new(0, eye - (root.Position.Y + CAMERA_HEAD_OFFSET), 0)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	CollectionService:AddTag(model, CharacterRig.TAG)
	return model
end

return CharacterRig
