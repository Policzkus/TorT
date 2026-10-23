--!strict
-- World builder dimensions (studs). Pure data; World/* on the server turns this into parts.
return {
	ROAD_WIDTH = 22,
	SIDEWALK_WIDTH = 6,
	GROUND_WIDTH = 200, -- full width of each street's ground plate (deep scaled houses fit)
	HOUSE_SETBACK = 34, -- road centre to the front wall of a house
	LOT_SPACING = 40, -- distance between houses on the same side
	ENTRANCE_MARGIN = 56, -- start of a street to its first house (drop-off and bus stop live here)
	END_MARGIN = 44, -- last house to the gate
	LAMP_SPACING = 64,
	BOUNDARY_HEIGHT = 40,

	HUB_SIZE = 170,

	-- Where nothing will ever be built, for parking things out of the way.
	FAR_AWAY_Y = -5000,

	-- Global lighting (zones tint on top of this, client-side).
	-- The moon hangs about 40 degrees up over the far end of each street (the latitude tilts it down
	-- the street at midnight), so it rakes light along the house sides and roofs instead of only
	-- lighting the tops of things from straight overhead. The fronts read from the cool moonlit
	-- ambient (per zone, in Config/Neighborhoods) and the warm lights: lanterns, lit windows, lamps.
	LIGHTING = {
		clockTime = 0,
		latitude = -26.5,
		brightness = 3, -- moonlight
		exposure = 0.4,
		diffuseScale = 0.5, -- EnvironmentDiffuseScale: the night sky's fill
		specularScale = 0.6,
		moonSize = 18,
		starCount = 1200,
		bloomIntensity = 0.9,
		bloomSize = 26,
		bloomThreshold = 1.1,
		fogOffset = 0.25,
		fogGlare = 0.4,
		fogHaze = 1.6,
	},
}
