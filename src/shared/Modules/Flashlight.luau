--!strict
-- How much light a flashlight gives (Config/Items.FLASHLIGHT), the same on every screen (server time
-- and whose it is): full while the battery's good; under `low` of it left, dimmer (down to
-- `dimmest`) and going yellow, like a torch on tired batteries; under `flicker`, it stutters, the
-- dips coming more often and going deeper the lower it gets, till it's dead. Pure: drawn by
-- Controllers/FlashlightController, tested in tests/flashlight.spec.

local Items = require(script.Parent.Parent.Config.Items)

local Flashlight = {}

-- 0..1 of a full battery, from `seconds` of light left.
function Flashlight.charge(seconds: number): number
	return math.clamp(seconds / Items.FLASHLIGHT.battery, 0, 1)
end

-- With `charge` (0..1) left, at server time `t`, for the one belonging to `seed` (their UserId):
-- how bright it is (0..1 of full) and how far it's gone yellow (0..1).
function Flashlight.output(charge: number, t: number, seed: number): (number, number)
	local rules = Items.FLASHLIGHT
	if charge <= 0 then
		return 0, 1
	end
	local good = math.clamp(charge / rules.low, 0, 1) -- 1 while it's above `low`
	local level = rules.dimmest + (1 - rules.dimmest) * good ^ 0.6
	local yellow = 1 - good
	if charge < rules.flicker then
		local dying = 1 - charge / rules.flicker -- 0 as it starts to stutter, 1 at the end
		-- A dip whenever the noise crosses a line that drops the lower it gets: rarer and shallow at
		-- first, near constant and deep at the end.
		local noise = math.noise(t * (2.5 + dying * 9), (seed % 997) + 0.37, 0.61)
		if noise > 0.42 - dying * 0.55 then
			level *= 0.08 + 0.5 * (1 - dying)
		end
	end
	return level, yellow
end

return Flashlight
