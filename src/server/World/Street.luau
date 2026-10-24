--!strict
-- One neighborhood street: ground, road, sidewalks, lamps, houses on both sides, three Candy Box
-- drop-offs (entrance, middle, end) and a bus stop. `start` is the road centre at the street's
-- beginning, with local -Z pointing down the street and +X to the walker's right.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HouseModels = require(ReplicatedStorage.Shared.Config.HouseModels)
local Meshes = require(ReplicatedStorage.Shared.Config.Meshes)
local World = require(ReplicatedStorage.Shared.Config.World)
local MeshLibrary = require(ReplicatedStorage.Shared.Modules.MeshLibrary)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Assets = require(script.Parent.Assets)
local Parts = require(script.Parent.Parts)
local Props = require(script.Parent.Props)

local M = Enum.Material
local MOON_FILL = Color3.fromRGB(165, 182, 220)

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
	dressLot: ((house: Model, base: CFrame, rng: Rng.Rng, yard: number, lotWidth: number) -> ())?,
}

local styles: { [string]: Style } = {}
for _, module in script.Parent.HouseStyles:GetChildren() do
	if module:IsA("ModuleScript") then
		styles[module.Name] = (require :: any)(module)
	end
end

local TREE_KIND: { [string]: Props.TreeKind } =
	{ Trailer = "dead", Cottage = "autumn", Farmhouse = "autumn", Victorian = "dead" }

local Street = {}

