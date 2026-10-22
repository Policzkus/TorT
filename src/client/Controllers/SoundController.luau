--!strict
-- Plays sounds from Config/Sounds by name. Missing or id-0 sounds are skipped silently, so a bad
-- asset can never break gameplay. One-shots are cloned so they can overlap.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local SoundController = {}

export type PlayOptions = { volume: number?, speed: number? }

local folder: Folder? = nil
local templates: { [string]: Sound } = {}

local function getFolder(): Folder
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "GameSounds"
		created.Parent = SoundService
		folder = created
	end
	return folder :: Folder
end

local function template(name: string): Sound?
	local existing = templates[name]
	if existing then
		return existing
	end
	local cfg = Sounds[name]
	if cfg == nil or cfg.id == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. cfg.id
	sound.Volume = cfg.volume
	sound.PlaybackSpeed = cfg.speed or 1
	sound.Looped = cfg.looped == true
	sound.Parent = getFolder()
	templates[name] = sound
	return sound
end

function SoundController.play(name: string, options: PlayOptions?)
	local base = template(name)
	if base == nil then
		return
	end
	if base.Looped then
		if not base.IsPlaying then
			base:Play()
		end
		return
	end
	local sound = base:Clone()
	if options then
		if options.volume then
			sound.Volume = base.Volume * options.volume
		end
		if options.speed then
			sound.PlaybackSpeed = base.PlaybackSpeed * options.speed
		end
	end
	sound.Parent = base.Parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function SoundController.stop(name: string)
	local base = templates[name]
	if base then
		base:Stop()
	end
end

function SoundController.Start()
	local list = {}
	for name in Sounds do
		local sound = template(name)
		if sound then
			table.insert(list, sound)
		end
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
	SoundController.play("NightAmbience")
end

return SoundController
