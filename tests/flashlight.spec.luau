local Flashlight = rbx.require("src/shared/Modules/Flashlight")
local Items = rbx.require("src/shared/Config/Items")

local RULES = Items.FLASHLIGHT

-- Its level without a dip (under `low`), for `charge` left.
local function steady(charge)
	local left = math.clamp(charge / RULES.low, 0, 1)
	return RULES.dimmest + (RULES.fade - RULES.dimmest) * left ^ 0.6
end

-- Share of moments over `seconds` (every 1/60 s) its light is dipped well under its steady level.
local function dips(charge, seconds, recovery)
	local count, total = 0, 0
	for i = 0, seconds * 60 do
		local level = Flashlight.output(charge, 1000 + i / 60, 4710305538, recovery)
		if level < steady(charge) * 0.7 then
			count += 1
		end
		total += 1
	end
	return count / total
end

return {
	["a fresh battery gives full, white light"] = function()
		local level, yellow = Flashlight.output(1, 10, 1)
		expect(level).toBe(1)
		expect(yellow).toBe(0)
		level, yellow = Flashlight.output(0.95, 10, 1)
		expect(level > 0.98).toBeTruthy()
		expect(yellow < 0.03).toBeTruthy()
	end,
	["it dims slowly through its life, going warmer, then fast"] = function()
		local last, lastYellow = math.huge, -1
		for i = 100, math.floor(RULES.flicker * 100) + 1, -1 do
			local level, yellow = Flashlight.output(i / 100, 10, 1)
			expect(level <= last + 1e-9).toBeTruthy()
			expect(yellow >= lastYellow - 1e-9).toBeTruthy()
			last, lastYellow = level, yellow
		end
		-- By `low` left it's at `fade` of full, a little warm: most of its life is still good light.
		local atLow, yellow = Flashlight.output(RULES.low, 10, 1)
		expect(atLow).toBeNear(RULES.fade, 1e-6)
		expect(yellow).toBeNear(0.25, 1e-6)
		-- Halfway through, still most of it.
		expect((Flashlight.output(0.65, 10, 1)) > 0.9).toBeTruthy()
	end,
	["a tired battery dims and yellows, never below dimmest before the stutter"] = function()
		local level, yellow = Flashlight.output(RULES.low / 2, 10, 1)
		expect(level < RULES.fade and level > RULES.dimmest).toBeTruthy()
		expect(yellow > 0.55 and yellow < 0.7).toBeTruthy()
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
	["a dying battery left off a while picks up a little, for a while"] = function()
		expect(Flashlight.recovery(0, 0)).toBe(0)
		expect(Flashlight.recovery(RULES.rest.full, 0)).toBe(1)
		expect(Flashlight.recovery(RULES.rest.full * 3, 0)).toBe(1)
		expect(Flashlight.recovery(RULES.rest.full / 2, 0)).toBeNear(0.5, 1e-9)
		expect(Flashlight.recovery(RULES.rest.full, RULES.rest.lasts)).toBeNear(math.exp(-1), 1e-9)
		-- Rested, it stutters less and gives a little more.
		local charge = RULES.flicker * 0.5
		expect(dips(charge, 30, 1) < dips(charge, 30, 0)).toBeTruthy()
		expect((Flashlight.output(0.2, 10, 1, 1)) > (Flashlight.output(0.2, 10, 1, 0))).toBeTruthy()
		-- Never more than a new one.
		expect((Flashlight.output(1, 10, 1, 1))).toBe(1)
	end,
	["light comes back off what it's pointed at: more, over less, up close"] = function()
		local near, nearRadius = Flashlight.bounce(3, 60, 1)
		local far, farRadius = Flashlight.bounce(40, 60, 1)
		expect(near > far).toBeTruthy()
		expect(nearRadius < farRadius).toBeTruthy()
		expect((Flashlight.bounce(60, 60, 1))).toBe(0)
		expect((Flashlight.bounce(3, 60, 0.2)) < near).toBeTruthy() -- a dark surface gives back less
		expect(nearRadius >= RULES.bounce.near and farRadius <= RULES.bounce.far).toBeTruthy()
	end,
	["a light in your eyes dazzles you, straight on and close the most"] = function()
		expect(Flashlight.glare(1, 0)).toBe(1)
		expect(Flashlight.glare(math.cos(math.rad(RULES.glare.cone + 1)), 5)).toBe(0)
		expect(Flashlight.glare(1, RULES.glare.range)).toBe(0)
		expect(Flashlight.glare(1, 10) > Flashlight.glare(1, 30)).toBeTruthy()
		expect(Flashlight.glare(1, 10) > Flashlight.glare(math.cos(math.rad(RULES.glare.cone / 2)), 10)).toBeTruthy()
	end,
	["charge is the share of a new battery"] = function()
		expect(Flashlight.charge(RULES.battery)).toBe(1)
		expect(Flashlight.charge(RULES.battery / 2)).toBeNear(0.5, 1e-9)
		expect(Flashlight.charge(-5)).toBe(0)
		expect(Flashlight.charge(RULES.battery * 2)).toBe(1)
	end,
}
