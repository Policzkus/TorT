--!strict
-- Cardboard Court: faded mobile homes on cinder blocks, chain-link fences, warm porch lights.
-- `base` is the ground point at the front-centre of the house; local -Z faces the street.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Parts = require(script.Parent.Parent.Parts)
local Props = require(script.Parent.Parent.Props)

local M = Enum.Material

local BODY_COLORS = { "E6D8B4", "B6D6C6", "E6B6A6", "B6C6DE", "D6CE9E", "CFC6D8" }
local DOOR_COLORS = { "F2EEE6", "8A3A2A", "4A5A3A", "3A4A6A" }

local Trailer = {}

function Trailer.build(parent: Instance, base: CFrame, rng: Rng.Rng, yard: number, lotWidth: number): (Model, BasePart)
	local house = Instance.new("Model")
	house.Name = "Trailer"
	local width, depth, height, lift = rng:pick({ 22, 24, 26 }), 12, 9, 1.5
	local body = rng:pick(BODY_COLORS)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	Parts.block(house, "Body", Vector3.new(width, height, depth), at(0, lift + height / 2, depth / 2), body, M.Plastic)
	Parts.decor(
		Parts.block(
			house,
			"Stripe",
			Vector3.new(width + 0.1, 0.7, depth + 0.1),
			at(0, lift + height * 0.42, depth / 2),
			"F4F0E8",
			M.Plastic
		)
	)
	Parts.block(
		house,
		"Roof",
		Vector3.new(width + 0.8, 0.6, depth + 0.8),
		at(0, lift + height + 0.3, depth / 2),
		"7E7A78",
		M.CorrodedMetal
	)
	Parts.block(
		house,
		"Skirt",
		Vector3.new(width - 0.6, lift, depth - 0.6),
		at(0, lift / 2, depth / 2),
		"5A5048",
		M.WoodPlanks
	)

	local doorX = if rng:chance(0.5) then -width / 2 + 6 else width / 2 - 6
	local door = Parts.block(
		house,
		"Door",
		Vector3.new(3.6, 6.6, 0.3),
		at(doorX, lift + 3.3, -0.15),
		rng:pick(DOOR_COLORS),
		M.Wood
	)
	Parts.decor(
		Parts.block(house, "DoorWindow", Vector3.new(1.6, 1.4, 0.1), at(doorX, lift + 5, -0.32), "1E2436", M.Glass)
	)
	Parts.decor(
		Parts.block(house, "Knob", Vector3.new(0.3, 0.3, 0.2), at(doorX + 1.3, lift + 3.1, -0.36), "D4B04A", M.Metal)
	)

	-- Wooden landing and step up to the door.
	Parts.block(house, "Landing", Vector3.new(6, lift, 4), at(doorX, lift / 2, -2), "6A5038", M.WoodPlanks)
	Parts.block(house, "Step", Vector3.new(6, lift / 2, 1.6), at(doorX, lift / 4, -4.8), "6A5038", M.WoodPlanks)
	for _, x in { -2.9, 2.9 } do
		Parts.decor(
			Parts.block(house, "Rail", Vector3.new(0.25, 2.6, 4), at(doorX + x, lift + 1.3, -2), "4A3828", M.Wood)
		)
	end

	-- Windows: lit ones glow warm, dark ones look empty.
	for x = -width / 2 + 4, width / 2 - 4, 6 do
		if math.abs(x - doorX) > 4.5 then
			local lit = rng:chance(0.6)
			Parts.decor(
				Parts.block(
					house,
					"Window",
					Vector3.new(3.6, 2.8, 0.2),
					at(x, lift + height * 0.6, -0.05),
					if lit then "FFD27A" else "1E2436",
					if lit then M.Neon else M.Glass
				)
			)
		end
	end

	local porchLight = Parts.decor(
		Parts.block(
			house,
			"PorchLight",
			Vector3.new(0.5, 0.8, 0.4),
			at(doorX + 2.6, lift + 5.6, -0.25),
			"FFE0A0",
			M.Neon
		)
	)
	Parts.light(porchLight, 16, 1.6, "FFB870")

	for i = 1, rng:int(1, 2) do
		Props.pumpkin(house, at(doorX - 2.2 + (i - 1) * 4.4, lift, -3), rng:range(1.3, 1.8))
	end

	-- Path from the step to the sidewalk, chain-link fence along the front with a gap for it.
	local pathStart = 5.6
	Parts.block(
		house,
		"Path",
		Vector3.new(4, 0.12, yard - pathStart),
		at(doorX, 0.06, -(pathStart + (yard - pathStart) / 2)),
		"7A766E",
		M.Concrete
	)
	local fenceZ = -(yard - 0.6)
	local halfLot = lotWidth / 2 - 1
	Props.fence(house, (at(-halfLot, 0, fenceZ)).Position, (at(doorX - 2.6, 0, fenceZ)).Position, "chain")
	Props.fence(house, (at(doorX + 2.6, 0, fenceZ)).Position, (at(halfLot, 0, fenceZ)).Position, "chain")
	Props.mailbox(house, at(doorX + 3.4, 0, fenceZ + 1.2), rng:pick({ "6E7278", "3A4A6A", "8A3A2A" }))

	-- One or two bits of trailer-park clutter.
	local otherSide = if doorX < 0 then 1 else -1
	if rng:chance(0.55) then
		Props.flamingo(
			house,
			at(otherSide * rng:range(4, 10), 0, -rng:range(4, yard - 4)) * CFrame.Angles(0, rng:range(0, 6.28), 0)
		)
	end
	if rng:chance(0.5) then
		Props.trashCan(house, at(otherSide * (width / 2 + 2.5), 0, depth * 0.3))
	end
	if rng:chance(0.35) then
		Props.tree(house, at(otherSide * (halfLot - 3), 0, -yard * 0.45), rng, "dead")
	end

	house.Parent = parent
	return house, door
end

return Trailer
