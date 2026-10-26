--!strict
-- Home Street, the hub: spawn, the main Candy Box, Sweet Tooth's Shop and the Spooky School Bus.
-- Centred on the origin; the road to Cardboard Court leaves through local -Z.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.Config.World)
local CandyPiece = require(ReplicatedStorage.Shared.Modules.CandyPiece)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Parts = require(script.Parent.Parts)
local Props = require(script.Parent.Props)

local M = Enum.Material

export type HubInfo = {
	spawn: SpawnLocation,
	dropoffs: { { id: string, position: Vector3 } },
	busStops: { BasePart },
	zone: { cframe: CFrame, size: Vector3 },
	arrival: CFrame,
	exit: CFrame, -- road centre where the first street begins
}

local Hub = {}

local function shopStall(parent: Instance, base: CFrame)
	local m = Instance.new("Model")
	m.Name = "SweetToothsShop"
	m.Parent = parent
	local wood, purple, orange = Parts.hex("6A4A2E"), Parts.hex("5A2E8A"), Parts.hex("FF8A00")
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local counter = Parts.block(m, "Counter", Vector3.new(12, 3.6, 3), at(0, 1.8, -1), wood, M.WoodPlanks)
	Parts.decor(Parts.block(m, "CounterTop", Vector3.new(12.4, 0.4, 3.4), at(0, 3.8, -1), "F2EEE6", M.SmoothPlastic))
	Parts.block(m, "BackWall", Vector3.new(12, 9.5, 0.6), at(0, 4.75, 3), purple, M.WoodPlanks)
	for _, x in { -5.8, 5.8 } do
		for _, z in { -2.4, 2.8 } do
			Parts.block(m, "Post", Vector3.new(0.6, 10, 0.6), at(x, 5, z), "F2EEE6", M.Wood)
		end
	end
	for i = 0, 6 do
		local x = -6 + i * 2 + 1
		Parts.decor(
			Parts.block(
				m,
				"Awning",
				Vector3.new(2, 0.35, 7),
				at(x - 0.0, 10.3, 0.2) * CFrame.Angles(math.rad(-10), 0, 0),
				if i % 2 == 0 then orange else purple,
				M.Fabric
			)
		)
	end
	local board = Parts.block(m, "SignBoard", Vector3.new(12, 2.6, 0.4), at(0, 12.4, -0.6), "2A1B3D", M.WoodPlanks)
	Parts.sign(board, Enum.NormalId.Front, "SWEET TOOTH'S SHOP", { color = Color3.fromHex("FFB347") })
	Parts.light(board, 22, 1.6, "FFB347")
	local jarColors = { "FF3B5C", "7CFF4F", "FFD23F" }
	for i, color in jarColors do
		local x = -4 + (i - 1) * 4
		Parts.decor(Parts.pole(m, "Jar", 2.2, 1.6, at(x, 4, -1), "DDEEFF", M.Glass, { Transparency = 0.5 }))
		for j = 0, 2 do
			Parts.candy(
				m,
				"Candy",
				0.6,
				at(x + (j - 1) * 0.35, 4.4 + j * 0.25, -1) * CandyPiece.tumble(i * 3 + j),
				color
			)
		end
	end
	local prompt = Parts.prompt(counter, "Shop", "Sweet Tooth's Shop", 12)
	prompt.UIOffset = Vector2.new(0, 30)
	CollectionService:AddTag(counter, "ShopStand")
	Props.hayBale(m, at(-8.5, 0, -1))
	Props.hayBale(m, at(8.5, 0, -1) * CFrame.Angles(0, 0.4, 0))
	Props.pumpkin(m, at(-8.5, 2.2, -1), 1.8)
	Props.pumpkin(m, at(8.6, 2.2, -1), 1.5)
end

local function titleSign(parent: Instance, base: CFrame)
	local m = Instance.new("Model")
	m.Name = "TitleSign"
	m.Parent = parent
	for _, x in { -11, 11 } do
		Parts.block(m, "Post", Vector3.new(1.2, 14.4, 1.2), base * CFrame.new(x, 7.2, 0), "4A3020", M.Wood) -- above the board
	end
	local board = Parts.block(m, "Board", Vector3.new(26, 8, 0.8), base * CFrame.new(0, 10, 0), "3A2418", M.WoodPlanks)
	Parts.sign(board, Enum.NormalId.Front, "TRICK OR TREAT\nWITH FRIENDS 🎃", { color = Color3.fromHex("FF8A00") })
	Parts.light(board, 26, 1.4, "FF8A00")
	for i = -2, 2 do
		Props.pumpkin(m, base * CFrame.new(i * 4.5, 0, -2), 2)
	end
