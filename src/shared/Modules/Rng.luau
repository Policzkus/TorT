--!strict
-- Deterministic pseudo-random numbers (Park-Miller "minimal standard" LCG).
-- The same seed gives the same sequence on the server, the client and in Lune tests, so both
-- sides can rebuild a mini-game or a world layout from just a seed.
-- Not for anything security-sensitive: the server still decides every reward.

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 48271 -- state * MULTIPLIER stays below 2^53, so the math is exact in doubles
local WARMUP = 4 -- nearby seeds give nearby first outputs; skip them

export type Rng = {
	next: (self: Rng) -> number,
	int: (self: Rng, min: number, max: number) -> number,
	range: (self: Rng, min: number, max: number) -> number,
	chance: (self: Rng, probability: number) -> boolean,
	pick: (self: Rng, list: { any }) -> any,
	weighted: (self: Rng, weights: { [string]: number }) -> string?,
	shuffle: (self: Rng, list: { any }) -> (),
}

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % (MODULUS - 1) + 1
	local self = setmetatable({ _state = state }, Rng) :: any
	for _ = 1, WARMUP do
		self:next()
	end
	return self
end

-- Uniform in [0, 1).
function Rng.next(self: any): number
	self._state = (self._state * MULTIPLIER) % MODULUS
	return (self._state - 1) / (MODULUS - 1)
end

-- Integer in [min, max], both inclusive.
function Rng.int(self: any, min: number, max: number): number
	return min + math.floor(self:next() * (max - min + 1))
end

-- Float in [min, max).
function Rng.range(self: any, min: number, max: number): number
	return min + self:next() * (max - min)
end

function Rng.chance(self: any, probability: number): boolean
	return self:next() < probability
end

function Rng.pick(self: any, list: { any }): any
	return list[self:int(1, #list)]
end

-- Picks a key with probability proportional to its weight. Keys are sorted first so the
-- result never depends on table iteration order.
function Rng.weighted(self: any, weights: { [string]: number }): string?
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys)
	local roll = self:next() * total
	for _, key in keys do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

-- Fisher-Yates, in place.
function Rng.shuffle(self: any, list: { any })
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

return Rng
