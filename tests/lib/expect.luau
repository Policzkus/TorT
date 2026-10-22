--!strict
-- Minimal assertions for specs.

local function show(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

local function expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(`expected {show(expected)}, got {show(actual)}`, 2)
			end
		end,
		toBeNear = function(expected: number, tolerance: number)
			if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
				error(`expected {show(expected)} ± {tolerance}, got {show(actual)}`, 2)
			end
		end,
		toBeTruthy = function()
			if not actual then
				error(`expected a truthy value, got {show(actual)}`, 2)
			end
		end,
		toBeFalsy = function()
			if actual then
				error(`expected a falsy value, got {show(actual)}`, 2)
			end
		end,
	}
end

return expect
