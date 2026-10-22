local RateLimiter = rbx.require("src/shared/Modules/RateLimiter")

local function fakeClock()
	local now = 0
	return function()
		return now
	end, function(seconds: number)
		now += seconds
	end
end

return {
	["allows the burst then blocks"] = function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(1, 3, clock)
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(false)
	end,
	["refills over time, capped at burst"] = function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(2, 2, clock)
		limiter:allow("a")
		limiter:allow("a")
		expect(limiter:allow("a")).toBe(false)
		advance(0.5) -- +1 token
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(false)
		advance(100) -- capped at 2
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("a")).toBe(false)
	end,
	["keys are independent and clear resets"] = function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(1, 1, clock)
		expect(limiter:allow("a")).toBe(true)
		expect(limiter:allow("b")).toBe(true)
		expect(limiter:allow("a")).toBe(false)
		limiter:clear("a")
		expect(limiter:allow("a")).toBe(true)
	end,
}
