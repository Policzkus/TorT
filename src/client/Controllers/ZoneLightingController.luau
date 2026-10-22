--!strict
-- Blends Lighting, fog and colour tint when you cross into another zone (the server sets the
-- player's "Zone" attribute). Purely visual and local.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ZoneLighting = require(ReplicatedStorage:WaitForChild("Shared").Modules.ZoneLighting)

local BLEND = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local ZoneLightingController = {}

local function blend(zoneId: string?)
	local properties = ZoneLighting.properties(zoneId)
	TweenService:Create(Lighting, BLEND, properties.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, BLEND, properties.atmosphere):Play()
	end
	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if colorCorrection then
		TweenService:Create(colorCorrection, BLEND, properties.colorCorrection):Play()
	end
end

function ZoneLightingController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		blend(player:GetAttribute("Zone") :: string?)
	end)
	blend(player:GetAttribute("Zone") :: string?)
end

return ZoneLightingController
