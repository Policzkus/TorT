--!strict
-- Maple Lane: small brick cottages with gable roofs, white picket fences and autumn trees.
-- `base` is the ground point at the front-centre of the house; local -Z faces the street.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Parts = require(script.Parent.Parent.Parts)
local Props = require(script.Parent.Parent.Props)

local M = Enum.Material

local BRICK_COLORS = { "8A3A2A", "9A4A32", "7A4030", "A0603A", "6E5A4A" }
local ROOF_COLORS = { "3A2E2E", "2E3440", "4A3A2A", "3A3A3E" }
local DOOR_COLORS = { "2A4A2A", "5A1E1E", "1E2A4A", "3A2A1E", "5A3A6A" }

local Cottage = {}

function Cottage.build(parent: Instance, base: CFrame, rng: Rng.Rng, yard: number, lotWidth: number): (Model, BasePart)
	local house = Instance.new("Model")
	house.Name = "Cottage"
	local width, depth, wall, floor = rng:pick({ 22, 24, 26 }), 16, 10, 1
	local top = floor + wall
	local roofHeight, overhang = 6.5, 1
	local brick, roof = rng:pick(BRICK_COLORS), rng:pick(ROOF_COLORS)
	local white = Parts.hex("F2EEE6")
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	Parts.block(
		house,
		"Foundation",
		Vector3.new(width + 0.4, floor, depth + 0.4),
		at(0, floor / 2, depth / 2),
		"6E6A66",
		M.Concrete
	)
	Parts.block(house, "Body", Vector3.new(width, wall, depth), at(0, floor + wall / 2, depth / 2), brick, M.Brick)

	-- Gable roof, ridge parallel to the street: two tilted slabs plus wedge gables at each end.
	local run = depth / 2 + overhang
	local slope = math.atan2(roofHeight, run)
	local slabLength = math.sqrt(run * run + roofHeight * roofHeight) + 0.4
	Parts.block(
		house,
		"RoofFront",
		Vector3.new(width + 2, 0.7, slabLength),
		at(0, top + roofHeight / 2, (depth / 2 - overhang) / 2) * CFrame.Angles(-slope, 0, 0),
		roof,
		M.Slate
	)
	Parts.block(
		house,
		"RoofBack",
		Vector3.new(width + 2, 0.7, slabLength),
		at(0, top + roofHeight / 2, (depth / 2 + depth + overhang) / 2) * CFrame.Angles(slope, 0, 0),
		roof,
		M.Slate
	)
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		Parts.wedge(
			house,
			"Gable",
			Vector3.new(0.6, roofHeight, depth / 2),
			at(x, top + roofHeight / 2, depth / 4),
			brick,
			M.Brick
		)
		Parts.wedge(
			house,
			"Gable",
			Vector3.new(0.6, roofHeight, depth / 2),
			at(x, top + roofHeight / 2, depth * 0.75) * CFrame.Angles(0, math.pi, 0),
			brick,
			M.Brick
		)
	end
	Parts.block(house, "Chimney", Vector3.new(2.4, 7, 2.4), at(width * 0.3, top + 3.5, depth * 0.7), "5A2E22", M.Brick)

	-- Door with a little porch.
	Parts.decor(Parts.block(house, "DoorFrame", Vector3.new(4.4, 7.6, 0.16), at(0, floor + 3.8, -0.08), white, M.Wood))
	local door =
		Parts.block(house, "Door", Vector3.new(3.6, 7, 0.3), at(0, floor + 3.5, -0.2), rng:pick(DOOR_COLORS), M.Wood)
	Parts.decor(Parts.block(house, "Knob", Vector3.new(0.3, 0.3, 0.2), at(1.3, floor + 3.3, -0.42), "D4B04A", M.Metal))
	Parts.block(house, "Porch", Vector3.new(8, floor, 4.5), at(0, floor / 2, -2.25), "8A8680", M.Concrete)
	Parts.block(house, "PorchRoof", Vector3.new(8.4, 0.4, 4.8), at(0, floor + 8.2, -2.3), white, M.WoodPlanks)
	for _, x in { -3.7, 3.7 } do
		Parts.decor(Parts.block(house, "Post", Vector3.new(0.5, 8, 0.5), at(x, floor + 4, -4.3), white, M.Wood))
	end

	for _, x in { -width * 0.3, width * 0.3 } do
		local lit = rng:chance(0.65)
		Parts.decor(
			Parts.block(house, "WindowFrame", Vector3.new(4.8, 4.8, 0.12), at(x, floor + 5.5, -0.06), white, M.Wood)
		)
		Parts.decor(
			Parts.block(
				house,
				"Window",
				Vector3.new(4, 4, 0.2),
				at(x, floor + 5.5, -0.12),
				if lit then "FFC870" else "1E2436",
				if lit then M.Neon else M.Glass
			)
		)
	end

	local porchLight = Parts.decor(
		Parts.block(house, "PorchLight", Vector3.new(0.5, 0.8, 0.4), at(2.7, floor + 5.8, -0.3), "FFE0A0", M.Neon)
	)
	Parts.light(porchLight, 16, 1.6, "FFB060")

	local pumpkins = rng:int(1, 3)
	for i = 1, pumpkins do
		local x = if i == 1 then -2.6 elseif i == 2 then 2.6 else -1.4
		Props.pumpkin(house, at(x, floor, -3.2 - (if i == 3 then 0.3 else 0)), rng:range(1.3, 2))
	end

	-- Path and white picket fence with a gap for it.
	local pathStart = 4.5
	Parts.block(
		house,
		"Path",
		Vector3.new(4, 0.12, yard - pathStart),
		at(0, 0.06, -(pathStart + (yard - pathStart) / 2)),
		"8A8680",
		M.Concrete
	)
	local fenceZ = -(yard - 0.6)
	local halfLot = lotWidth / 2 - 1
	Props.fence(house, (at(-halfLot, 0, fenceZ)).Position, (at(-2.6, 0, fenceZ)).Position, "picket")
	Props.fence(house, (at(2.6, 0, fenceZ)).Position, (at(halfLot, 0, fenceZ)).Position, "picket")
	Props.mailbox(house, at(3.4, 0, fenceZ + 1.2), rng:pick({ "2A2A2E", "8A3A2A", "2A4A2A" }))

	local treeSide = if rng:chance(0.5) then -1 else 1
	if rng:chance(0.75) then
		Props.tree(house, at(treeSide * (halfLot - 4), 0, -yard * 0.5), rng, "autumn")
	end
	for _ = 1, rng:int(0, 2) do
		Props.gravestone(
			house,
			at(-treeSide * rng:range(6, halfLot - 3), 0, -rng:range(5, yard - 4))
				* CFrame.Angles(0, rng:range(-0.3, 0.3), 0),
			rng
		)
	end

	house.Parent = parent
	return house, door
end

return Cottage
