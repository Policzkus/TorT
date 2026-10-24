--!strict
-- Plays sounds from Config/Sounds by name. Missing or id-0 sounds are skipped silently, so a bad
-- asset can never break gameplay. One-shots are cloned so they can overlap.
-- A sound is one of: an uploaded `id`; a `clip` cut from one of the sprite files (Config/
-- SoundSprites: many short sounds in one upload, a random variant each time; until the sprite is
-- uploaded the `id`, if any, plays instead); or, with `slice`, a random piece that long of the
-- `id` sound (the homeowners' muttering voice is made of whisper slices).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundSprites = require(Shared.Config.SoundSprites)
local Sounds = require(Shared.Config.Sounds)

local SoundController = {}

-- at: play from this part (3D, fades with distance) instead of everywhere.
export type PlayOptions = { volume: number?, speed: number?, at: BasePart? }

local ROLLOFF_MIN = 8
local ROLLOFF_MAX = 90

local folder: Folder? = nil
local templates: { [string]: Sound } = {}
local clipOf: { [string]: SoundSprites.Clip } = {} -- sounds that play a sprite clip
local groups: { [string]: SoundGroup } = {}
local random = Random.new()

-- "SFX" and "Music" groups carry the player's volume settings.
function SoundController.group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = 1
	group.Parent = SoundService
	groups[name] = group
	return group
end

function SoundController.setVolumes(music: number, sfx: number)
	SoundController.group("Music").Volume = music * 2 -- 0.5 (the default setting) = full volume
	SoundController.group("SFX").Volume = sfx
end

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
	if cfg == nil then
		return nil
	end
	local clip = cfg.clip and SoundSprites.clips[cfg.clip]
	local spriteId = clip and SoundSprites.sprites[clip.sprite] or 0
	local id = if spriteId ~= 0 then spriteId else cfg.id or 0
	if id == 0 then
		return nil
	end
	if spriteId ~= 0 and clip then
		clipOf[name] = clip
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = cfg.volume
	sound.PlaybackSpeed = cfg.speed or 1
	sound.Looped = cfg.looped == true
	sound.SoundGroup = SoundController.group("SFX")
	sound.Parent = getFolder()
	templates[name] = sound
	return sound
end

-- Stops a one-shot after `seconds` of playback, fading the last bit so the cut doesn't click.
local function cutAfter(sound: Sound, seconds: number)
	local fade = math.min(0.04, seconds * 0.3)
	task.delay(math.max(0, seconds - fade), function()
		if sound.Parent then
			TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 }):Play()
			task.delay(fade, function()
				sound:Destroy()
			end)
		end
	end)
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
	local cfg = Sounds[name]
	local sound = base:Clone()
	if options then
		if options.volume then
			sound.Volume = base.Volume * options.volume
		end
		if options.speed then
			sound.PlaybackSpeed = base.PlaybackSpeed * options.speed
		end
	end
	if options and options.at then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ROLLOFF_MIN
		sound.RollOffMaxDistance = ROLLOFF_MAX
		sound.Parent = options.at
	else
		sound.Parent = base.Parent
	end
	local clip = clipOf[name]
	if clip then
		local part = clip.parts[random:NextInteger(1, #clip.parts)]
		sound.TimePosition = part[1]
		sound:Play()
		cutAfter(sound, part[2] / sound.PlaybackSpeed)
		return
	end
	if cfg.slice and base.TimeLength > cfg.slice then
		sound.TimePosition = random:NextNumber(0, base.TimeLength - cfg.slice)
		sound:Play()
		cutAfter(sound, cfg.slice / sound.PlaybackSpeed)
		return
	end
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

-- A looping sound's own Sound, to fade or move it (ambience).
function SoundController.loop(name: string): Sound?
	local base = template(name)
	return if base and base.Looped then base else nil
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
end

return SoundController
