--!strict
-- One neighborhood street: ground, road, sidewalks, lamps, houses on both sides, three Candy Box
-- drop-offs (entrance, middle, end) and a bus stop. `start` is the road centre at the street's
-- beginning, with local -Z pointing down the street and +X to the walker's right.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local World = require(ReplicatedStorage.Shared.Config.World)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Assets = require(script.Parent.Assets)
local Parts = require(script.Parent.Parts)
local Props = require(script.Parent.Props)

local M = Enum.Material

export type HouseInfo = {
	id: string,
	neighborhood: string,
	index: number,
	model: Model,
	door: BasePart,
	prompt: ProximityPrompt,
}

export type DropoffInfo = { id: string, position: Vector3 }

export type StreetInfo = {
	id: string,
	length: number,
	start: CFrame,
	finish: CFrame, -- road centre at the end, same orientation as start
	houses: { HouseInfo },
	dropoffs: { DropoffInfo },
	busStops: { BasePart },
	zone: { cframe: CFrame, size: Vector3 },
	arrival: CFrame, -- where the bus drops you off
}

type Style = {
	build: (parent: Instance, base: CFrame, rng: Rng.Rng, yard: number, lotWidth: number) -> (Model, BasePart),
}

local styles: { [string]: Style } = {}
for _, module in script.Parent.HouseStyles:GetChildren() do
	if module:IsA("ModuleScript") then
		styles[module.Name] = (require :: any)(module)
	end
end

local TREE_KIND: { [string]: Props.TreeKind } = { Trailer = "dead", Cottage = "autumn" }

local Street = {}

function Street.length(houseCount: number): number
	return World.ENTRANCE_MARGIN + math.ceil(houseCount / 2) * World.LOT_SPACING + World.END_MARGIN
end

local function setupDoor(info: HouseInfo)
	local door = info.door
	door:SetAttribute("HouseId", info.id)
	door:SetAttribute("Neighborhood", info.neighborhood)
	CollectionService:AddTag(door, "Door")
end

local function placeHouse(
	parent: Instance,
	neighborhood: any,
	index: number,
	lot: CFrame,
	rng: Rng.Rng,
	yard: number
): HouseInfo?
	local id = string.format("%s_%02d", neighborhood.id, index)
	local house: Model, door: BasePart
	local custom = Assets.clone("Houses", neighborhood.style)
	if custom then
		local customDoor = custom:FindFirstChild("Door", true)
		if customDoor and customDoor:IsA("BasePart") then
			custom:PivotTo(lot)
			custom.Parent = parent
			house, door = custom, customDoor
		else
			warn(
				`[World] ReplicatedStorage.Assets.Houses.{neighborhood.style} has no BasePart named Door; using procedural`
			)
			custom:Destroy()
		end
	end
	if house == nil then
		local style = styles[neighborhood.style]
		if style == nil then
			warn(`[World] No house style '{neighborhood.style}' for {neighborhood.id}`)
			return nil
		end
		house, door = style.build(parent, lot, rng, yard, World.LOT_SPACING)
	end
	house.Name = "House_" .. id
	house.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	house:SetAttribute("HouseId", id)
	local prompt = Parts.prompt(door, "Knock", "Trick or treat!", 10)
	local info: HouseInfo =
		{ id = id, neighborhood = neighborhood.id, index = index, model = house, door = door, prompt = prompt }
	setupDoor(info)
	return info
end

-- Handmade swap-in: Workspace.Handmade.<NeighborhoodId> replaces the procedural houses. Every
-- BasePart named "Door" inside it becomes a knockable house.
local function handmadeHouses(neighborhood: any): { HouseInfo }?
	local root = Workspace:FindFirstChild("Handmade")
	local folder = root and root:FindFirstChild(neighborhood.id)
	if folder == nil then
		return nil
	end
	local houses = {}
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Door" then
			local index = #houses + 1
			local model = descendant:FindFirstAncestorOfClass("Model") or folder
			local info: HouseInfo = {
				id = string.format("%s_%02d", neighborhood.id, index),
				neighborhood = neighborhood.id,
				index = index,
				model = model :: Model,
				door = descendant,
				prompt = Parts.prompt(descendant, "Knock", "Trick or treat!", 10),
			}
			setupDoor(info)
			table.insert(houses, info)
		end
	end
	print(`[World] {neighborhood.id}: using {#houses} handmade houses`)
	return houses
end

