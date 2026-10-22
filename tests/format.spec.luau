local Format = rbx.require("src/shared/Modules/Format")

return {
	["small numbers stay whole"] = function()
		expect(Format.number(0)).toBe("0")
		expect(Format.number(7.9)).toBe("7")
		expect(Format.number(999)).toBe("999")
	end,
	["suffixes truncate instead of rounding"] = function()
		expect(Format.number(1000)).toBe("1K")
		expect(Format.number(1230)).toBe("1.23K")
		expect(Format.number(1234)).toBe("1.23K")
		expect(Format.number(12345)).toBe("12.3K")
		expect(Format.number(123456)).toBe("123K")
		expect(Format.number(999999)).toBe("999K")
		expect(Format.number(1.5e6)).toBe("1.5M")
		expect(Format.number(2.5e9)).toBe("2.5B")
		expect(Format.number(1e12)).toBe("1T")
	end,
	["float error does not drop a digit"] = function()
		expect(Format.number(1.23e3)).toBe("1.23K")
		expect(Format.number(4.56e6)).toBe("4.56M")
		expect(Format.number(1.1e3)).toBe("1.1K")
	end,
	["negatives and non-finite"] = function()
		expect(Format.number(-1500)).toBe("-1.5K")
		expect(Format.number(0 / 0)).toBe("0")
		expect(Format.number(math.huge)).toBe("∞")
	end,
	["huge values use the last suffix instead of crashing"] = function()
		expect(string.sub(Format.number(1e40), -2)).toBe("Dc")
	end,
	["commas"] = function()
		expect(Format.commas(0)).toBe("0")
		expect(Format.commas(999)).toBe("999")
		expect(Format.commas(1234)).toBe("1,234")
		expect(Format.commas(1234567)).toBe("1,234,567")
		expect(Format.commas(-100000)).toBe("-100,000")
	end,
	["clock and duration"] = function()
		expect(Format.clock(65)).toBe("1:05")
		expect(Format.clock(3723)).toBe("1:02:03")
		expect(Format.duration(45)).toBe("45s")
		expect(Format.duration(125)).toBe("2m 5s")
		expect(Format.duration(120)).toBe("2m")
		expect(Format.duration(7500)).toBe("2h 5m")
	end,
}
