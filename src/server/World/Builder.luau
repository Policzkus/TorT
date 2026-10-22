--!strict
-- Builds the whole world from config at server start: hub → gate → street → gate → … .
-- Deterministic (seeded), so the layout is identical on every server.
-- Edit-mode preview from the command bar:
--   require(game.ServerScriptService.Server.World.Builder).build(workspace)   (delete Workspace.World after)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local World = require(ReplicatedStorage.Shared.Config.World)
local Hub = require(script.Parent.Hub)
local Parts = require(script.Parent.Parts)
local Props = require(script.Parent.Props)
local Street = require(script.Parent.Street)

export type Zone = { id: string, cframe: CFrame, size: Vector3 }

export type GateInfo = {
	model: Model,
	frame: CFrame, -- gate centre on the road, local -Z into the street it guards
	state: Props.GateState,
}

export type WorldInfo = {
	folder: Folder,
	spawn: SpawnLocation,
	houses: { [string]: Street.HouseInfo },
	dropoffs: { Street.DropoffInfo },
	busStops: { BasePart },
	zones: { Zone },
	streets: { [string]: Street.StreetInfo },
	gates: { [string]: GateInfo },
	arrivals: { [string]: CFrame }, -- zone id ("Hub" or a neighborhood id) -> bus drop-off
}

local Builder = {}

local GATE_INSET = 2 -- studs into the street the gate stands

local function gateState(neighborhood: any): Props.GateState
	if not neighborhood.enabled then
		return "comingSoon"
	end
	if neighborhood.unlock.price > 0 or neighborhood.unlock.rebirths > 0 then
		return "locked"
	end
	return "open"
end

-- Closes the outer side of a bend between two streets.
local function bendWalls(parent: Instance, finish: CFrame, nextStart: CFrame)
	local half = World.GROUND_WIDTH / 2 + 1
	for _, side in { -1, 1 } do
		local a = (finish * CFrame.new(side * half, 0, 2)).Position
		local b = (nextStart * CFrame.new(side * half, 0, -2)).Position
		Parts.wallBetween(parent, a, b, World.BOUNDARY_HEIGHT)
	end
end

-- The road past the last built street ends in a hedge.
local function deadEnd(parent: Instance, frame: CFrame)
	Parts.block(
		parent,
		"DeadEnd",
		Vector3.new(World.GROUND_WIDTH, 16, 6),
		frame * CFrame.new(0, 8, -14),
		"18301E",
		Enum.Material.LeafyGrass
	)
	Parts.invisibleWall(
		parent,
		Vector3.new(World.GROUND_WIDTH, World.BOUNDARY_HEIGHT, 2),
		frame * CFrame.new(0, World.BOUNDARY_HEIGHT / 2, -8)
	)
end

function Builder.build(parent: Instance): WorldInfo
	local startedAt = os.clock()
	local folder = Instance.new("Folder")
	folder.Name = "World"

	local hub = Hub.build(folder)
	local info: WorldInfo = {
		folder = folder,
		spawn = hub.spawn,
		houses = {},
		dropoffs = table.clone(hub.dropoffs),
		busStops = table.clone(hub.busStops),
		zones = { { id = "Hub", cframe = hub.zone.cframe, size = hub.zone.size } },
		streets = {},
		gates = {},
		arrivals = { Hub = hub.arrival },
	}

	local gatesFolder = Instance.new("Folder")
	gatesFolder.Name = "Gates"
	gatesFolder.Parent = folder
	local gateWidth = World.ROAD_WIDTH + World.SIDEWALK_WIDTH * 2
	local cursor = hub.exit
	local previousFinish: CFrame? = nil
	local houseCount = 0
	local endedAtComingSoon = false

	for _, neighborhood in Neighborhoods.list do
		local state = gateState(neighborhood)
		local gateFrame = cursor * CFrame.new(0, 0, -GATE_INSET)
		local gate = Props.gate(gatesFolder, gateFrame, gateWidth, World.GROUND_WIDTH, neighborhood, state)
		info.gates[neighborhood.id] = { model = gate, frame = gateFrame, state = state }
		if previousFinish then
			bendWalls(folder, previousFinish, cursor)
		end
		if state == "comingSoon" then
			deadEnd(folder, cursor)
			endedAtComingSoon = true
			break
		end

		local street = Street.build(folder, neighborhood, cursor)
		info.streets[neighborhood.id] = street
		table.insert(info.zones, { id = neighborhood.id, cframe = street.zone.cframe, size = street.zone.size })
		info.arrivals[neighborhood.id] = street.arrival
		for _, house in street.houses do
			info.houses[house.id] = house
			houseCount += 1
		end
		for _, dropoff in street.dropoffs do
			table.insert(info.dropoffs, dropoff)
		end
		for _, stop in street.busStops do
			table.insert(info.busStops, stop)
		end
		previousFinish = street.finish
		cursor = street.finish * CFrame.Angles(0, math.rad(neighborhood.turn), 0)
	end
	if not endedAtComingSoon then
		deadEnd(folder, cursor)
	end

	folder.Parent = parent
	local partCount = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			partCount += 1
		end
	end
	print(
		`[World] Built {houseCount} houses, {#info.dropoffs} drop-offs, {partCount} parts in {math.round(
			(os.clock() - startedAt) * 1000
		)} ms`
	)
	return info
end

return Builder
