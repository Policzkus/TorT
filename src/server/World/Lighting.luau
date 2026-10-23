--!strict
-- Always night (PROMPT §3.19): moon, fog, bloom. Reuses the place's existing effects when present
-- and creates them otherwise. Per-zone tints are tweened on the client (ZoneLightingController).

local LightingService = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.Config.World)
local ZoneLighting = require(ReplicatedStorage.Shared.Modules.ZoneLighting)

local Lighting = {}

local function ensure(className: string, name: string): Instance
	local existing = LightingService:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = LightingService
	return created
end

local function assign(instance: Instance, properties: { [string]: any })
	for key, value in properties do
		(instance :: any)[key] = value
	end
end

function Lighting.apply()
	local cfg = World.LIGHTING
	LightingService.ClockTime = cfg.clockTime
	LightingService.GeographicLatitude = cfg.latitude
	LightingService.Brightness = cfg.brightness
	LightingService.ExposureCompensation = cfg.exposure
	LightingService.GlobalShadows = true
	LightingService.EnvironmentDiffuseScale = cfg.diffuseScale
	LightingService.EnvironmentSpecularScale = cfg.specularScale

	local sky = ensure("Sky", "NightSky") :: Sky
	sky.MoonAngularSize = cfg.moonSize
	sky.StarCount = cfg.starCount
	sky.CelestialBodiesShown = true

	local atmosphere = ensure("Atmosphere", "Fog") :: Atmosphere
	atmosphere.Offset = cfg.fogOffset
	atmosphere.Glare = cfg.fogGlare
	atmosphere.Haze = cfg.fogHaze

	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = cfg.bloomIntensity
	bloom.Size = cfg.bloomSize
	bloom.Threshold = cfg.bloomThreshold

	local colorCorrection = ensure("ColorCorrectionEffect", "ZoneTint")

	-- Leftovers from the default place template that fight a night look.
	local sunRays = LightingService:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		(sunRays :: SunRaysEffect).Enabled = false
	end
	local depthOfField = LightingService:FindFirstChildOfClass("DepthOfFieldEffect")
	if depthOfField then
		(depthOfField :: DepthOfFieldEffect).Enabled = false
	end

	local hub = ZoneLighting.properties(nil)
	assign(LightingService, hub.lighting)
	assign(atmosphere, hub.atmosphere)
	assign(colorCorrection, hub.colorCorrection)
end

return Lighting