function Street.build(parent: Instance, neighborhood: any, start: CFrame): StreetInfo
	local rng = Rng.new(neighborhood.seed)
	local folder = Instance.new("Folder")
	folder.Name = neighborhood.id
	local colors = neighborhood.colors
	local length = Street.length(neighborhood.houses)
	local half = World.GROUND_WIDTH / 2
	local roadHalf = World.ROAD_WIDTH / 2
	local walkOffset = roadHalf + World.SIDEWALK_WIDTH / 2
	local function at(x: number, y: number, z: number): CFrame
		return start * CFrame.new(x, y, -z) -- z measured down the street
	end

	-- Ground, road, sidewalks, centre line.
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	Parts.block(
		ground,
		"Grass",
		Vector3.new(World.GROUND_WIDTH, 2, length),
		at(0, -1, length / 2),
		colors.ground,
		M.Grass
	)
	Parts.block(
		ground,
		"Road",
		Vector3.new(World.ROAD_WIDTH, 0.2, length),
		at(0, 0.1, length / 2),
		colors.road,
		M.Asphalt
	)
	for _, side in { -1, 1 } do
		Parts.block(
			ground,
			"Sidewalk",
			Vector3.new(World.SIDEWALK_WIDTH, 0.5, length),
			at(side * walkOffset, 0.25, length / 2),
			colors.sidewalk,
			M.Concrete
		)
		-- Tree-line hedge along the edge; the fog hides whatever is beyond.
		Parts.block(
			ground,
			"Treeline",
			Vector3.new(4, 14, length),
			at(side * (half - 2), 7, length / 2),
			"18301E",
			M.LeafyGrass
		)
		Parts.invisibleWall(
			ground,
			Vector3.new(2, World.BOUNDARY_HEIGHT, length + 4),
			at(side * (half + 1), World.BOUNDARY_HEIGHT / 2, length / 2)
		)
	end
	for z = 8, length - 8, 14 do
		Parts.decor(Parts.block(ground, "Line", Vector3.new(0.5, 0.05, 6), at(0, 0.22, z), "D9B44A", M.SmoothPlastic))
	end
	-- Round plaza at the far end so the next street can bend off at an angle without gaps.
	Parts.disc(ground, "Bend", World.GROUND_WIDTH, 2, at(0, -2, length), colors.ground, M.Grass)
	Parts.disc(
		ground,
		"BendRoad",
		World.ROAD_WIDTH + World.SIDEWALK_WIDTH * 2,
		0.2,
		at(0, 0, length),
		colors.road,
		M.Asphalt
	)

	-- Houses: alternate sides, the right side shifted a little so the street isn't a mirror image.
	local houses: { HouseInfo } = handmadeHouses(neighborhood) or {}
	local yard = World.HOUSE_SETBACK - roadHalf - World.SIDEWALK_WIDTH
	if #houses == 0 then
		local housesFolder = Instance.new("Folder")
		housesFolder.Name = "Houses"
		housesFolder.Parent = folder
		for i = 0, neighborhood.houses - 1 do
			local slot = i // 2
			local side = if i % 2 == 0 then -1 else 1
			local z = World.ENTRANCE_MARGIN + World.LOT_SPACING * (slot + 0.5) + (if side > 0 then 10 else 0)
			local facing = CFrame.Angles(0, if side > 0 then math.rad(90) else math.rad(-90), 0)
			local lot = at(side * World.HOUSE_SETBACK, 0, z) * facing
			local info = placeHouse(housesFolder, neighborhood, i + 1, lot, rng, yard)
			if info then
				table.insert(houses, info)
			end
		end
	end

	-- Street lamps, alternating sides, arms reaching over the road.
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	local lampSide = -1
	for z = 30, length - 20, World.LAMP_SPACING do
		local x = lampSide * (roadHalf + World.SIDEWALK_WIDTH - 0.8)
		local facing = CFrame.Angles(0, if lampSide > 0 then 0 else math.pi, 0)
		Props.lamp(props, at(x, 0.5, z) * facing)
		lampSide = -lampSide
	end
	-- Decorations between the lots.
	for _ = 1, 6 do
		local side = if rng:chance(0.5) then -1 else 1
		local z = rng:range(World.ENTRANCE_MARGIN, length - World.END_MARGIN)
		Props.pumpkin(props, at(side * (walkOffset + World.SIDEWALK_WIDTH / 2 + 1.5), 0, z), rng:range(1.4, 2.2))
	end
	local treeKind = TREE_KIND[neighborhood.style] or "pine"
	for _, side in { -1, 1 } do
		for z = 20, length - 10, 26 do
			Props.tree(props, at(side * rng:range(half - 14, half - 8), 0, z + rng:range(-6, 6)), rng, treeKind)
		end
	end

	-- Candy Box drop-offs at the entrance, the middle (on an island in the road) and the end.
	local dropoffs: { DropoffInfo } = {}
	local spots = {
		{ id = neighborhood.id .. "_Entrance", frame = at(-(walkOffset + 13), 0, 24) },
		{ id = neighborhood.id .. "_Middle", frame = at(0, 0.2, length / 2) },
		{ id = neighborhood.id .. "_End", frame = at(walkOffset + 13, 0, length - 22) },
	}
	for _, spot in spots do
		local _, position = Props.dropoff(props, spot.frame, spot.id)
		table.insert(dropoffs, { id = spot.id, position = position })
	end

	local busStops: { BasePart } = {}
	local _, sign = Props.busStop(props, at(walkOffset + 1, 0.5, 30) * CFrame.Angles(0, math.rad(90), 0))
	table.insert(busStops, sign)

	folder.Parent = parent
	return {
		id = neighborhood.id,
		length = length,
		start = start,
		finish = start * CFrame.new(0, 0, -length),
		houses = houses,
		dropoffs = dropoffs,
		busStops = busStops,
		zone = { cframe = at(0, 30, length / 2), size = Vector3.new(World.GROUND_WIDTH, 80, length) },
		arrival = at(8, 3, 34),
	}
end

return Street