end

function Hub.build(parent: Instance): HubInfo
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	local rng = Rng.new(777)
	local size = World.HUB_SIZE
	local half = size / 2
	local roadHalf = World.ROAD_WIDTH / 2

	Parts.block(folder, "Grass", Vector3.new(size, 2, size), CFrame.new(0, -1, 0), "3E5430", M.Grass)
	Parts.disc(folder, "Plaza", 124, 0.25, CFrame.new(0, 0, 4), "4E4A56", M.Cobblestone)
	Parts.block(
		folder,
		"Road",
		Vector3.new(World.ROAD_WIDTH, 0.2, 30),
		CFrame.new(0, 0.1, -half + 15),
		"2E2C33",
		M.Asphalt
	)
	for _, side in { -1, 1 } do
		Parts.block(
			folder,
			"Sidewalk",
			Vector3.new(World.SIDEWALK_WIDTH, 0.5, 30),
			CFrame.new(side * (roadHalf + World.SIDEWALK_WIDTH / 2), 0.25, -half + 15),
			"6E6A64",
			M.Concrete
		)
		-- Boundary on the sides.
		Parts.block(
			folder,
			"Treeline",
			Vector3.new(4, 14, size),
			CFrame.new(side * (half - 2), 7, 0),
			"18301E",
			M.LeafyGrass
		)
		Parts.invisibleWall(
			folder,
			Vector3.new(2, World.BOUNDARY_HEIGHT, size + 4),
			CFrame.new(side * (half + 1), World.BOUNDARY_HEIGHT / 2, 0)
		)
	end
	-- (Between the side tree lines, not into them: their ends met in one plane.)
	Parts.block(folder, "Treeline", Vector3.new(size - 8, 14, 4), CFrame.new(0, 7, half - 2), "18301E", M.LeafyGrass)
	Parts.invisibleWall(
		folder,
		Vector3.new(size + 4, World.BOUNDARY_HEIGHT, 2),
		CFrame.new(0, World.BOUNDARY_HEIGHT / 2, half + 1)
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 50)
	spawn.Color = Color3.fromHex("6A4A2E")
	spawn.Material = M.WoodPlanks
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	titleSign(folder, CFrame.new(0, 0, 72))
	shopStall(folder, CFrame.new(40, 0, 6) * CFrame.Angles(0, math.rad(90), 0))
	local _, busDoor = Props.bus(folder, CFrame.new(-46, 0, 24))
	local _, mainPosition = Props.dropoff(folder, CFrame.new(-24, 0.25, -22), "Hub_Main")

	-- Lamps around the plaza, decorations.
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2 + math.pi / 8
		local position = Vector3.new(math.cos(angle) * 60, 0, 4 + math.sin(angle) * 60)
		local base = CFrame.lookAt(position, Vector3.new(0, 0, 4)) * CFrame.Angles(0, math.rad(-90), 0)
		Props.lamp(folder, base)
	end
	Props.pumpkin(folder, CFrame.new(24, 0.25, 40), 7)
	for _ = 1, 10 do
		local angle = rng:range(0, math.pi * 2)
		local radius = rng:range(30, 55)
		Props.pumpkin(
			folder,
			CFrame.new(math.cos(angle) * radius, 0.25, 4 + math.sin(angle) * radius),
			rng:range(1.4, 2.4)
		)
	end
	for _, spot in
		{ Vector3.new(-62, 0, 62), Vector3.new(62, 0, 62), Vector3.new(-66, 0, -40), Vector3.new(66, 0, -50) }
	do
		Props.tree(folder, CFrame.new(spot), rng, "dead")
	end

	folder.Parent = parent
	return {
		spawn = spawn,
		dropoffs = { { id = "Hub_Main", position = mainPosition } },
		busStops = { busDoor },
		zone = { cframe = CFrame.new(0, 30, 0), size = Vector3.new(size, 80, size) },
		arrival = CFrame.lookAt(Vector3.new(-32, 3, 16), Vector3.new(0, 3, 16)),
		exit = CFrame.new(0, 0, -half),
	}
end

return Hub
