--!strict
-- How much light a flashlight gives (Config/Items.FLASHLIGHT), the same on every screen (server time
-- and whose it is). Like a torch on real cells: a fresh one is at full and white, and dims slowly as
-- it's used, going a little warmer (to `fade` of full by `low` left); then the cells give out fast,
-- the light dimmer (down to `dimmest`) and yellow; under `flicker` it stutters (a sagging cell, a
-- loose contact), the dips coming more often and going deeper the lower it gets, a slow wavering
-- under them, till it's dead. Left off a while, a tired battery picks up a little (`rest`).
-- Also how much light comes back off what the beam hits (bounce), and how much a light pointed at
-- you dazzles you (glare). Pure: drawn by Controllers/FlashlightController, tested in
-- tests/flashlight.spec.

local Items = require(script.Parent.Parent.Config.Items)

local Flashlight = {}

-- 0..1 of a full battery, from `seconds` of light left.
function Flashlight.charge(seconds: number): number
	return math.clamp(seconds / Items.FLASHLIGHT.battery, 0, 1)
end

-- 0..1: how much a tired battery has picked up, having been off `rested` seconds before it was
-- switched on `since` seconds ago (it fades once it's on again).
function Flashlight.recovery(rested: number, since: number): number
	local rest = Items.FLASHLIGHT.rest
	return math.clamp(rested / rest.full, 0, 1) * math.exp(-math.max(since, 0) / rest.lasts)
end

-- With `charge` (0..1) left, at server time `t`, for the one belonging to `seed` (their UserId), a
-- tired battery having picked up `recovery` (0..1, Flashlight.recovery): how bright it is (0..1 of
-- full) and how far it's gone yellow (0..1).
function Flashlight.output(charge: number, t: number, seed: number, recovery: number?): (number, number)
	local rules = Items.FLASHLIGHT
	if charge <= 0 then
		return 0, 1
	end
	-- (A rested battery: a little more to give for a while, never more than it had new.)
	local c = math.min(1, charge + rules.rest.gain * (recovery or 0))
	local level, yellow
	if c >= rules.low then
		local used = 1 - (c - rules.low) / (1 - rules.low) -- 0 new .. 1 at `low`
		level = 1 - (1 - rules.fade) * used ^ 1.25
		yellow = 0.25 * used
	else
		local left = c / rules.low -- 1 at `low` .. 0 dead
		level = rules.dimmest + (rules.fade - rules.dimmest) * left ^ 0.6
		yellow = 0.25 + 0.75 * (1 - left)
	end
	if c < rules.flicker then
		local dying = 1 - c / rules.flicker -- 0 as it starts to stutter, 1 at the end
		local key = (seed % 997) + 0.37
		-- A slow wavering, the cells sagging and catching...
		local waver = (math.noise(t * 1.3, key, 4.2) + 1) / 2
		level *= 1 - 0.18 * dying * waver
		-- ...and a dip whenever the noise crosses a line that drops the lower it gets: rarer and
		-- shallow at first, near constant and deep at the end.
		local noise = math.noise(t * (2.5 + dying * 9), key, 0.61)
		if noise > 0.42 - dying * 0.55 then
			level *= 0.08 + 0.5 * (1 - dying)
		end
	end
	return level, yellow
end

-- The light coming back off what the beam hits `distance` studs out (of a beam reaching `range`),
-- off a surface that reflects `reflect` (0..1, how light it is): how bright (0..1 of the bounce's
-- brightness) and how far round the spot it lights (studs). Close up, a lot comes back over a small
-- patch; further off, a dimmer glow over more.
function Flashlight.bounce(distance: number, range: number, reflect: number): (number, number)
	local rules = Items.FLASHLIGHT.bounce
	local k = math.clamp(distance / range, 0, 1)
	local strength = (1 - k) ^ 2 * math.clamp(reflect, 0, 1)
	return strength, rules.near + (rules.far - rules.near) * k
end

-- How much a light `distance` studs off, pointed `alignment` (the cosine of the angle between where
-- it points and you) at you, dazzles you: 0..1.
function Flashlight.glare(alignment: number, distance: number): number
	local rules = Items.FLASHLIGHT.glare
	local cone = math.cos(math.rad(rules.cone))
	if alignment <= cone or distance >= rules.range then
		return 0
	end
	local aimed = (alignment - cone) / (1 - cone)
	local near = 1 - distance / rules.range
	return math.clamp(aimed * aimed * near, 0, 1)
end

return Flashlight
