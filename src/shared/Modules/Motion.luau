--!strict
-- The maths of moving (Controllers/MovementController, CameraController, ViewmodelController,
-- CharacterAnimController; Services/KniferService): plain numbers only, so the tests run it outside
-- Roblox. Tuning lives in Config/Movement.

local Movement = require(script.Parent.Parent.Config.Movement)

local Motion = {}

-- Eases `x` toward `target`, the same however the frames fall: `rate` is how quickly (per second).
function Motion.ease(x: number, target: number, rate: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-rate * dt))
end

-- A damped spring: `x` (moving at `v`) pulled toward `target`. `frequency` is how quickly (radians a
-- second), `damping` 1 settles without overshooting, under 1 overshoots a little. Returns the new x
-- and v. Steps in small slices so a long frame can't throw it off.
function Motion.spring(
	x: number,
	v: number,
	target: number,
	frequency: number,
	damping: number,
	dt: number
): (number, number)
	local remaining = math.min(dt, 0.1)
	while remaining > 0 do
		local h = math.min(remaining, 1 / 120)
		remaining -= h
		v += ((target - x) * frequency * frequency - v * 2 * damping * frequency) * h
		x += v * h
	end
	return x, v
end

-- One frame of your walk (vx, vz: studs/s along the ground) easing toward what you're pressing (tx,
-- tz). Speeding up goes at ACCEL.start up to a walk and ACCEL.sprint past it, slowing down at
-- ACCEL.stop, turning at ACCEL.turn: walking speeds (`walk`) per second, times `scale` (ACCEL.air
-- off the ground).
function Motion.accelerate(
	vx: number,
	vz: number,
	tx: number,
	tz: number,
	walk: number,
	scale: number,
	dt: number
): (number, number)
	local rates = Movement.ACCEL
	local per = walk * scale
	local dx, dz = tx - vx, tz - vz
	local speed = math.sqrt(vx * vx + vz * vz)
	if speed < 1e-3 then
		local change = math.sqrt(dx * dx + dz * dz)
		local most = rates.start * per * dt
		if change <= most then
			return tx, tz
		end
		return vx + dx / change * most, vz + dz / change * most
	end
	local ux, uz = vx / speed, vz / speed
	-- Along the way you're going: slowing down, or speeding up (quickly to a walk, slower past it).
	local along = dx * ux + dz * uz
	local change: number
	if along < 0 then
		change = math.max(along, -rates.stop * per * dt)
	else
		local left = dt
		local gained = 0
		if speed < walk then
			local start = rates.start * per
			local toWalk = math.min(along, walk - speed)
			if toWalk >= start * left then
				gained, left = start * left, 0
			else
				gained, left = toWalk, left - toWalk / start
			end
		end
		change = gained + math.min(along - gained, rates.sprint * per * left)
	end
	-- Across it: turning.
	local px, pz = dx - along * ux, dz - along * uz
	local across = math.sqrt(px * px + pz * pz)
	local most = rates.turn * per * dt
	if across > most then
		px, pz = px / across * most, pz / across * most
	end
	return vx + ux * change + px, vz + uz * change + pz
end

-- How much of a sprint counts, moving this far toward where you look (the dot of the two, -1..1).
function Motion.sprintShare(forward: number): number
	local range = Movement.FORWARD
	return math.clamp((forward - range.none) / (range.full - range.none), 0, 1)
end

-- Studs between footfalls at `speed`, `crouch` (0..1) down: longer strides when faster, a creep's a
-- little longer and slower.
function Motion.stride(speed: number, crouch: number): number
	return Movement.STRIDE * math.sqrt(math.max(speed / 16, 0.4)) * (1 + 0.15 * crouch)
end

-- How far into the dip of a step the head is (1 as a foot lands, 0 mid-stride), from the gait's
-- phase (π a step: a foot lands at each multiple of π). Sharp at the footfall, flat between.
function Motion.footfall(phase: number): number
	local s = phase % math.pi
	return (0.5 + 0.5 * math.cos(2 * s)) ^ 1.5
end

-- Studs your eyes go down crouching, for a body `hipHeight` to the hips with a root box `rootHeight`
-- tall above them (Modules/CharacterRig: the box goes from the hips to just under the eyes).
function Motion.crouchDrop(hipHeight: number, rootHeight: number): number
	return (hipHeight + rootHeight) * (1 - Movement.CROUCH_EYE)
end

-- Is someone who says they're crouching really creeping (no faster than a crouch walk), for `base`
-- their walking speed?
function Motion.creeping(crouching: boolean, speed: number, base: number): boolean
	return crouching and speed <= base * Movement.CROUCH * Movement.CROUCH_GRACE
end

-- How hard a landing from a fall at `fall` studs/s is felt (0..1).
function Motion.landingImpact(fall: number): number
	local landing = Movement.LANDING
	return math.clamp((fall - landing.felt) / (landing.hardest - landing.felt), 0, 1)
end

-- Your speed just after landing from a fall at `fall` studs/s, as a share of what it should be.
function Motion.landingSlow(fall: number): number
	local landing = Movement.LANDING
	local hard = math.clamp((fall - landing.from) / (landing.full - landing.from), 0, 1)
	return 1 - (1 - landing.slow) * hard
end

return Motion
