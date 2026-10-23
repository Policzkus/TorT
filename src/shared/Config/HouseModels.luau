--!strict
-- Which AI house models (Config/Meshes keys) each neighbourhood uses, and where each model's front
-- door is. Every run rolls one model per lot, so streets look different each playthrough. Models
-- that fail to load are skipped; if none load, the street falls back to its part-built style.
--
-- door: measured from straight-on screenshots of each mesh (2026-10-23), as fractions of the mesh
-- size so they don't depend on scale:
--   face   - the side of the mesh the door is on ("Front" = -Z, "Right" = +X, "Back", "Left")
--   x      - door centre, right of that face's centre as you look at it (fraction of face width)
--   bottom - door sill height (fraction of mesh height); raycasts refine it at build time
--   height - door height (fraction of mesh height); sets the house scale (see DOOR_HEIGHT)
--   width  - door width (fraction of face width)

export type Face = "Front" | "Right" | "Back" | "Left"
export type Door = { face: Face, x: number, bottom: number, height: number, width: number }

local DOORS: { [string]: Door } = {
	CardboardCourt_A = { face = "Left", x = 0.075, bottom = 0.194, height = 0.406, width = 0.1 }, -- trailer, door on the side
	CardboardCourt_B = { face = "Front", x = -0.029, bottom = 0.127, height = 0.3, width = 0.097 },
	CardboardCourt_C = { face = "Front", x = 0.22, bottom = 0.14, height = 0.24, width = 0.11 },
	MapleLane_A = { face = "Front", x = 0.157, bottom = 0.11, height = 0.169, width = 0.097 },
	MapleLane_B = { face = "Front", x = -0.085, bottom = 0.088, height = 0.27, width = 0.19 },
	MapleLane_C = { face = "Front", x = 0.069, bottom = 0.12, height = 0.265, width = 0.19 },
	PumpkinHollow_A = { face = "Front", x = -0.1125, bottom = 0.069, height = 0.22, width = 0.106 },
	PumpkinHollow_B = { face = "Front", x = 0.05, bottom = 0.054, height = 0.21, width = 0.106 },
	PumpkinHollow_C = { face = "Front", x = 0, bottom = 0.09, height = 0.216, width = 0.18 },
	RavenRidge_A = { face = "Front", x = 0, bottom = 0.057, height = 0.17, width = 0.142 },
	RavenRidge_B = { face = "Right", x = 0.206, bottom = 0.0825, height = 0.165, width = 0.105 },
	RavenRidge_C = { face = "Front", x = 0, bottom = 0.092, height = 0.164, width = 0.157 },
	MansionHill_A = { face = "Front", x = 0, bottom = 0.1, height = 0.12, width = 0.124 },
	MansionHill_B = { face = "Front", x = 0, bottom = 0.157, height = 0.164, width = 0.103 },
	MansionHill_C = { face = "Front", x = -0.027, bottom = 0.174, height = 0.203, width = 0.089 },
	BlackwoodEstates_A = { face = "Front", x = 0, bottom = 0.069, height = 0.188, width = 0.13 },
	BlackwoodEstates_B = { face = "Front", x = 0, bottom = 0.095, height = 0.196, width = 0.091 },
	BlackwoodEstates_C = { face = "Front", x = -0.026, bottom = 0.1125, height = 0.135, width = 0.125 },
}

local MODELS: { [string]: { string } } = {
	-- Cardboard Court uses the hand-built Victorian (World/HouseStyles/Victorian) instead; the AI
	-- meshes looked like rough 3D scans (user feedback, 2026-10-23).
	CardboardCourt = {},
	MapleLane = { "MapleLane_A", "MapleLane_B", "MapleLane_C" },
	PumpkinHollow = { "PumpkinHollow_A", "PumpkinHollow_B", "PumpkinHollow_C" },
	RavenRidge = { "RavenRidge_A", "RavenRidge_B", "RavenRidge_C" },
	-- MansionHill_B (white jagged "crown") is out of rotation: it doesn't read as a house.
	MansionHill = { "MansionHill_A", "MansionHill_C" },
	BlackwoodEstates = { "BlackwoodEstates_A", "BlackwoodEstates_B", "BlackwoodEstates_C" },
}

-- Every house is scaled so its front door is this tall (kids are ~4.6 studs, homeowners 7–9: the
-- tall ones duck to get out).
local DOOR_HEIGHT = 7.5
-- Gap between neighbouring houses on the same side of the street.
local LOT_MARGIN = 6

local YAW: { [Face]: number } = { Front = 0, Right = math.pi / 2, Back = math.pi, Left = -math.pi / 2 }

local HouseModels = {
	MODELS = MODELS,
	DOORS = DOORS,
	DOOR_HEIGHT = DOOR_HEIGHT,
}

-- Scale factor for a model whose mesh is `size` (Config/Meshes size).
function HouseModels.scale(name: string, size: { number }): number
	local door = DOORS[name]
	if door == nil then
		return 1
	end
	return DOOR_HEIGHT / (door.height * size[2])
end

-- Rotation (about Y) that turns the door's side of the mesh toward the street (lot -Z).
function HouseModels.yaw(name: string): number
	local door = DOORS[name]
	return if door then YAW[door.face] else 0
end

-- Footprint after scaling and turning: width along the street, depth back from the lot line.
function HouseModels.footprint(name: string, size: { number }): (number, number)
	local s = HouseModels.scale(name, size)
	local door = DOORS[name]
	local sideways = door ~= nil and (door.face == "Left" or door.face == "Right")
	local width = (if sideways then size[3] else size[1]) * s
	local depth = (if sideways then size[1] else size[3]) * s
	return width, depth
end

-- Distance between lots on one side of a neighbourhood's street: its widest house plus a margin.
function HouseModels.lotSpacing(neighborhoodId: string, meshSizes: { [string]: { number } }, minimum: number): number
	local spacing = minimum
	for _, name in MODELS[neighborhoodId] or {} do
		local size = meshSizes[name]
		if size then
			local width = HouseModels.footprint(name, size)
			spacing = math.max(spacing, width + LOT_MARGIN)
		end
	end
	return math.ceil(spacing)
end

return HouseModels
