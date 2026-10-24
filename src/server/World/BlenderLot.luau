--!strict
-- Dresses the lot around a Blender house model from its data (HouseData/<Style>.luau, written by
-- art/scripts/housekit.py, or a table in the same shape): a dead lawn, stepping stones from the
-- steps to the gate, a fence of the yard set's pieces (wrought iron or rotten pickets) with a double
-- gate standing open, a dead tree, a mailbox, graves; then it lights a few of the house's rooms and
-- furnishes them all from the Blender furniture set (a layout per room from Config/RoomLayouts, so
-- no two houses look alike inside), with at most one figure watching from a window. Works in the
-- lot's frame (x across, -z toward the street), where Blender x runs the other way.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomLayouts = require(ReplicatedStorage.Shared.Config.RoomLayouts)
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
-- furniture. Returns the room a figure should stand in, if any: usually a lit one.
function BlenderLot.roomLights(house: Model, base: CFrame, rng: Rng.Rng, rooms: { HouseData.Room }): HouseData.Room?
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
	for _, room in rooms do
		local isLit = if room.attic then rng:chance(0.4) else lit[room.id] == true
		if isLit then
			lit[room.id] = true
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
	local figureRooms = {}
	for _, room in rooms do
		-- The figure is a head taller than anyone (7.5 studs): not in the low attics.
		if room.figure and room.box.ceil - room.box.floor >= 8 then
			table.insert(figureRooms, room)
		end
	end
	rng:shuffle(figureRooms)
	for _, room in figureRooms do
		if lit[room.id] and rng:chance(0.6) then
			return room
		end
	end
	if #figureRooms > 0 and rng:chance(0.25) then
		return figureRooms[1] -- one left in the dark for the flashlight to find
	end
	return nil
end

