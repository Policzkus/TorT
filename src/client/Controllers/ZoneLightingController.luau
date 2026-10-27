--!strict
-- Blends Lighting, fog and colour tint when you cross into another zone (the server sets the
-- player's "Zone" attribute). Purely visual and local. In the Witching Hour (and under the Blood
-- Moon) the sky goes red: red fog thick with haze, a red glare, red night light (the moon itself:
-- MoonController). In a blackout on your street (the Knifer's come: BlackoutController) the night
-- itself is darker too (Knifer.BLACKOUT.darker of its light).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knifer = require(ReplicatedStorage:WaitForChild("Shared").Config.Knifer)
local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local ZoneLighting = require(ReplicatedStorage:WaitForChild("Shared").Modules.ZoneLighting)

local BLEND = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local RED_BLEND = TweenInfo.new(12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- the sky reddening

local ZoneLightingController = {}

local worldState: Instance? = nil
local wasRed = false

local function blend(zoneId: string?)
	local properties = ZoneLighting.properties(zoneId)
	properties.atmosphere.Haze = World.LIGHTING.fogHaze
	properties.atmosphere.Glare = World.LIGHTING.fogGlare
	-- Witching Hour and the Blood Moon paint everything red.
	local witching = worldState ~= nil and worldState:GetAttribute("Witching") == true
	local bloodMoon = worldState ~= nil and worldState:GetAttribute("BloodMoon") == true
	local red = witching or bloodMoon
	if red then
		properties.atmosphere.Color = Color3.fromHex(if witching then "9A2228" else "7A3A40")
		properties.atmosphere.Decay = Color3.fromHex("4A0A12")
		properties.atmosphere.Density = math.min(0.75, properties.atmosphere.Density + 0.12)
		properties.atmosphere.Haze = World.LIGHTING.fogHaze + 1.2
		properties.atmosphere.Glare = 1.4
		properties.lighting.OutdoorAmbient = (properties.lighting.OutdoorAmbient :: Color3):Lerp(
			Color3.fromHex("6A1418"),
			0.55
		)
		properties.lighting.Ambient = (properties.lighting.Ambient :: Color3):Lerp(Color3.fromHex("4A0E12"), 0.35)
		properties.colorCorrection.TintColor = Color3.fromHex(if witching then "FFC0C0" else "FFDADA")
		properties.colorCorrection.Saturation = 0.15
	end
	-- The power's out here: darker still.
	if worldState ~= nil and zoneId ~= nil and worldState:GetAttribute("Blackout_" .. zoneId) ~= nil then
		local k = Knifer.BLACKOUT.darker
		for _, key in { "OutdoorAmbient", "Ambient" } do
			local color = properties.lighting[key] :: Color3
			properties.lighting[key] = Color3.new(color.R * k, color.G * k, color.B * k)
		end
	end
	-- Going red (or back) is slow, a zone change quick.
	local info = if red ~= wasRed then RED_BLEND else BLEND
	wasRed = red
	TweenService:Create(Lighting, info, properties.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, properties.atmosphere):Play()
	end
	-- By name: the camera's own grade (CameraController's PSXGrade) is a ColorCorrectionEffect too.
	local colorCorrection = Lighting:FindFirstChild("ZoneTint")
	if colorCorrection then
		TweenService:Create(colorCorrection, info, properties.colorCorrection):Play()
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
		worldState.AttributeChanged:Connect(function(name)
			if string.sub(name, 1, 9) == "Blackout_" then
				refresh()
			end
		end)
		refresh()
	end
end

return ZoneLightingController
