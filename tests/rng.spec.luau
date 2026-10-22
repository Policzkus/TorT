local Rng = rbx.require("src/shared/Modules/Rng")

return {
	["same seed gives the same sequence"] = function()
		local a, b = Rng.new(1234), Rng.new(1234)
		for _ = 1, 100 do
			expect(a:next()).toBe(b:next())
		end
	end,
	["outputs stay in [0, 1)"] = function()
		local rng = Rng.new(7)
		for _ = 1, 10000 do
			local value = rng:next()
			if value < 0 or value >= 1 then
				error(`out of range: {value}`)
			end
		end
	end,
	["neighbouring seeds diverge"] = function()
		expect(math.abs(Rng.new(1):next() - Rng.new(2):next()) > 0.01).toBe(true)
	end,
	["int is inclusive and roughly uniform"] = function()
		local rng = Rng.new(99)
		local counts = { 0, 0, 0, 0 }
		for _ = 1, 40000 do
			local value = rng:int(1, 4)
			counts[value] += 1
		end
		for value = 1, 4 do
			expect(counts[value]).toBeNear(10000, 400)
		end
	end,
	["weighted follows the weights and ignores key order"] = function()
		local rng = Rng.new(5)
		local counts = { a = 0, b = 0, c = 0 }
		for _ = 1, 30000 do
			local key = rng:weighted({ c = 1, a = 3, b = 0, d = -5 }) :: string
			counts[key] += 1
		end
		expect(counts.b).toBe(0)
		expect(counts.a / 30000).toBeNear(0.75, 0.015)
		expect(Rng.new(5):weighted({ x = 1 })).toBe("x")
		expect(Rng.new(5):weighted({})).toBe(nil)
	end,
}
