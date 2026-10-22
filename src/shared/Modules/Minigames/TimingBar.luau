--!strict
-- Timing Bar rules, shared by the client (drawing) and the server (grading).
-- A needle sweeps a 0..1 bar and bounces at the ends; tap while it's inside the zone.
-- Everything comes from (seed, difficulty), so the server re-simulates exactly what the player saw.

local Config = script.Parent.Parent.Parent.Config
local Minigames = require(Config.Minigames)
local Rng = require(script.Parent.Parent.Rng)

local Rules = Minigames.TimingBar

export type Widths = { GOOD: number, GREAT: number, PERFECT: number }

export type Spec = {
	difficulty: number,
	sweep: number, -- seconds for one pass across the bar
	widths: Widths, -- full zone widths (fraction of the bar)
	zones: { number }, -- zone centre for each hit
	reversals: { number }, -- times (s) when the needle suddenly flips direction
	timeout: number, -- seconds until unhit hits count as MISS
}

local GRADE_SCORE = { MISS = 0, GOOD = 1, GREAT = 2, PERFECT = 3 }
local SCORE_GRADE = { [0] = "MISS", "GOOD", "GREAT", "PERFECT" }

local TimingBar = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function TimingBar.generate(seed: number, difficulty: number): Spec
	local d = math.clamp(math.floor(difficulty), Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local t = (d - Minigames.DIFFICULTY_MIN) / (Minigames.DIFFICULTY_MAX - Minigames.DIFFICULTY_MIN)
	local rng = Rng.new(seed)

	local widths: Widths = {
		GOOD = lerp(Rules.easyWidths.GOOD, Rules.hardWidths.GOOD, t),
		GREAT = lerp(Rules.easyWidths.GREAT, Rules.hardWidths.GREAT, t),
		PERFECT = lerp(Rules.easyWidths.PERFECT, Rules.hardWidths.PERFECT, t),
	}
	local sweep = lerp(Rules.easySweep, Rules.hardSweep, t)
	local hits = if d >= Rules.twoHitsFrom then 2 else 1

	local zones = {}
	for hit = 1, hits do
		local centre = rng:range(Rules.zoneMin, Rules.zoneMax)
		-- Keep consecutive zones apart so the second hit is a real second hit.
		for _ = 1, 4 do
			if hit == 1 or math.abs(centre - zones[hit - 1]) >= 0.2 then
				break
			end
			centre = rng:range(Rules.zoneMin, Rules.zoneMax)
		end
		zones[hit] = centre
	end

	local timeout = hits * sweep * Rules.passesPerHit + 0.3
	local reversals = {}
	if d >= Rules.reverseFrom then
		local at = rng:range(0.5, 1.1) * sweep
		while at < timeout do
			table.insert(reversals, at)
			at += rng:range(0.6, 1.4) * sweep
		end
	end

	return {
		difficulty = d,
		sweep = sweep,
		widths = widths,
		zones = zones,
		reversals = reversals,
		timeout = timeout,
	}
end

-- Needle position (0..1) at time t seconds after the start. Starts at 0 moving right.
function TimingBar.needleAt(spec: Spec, t: number): number
	local distance, direction, last = 0, 1, 0
	for _, flip in spec.reversals do
		if flip >= t then
			break
		end
		distance += direction * (flip - last)
		direction = -direction
		last = flip
	end
	distance += direction * (t - last)
	local phase = (distance / spec.sweep) % 2 -- Luau's % floors, so this is always in [0, 2)
	return if phase <= 1 then phase else 2 - phase
end

function TimingBar.gradeAt(spec: Spec, hit: number, t: number): string
	local zone = spec.zones[hit]
	if zone == nil or t > spec.timeout then
		return "MISS"
	end
	-- Compare the distance from the centre to HALF of each (full) zone width.
	local offset = math.abs(TimingBar.needleAt(spec, t) - zone) * 2
	if offset <= spec.widths.PERFECT then
		return "PERFECT"
	elseif offset <= spec.widths.GREAT then
		return "GREAT"
	elseif offset <= spec.widths.GOOD then
		return "GOOD"
	end
	return "MISS"
end

-- Overall grade for a list of tap times: the average of the hit scores, rounded down.
-- Missing taps count as MISS. Returns (grade, per-hit grades).
function TimingBar.grade(spec: Spec, taps: { number }): (string, { string })
	local perHit = {}
	local total = 0
	for hit = 1, #spec.zones do
		local tap = taps[hit]
		local grade = if tap then TimingBar.gradeAt(spec, hit, tap) else "MISS"
		perHit[hit] = grade
		total += GRADE_SCORE[grade]
	end
	return SCORE_GRADE[math.floor(total / #spec.zones)], perHit
end

-- Server-side sanity check of submitted taps (raw times, seconds since the challenge started).
-- `elapsed` is how long the server says the challenge has been running.
function TimingBar.validTaps(spec: Spec, taps: any, elapsed: number): boolean
	if type(taps) ~= "table" or #taps > #spec.zones then
		return false
	end
	local previous = -math.huge
	for index, tap in taps do
		if type(index) ~= "number" or type(tap) ~= "number" or tap ~= tap then
			return false
		end
		if tap < Minigames.MIN_REACTION or tap - previous < Minigames.MIN_TAP_GAP then
			return false
		end
		if tap > elapsed + Minigames.LATENCY_GRACE then
			return false
		end
		previous = tap
	end
	return true
end

return TimingBar
