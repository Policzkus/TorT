--!strict
-- The lobby (PROMPT §V2.2): the bus turnaround at the edge of town, at night. A ring of road round
-- a paved island where you arrive, four party buses parked along it with their doors to the island
-- (Services/PartyService), lamps, and the town's houses all round behind their fences, lit up and
-- shut (nobody answers here). Centred on the origin.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local World = require(ReplicatedStorage.Shared.Config.World)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Assets = require(script.Parent.Assets)
local Parts = require(script.Parent.Parts)
local Props = require(script.Parent.Props)

local M = Enum.Material

local ISLAND = 28 -- radius of the paved island in the middle
local ROAD = 22 -- width of the ring road round it
local WALK = 7 -- width of the sidewalk round the road
local YARD = 17 -- sidewalk to the front of the houses
local BUS_RING = ISLAND + ROAD / 2 -- where the buses park (their centre line)
local BOUNDARY = 128
local HOUSE_STYLES = { "Victorian", "Mansard", "Farmhouse" }

local Lobby = {}

-- Faces along the ring at `angle` (radians round the centre), local +X toward the middle.
local function onRing(radius: number, angle: number, y: number): CFrame
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	return CFrame.fromMatrix(out * radius + Vector3.new(0, y, 0), -out, Vector3.yAxis)
end

-- A ring of `count` blocks `width` wide (radially) and `height` tall, centred on `radius`.
local function ring(
	parent: Instance,
	name: string,
	radius: number,
	width: number,
	height: number,
	top: number,
	count: number,
	color: string,
	material: Enum.Material
)
	local length = 2 * math.pi * (radius + width / 2) / count + 0.4
	for k = 0, count - 1 do
		local angle = (k + 0.5) / count * 2 * math.pi
		Parts.block(
			parent,
			name,
			Vector3.new(width, height, length),
			onRing(radius, angle, top - height / 2),
			color,
			material
		)
	end
end

