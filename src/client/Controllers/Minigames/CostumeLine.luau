--!strict
-- Costume Line UI: the homeowner asks you something in their speech bubble (DialogController);
-- once it's typed out, pick the reply in the style they'd like before the line under the replies
-- runs out. Click or tap a reply, or keys 1-4 / the gamepad. Input: { time, choice }.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dialogue = require(Shared.Config.Dialogue)
local Houses = require(Shared.Modules.Houses)
local Rules = require(Shared.Modules.Minigames.CostumeLine)
local Dialog = require(script.Parent.Parent.DialogController)

export type Callbacks = {
	onTap: (hit: number, grade: string, total: number) -> (),
	onDone: (input: { number }, spec: any) -> (),
}

local CostumeLine = {}

local function houseOf(houseId: any): Model?
	if type(houseId) ~= "string" then
		return nil
	end
	for _, door in CollectionService:GetTagged("Door") do
		if door:GetAttribute("HouseId") == houseId then
			return Houses.of(door)
		end
	end
	return nil
end

function CostumeLine.run(_parent: Frame, challenge: any, callbacks: Callbacks)
	local spec = Rules.generate(challenge.seed, challenge.difficulty, challenge.context)
	local personality = Dialogue.personalities[spec.personality]
	local context = challenge.context
	local house = houseOf(type(context) == "table" and context.houseId)

	local startedAt = os.clock()
	local done = false
	local connection: RBXScriptConnection
	local asked: Dialog.Asked

	local function finish(input: { number })
		if done then
			return
		end
		done = true
		connection:Disconnect()
		callbacks.onDone(input, spec)
	end

	asked = Dialog.ask(house, spec.greeting, spec.options, personality.voice, spec.read, function(index: number)
		if done then
			return
		end
		asked.mark(index, spec.correct)
		finish({ os.clock() - startedAt, index })
	end)

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt - spec.read
		asked.setTime(1 - math.max(0, t) / spec.timer)
		if t > spec.timer then
			asked.mark(0, spec.correct)
			finish({})
		end
	end)

	return {
		usesOwnButtons = true,
		cancel = function()
			if not done then
				done = true
				connection:Disconnect()
				asked.close()
			end
		end,
	}
end

return CostumeLine
