--!strict
-- Nerve Hold rules. Press and keep holding while the house gets scary; the nerve bar fills from
-- your press to `duration`. Let go early = flinch. Input: { pressTime, releaseTime }.

local Config = script.Parent.Parent.Parent.Config
local Minigames = require(Config.Minigames)
local Rng = require(script.Parent.Parent.Rng)

local Rules = Minigames.NerveHold

export type Scare = { at: number, kind: string } -- "flicker" | "face" | "whisper" | "trap"

export type Spec = {
	difficulty: number,
	duration: number,
	scares: { Scare },
	timeout: number,
}

local NerveHold = {}

local SCARE_KINDS = { "flicker", "face", "whisper" }

function NerveHold.generate(seed: number, difficulty: number, _context: any?): Spec
	local d = math.clamp(math.floor(difficulty), Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local t = (d - Minigames.DIFFICULTY_MIN) / (Minigames.DIFFICULTY_MAX - Minigames.DIFFICULTY_MIN)
	local rng = Rng.new(seed)
	local duration = Rules.easyDuration + (Rules.hardDuration - Rules.easyDuration) * t

	local scares: { Scare } = {}
	local count = 2 + math.floor(d / 2)
	for i = 1, count do
		local at = duration * (i / (count + 1)) + rng:range(-0.2, 0.2)
		table.insert(scares, { at = math.max(0.4, at), kind = rng:pick(SCARE_KINDS) })
	end
	if d >= Rules.trapsFrom then
		table.insert(scares, { at = duration * rng:range(0.45, 0.85), kind = "trap" })
	end
	table.sort(scares, function(a, b)
		return a.at < b.at
	end)

	return { difficulty = d, duration = duration, scares = scares, timeout = duration + 0.5 }
end

-- Share of the hold completed (0..1).
function NerveHold.heldShare(spec: Spec, input: { number }): number
	local press, release = input[1], input[2]
	if press == nil or press > Rules.pressWindow then
		return 0
	end
	local finish = math.min(release or spec.duration, spec.duration)
	return math.clamp((finish - press) / (spec.duration - press), 0, 1)
end

function NerveHold.grade(spec: Spec, input: { number }): (string, { string })
	local share = NerveHold.heldShare(spec, input)
	local grade = if share >= Rules.perfect - 1e-6
		then "PERFECT"
		elseif share >= Rules.great then "GREAT"
		elseif share >= Rules.good then "GOOD"
		else "MISS"
	return grade, { grade }
end

function NerveHold.validInput(spec: Spec, input: any, elapsed: number): boolean
	if type(input) ~= "table" or #input > 2 then
		return false
	end
	local press, release = input[1], input[2]
	if press == nil then
		return true -- never pressed: a flinch, graded MISS
	end
	if type(press) ~= "number" or press ~= press or press < Minigames.MIN_REACTION then
		return false
	end
	if release ~= nil and (type(release) ~= "number" or release ~= release or release <= press) then
		return false
	end
	local last = release or press
	return math.min(last, spec.duration) <= elapsed + Minigames.LATENCY_GRACE
end

return NerveHold
