--!strict
-- The night around you: crickets and an eerie wind always under everything, and now and then
-- something out in the dark: an owl, thunder rolling in the distance, a church bell, whispering
-- from somewhere close that you can't quite place. Each comes from a random spot around you (3D),
-- so you turn your head.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent.SoundController)

local AmbienceController = {}

type Event = { sound: string, every: { number }, distance: { number }, height: number }

-- every: seconds between them (random in the range); distance: studs from you.
local EVENTS: { Event } = {
	{ sound = "Owl", every = { 35, 80 }, distance = { 35, 55 }, height = 18 },
	{ sound = "Thunder", every = { 80, 170 }, distance = { 45, 60 }, height = 40 },
	{ sound = "ChurchBell", every = { 160, 320 }, distance = { 50, 60 }, height = 30 },
	{ sound = "Whispers", every = { 110, 240 }, distance = { 14, 22 }, height = 4 },
}

local function emitter(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "AmbientSound"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = position
	part.Parent = Workspace
	return part
end

local function run(event: Event)
	task.wait(math.random(event.every[1], event.every[2]) * 0.5) -- the first one comes sooner
	while true do
		local camera = Workspace.CurrentCamera
		if camera and Players.LocalPlayer.Character then
			local angle = math.random() * math.pi * 2
			local distance = event.distance[1] + math.random() * (event.distance[2] - event.distance[1])
			local offset = Vector3.new(math.cos(angle) * distance, event.height, math.sin(angle) * distance)
			local part = emitter(camera.CFrame.Position + offset)
			Sound.play(event.sound, { at = part, speed = 0.92 + math.random() * 0.16 })
			task.delay(30, function()
				part:Destroy()
			end)
		end
		task.wait(math.random(event.every[1], event.every[2]))
	end
end

function AmbienceController.Start()
	Sound.play("NightAmbience")
	Sound.play("Wind")
	for _, event in EVENTS do
		task.spawn(run, event)
	end
end

return AmbienceController
