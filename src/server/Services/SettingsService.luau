--!strict
-- Saves the player's settings (PROMPT §3.18). Everything is validated; bad values are ignored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Modules.Net)
local DataService = require(script.Parent.DataService)

local JUMPSCARE = { Full = true, Reduced = true, Off = true }

local SettingsService = {}

local function volume(value: any): number?
	if type(value) == "number" and value == value then
		return math.clamp(value, 0, 1)
	end
	return nil
end

function SettingsService.Start()
	Net.connect("SaveSettings", function(player: Player, incoming: any)
		if type(incoming) ~= "table" then
			return
		end
		DataService.mutate(player, "settings", function(settings)
			settings.music = volume(incoming.music) or settings.music
			settings.sfx = volume(incoming.sfx) or settings.sfx
			if JUMPSCARE[incoming.jumpscare] then
				settings.jumpscare = incoming.jumpscare
			end
			if type(incoming.reduceFlash) == "boolean" then
				settings.reduceFlash = incoming.reduceFlash
			end
			if type(incoming.psx) == "boolean" then
				settings.psx = incoming.psx
			end
		end)
	end, { rate = 1, burst = 4 })
end

return SettingsService
