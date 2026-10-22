local KnockRhythm = rbx.require("src/shared/Modules/Minigames/KnockRhythm")
local NerveHold = rbx.require("src/shared/Modules/Minigames/NerveHold")
local CostumeLine = rbx.require("src/shared/Modules/Minigames/CostumeLine")
local Dialogue = rbx.require("src/shared/Config/Dialogue")

-- Taps that copy the pattern exactly, starting at `start`.
local function perfectTaps(spec, start)
	local taps = {}
	for i, offset in spec.pattern do
		taps[i] = start + offset
	end
	return taps
end

return {
	["knock rhythm scales with difficulty"] = function()
		local easy, hard = KnockRhythm.generate(1, 1), KnockRhythm.generate(1, 8)
		expect(#easy.pattern).toBe(3)
		expect(#hard.pattern).toBe(7)
		expect(easy.beat > hard.beat).toBe(true)
		expect(#easy.fakes).toBe(0)
		expect(#hard.fakes > 0).toBe(true)
	end,
	["knock rhythm: copying the pattern is PERFECT, any start time"] = function()
		local spec = KnockRhythm.generate(7, 4)
		expect((KnockRhythm.grade(spec, perfectTaps(spec, spec.turnAt + 0.4)))).toBe("PERFECT")
		expect((KnockRhythm.grade(spec, perfectTaps(spec, spec.turnAt + 1.1)))).toBe("PERFECT")
	end,
	["knock rhythm: sloppy timing drops the grade, no taps is MISS"] = function()
		local spec = KnockRhythm.generate(8, 2)
		local taps = perfectTaps(spec, spec.turnAt + 0.3)
		for i = 2, #taps do
			taps[i] += 0.1
		end
		expect((KnockRhythm.grade(spec, taps))).toBe("GREAT")
		expect((KnockRhythm.grade(spec, {}))).toBe("MISS")
		expect((KnockRhythm.grade(spec, { spec.turnAt + 0.3 }))).toBe("MISS")
	end,
	["knock rhythm rejects taps during the listen phase"] = function()
		local spec = KnockRhythm.generate(9, 3)
		expect(KnockRhythm.validInput(spec, perfectTaps(spec, spec.turnAt + 0.2), spec.timeout)).toBe(true)
		expect(KnockRhythm.validInput(spec, { spec.listenAt }, spec.timeout)).toBe(false)
		expect(KnockRhythm.validInput(spec, perfectTaps(spec, spec.turnAt + 0.2), spec.turnAt)).toBe(false)
	end,
	["nerve hold: holding to the end is PERFECT, flinching early is MISS"] = function()
		local spec = NerveHold.generate(3, 3)
		expect((NerveHold.grade(spec, { 0.3, spec.duration }))).toBe("PERFECT")
		expect((NerveHold.grade(spec, { 0.3 }))).toBe("PERFECT") -- release missing = held through
		expect((NerveHold.grade(spec, { 0.3, 0.6 }))).toBe("MISS")
		expect((NerveHold.grade(spec, {}))).toBe("MISS")
		expect((NerveHold.grade(spec, { 2.5, spec.duration }))).toBe("MISS") -- pressed too late
	end,
	["nerve hold: partial holds grade by share"] = function()
		local spec = NerveHold.generate(4, 1)
		local press = 0.5
		local span = spec.duration - press
		expect((NerveHold.grade(spec, { press, press + span * 0.8 }))).toBe("GREAT")
		expect((NerveHold.grade(spec, { press, press + span * 0.5 }))).toBe("GOOD")
	end,
	["nerve hold adds a trap from difficulty 5"] = function()
		local function hasTrap(spec)
			for _, scare in spec.scares do
				if scare.kind == "trap" then
					return true
				end
			end
			return false
		end
		expect(hasTrap(NerveHold.generate(5, 4))).toBe(false)
		expect(hasTrap(NerveHold.generate(5, 5))).toBe(true)
	end,
	["costume line uses the house personality and has one right answer"] = function()
		local spec = CostumeLine.generate(11, 1, { personality = "WitchyWanda" })
		expect(spec.personality).toBe("WitchyWanda")
		expect(#spec.options).toBe(2)
		expect(table.find(Dialogue.personalities.WitchyWanda.answers, spec.options[spec.correct]) ~= nil).toBe(true)
		local hard = CostumeLine.generate(11, 8, { personality = "CoachCarl" })
		expect(#hard.options).toBe(4)
	end,
	["costume line grades speed and correctness"] = function()
		local spec = CostumeLine.generate(12, 1, { personality = "GrumpyGus" })
		local wrong = if spec.correct == 1 then 2 else 1
		expect((CostumeLine.grade(spec, { spec.timer * 0.2, spec.correct }))).toBe("PERFECT")
		expect((CostumeLine.grade(spec, { spec.timer * 0.5, spec.correct }))).toBe("GREAT")
		expect((CostumeLine.grade(spec, { spec.timer * 0.9, spec.correct }))).toBe("GOOD")
		expect((CostumeLine.grade(spec, { spec.timer * 0.2, wrong }))).toBe("MISS")
		expect((CostumeLine.grade(spec, {}))).toBe("MISS")
		expect(CostumeLine.validInput(spec, { 1, 99 }, 5)).toBe(false)
		expect(CostumeLine.validInput(spec, { 1, 1.5 }, 5)).toBe(false)
	end,
	["every personality has enough lines"] = function()
		local lines = 0
		for _, id in Dialogue.ORDER do
			local p = Dialogue.personalities[id]
			expect(#p.greetings >= 3).toBe(true)
			expect(#p.answers >= 5).toBe(true)
			lines += #p.greetings + #p.answers
		end
		expect(lines >= 40).toBe(true)
	end,
}