-- The furniture set, if it's been imported (tools/setup_furniture.luau).
function BlenderLot.furnitureSet(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Furniture")
end

local MARGIN = 0.3 -- studs kept clear of the walls (the wallpaper and skirting stand inside the box)

type Box = { x0: number, x1: number, y0: number, y1: number }

-- A piece's footprint in its own frame, Blender-style (x across, y back), and its height.
local function extents(piece: BasePart): (Box, number)
	local centre = piece.PivotOffset:Inverse().Position -- the mesh's centre in its pivot frame
	local size = piece.Size
	-- The pivot frame is Roblox's: Blender x is -X, y is Z, z is Y.
	return {
		x0 = -centre.X - size.X / 2,
		x1 = -centre.X + size.X / 2,
		y0 = centre.Z - size.Z / 2,
		y1 = centre.Z + size.Z / 2,
	},
		centre.Y + size.Y / 2
end

-- The footprint turned by yaw (radians) and moved to (x, y).
local function turned(box: Box, yaw: number, x: number, y: number): Box
	local c, s = math.cos(yaw), math.sin(yaw)
	local out = { x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge }
	for _, px in { box.x0, box.x1 } do
		for _, py in { box.y0, box.y1 } do
			local rx, ry = px * c - py * s + x, px * s + py * c + y
			out.x0, out.x1 = math.min(out.x0, rx), math.max(out.x1, rx)
			out.y0, out.y1 = math.min(out.y0, ry), math.max(out.y1, ry)
		end
	end
	return out
end

-- Slides a coordinate so its footprint [v + a0, v + a1] stays within [-half, half]; centres it
-- when it can't fit.
local function clampAxis(v: number, a0: number, a1: number, half: number): number
	local lo, hi = -half + MARGIN - a0, half - MARGIN - a1
	if lo > hi then
		return (lo + hi) / 2
	end
	return math.clamp(v, lo, hi)
end

-- Footprints may touch or tuck in a little (chairs under a table) before they count as overlapping.
local TUCK = 0.35
local function overlaps(a: Box, b: Box): boolean
	return a.x0 + TUCK < b.x1 - TUCK
		and b.x0 + TUCK < a.x1 - TUCK
		and a.y0 + TUCK < b.y1 - TUCK
		and b.y0 + TUCK < a.y1 - TUCK
end
local function clear(spot: Box, taken: { Box }): boolean
	for _, other in taken do
		if overlaps(spot, other) then
			return false
		end
	end
	return true
end

-- A room's frame: its centre on the floor, turned so local -y points at its front (window) wall;
-- w is its width across, d its depth from the front back.
local FRONT_YAW = { y0 = 0, y1 = math.pi, x0 = -math.pi / 2, x1 = math.pi / 2 }
local function roomFrame(room: HouseData.Room): (number, number, number, number, number)
	local b = room.box
	local w, d = b.x1 - b.x0, b.y1 - b.y0
	if room.front == "x0" or room.front == "x1" then
		w, d = d, w
	end
	return (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, FRONT_YAW[room.front] or 0, w, d
end

local function pickLayout(
	rng: Rng.Rng,
	room: HouseData.Room,
	w: number,
	d: number,
	used: { [string]: boolean }
): RoomLayouts.Layout?
	local weights: { [string]: number } = {}
	local byName: { [string]: RoomLayouts.Layout } = {}
	for _, layout in RoomLayouts do
		if table.find(layout.roles, room.role) and w >= layout.minW and d >= layout.minD then
			byName[layout.name] = layout
			-- The same layout twice in one house happens, but rarely.
			weights[layout.name] = layout.weight * (if used[layout.name] then 0.15 else 1)
		end
	end
	local name = rng:weighted(weights)
	return if name then byName[name] else nil
end

-- Furnishes every room but the halls (their stairs are part of the house) with a layout that fits
-- it, mirrored half the time and nudged a little, and stands the figure in figureRoom.
function BlenderLot.furnish(
	house: Model,
	base: CFrame,
	rng: Rng.Rng,
	rooms: { HouseData.Room },
	figureRoom: HouseData.Room?
)
	local set = BlenderLot.furnitureSet()
	if set == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Furniture"
	local used: { [string]: boolean } = {}
	for _, room in rooms do
		if room.role == "hall" then
			continue
		end
		local cx, cy, frameYaw, w, d = roomFrame(room)
		local height = room.box.ceil - room.box.floor
		local c, s = math.cos(frameYaw), math.sin(frameYaw)
		local function place(template: BasePart, lx: number, ly: number, yaw: number, lift: number, scale: Vector3?)
			local x, y = cx + lx * c - ly * s, cy + lx * s + ly * c
			local piece = template:Clone()
			if scale then
				piece.Size *= scale
			end
			piece:PivotTo(base * CFrame.new(-x, room.box.floor + lift, y) * CFrame.Angles(0, frameYaw + yaw, 0))
			piece.Parent = folder
		end
		local taken: { Box } = {}
		local layout = pickLayout(rng, room, w, d, used)
		if layout then
			used[layout.name] = true
			local mirror = if rng:chance(0.5) then -1 else 1
			for _, item in layout.items do
				local template = set:FindFirstChild(item.piece) :: BasePart?
				if template == nil then
					continue
				end
				local box, top = extents(template)
				local lift = item.z or 0
				if top + lift > height - 0.2 then
					continue -- too tall for this room (attics)
				end
				local at = item.at
				local u = item.u or 0.5
				if mirror < 0 then
					if at == "left" or at == "right" then
						at = if at == "left" then "right" else "left"
					elseif at == "wallLeft" or at == "wallRight" then
						at = if at == "wallLeft" then "wallRight" else "wallLeft"
					else
						u = 1 - u
					end
				end
				local lx, ly, yaw
				if at == "back" or at == "wall" then
					lx, ly, yaw = (u - 0.5) * w, d / 2 - MARGIN - box.y1, 0
				elseif at == "left" or at == "wallLeft" then
					-- Turned to face the right-hand wall, its back (+y) against the left one.
					lx, ly, yaw = -w / 2 + MARGIN + box.y1, (u - 0.5) * d, math.pi / 2
				elseif at == "right" or at == "wallRight" then
					lx, ly, yaw = w / 2 - MARGIN - box.y1, (u - 0.5) * d, -math.pi / 2
				else
					lx = if item.x then item.x * mirror else (u - 0.5) * w
					ly = if item.y then item.y else ((item.v or 0.5) - 0.5) * d
					-- Nobody lines furniture up exactly.
					lx += rng:range(-0.3, 0.3)
					ly += rng:range(-0.3, 0.3)
					yaw = math.rad((item.yaw or 0) * mirror) + rng:range(-0.08, 0.08)
				end
				local foot = turned(box, yaw, 0, 0)
				local roomW, roomD = w - 2 * MARGIN, d - 2 * MARGIN
				local scale: Vector3? = nil
				if foot.x1 - foot.x0 > roomW or foot.y1 - foot.y0 > roomD then
					if item.piece ~= "Rug" then
						continue -- it would stick through a wall
					end
					-- A rug is cut to fit (it lies square to the room, give or take a nudge).
					local kx = math.min(1, roomW / (foot.x1 - foot.x0) - 0.03)
					local ky = math.min(1, roomD / (foot.y1 - foot.y0) - 0.03)
					scale = Vector3.new(kx, 1, ky)
					box = { x0 = box.x0 * kx, x1 = box.x1 * kx, y0 = box.y0 * ky, y1 = box.y1 * ky }
					foot = turned(box, yaw, 0, 0)
				end
				lx = clampAxis(lx, foot.x0, foot.x1, w / 2)
				ly = clampAxis(ly, foot.y0, foot.y1, d / 2)
				-- Floor pieces mustn't run into each other (a small room squeezes a layout); the
				-- first in the list wins. Hung and lifted ones and rugs don't count.
				local floor = lift == 0
					and at ~= "wall"
					and at ~= "wallLeft"
					and at ~= "wallRight"
					and item.piece ~= "Rug"
				local spot = turned(box, yaw, lx, ly)
				if floor and not clear(spot, taken) then
					continue
				end
				place(template, lx, ly, yaw, lift, scale)
				if floor then
					table.insert(taken, spot)
				end
			end
		end
		local figure = set:FindFirstChild("Figure") :: BasePart?
		if room == figureRoom and figure then
			-- Close behind the glass, looking out, somewhere nothing else stands.
			local box = extents(figure)
			for _ = 1, 10 do
				local yaw = rng:range(-0.35, 0.35)
				local foot = turned(box, yaw, 0, 0)
				local lx = clampAxis(rng:range(-w / 3, w / 3), foot.x0, foot.x1, w / 2)
				local ly = clampAxis(-d / 2 + rng:range(1.6, 2.6), foot.y0, foot.y1, d / 2)
				if clear(turned(box, yaw, lx, ly), taken) then
					place(figure, lx, ly, yaw, 0)
					break
				end
			end
		end
	end
	folder.Parent = house
end

local HALL_LIGHT = Color3.fromRGB(255, 168, 104)
local HALL_FLAME = Color3.fromRGB(255, 196, 120)

-- The entrance hall behind the front door (Data.hall): a few pieces where the door opens onto,
-- each spot picking its own (or staying empty), the chandelier or bare bulb that hangs there, a
-- light that's off until the house stands open ("HallLight": HouseService switches it, and the
-- chandelier's candle flames with it), and "HallFigure", where an open house's figure stands
-- looking out (HouseVisualController).
function BlenderLot.dressHall(house: Model, base: CFrame, rng: Rng.Rng, hall: HouseData.Hall)
	local function at(p: Vector3, yaw: number): CFrame
		return base * CFrame.new(-p.X, p.Z, p.Y) * CFrame.Angles(0, math.rad(yaw), 0)
	end
	local turn = rng:range(0, 360) -- the hanging piece's, and its flames'
	local set = BlenderLot.furnitureSet()
	if set then
		local folder = house:FindFirstChild("Furniture") or Instance.new("Folder")
		folder.Name = "Furniture"
		for _, prop in hall.props do
			local template = set:FindFirstChild(rng:pick(prop.pieces)) :: BasePart?
			if template and rng:chance(prop.chance) then
				local piece = template:Clone()
				piece:PivotTo(at(prop.at, prop.yaw + rng:range(-6, 6)))
				piece.Parent = folder
			end
		end
		local template = if hall.hang then set:FindFirstChild(hall.hang) :: BasePart? else nil
		if template then
			local hanging = template:Clone()
			hanging.CastShadow = false -- the hall light hangs right under it
			hanging:PivotTo(at(hall.lamp, turn))
			hanging.Parent = folder
		end
		folder.Parent = house
	end
	local function marker(name: string, cframe: CFrame): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Transparency = 1
		part.Size = Vector3.one * 0.2
		part.CFrame = cframe
		part.Parent = house
		return part
	end
	local glow = marker("HallLight", at(hall.lamp - Vector3.new(0, 0, hall.drop or 0.6), 0))
	local light = Instance.new("PointLight")
	light.Range = hall.range or 15
	light.Brightness = 1.3
	light.Color = HALL_LIGHT
	-- No shadows: the hall's own trim and ceiling shadowed it to black (and so it spills out of
	-- the open door onto the porch, the way a lit hall does).
	light.Shadows = false
	light.Enabled = false
	light.Parent = glow
	-- The candles' flames, out until the house stands open.
	local hung = at(hall.lamp, turn)
	for _, offset in hall.flames or {} do
		local flame = Instance.new("Part")
		flame.Name = "Flame"
		flame.Shape = Enum.PartType.Ball
		flame.Size = Vector3.one * 0.24
		flame.Material = Enum.Material.Neon
		flame.Color = HALL_FLAME
		flame.Transparency = 1
		flame.Anchored, flame.CanCollide, flame.CanQuery, flame.CanTouch, flame.CastShadow =
			true, false, false, false, false
		flame.CFrame = hung * CFrame.new(-offset.X, offset.Z, offset.Y)
		flame.Parent = glow
	end
	marker("HallFigure", at(hall.figure, 0))
end

-- The whole dressing: the yard (when the yard set is there), the room lights, the furniture and
-- the entrance hall. Returns false
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
	local figureRoom = BlenderLot.roomLights(house, base, rng, data.rooms)
	BlenderLot.furnish(house, base, rng, data.rooms, figureRoom)
	if data.hall then
		BlenderLot.dressHall(house, base, rng, data.hall)
	end
	return set ~= nil
end

return BlenderLot
