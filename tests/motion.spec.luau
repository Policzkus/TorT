local Motion = rbx.require("src/shared/Modules/Motion")
local Movement = rbx.require("src/shared/Config/Movement")

local FRAME = 1 / 60
local WALK = 16

-- Seconds of 60 fps frames until the walk (vx, vz) is within 0.05 of (tx, tz), and the top speed on the way.
local function settle(vx, vz, tx, tz, scale)
	local t, top = 0, 0
	while math.abs(vx - tx) + math.abs(vz - tz) > 0.05 and t < 5 do
		vx, vz = Motion.accelerate(vx, vz, tx, tz, WALK, scale or 1, FRAME)
		top = math.max(top, math.sqrt(vx * vx + vz * vz))
		t += FRAME
	end
	return t, top
end

return {
	["from standing to a walk in about 1/ACCEL.start seconds"] = function()
		local t = settle(0, 0, 0, -WALK)
		expect(t).toBeNear(1 / Movement.ACCEL.start, 0.04)
	end,
	["a walk stops in about 1/ACCEL.stop seconds, a run takes longer"] = function()
		expect((settle(0, -WALK, 0, 0))).toBeNear(1 / Movement.ACCEL.stop, 0.04)
		local run = WALK * Movement.SPRINT
		expect((settle(0, -run, 0, 0))).toBeNear(Movement.SPRINT / Movement.ACCEL.stop, 0.04)
	end,
	["a run builds up more slowly than a walk"] = function()
		local run = WALK * Movement.SPRINT
		local t = settle(0, -WALK, 0, -run)
		expect(t).toBeNear((Movement.SPRINT - 1) / Movement.ACCEL.sprint, 0.04)
		-- From standing: quickly to a walk, then the slow part.
		local fromStill = settle(0, 0, 0, -run)
		expect(fromStill).toBeNear(1 / Movement.ACCEL.start + (Movement.SPRINT - 1) / Movement.ACCEL.sprint, 0.05)
	end,
	["turning never goes faster than you were going"] = function()
		local t, top = settle(0, -WALK, WALK, 0)
		expect(top <= WALK + 1e-6).toBeTruthy()
		expect(t < 0.3).toBeTruthy()
	end,
	["in the air you keep most of your momentum"] = function()
		local vx, vz = 0, -WALK
		for _ = 1, 12 do -- 0.2 s with nothing pressed
			vx, vz = Motion.accelerate(vx, vz, 0, 0, WALK, Movement.ACCEL.air, FRAME)
		end
		expect(-vz > WALK * 0.7).toBeTruthy()
	end,
	["a long frame can't overshoot"] = function()
		local vx, vz = Motion.accelerate(0, 0, 0, -WALK, WALK, 1, 2)
		expect(vx).toBe(0)
		expect(vz).toBe(-WALK)
		vx, vz = Motion.accelerate(0, -WALK, 0, 0, WALK, 1, 2)
		expect(math.abs(vz) < 1e-9).toBeTruthy()
	end,
	["the spring settles on its target, overshooting a little under damping 1"] = function()
		local x, v, peak = 0, 0, 0
		for _ = 1, 120 do
			x, v = Motion.spring(x, v, 1, 16, 0.75, FRAME)
			peak = math.max(peak, x)
		end
		expect(x).toBeNear(1, 1e-3)
		expect(peak > 1 and peak < 1.06).toBeTruthy()
		-- Big hitches: each counts as 0.1 s at most, and it stays steady.
		local y, w = 0, 0
		for _ = 1, 3 do
			y, w = Motion.spring(y, w, 1, 16, 1, 0.5)
		end
		expect(y > 0.9 and y <= 1).toBeTruthy()
		expect(math.abs(w) < 1).toBeTruthy()
	end,
	["ease gets the same place however the frames fall"] = function()
		local a = Motion.ease(0, 1, 5, 0.2)
		local b = 0
		for _ = 1, 4 do
			b = Motion.ease(b, 1, 5, 0.05)
		end
		expect(a).toBeNear(b, 1e-9)
	end,
	["sprinting counts only going forward"] = function()
		expect(Motion.sprintShare(1)).toBe(1)
		expect(Motion.sprintShare(Movement.FORWARD.full)).toBe(1)
		expect(Motion.sprintShare(0)).toBe(0)
		expect(Motion.sprintShare(-1)).toBe(0)
		local diagonal = Motion.sprintShare(math.sqrt(0.5))
		expect(diagonal > 0.5 and diagonal < 1).toBeTruthy()
	end,
	["strides are STRIDE at speed 16, longer when faster, never zero"] = function()
		expect(Motion.stride(16, 0)).toBeNear(Movement.STRIDE, 1e-9)
		expect(Motion.stride(26, 0) > Motion.stride(16, 0)).toBeTruthy()
		expect(Motion.stride(0, 0) > 0).toBeTruthy()
		expect(Motion.stride(8, 1) > Motion.stride(8, 0)).toBeTruthy()
	end,
	["the head is lowest as a foot lands, level mid-stride, every π"] = function()
		expect(Motion.footfall(0)).toBeNear(1, 1e-9)
		expect(Motion.footfall(math.pi / 2)).toBeNear(0, 1e-9)
		expect(Motion.footfall(math.pi * 3)).toBeNear(1, 1e-9)
		expect(Motion.footfall(math.pi * 3 + 0.3)).toBeNear(Motion.footfall(0.3), 1e-9)
	end,
	["crouched eyes are CROUCH_EYE of standing ones"] = function()
		local hip, box = 2, 2.4 -- eyes just over hip + box
		expect(hip + box - Motion.crouchDrop(hip, box)).toBeNear((hip + box) * Movement.CROUCH_EYE, 1e-9)
	end,
	["a crouch only counts at a crouch walk"] = function()
		expect(Motion.creeping(true, 0, 16)).toBe(true)
		expect(Motion.creeping(true, 16 * Movement.CROUCH, 16)).toBe(true)
		expect(Motion.creeping(true, 16, 16)).toBe(false)
		expect(Motion.creeping(false, 2, 16)).toBe(false)
		expect(Motion.creeping(true, 12, 26)).toBe(true) -- faster Sneakers creep faster
	end,
	["a jump's landing is felt, but less than a big drop"] = function()
		expect(Motion.landingImpact(Movement.LANDING.felt)).toBe(0)
		local jump = Motion.landingImpact(50)
		expect(jump > 0.2 and jump < 0.5).toBeTruthy()
		expect(Motion.landingImpact(1000)).toBe(1)
	end,
	["only hard landings slow you"] = function()
		expect(Motion.landingSlow(10)).toBe(1)
		expect(Motion.landingSlow(53)).toBe(1) -- an ordinary jump
		expect(Motion.landingSlow(Movement.LANDING.from)).toBe(1)
		expect(Motion.landingSlow(Movement.LANDING.full)).toBeNear(Movement.LANDING.slow, 1e-9)
		expect(Motion.landingSlow(500)).toBeNear(Movement.LANDING.slow, 1e-9)
	end,
}