-- Which house style stands on lot i: streets with several styles alternate them like a
-- checkerboard (across the road and next door differ). A style whose model hasn't been imported
-- gives way to the street's main one.
local function lotStyle(neighborhood: any, i: number): string
	local list = neighborhood.styles
	if list == nil or #list < 2 then
		return neighborhood.style
	end
	local name = list[((i // 2) + (i % 2)) % #list + 1]
	if name ~= neighborhood.style and Assets.find("Houses", name) == nil then
		return neighborhood.style
	end
	return name
end

-- Lot spacing for a neighbourhood: its widest (scaled) house model plus a margin.
function Street.lotSpacing(neighborhoodId: string): number
	local sizes: { [string]: { number } } = {}
	for name, mesh in Meshes do
		sizes[name] = mesh.size
	end
	return HouseModels.lotSpacing(neighborhoodId, sizes, World.LOT_SPACING)
end

function Street.length(houseCount: number, lotSpacing: number?): number
	return World.ENTRANCE_MARGIN + math.ceil(houseCount / 2) * (lotSpacing or World.LOT_SPACING) + World.END_MARGIN
end

local function setupDoor(info: HouseInfo)
	local door = info.door
	door:SetAttribute("HouseId", info.id)
	door:SetAttribute("Neighborhood", info.neighborhood)
	CollectionService:AddTag(door, "Door")
end

-- An AI-generated house (Config/HouseModels) on this lot: the mesh shell scaled so its front door is
-- HouseModels.DOOR_HEIGHT tall and turned so the door faces the street, an invisible knock zone on
-- the door itself (found by raycast), a porch light beside it and a path from the sidewalk.
-- Returns nil if none of the neighbourhood's models loaded.
local function meshHouse(
	parent: Instance,
	neighborhood: any,
	lot: CFrame,
	rng: Rng.Rng,
	yard: number
): (Model?, BasePart?)
	local names = HouseModels.MODELS[neighborhood.id]
	if names == nil or #names == 0 then
		return nil, nil
	end
	local order = table.clone(names)
	rng:shuffle(order)
	for _, name in order do
		local shell = MeshLibrary.get(name)
		local mesh = Meshes[name]
		if shell and mesh then
			local house = Instance.new("Model")
			house.Name = name
			local scale = HouseModels.scale(name, mesh.size)
			local width, depth = HouseModels.footprint(name, mesh.size)
			shell.Size = Vector3.new(mesh.size[1], mesh.size[2], mesh.size[3]) * scale
			shell.Name = "Shell"
			shell.Anchored = true
			shell.CanCollide = true
			shell.CanQuery = true
			shell.CFrame = lot * CFrame.new(0, shell.Size.Y / 2, depth / 2) * CFrame.Angles(0, HouseModels.yaw(name), 0)

			-- Where the door is: the calibration gives x and the sill, raycasts give the exact surface.
			local spec = HouseModels.DOORS[name]
				or { face = "Front", x = 0, bottom = 0, height = HouseModels.DOOR_HEIGHT / shell.Size.Y, width = 0.15 }
			local doorHeight = HouseModels.DOOR_HEIGHT
			local doorWidth = math.clamp(spec.width * width, 3, 7)
			local doorX = -spec.x * width -- the viewer's right is the lot's -X
			local sill = spec.bottom * shell.Size.Y
			shell.Parent = Workspace -- raycasts only see the workspace
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { shell }
			local surface = 1
			local hit = Workspace:Raycast(
				lot:PointToWorldSpace(Vector3.new(doorX, sill + doorHeight * 0.55, -4)),
				lot:VectorToWorldSpace(Vector3.new(0, 0, depth + 4)),
				params
			)
			if hit then
				surface = lot:PointToObjectSpace(hit.Position).Z
			end
			local floor = Workspace:Raycast(
				lot:PointToWorldSpace(Vector3.new(doorX, sill + 2.5, surface - 0.8)),
				lot:VectorToWorldSpace(Vector3.new(0, -(sill + 5), 0)),
				params
			)
			if floor then
				local y = lot:PointToObjectSpace(floor.Position).Y
				if math.abs(y - sill) < 2.5 then
					sill = y
				end
			end
			shell.Parent = house

			local door = Parts.block(
				house,
				"Door",
				Vector3.new(doorWidth, doorHeight, 0.4),
				lot * CFrame.new(doorX, sill + doorHeight / 2, surface - 0.25),
				"050505",
				M.SmoothPlastic,
				{ Transparency = 1, CanCollide = false, CastShadow = false }
			)
			local porch = Parts.block(
				house,
				"PorchLight",
				Vector3.one * 0.4,
				lot * CFrame.new(doorX + doorWidth / 2 + 1.2, sill + doorHeight + 0.4, surface - 0.8),
				"FFE0A0",
				M.Neon,
				{ Transparency = 1, CanCollide = false, CanQuery = false }
			)
			Parts.light(porch, 18, 1.4, "FFB070")
			Parts.block(
				house,
				"Path",
				Vector3.new(4, 0.12, yard),
				lot * CFrame.new(doorX, 0.06, -yard / 2),
				"6E6A64",
				M.Concrete
			)
			house:SetAttribute("DoorWidth", doorWidth)
			house:SetAttribute("DoorHeight", doorHeight)
			house.Parent = parent
			return house, door
		end
	end
	return nil, nil
end

local function placeHouse(
	parent: Instance,
	neighborhood: any,
	index: number,
	lot: CFrame,
	rng: Rng.Rng,
	variantRng: Rng.Rng,
	yard: number,
	styleName: string
): HouseInfo?
	local id = string.format("%s_%02d", neighborhood.id, index)
	local house: Model, door: BasePart
	local custom = Assets.clone("Houses", styleName)
	if custom then
		local customDoor = custom:FindFirstChild("Door", true)
		if customDoor and customDoor:IsA("BasePart") then
			custom:PivotTo(lot)
			-- Styles can dress the lot around an imported model (fence, gate, path, garden).
			local style = styles[styleName] :: any
			if style and style.dressLot then
				style.dressLot(custom, lot, rng, yard, World.LOT_SPACING)
			end
			custom.Parent = parent
			house, door = custom, customDoor
		else
			warn(`[World] ReplicatedStorage.Assets.Houses.{styleName} has no BasePart named Door; using procedural`)
			custom:Destroy()
		end
	end
	if house == nil then
		local meshModel, meshDoor = meshHouse(parent, neighborhood, lot, variantRng, yard)
		if meshModel and meshDoor then
			house, door = meshModel, meshDoor
		end
	end
	if house == nil then
		local style = styles[styleName]
		if style == nil then
			warn(`[World] No house style '{styleName}' for {neighborhood.id}`)
			return nil
		end
		house, door = style.build(parent, lot, rng, yard, World.LOT_SPACING)
	end
	house.Name = "House_" .. id
	house.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- Moonlight off the fog: a soft cool fill from over the sidewalk, so the yard and the house front
	-- still read where the next house along throws its long moon shadow (World.LIGHTING). Outside
	-- the house model, so a Lights Off house doesn't put the moon out too.
	local fill = Parts.block(
		parent,
		"MoonFill_" .. id,
		Vector3.one * 0.2,
		lot * CFrame.new(0, 14, -(yard + 7)),
		"000000",
		M.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	)
	Parts.light(fill, 34, 0.65, MOON_FILL)
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
	local rng = Rng.new(neighborhood.seed) -- layout and props: identical every server
	-- Which house model stands on which lot changes every run, so no two playthroughs look alike.
	local variantRng = Rng.new(Random.new():NextInteger(1, 2147483646))
	local folder = Instance.new("Folder")
	folder.Name = neighborhood.id
	local colors = neighborhood.colors
	local lotSpacing = Street.lotSpacing(neighborhood.id)
	local length = Street.length(neighborhood.houses, lotSpacing)
	local half = World.GROUND_WIDTH / 2
	local roadHalf = World.ROAD_WIDTH / 2
	local walkOffset = roadHalf + World.SIDEWALK_WIDTH / 2
	local function at(x: number, y: number, z: number): CFrame
		return start * CFrame.new(x, y, -z) -- z measured down the street
	end

	-- Ground, road, sidewalks, centre line. Every other street sits a hair higher: where one street
	-- bends into the next their slabs overlap, and two tops in one plane flicker.
	local lift = if neighborhood.tier % 2 == 0 then 0.06 else 0
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	Parts.block(
		ground,
		"Grass",
		Vector3.new(World.GROUND_WIDTH, 2, length),
		at(0, -1 + lift, length / 2),
		colors.ground,
		M.Grass
	)
	Parts.block(
		ground,
		"Road",
		Vector3.new(World.ROAD_WIDTH, 0.2, length),
		at(0, 0.1 + lift, length / 2),
		colors.road,
		M.Asphalt
	)
	for _, side in { -1, 1 } do
		Parts.block(
			ground,
			"Sidewalk",
			Vector3.new(World.SIDEWALK_WIDTH, 0.5, length),
			at(side * walkOffset, 0.25 + lift, length / 2),
			colors.sidewalk,
			M.Concrete
		)
		-- Tree-line hedge along the edge; the fog hides whatever is beyond.
		Parts.block(
			ground,
			"Treeline",
			Vector3.new(4, 14, length),
			at(side * (half - 2), 7 + lift, length / 2),
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
		Parts.decor(
			Parts.block(ground, "Line", Vector3.new(0.5, 0.05, 6), at(0, 0.22 + lift, z), "D9B44A", M.SmoothPlastic)
		)
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
			local z = World.ENTRANCE_MARGIN + lotSpacing * (slot + 0.5) + (if side > 0 then lotSpacing / 4 else 0)
			local facing = CFrame.Angles(0, if side > 0 then math.rad(90) else math.rad(-90), 0)
			local lot = at(side * World.HOUSE_SETBACK, 0, z) * facing
			local info =
				placeHouse(housesFolder, neighborhood, i + 1, lot, rng, variantRng, yard, lotStyle(neighborhood, i))
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
	-- Decorations between the lots, unless the houses dress their own yards (the Blender Victorian
	-- has fenced yards with pumpkins of its own, and these would land inside the fence).
	local style = styles[neighborhood.style] :: any
	local dressed = style ~= nil and style.dressLot ~= nil and Assets.find("Houses", neighborhood.style) ~= nil
	for _ = 1, if dressed then 0 else 6 do
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
