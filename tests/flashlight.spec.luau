local Flashlight = rbx.require("src/shared/Modules/Flashlight")
local Items = rbx.require("src/shared/Config/Items")

local RULES = Items.FLASHLIGHT

-- Share of moments over `seconds` (every 1/60 s) its light is dipped well under its steady level.
local function dips(charge, seconds)
	local good = math.clamp(charge / RULES.low, 0, 1)
	local steady = RULES.dimmest + (1 - RULES.dimmest) * good ^ 0.6 -- its level without a dip
	local count, total = 0, 0
	for i = 0, seconds * 60 do
		local level = Flashlight.output(charge, 1000 + i / 60, 4710305538)
		if level < steady * 0.7 then
			count += 1
		end
		total += 1
	end
	return count / total
end

return {
	["a good battery gives full, white light"] = function()
		local level, yellow = Flashlight.output(1, 10, 1)
		expect(level).toBe(1)
		expect(yellow).toBe(0)
		level, yellow = Flashlight.output(RULES.low + 0.01, 10, 1)
		expect(level).toBe(1)
		expect(yellow).toBe(0)
	end,
	["a tired battery dims and yellows, never below dimmest before the stutter"] = function()
		local level, yellow = Flashlight.output(RULES.low / 2, 10, 1)
		expect(level < 1 and level > RULES.dimmest).toBeTruthy()
		expect(yellow > 0.4 and yellow < 0.6).toBeTruthy()
		local lower = Flashlight.output(RULES.low / 4, 10, 1)
		expect(lower < level).toBeTruthy()
	end,
	["dead is dark"] = function()
		local level, yellow = Flashlight.output(0, 10, 1)
		expect(level).toBe(0)
		expect(yellow).toBe(1)
	end,
	["it stutters only once it's nearly dead, more the lower it gets"] = function()
		expect(dips(RULES.flicker + 0.02, 20)).toBe(0)
		local early = dips(RULES.flicker * 0.8, 30)
		local late = dips(RULES.flicker * 0.1, 30)
		expect(late > early).toBeTruthy()
		expect(late > 0.2).toBeTruthy()
	end,
	["the same flicker on every screen"] = function()
		local a = Flashlight.output(0.05, 1234.5, 42)
		local b = Flashlight.output(0.05, 1234.5, 42)
		expect(a).toBe(b)
	end,
	["charge is the share of a new battery"] = function()
		expect(Flashlight.charge(RULES.battery)).toBe(1)
		expect(Flashlight.charge(RULES.battery / 2)).toBeNear(0.5, 1e-9)
		expect(Flashlight.charge(-5)).toBe(0)
		expect(Flashlight.charge(RULES.battery * 2)).toBe(1)
	end,
}
