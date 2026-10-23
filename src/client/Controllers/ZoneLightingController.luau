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

local worldState: Instance? = nil

local function blend(zoneId: string?)
	local properties = ZoneLighting.properties(zoneId)
	-- Witching Hour and the Blood Moon paint everything red.
	local witching = worldState ~= nil and worldState:GetAttribute("Witching") == true
	local bloodMoon = worldState ~= nil and worldState:GetAttribute("BloodMoon") == true
	if witching or bloodMoon then
		properties.atmosphere.Color = Color3.fromHex(if witching then "8A2A2E" else "7A3A40")
		properties.atmosphere.Decay = Color3.fromHex("3A0A10")
		properties.atmosphere.Density = math.min(0.75, properties.atmosphere.Density + 0.12)
		properties.colorCorrection.TintColor = Color3.fromHex(if witching then "FFC8C8" else "FFDADA")
		properties.colorCorrection.Saturation = 0.15
	end
	TweenService:Create(Lighting, BLEND, properties.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, BLEND, properties.atmosphere):Play()
	end
	-- By name: the camera's own grade (CameraController's PSXGrade) is a ColorCorrectionEffect too.
	local colorCorrection = Lighting:FindFirstChild("ZoneTint")
	if colorCorrection then
		TweenService:Create(colorCorrection, BLEND, properties.colorCorrection):Play()
	end
end

function ZoneLightingController.Start()
	local player = Players.LocalPlayer
	local function refresh()
		blend(player:GetAttribute("Zone") :: string?)
	end
	player:GetAttributeChangedSignal("Zone"):Connect(refresh)
	refresh()
	worldState = ReplicatedStorage:WaitForChild("WorldState", 15)
	if worldState then
		worldState:GetAttributeChangedSignal("Witching"):Connect(refresh)
		worldState:GetAttributeChangedSignal("BloodMoon"):Connect(refresh)
		refresh()
	end
end

return ZoneLightingController
