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
	LIGHTING = {
		clockTime = 0,
		brightness = 2.2, -- moonlight
		exposure = 0,
		moonSize = 20,
		starCount = 1200,
		bloomIntensity = 0.9,
		bloomSize = 26,
		bloomThreshold = 1.1,
		fogOffset = 0.25,
		fogGlare = 0,
		fogHaze = 1.4,
	},
}
