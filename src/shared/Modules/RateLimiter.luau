--!strict
-- Token bucket per key (usually a Player). `rate` tokens refill per second up to `burst`.
-- The clock is injectable so tests can control time.

export type RateLimiter = {
	allow: (self: RateLimiter, key: any) -> boolean,
	clear: (self: RateLimiter, key: any) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rate: number, burst: number, clock: (() -> number)?): RateLimiter
	local self = setmetatable({}, RateLimiter) :: any
	self._rate = rate
	self._burst = burst
	self._clock = clock or os.clock
	self._buckets = {} :: { [any]: Bucket }
	return self
end

function RateLimiter:allow(key: any): boolean
	local now = self._clock()
	local bucket: Bucket = self._buckets[key] or { tokens = self._burst, last = now }
	self._buckets[key] = bucket
	bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.last) * self._rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:clear(key: any)
	self._buckets[key] = nil
end

return RateLimiter