-- A light in the bus roof over each party seat, on while someone sits there (the user: from outside
-- you see who's on the bus): this far above the seat, shining down on them.
local SEAT_LIGHT = { up = 6, range = 9, angle = 75, brightness = 3, color = Color3.fromRGB(255, 214, 160) }
-- Where a party seat sits on its bench, from the Blender marker (Mark_Seat, 0.05 over the cushion):
-- its top level with the cushion, a touch forward so the biggest costumes clear the backrest (the
-- benches are spaced for their legs). The sitter is raised the rest of the way by their own build
-- (CharacterAnimController).
local SEAT_ON_BENCH = CFrame.new(0, -0.25, -0.15)

-- A party bus: the Blender one (Assets.Lobby.Bus) or, until it's imported, the old built one.
-- Seats for the party, with their lights, and the door's prompt. `base` faces along the bus, its
-- door on local +X.
local function bus(parent: Instance, base: CFrame, id: number): Model
	local model = Assets.clone("Lobby", "Bus")
	local door: BasePart?
	if model then
		model:PivotTo(base)
		model.Parent = parent
		door = model:FindFirstChild("Door", true) :: BasePart?
	else
		local built, builtDoor = Props.bus(parent, base)
		model, door = built, builtDoor
		CollectionService:RemoveTag(builtDoor, "BusStop")
		local old = builtDoor:FindFirstChildOfClass("ProximityPrompt")
		if old then
			old:Destroy()
		end
	end
	local busModel = model :: Model
	busModel.Name = "PartyBus" .. id
	busModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the door and seats arrive with it
	busModel:SetAttribute("BusId", id)
	local seats = Instance.new("Folder")
	seats.Name = "Seats"
	seats.Parent = busModel
	for k = 1, Runs.PARTY_MAX do
		local mark = busModel:FindFirstChild("Seat" .. k, true)
		local at = if mark and mark:IsA("BasePart")
			then mark.CFrame
			else base * CFrame.new(if k % 2 == 1 then -2 else 2, 2.3, -6 + (k - 1) // 2 * 5)
		local seat = Instance.new("Seat")
		seat.Name = "Seat" .. k
		seat.Size = Vector3.new(2, 0.4, 2)
		seat.CFrame = if mark then at * SEAT_ON_BENCH else at
		seat.Anchored = true
		seat.CanCollide = false
		seat.Transparency = 1
		seat.CanTouch = false -- only PartyService seats people (no sitting down by walking into it)
		seat.Parent = seats
		local above = Instance.new("Attachment")
		above.Name = "SeatLight"
		above.Position = Vector3.new(0, SEAT_LIGHT.up + 0.25, 0)
		above.Parent = seat
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = SEAT_LIGHT.range
		light.Angle = SEAT_LIGHT.angle
		light.Brightness = SEAT_LIGHT.brightness
		light.Color = SEAT_LIGHT.color
		light.Shadows = true
		light.Enabled = false
		light.Parent = above
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			light.Enabled = seat.Occupant ~= nil
		end)
	end
	if door then
		local prompt = Parts.prompt(door, "Get on", "Party bus", 12)
		prompt.Name = "Board"
		prompt.UIOffset = Vector2.new(0, 20)
	end
	CollectionService:AddTag(busModel, "PartyBus")
	return busModel
end

-- A house of the town round the turnaround: shut, lit inside, its yard dressed.
local function house(parent: Instance, styleName: string, lot: CFrame, rng: Rng.Rng)
	local model = Assets.clone("Houses", styleName)
	if model == nil then
		return
	end
	model:PivotTo(lot)
	local styles = script.Parent.HouseStyles
	local styleModule = styles:FindFirstChild(styleName)
	local style = if styleModule and styleModule:IsA("ModuleScript") then (require :: any)(styleModule) else nil
	if style and style.dressLot then
		style.dressLot(model, lot, rng, YARD, World.LOT_SPACING)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
end

export type LobbyInfo = {
	folder: Folder,
	spawn: SpawnLocation,
	buses: { Model },
	zone: { cframe: CFrame, size: Vector3 },
}

function Lobby.build(parent: Instance): LobbyInfo
	local rng = Rng.new(31)
	local folder = Instance.new("Folder")
	folder.Name = "World"
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder

	-- Grass to the edge, the ring road, its sidewalk, the island in the middle with its curb.
	Parts.disc(ground, "Grass", BOUNDARY * 2 + 20, 2, CFrame.new(0, -2, 0), "2C3A26", M.Grass)
	Parts.disc(ground, "Road", (ISLAND + ROAD) * 2, 0.2, CFrame.new(0, 0, 0), "2E2E33", M.Asphalt)
	ring(ground, "Sidewalk", ISLAND + ROAD + WALK / 2, WALK, 0.5, 0.5, 48, "6B6862", M.Concrete)
	Parts.disc(ground, "Island", ISLAND * 2, 0.5, CFrame.new(0, 0, 0), "5E5B55", M.Concrete)
	ring(ground, "Curb", ISLAND - 0.4, 0.8, 0.7, 0.7, 40, "7A766E", M.Concrete)
	for k = 0, 7 do -- the dashed line round the middle of the road
		for d = 0, 3 do
			local angle = (k * 4 + d + 0.5) / 32 * 2 * math.pi
			Parts.decor(
				Parts.block(
					ground,
					"Line",
					Vector3.new(0.5, 0.05, 5),
					onRing(BUS_RING + 5.5, angle, 0.22),
					"D9B44A",
					M.SmoothPlastic
				)
			)
		end
	end
	local walls = Instance.new("Folder")
	walls.Name = "Boundary"
	walls.Parent = folder
	for k = 0, 23 do
		local angle = (k + 0.5) / 24 * 2 * math.pi
		Parts.invisibleWall(
			walls,
			Vector3.new(2, World.BOUNDARY_HEIGHT, 2 * math.pi * BOUNDARY / 24 + 2),
			onRing(BOUNDARY, angle, World.BOUNDARY_HEIGHT / 2)
		)
	end

	-- The party buses, along the road with their doors to the island.
	local buses = {}
	local busFolder = Instance.new("Folder")
	busFolder.Name = "Buses"
	busFolder.Parent = folder
	for k = 1, 4 do
		table.insert(buses, bus(busFolder, onRing(BUS_RING, (k - 0.5) / 4 * 2 * math.pi, 0), k))
	end

	-- The town all round, behind the sidewalk; trees in the gaps and out to the fog.
	local houses = Instance.new("Folder")
	houses.Name = "Houses"
	houses.Parent = folder
	local front = ISLAND + ROAD + WALK + YARD
	for k = 0, 7 do
		local angle = k / 8 * 2 * math.pi
		local at = Vector3.new(math.cos(angle), 0, math.sin(angle)) * front
		house(houses, HOUSE_STYLES[k % #HOUSE_STYLES + 1], CFrame.lookAt(at, Vector3.zero), rng)
	end
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	for k = 0, 15 do
		local angle = (k + 0.5) / 16 * 2 * math.pi + rng:range(-0.05, 0.05)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		Props.tree(props, CFrame.new(out * rng:range(front + 26, BOUNDARY - 8)), rng, "dead")
	end
	-- Lamps round the sidewalk and round the island.
	for k = 0, 7 do
		local angle = (k + 0.5) / 8 * 2 * math.pi + math.pi / 8
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		Props.lamp(props, CFrame.fromMatrix(out * (ISLAND + ROAD + 1.6) + Vector3.new(0, 0.5, 0), out, Vector3.yAxis))
	end
	for k = 0, 3 do
		local angle = k / 4 * 2 * math.pi
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		Props.lamp(props, CFrame.fromMatrix(out * (ISLAND - 3) + Vector3.new(0, 0.5, 0), -out, Vector3.yAxis))
	end
	local pile = Assets.find("Decor", "PumpkinPile")
	if pile and pile:IsA("PVInstance") then
		local copy = pile:Clone()
		copy:PivotTo(CFrame.new(0, 0.5, 0))
		copy.Parent = props
	else
		Props.pumpkin(props, CFrame.new(0, 0.5, 0), 3)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.2, ISLAND * 0.55)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = folder

	folder.Parent = parent
	return {
		folder = folder,
		spawn = spawn,
		buses = buses,
		zone = { cframe = CFrame.new(0, 30, 0), size = Vector3.new(BOUNDARY * 2, 80, BOUNDARY * 2) },
	}
end

return Lobby
