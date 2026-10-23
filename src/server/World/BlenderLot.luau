--!strict
-- Dresses the lot around a Blender house model from its data (HouseData/<Style>.luau, written by
-- art/scripts/housekit.py, or a table in the same shape): a dead lawn, stepping stones from the
-- steps to the gate, a fence of the yard set's pieces (wrought iron or rotten pickets) with a double
-- gate standing open, a dead tree, a mailbox, graves; then it lights a few of the house's rooms and
-- keeps at most one of its figures. Works in the lot's frame (x across, -z toward the street),
-- where Blender x runs the other way.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local HouseData = require(script.Parent.HouseData.Types)
local Parts = require(script.Parent.Parts)

local BlenderLot = {}

type Fence = {
	panel: string,
	post: string,
	pillar: string,
	gate: string,
	pillarAt: number,
	pillarHalf: number,
	height: number,
}

-- pillarAt: the gate's posts' centres beyond the gate's edges; pillarHalf: where the fence starts.
local FENCES: { [string]: Fence } = {
	Iron = {
		panel = "FencePanel",
		post = "FencePost",
		pillar = "Pillar",
		gate = "GateLeaf",
		pillarAt = 0.85,
		pillarHalf = 0.75,
		height = 4.6,
	},
	Picket = {
		panel = "PicketPanel",
		post = "PicketPost",
		pillar = "PicketPost",
		gate = "PicketGate",
		pillarAt = 0.3,
		pillarHalf = 0.25,
		height = 4.2,
	},
}
local OTHER_PIECES = { "Tree", "Tree2", "Mailbox", "Grave1", "Grave2", "Flag1", "Flag2" }
local GATE_WIDTH = 4.4

-- Every room's light: a lamp, candlelight or a bare bulb.
local ROOM_LIGHTS = {
	Color3.fromRGB(255, 176, 104),
	Color3.fromRGB(255, 150, 80),
	Color3.fromRGB(236, 226, 196),
}

