--!strict
-- Background music: the track of the zone you're in, swapped for the Witching Hour or Blood Moon
-- theme while those are on. Crossfades; volume follows Settings → Music (SoundGroup "Music").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Music = require(ReplicatedStorage:WaitForChild("Shared").Config.Music)
local Sound = require(script.Parent.SoundController)

local MusicController = {}

local playing: Sound? = nil
local playingId = 0
local state: Instance? = nil

local function wanted(): Music.Track?
	if state and state:GetAttribute("BloodMoon") == true then
		return Music.bloodMoon
	end
	if state and state:GetAttribute("Witching") == true then
		return Music.witching
	end
	local zone = Players.LocalPlayer:GetAttribute("Zone")
	return Music.zones[if type(zone) == "string" then zone else "Hub"] or Music.zones.Hub
end

local function refresh()
	local track = wanted()
	if track == nil or track.id == playingId then
		return
	end
	playingId = track.id
	local fade = TweenInfo.new(Music.FADE, Enum.EasingStyle.Sine)
	local old = playing
	if old then
		local out = TweenService:Create(old, fade, { Volume = 0 })
		out.Completed:Once(function()
			old:Destroy()
		end)
		out:Play()
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = "rbxassetid://" .. track.id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = Sound.group("Music")
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, fade, { Volume = track.volume }):Play()
	playing = sound
end

function MusicController.Start()
	state = ReplicatedStorage:WaitForChild("WorldState", 15)
	if state then
		state:GetAttributeChangedSignal("Witching"):Connect(refresh)
		state:GetAttributeChangedSignal("BloodMoon"):Connect(refresh)
	end
	Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(refresh)
	refresh()
end

return MusicController
