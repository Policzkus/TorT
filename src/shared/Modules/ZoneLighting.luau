--!strict
-- Turns a zone's lighting config into property tables for Lighting, Atmosphere and
-- ColorCorrection. The server applies the hub look at boot; the client tweens between zones.

local Config = script.Parent.Parent.Config
local Neighborhoods = require(Config.Neighborhoods)

export type Properties = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	colorCorrection: { [string]: any },
}

local ZoneLighting = {}

function ZoneLighting.config(zoneId: string?): Neighborhoods.Lighting
	local neighborhood = if zoneId then Neighborhoods.byId[zoneId] else nil
	return if neighborhood then neighborhood.lighting else Neighborhoods.HUB_LIGHTING
end

function ZoneLighting.properties(zoneId: string?): Properties
	local cfg = ZoneLighting.config(zoneId)
	return {
		lighting = {
			Ambient = Color3.fromHex(cfg.ambient),
			OutdoorAmbient = Color3.fromHex(cfg.outdoorAmbient),
		},
		atmosphere = {
			Color = Color3.fromHex(cfg.fogColor),
			Decay = Color3.fromHex(cfg.fogDecay),
			Density = cfg.fogDensity,
		},
		colorCorrection = {
			TintColor = Color3.fromHex(cfg.tint),
			Saturation = cfg.saturation,
			Contrast = cfg.contrast,
		},
	}
end

return ZoneLighting