-- The yard set, if it's been imported with everything this fence needs.
function BlenderLot.yardSet(fence: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local set = assets and assets:FindFirstChild("Yard")
	local kind = FENCES[fence]
	if set == nil or kind == nil then
		return nil
	end
	for _, name in { kind.panel, kind.post, kind.pillar, kind.gate } do
		if set:FindFirstChild(name) == nil then
			return nil
		end
	end
	for _, name in OTHER_PIECES do
		if set:FindFirstChild(name) == nil then
			return nil
		end
	end
	return set
end

local function hinged(parent: Instance, hingeCF: CFrame, openAngle: number): Model
	local m = Instance.new("Model")
	m.Name = "Gate"
	local hinge = Parts.block(m, "Hinge", Vector3.one * 0.1, hingeCF, "000000", Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	m.PrimaryPart = hinge
	m:SetAttribute("Kind", "Gate")
	m:SetAttribute("OpenAngle", openAngle)
	m:SetAttribute("Openable", true)
	m:SetAttribute("Open", false)
	m.Parent = parent
	CollectionService:AddTag(m, "Hinged")
	return m
end

function BlenderLot.yard(
	house: Model,
	base: CFrame,
	rng: Rng.Rng,
	yardDepth: number,
	lotWidth: number,
	data: HouseData.Data,
	set: Instance
)
	local kind = FENCES[data.yard.fence]
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local function place(name: string, cframe: CFrame, parent: Instance?): PVInstance
		local piece = (set:FindFirstChild(name) :: PVInstance):Clone()
		piece:PivotTo(cframe)
		piece.Parent = parent or house
		return piece
	end
	local function spin(amount: number): CFrame
		return CFrame.Angles(0, rng:range(-amount, amount), 0)
	end
	local function blocker(parent: Instance, size: Vector3, cframe: CFrame, shape: Enum.PartType?): BasePart
		local collider = Parts.block(parent, "Collision", size, cframe, "060607", Enum.Material.SmoothPlastic, {
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		if shape then
			collider.Shape = shape
		end
		return collider
	end
	local doorX = -data.door.x
	local fenceZ = -(yardDepth - 0.6)
	local half = lotWidth / 2 - 1
	local pillarX = GATE_WIDTH / 2 + kind.pillarAt
	local lawn = Parts.decor(
		Parts.block(
			house,
			"Lawn",
			Vector3.new(half * 2, 0.1, yardDepth - 1),
			at(0, 0.06, fenceZ / 2),
			"6B6448",
			Enum.Material.Grass
		)
	)
	lawn.MaterialVariant = "TorT_DeadGrass"

	-- Stepping stones from the steps to the gate.
	local z, i = data.yard.pathFrom, 0
	while z > fenceZ + 0.6 do
		place(
			if i % 2 == 0 then "Flag1" else "Flag2",
			at(doorX + rng:range(-0.3, 0.3), 0.02, z)
				* spin(0.4)
				* CFrame.Angles(0, if i % 2 == 0 then 0 else math.pi, 0)
		)
		z -= 2.1 + rng:range(0.1, 0.4)
		i += 1
	end

	-- The fence: panels stretched to share each run evenly, posts between them.
	local template = set:FindFirstChild(kind.panel) :: MeshPart
	local stretch = template:GetAttribute("StretchAxis") :: Vector3
	local length = template:GetAttribute("Length") :: number
	local function fence(xa: number, xb: number, firstPost: boolean, lastPost: boolean)
		local run = xb - xa
		blocker(house, Vector3.new(run, kind.height, 0.4), at((xa + xb) / 2, kind.height / 2, fenceZ))
		local n = math.max(1, math.floor(run / length + 0.5))
		local w = run / n
		for k = 0, n - 1 do
			-- Turning some panels round keeps the baked wear from repeating.
			local turn = if rng:chance(0.5) then math.pi else 0
			local panel = place(kind.panel, at(xa + (k + 0.5) * w, 0, fenceZ) * CFrame.Angles(0, turn, 0)) :: MeshPart
			panel.Size += panel.Size * stretch * (w / length - 1)
		end
		for k = 0, n do
			if (k > 0 and k < n) or (k == 0 and firstPost) or (k == n and lastPost) then
				place(kind.post, at(xa + k * w, 0, fenceZ) * spin(0.05))
			end
		end
	end
	fence(-half, doorX - pillarX - kind.pillarHalf, true, false) -- no post against the gate's posts
	fence(doorX + pillarX + kind.pillarHalf, half, false, true)
	for _, side in { -1, 1 } do
		place(kind.pillar, at(doorX + side * pillarX, 0, fenceZ) * spin(0.03))
	end
	-- A double gate standing open into the yard; one prompt swings both leaves (HingeService,
	-- Group). The second leaf is the same mesh turned round, so it opens the other way.
	for _, side in { 1, -1 } do
		local hinge = at(doorX + side * GATE_WIDTH / 2, 0, fenceZ)
			* CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
		local gate = hinged(house, hinge, side * 80)
		gate:SetAttribute("Group", "Gate")
		local leaf = place(kind.gate, hinge, gate) :: BasePart
		leaf.Name = "Panel" -- where HingeController plays its creak
		blocker(
			gate,
			Vector3.new(GATE_WIDTH / 2 - 0.2, kind.height - 0.4, 0.3),
			hinge * CFrame.new(-GATE_WIDTH / 4, 2.2, 0)
		)
		if side > 0 then
			Parts.prompt(leaf, "Close", "Gate", 8)
		end
		gate:SetAttribute("Open", true)
	end

	-- A dead tree, a mailbox by the gate, and graves.
	local tree = data.yard.tree
	local treeAt = at(-tree.X, 0, tree.Y)
	place(if rng:chance(0.5) then "Tree" else "Tree2", treeAt * CFrame.Angles(0, rng:range(0, 2 * math.pi), 0))
	blocker(
		house,
		Vector3.new(8, 2, 2),
		treeAt * CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Enum.PartType.Cylinder
	)
	place("Mailbox", at(doorX - pillarX - 1.7, 0, fenceZ + 1.2) * spin(0.15))
	for n, grave in data.yard.graves do
		place(if n % 2 == 1 then "Grave1" else "Grave2", at(-grave.X, 0, grave.Y) * spin(0.3))
	end
end

-- Lights two to four rooms (and the attic sometimes): a glowing bulb under the room's lamp shade
-- and a warm light spilling out through the glass. The rest stay dark until a flashlight finds the
-- furniture. Keeps at most one Figure_<room> mesh, usually in a lit room.
function BlenderLot.roomLights(house: Model, base: CFrame, rng: Rng.Rng, rooms: { HouseData.Room })
	local candidates = {}
	for i, room in rooms do
		if not room.attic then
			table.insert(candidates, i)
		end
	end
	rng:shuffle(candidates)
	local lit: { [string]: boolean } = {}
	for n = 1, math.min(#candidates, rng:int(2, 4)) do
		lit[rooms[candidates[n]].id] = true
	end
	local keep: string? = nil
	local figureRooms = {}
	for _, room in rooms do
		if room.figure then
			table.insert(figureRooms, room)
		end
	end
	rng:shuffle(figureRooms)
	for _, room in figureRooms do
		if lit[room.id] and rng:chance(0.6) then
			keep = room.id
			break
		end
	end
	if keep == nil and #figureRooms > 0 and rng:chance(0.25) then
		keep = figureRooms[1].id -- one left in the dark for the flashlight to find
	end
	for _, room in rooms do
		local figure = house:FindFirstChild("Figure_" .. room.id, true)
		if figure and room.id ~= keep then
			figure:Destroy()
		end
		local isLit = if room.attic then rng:chance(0.4) else lit[room.id] == true
		if isLit then
			local color = rng:pick(ROOM_LIGHTS)
			local bulb = Instance.new("Part")
			bulb.Name = "RoomBulb"
			bulb.Shape = Enum.PartType.Ball
			bulb.Size = Vector3.one * 0.45
			bulb.Material = Enum.Material.Neon
			bulb.Color = color
			bulb.Anchored, bulb.CanCollide, bulb.CanQuery, bulb.CanTouch, bulb.CastShadow =
				true, false, false, false, false
			bulb.CFrame = base * CFrame.new(-room.lamp.X, room.lamp.Z, room.lamp.Y)
			local light = Instance.new("PointLight")
			light.Range = 18
			light.Brightness = 1.4
			light.Color = color
			light.Shadows = true
			light.Parent = bulb
			bulb.Parent = house
		end
	end
end

-- The whole dressing: the yard (when the yard set is there) and the room lights. Returns false
-- when the yard set is missing, so the caller can build a yard of its own.
function BlenderLot.dress(
	house: Model,
	base: CFrame,
	rng: Rng.Rng,
	yardDepth: number,
	lotWidth: number,
	data: HouseData.Data
): boolean
	local set = BlenderLot.yardSet(data.yard.fence)
	if set then
		BlenderLot.yard(house, base, rng, yardDepth, lotWidth, data, set)
	end
	BlenderLot.roomLights(house, base, rng, data.rooms)
	return set ~= nil
end

return BlenderLot
