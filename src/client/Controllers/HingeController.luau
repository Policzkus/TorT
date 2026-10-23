--!strict
-- Swings every hinged door, gate and cellar hatch (tag "Hinged") to match its Open attribute:
-- smoothly and locally on each client, with a creak as it opens and a bang as it shuts. Loose
-- shutters knock in the wind. Front doors belong to the homeowner (HomeownerController.door).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent.SoundController)

local HingeController = {}

local OPEN_TIME = 0.9
local CLOSE_TIME = 0.55
local WIND_RANGE = 120 -- shutters only bother knocking when someone's close enough to hear

type Hinge = {
	model: Model,
	closed: CFrame,
	angle: number,
	from: number,
	to: number,
	clock: number,
	duration: number,
	closing: boolean,
	wind: number, -- next wind gust (loose shutters)
}

local hinges: { [Model]: Hinge } = {}
local random = Random.new()

local function ease(t: number): number
	return 1 - (1 - t) ^ 3
end

local function sound(model: Model, name: string, options: { volume: number?, speed: number? }?)
	local at = model:FindFirstChild("Slab") or model:FindFirstChild("Door") or model:FindFirstChild("Panel")
	if at and at:IsA("BasePart") then
		Sound.play(name, { volume = options and options.volume, speed = options and options.speed, at = at })
	end
end

local function swing(hinge: Hinge, to: number, duration: number)
	hinge.from = hinge.angle
	hinge.to = to
	hinge.clock = 0
	hinge.duration = duration
	hinge.closing = math.abs(to) < math.abs(hinge.angle)
end

local function onOpenChanged(hinge: Hinge)
	local open = hinge.model:GetAttribute("Open") == true
	local target = if open then (hinge.model:GetAttribute("OpenAngle") :: number?) or 90 else 0
	swing(hinge, target, if open then OPEN_TIME else CLOSE_TIME)
	if open then
		sound(hinge.model, "Creak", { speed = random:NextNumber(0.85, 1.15) })
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or hinges[instance] then
		return
	end
	local model = instance
	local kind = model:GetAttribute("Kind")
	if kind == "FrontDoor" then
		return -- the homeowner opens these
	end
	if model.PrimaryPart == nil then
		model:GetPropertyChangedSignal("PrimaryPart"):Wait()
	end
	local hinge: Hinge = {
		model = model,
		closed = model:GetPivot(),
		angle = 0,
		from = 0,
		to = 0,
		clock = 1,
		duration = 1,
		closing = false,
		wind = os.clock() + random:NextNumber(2, 8),
	}
	hinges[model] = hinge
	model:GetAttributeChangedSignal("Open"):Connect(function()
		onOpenChanged(hinge)
	end)
	if model:GetAttribute("Open") == true then
		-- Already open when it streamed in: just put it there, no creak.
		hinge.angle = (model:GetAttribute("OpenAngle") :: number?) or 90
		hinge.to = hinge.angle
		model:PivotTo(hinge.closed * CFrame.Angles(0, math.rad(hinge.angle), 0))
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	for model, hinge in hinges do
		if model.Parent == nil then
			hinges[model] = nil
			continue
		end
		-- Loose shutters swing in the wind now and then and knock back against the wall.
		if model:GetAttribute("Loose") == true and now >= hinge.wind and hinge.clock >= hinge.duration then
			hinge.wind = now + random:NextNumber(3, 9)
			local near = camera and (camera.CFrame.Position - model:GetPivot().Position).Magnitude < WIND_RANGE
			if near then
				local gust = random:NextNumber(12, 32) * (if random:NextNumber() < 0.5 then -1 else 1)
				swing(hinge, gust, random:NextNumber(0.8, 1.6))
				sound(model, "Creak", { volume = 0.35, speed = random:NextNumber(1.2, 1.6) })
				task.delay(hinge.duration + random:NextNumber(0.2, 0.8), function()
					if hinges[model] == hinge then
						swing(hinge, 0, 0.25)
					end
				end)
			end
		end
		if hinge.clock < hinge.duration then
			hinge.clock = math.min(hinge.duration, hinge.clock + dt)
			local t = hinge.clock / hinge.duration
			hinge.angle = hinge.from + (hinge.to - hinge.from) * (if hinge.closing then t * t else ease(t))
			model:PivotTo(hinge.closed * CFrame.Angles(0, math.rad(hinge.angle), 0))
			if hinge.clock >= hinge.duration and hinge.closing and math.abs(hinge.to) < 0.01 then
				local kind = model:GetAttribute("Kind")
				sound(model, if kind == "Shutter" then "KnockSingle" else "DoorSlam", {
					volume = if kind == "Shutter" then 0.3 else 0.8,
				})
			end
		end
	end
end

function HingeController.Start()
	CollectionService:GetInstanceAddedSignal("Hinged"):Connect(function(model)
		task.spawn(track, model)
	end)
	for _, model in CollectionService:GetTagged("Hinged") do
		task.spawn(track, model)
	end
	RunService.RenderStepped:Connect(step)
end

return HingeController
