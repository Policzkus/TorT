--!strict
-- The Blender Second Empire mansion (art/scripts/mansard.py, imported as
-- ReplicatedStorage.Assets.Houses.Mansard), standing between the Victorians on Cardboard Court:
-- its lot is dressed from the generated data (HouseData/Mansard) and some of its rooms are lit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local BlenderLot = require(script.Parent.Parent.BlenderLot)
local Victorian = require(script.Parent.Victorian)
local data = require(script.Parent.Parent.HouseData.Mansard)

local Mansard = {}

Mansard.build = Victorian.build -- the built fallback when there's no model

function Mansard.dressLot(house: Model, base: CFrame, rng: Rng.Rng, yardDepth: number, lotWidth: number)
	BlenderLot.dress(house, base, rng, yardDepth, lotWidth, data)
end

return Mansard
