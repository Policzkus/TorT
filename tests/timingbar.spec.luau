local TimingBar = rbx.require("src/shared/Modules/Minigames/TimingBar")

-- First time the needle reaches `position` while moving right (no reversals).
local function firstPass(spec, position)
	return position * spec.sweep
end

return {
	["the same seed rebuilds the same challenge"] = function()
		local a, b = TimingBar.generate(42, 7), TimingBar.generate(42, 7)
		expect(a.zones[1]).toBe(b.zones[1])
		expect(#a.reversals).toBe(#b.reversals)
		expect(TimingBar.needleAt(a, 1.234)).toBe(TimingBar.needleAt(b, 1.234))
	end,
	["needle bounces between 0 and 1"] = function()
		local spec = TimingBar.generate(1, 1)
		expect(TimingBar.needleAt(spec, 0)).toBe(0)
		expect(TimingBar.needleAt(spec, spec.sweep)).toBeNear(1, 1e-9)
		expect(TimingBar.needleAt(spec, spec.sweep * 1.5)).toBeNear(0.5, 1e-9)
		expect(TimingBar.needleAt(spec, spec.sweep * 2)).toBeNear(0, 1e-9)
	end,
	["difficulty scales hits, speed and zones"] = function()
		local easy, hard = TimingBar.generate(3, 1), TimingBar.generate(3, 8)
		expect(#easy.zones).toBe(1)
		expect(#hard.zones).toBe(2)
		expect(easy.sweep).toBeNear(1.6, 1e-9)
		expect(hard.sweep).toBeNear(0.7, 1e-9)
		expect(easy.widths.PERFECT > hard.widths.PERFECT).toBe(true)
		expect(#easy.reversals).toBe(0)
		expect(#hard.reversals > 0).toBe(true)
	end,
	["low difficulty finishes within 4 seconds"] = function()
		expect(TimingBar.generate(9, 1).timeout <= 4.3).toBe(true)
	end,
	["tapping the zone centre is PERFECT, far away is MISS"] = function()
		local spec = TimingBar.generate(11, 1)
		local t = firstPass(spec, spec.zones[1])
		expect(TimingBar.gradeAt(spec, 1, t)).toBe("PERFECT")
		expect(TimingBar.gradeAt(spec, 1, 0.13)).toBe("MISS")
	end,
	["grades widen around the centre"] = function()
		local spec = TimingBar.generate(12, 1)
		local zone = spec.zones[1]
		local great = zone + (spec.widths.PERFECT + spec.widths.GREAT) / 4
		local good = zone + (spec.widths.GREAT + spec.widths.GOOD) / 4
		expect(TimingBar.gradeAt(spec, 1, firstPass(spec, great))).toBe("GREAT")
		expect(TimingBar.gradeAt(spec, 1, firstPass(spec, good))).toBe("GOOD")
	end,
	["two-hit grade is the rounded-down average"] = function()
		local spec = TimingBar.generate(13, 5)
		expect(#spec.zones).toBe(2)
		local perfect1 = firstPass(spec, spec.zones[1])
		local grade, perHit = TimingBar.grade(spec, { perfect1 })
		expect(perHit[1]).toBe("PERFECT")
		expect(perHit[2]).toBe("MISS")
		expect(grade).toBe("GOOD") -- (3 + 0) / 2 = 1.5 -> GOOD
	end,
	["taps after the timeout are MISS"] = function()
		local spec = TimingBar.generate(14, 1)
		expect(TimingBar.gradeAt(spec, 1, spec.timeout + 0.01)).toBe("MISS")
	end,
	["tap validation rejects impossible input"] = function()
		local spec = TimingBar.generate(15, 5)
		expect(TimingBar.validTaps(spec, { 0.5, 1.0 }, 2)).toBe(true)
		expect(TimingBar.validTaps(spec, {}, 2)).toBe(true)
		expect(TimingBar.validTaps(spec, { 0.01 }, 2)).toBe(false) -- faster than human
		expect(TimingBar.validTaps(spec, { 0.5, 0.52 }, 2)).toBe(false) -- double tap too fast
		expect(TimingBar.validTaps(spec, { 1.9 }, 1)).toBe(false) -- claims a time that hasn't happened
		expect(TimingBar.validTaps(spec, { 0.5, 1.0, 1.5 }, 2)).toBe(false) -- too many taps
		expect(TimingBar.validTaps(spec, { 0 / 0 }, 2)).toBe(false)
		expect(TimingBar.validTaps(spec, "nope", 2)).toBe(false)
	end,
}
