--!strict
-- Builds a playable character from Config/Characters (PROMPT §V2.3: nobody plays as their Roblox
-- avatar). The six AI mesh segments are the body parts, with R6 names so code looking for "Torso" or
-- "Right Arm" keeps working, joined by Motor6Ds at the neck, shoulders and hips.
-- CharacterAnimController animates them. The Humanoid uses the R15 rig type, so HipHeight puts the
-- feet on the ground whatever the proportions.

local CollectionService = game:GetService("CollectionService")

local Characters = require(script.Parent.Parent.Config.Characters)
local MeshLibrary = require(script.Parent.MeshLibrary)

local CharacterRig = {}

CharacterRig.TAG = "TorTRig"

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

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

function CharacterRig.meshName(characterId: string, segment: string): string
	return `Char_{characterId}_{segment}`
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

-- A new rig with its feet at the origin, facing -Z. Nil when the meshes aren't loaded.
-- `preview` builds a static, anchored copy (for ViewportFrames) without a Humanoid.
function CharacterRig.build(characterId: string, preview: boolean?): Model?
	local def = Characters[characterId]
	if def == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = characterId
	local parts: { [string]: BasePart } = {}
	for segment, partName in PART_NAMES do
		local seg = def.segments[segment]
		local part = if seg then MeshLibrary.get(CharacterRig.meshName(characterId, segment)) else nil
		if seg == nil or part == nil then
			model:Destroy()
			return nil
		end
		part.Name = partName
		part.Size = vector(seg.size)
		part.CFrame = CFrame.new(vector(seg.offset))
		part.Anchored = preview == true
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = not preview
		part.CanQuery = not preview
		part.Parent = model
		parts[segment] = part
	end
	if preview then
		model.WorldPivot = CFrame.identity -- between the feet, so it turns in place
		return model
	end

	local head, torso = parts.Head, parts.Torso
	local hip = math.max(top(parts.LeftLeg), top(parts.RightLeg))
	local eye = def.eye or (head.Position.Y + head.Size.Y * 0.1)
	-- The root is the collision box from the hips to just below the eyes.
	local rootHeight = math.max(1, eye - hip - 0.4)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(math.clamp(torso.Size.X, 1.4, 2.6), rootHeight, ROOT_DEPTH)
	root.CFrame = CFrame.new(0, hip + rootHeight / 2, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	joint("RootJoint", root, torso, Vector3.new(0, hip, 0))
	joint("Neck", torso, head, head.Position - Vector3.new(0, head.Size.Y / 2, 0))
	for _, side in { "Left", "Right" } do
		local arm = parts[side .. "Arm"]
		local leg = parts[side .. "Leg"]
		local shoulder = top(arm) - math.min(0.3, arm.Size.Y * 0.12)
		joint(side .. " Shoulder", torso, arm, Vector3.new(arm.Position.X, shoulder, arm.Position.Z))
		joint(side .. " Hip", torso, leg, Vector3.new(leg.Position.X, top(leg), leg.Position.Z))
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

	model:SetAttribute("CharacterId", characterId)
	CollectionService:AddTag(model, CharacterRig.TAG)
	return model
end

return CharacterRig
