--!strict
-- Background music: the track of the zone you're in, swapped for the Witching Hour or Blood Moon
-- theme while those are on, and for the chase music while something's after you (the Knifer:
-- KniferController; a homeowner whose bowl you emptied: OwnerChaseController).
-- Crossfades; volume follows Settings → Music (SoundGroup "Music").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Music = require(ReplicatedStorage:WaitForChild("Shared").Config.Music)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)

local MusicController = {}

local SETTINGS_WAIT = 10

local playing: Sound? = nil
local playingId = 0
local state: Instance? = nil
local chased = false -- anything's after you
local chasers: { [string]: boolean } = {} -- who says so ("knifer", "owner")

local function wanted(): Music.Track?
	if chased then
		return Music.chase
	end
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
	local quick = chased or (playing ~= nil and playing:GetAttribute("Chase") == true)
	local fade = TweenInfo.new(if quick then Music.CHASE_FADE else Music.FADE, Enum.EasingStyle.Sine)
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
	sound:SetAttribute("Chase", chased)
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, fade, { Volume = track.volume }):Play()
	playing = sound
end

-- `source` (the Knifer, a homeowner) is after you (on) or you've lost them (off): the chase music
-- comes in fast while any of them is, and goes when none is.
function MusicController.setChase(source: string, on: boolean)
	chasers[source] = if on then true else nil
	local any = next(chasers) ~= nil
	if any ~= chased then
		chased = any
		refresh()
	end
end

function MusicController.Start()
	-- Not a note before the saved settings are in: Settings → Music may be off, and the default
	-- volume would blare until they arrived. (The data store answers in a second or two; after
	-- SETTINGS_WAIT the defaults go.)
	local waited = 0
	while not StateController.isLoaded() and waited < SETTINGS_WAIT do
		waited += task.wait(0.1)
	end
	state = ReplicatedStorage:WaitForChild("WorldState", 15)
	if state then
		state:GetAttributeChangedSignal("Witching"):Connect(refresh)
		state:GetAttributeChangedSignal("BloodMoon"):Connect(refresh)
	end
	Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(refresh)
	refresh()
end

return MusicController
