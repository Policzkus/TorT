--!strict
-- Knock Rhythm rules, shared by client (playback/drawing) and server (grading).
-- The door knocks a pattern during the listen phase; from `turnAt` the player repeats it.
-- Only the rhythm matters: the player's first tap anchors the pattern.

local Config = script.Parent.Parent.Parent.Config
local Minigames = require(Config.Minigames)
local Rng = require(script.Parent.Parent.Rng)

local Rules = Minigames.KnockRhythm

export type Spec = {
	difficulty: number,
	beat: number, -- seconds per beat
	pattern: { number }, -- knock offsets from the first knock (pattern[1] = 0)
	fakes: { number }, -- times of distracting creaks during the listen phase
	listenAt: number, -- time of the first knock
	turnAt: number, -- when the player may start repeating
	timeout: number,
}

local KnockRhythm = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function KnockRhythm.generate(seed: number, difficulty: number, _context: any?): Spec
	local d = math.clamp(math.floor(difficulty), Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local t = (d - Minigames.DIFFICULTY_MIN) / (Minigames.DIFFICULTY_MAX - Minigames.DIFFICULTY_MIN)
	local rng = Rng.new(seed)
	local knocks = math.round(lerp(Rules.easyKnocks, Rules.hardKnocks, t))
	local beat = 60 / lerp(Rules.easyBpm, Rules.hardBpm, t)

	local gaps = { 1 }
	if d >= Rules.syncopationFrom then
		table.insert(gaps, 0.5)
	end
	if d >= Rules.longGapFrom then
		table.insert(gaps, 1.5)
	end
	local pattern = { 0 }
	for _ = 2, knocks do
		table.insert(pattern, pattern[#pattern] + beat * rng:pick(gaps))
	end
	local length = pattern[#pattern]
	local turnAt = Rules.leadIn + length + Rules.gapBeforeTurn

	local fakes = {}
	if d >= Rules.fakesFrom then
		for _ = 1, rng:int(1, 2) do
			table.insert(fakes, Rules.leadIn + rng:range(0, length))
		end
		table.sort(fakes)
	end

	return {
		difficulty = d,
		beat = beat,
		pattern = pattern,
		fakes = fakes,
		listenAt = Rules.leadIn,
		turnAt = turnAt,
		timeout = turnAt + length + Rules.answerTime,
	}
end

-- Average timing error of the taps against the pattern (seconds).
function KnockRhythm.averageError(spec: Spec, taps: { number }): number
	local anchor = taps[1]
	if anchor == nil then
		return math.huge
	end
	local total = 0
	for index = 2, #spec.pattern do
		local tap = taps[index]
		local err = if tap then math.abs((tap - anchor) - spec.pattern[index]) else Rules.missingTapError
		total += math.min(err, Rules.missingTapError)
	end
	return total / math.max(1, #spec.pattern - 1)
end

function KnockRhythm.grade(spec: Spec, taps: { number }): (string, { string })
	if #taps == 0 then
		return "MISS", {}
	end
	local err = KnockRhythm.averageError(spec, taps)
	local grade = if err <= Rules.perfect
		then "PERFECT"
		elseif err <= Rules.great then "GREAT"
		elseif err <= Rules.good then "GOOD"
		else "MISS"
	return grade, { grade }
end

function KnockRhythm.validInput(spec: Spec, taps: any, elapsed: number): boolean
	if type(taps) ~= "table" or #taps > #spec.pattern then
		return false
	end
	local previous = -math.huge
	for index, tap in taps do
		if type(index) ~= "number" or type(tap) ~= "number" or tap ~= tap then
			return false
		end
		if tap < spec.turnAt - 0.25 or tap - previous < Minigames.MIN_TAP_GAP or tap > spec.timeout then
			return false
		end
		if tap > elapsed + Minigames.LATENCY_GRACE then
			return false
		end
		previous = tap
	end
	return true
end

return KnockRhythm
