--!strict
-- The Blender farmhouse (art/scripts/farmhouse.py, imported as ReplicatedStorage.Assets.Houses.Farmhouse),
-- one of the three houses on Cardboard Court: its lot is dressed from the generated data
-- (HouseData/Farmhouse) with a picket fence, and some of its rooms are lit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local BlenderLot = require(script.Parent.Parent.BlenderLot)
local Cottage = require(script.Parent.Cottage)
local data = require(script.Parent.Parent.HouseData.Farmhouse)

local Farmhouse = {}

Farmhouse.build = Cottage.build -- the built fallback when there's no model

function Farmhouse.dressLot(house: Model, base: CFrame, rng: Rng.Rng, yardDepth: number, lotWidth: number)
	BlenderLot.dress(house, base, rng, yardDepth, lotWidth, data)
end

return Farmhouse
