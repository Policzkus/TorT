--!strict
-- Costume Line rules. The homeowner (a personality, from the house) greets you; pick the answer
-- in the style they like before the timer runs out. Input: { answerTime, optionIndex }.

local Config = script.Parent.Parent.Parent.Config
local Dialogue = require(Config.Dialogue)
local Minigames = require(Config.Minigames)
local Rng = require(script.Parent.Parent.Rng)

local Rules = Minigames.CostumeLine

export type Spec = {
	difficulty: number,
	personality: string,
	greeting: string,
	options: { string },
	correct: number,
	timer: number,
	timeout: number,
}

local CostumeLine = {}

-- `context.personality` comes from the house; a random one is used if it's missing.
function CostumeLine.generate(seed: number, difficulty: number, context: any?): Spec
	local d = math.clamp(math.floor(difficulty), Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local t = (d - Minigames.DIFFICULTY_MIN) / (Minigames.DIFFICULTY_MAX - Minigames.DIFFICULTY_MIN)
	local rng = Rng.new(seed)
	local personalityId = if type(context) == "table" and Dialogue.personalities[context.personality]
		then context.personality
		else rng:pick(Dialogue.ORDER)
	local personality = Dialogue.personalities[personalityId]

	local optionCount = math.round(Rules.easyOptions + (Rules.hardOptions - Rules.easyOptions) * t)
	local others = {}
	for _, id in Dialogue.ORDER do
		if id ~= personalityId then
			table.insert(others, id)
		end
	end
	rng:shuffle(others)

	local options = { rng:pick(personality.answers) }
	for i = 1, optionCount - 1 do
		local other = Dialogue.personalities[others[(i - 1) % #others + 1]]
		table.insert(options, rng:pick(other.answers))
	end
	local correctText = options[1]
	rng:shuffle(options)
	local correct = table.find(options, correctText) :: number

	local timer = Rules.easyTimer + (Rules.hardTimer - Rules.easyTimer) * t
	return {
		difficulty = d,
		personality = personalityId,
		greeting = rng:pick(personality.greetings),
		options = options,
		correct = correct,
		timer = timer,
		timeout = timer + 0.2,
	}
end

function CostumeLine.grade(spec: Spec, input: { number }): (string, { string })
	local at, choice = input[1], input[2]
	if at == nil or choice ~= spec.correct or at > spec.timer then
		return "MISS", { "MISS" }
	end
	local share = at / spec.timer
	local grade = if share <= Rules.perfectShare then "PERFECT" elseif share <= Rules.greatShare then "GREAT" else "GOOD"
	return grade, { grade }
end

function CostumeLine.validInput(spec: Spec, input: any, elapsed: number): boolean
	if type(input) ~= "table" or #input > 2 then
		return false
	end
	local at, choice = input[1], input[2]
	if at == nil then
		return true -- timed out
	end
	if type(at) ~= "number" or at ~= at or at < 0.3 or at > elapsed + Minigames.LATENCY_GRACE then
		return false
	end
	return type(choice) == "number" and choice >= 1 and choice <= #spec.options and choice % 1 == 0
end

return CostumeLine
