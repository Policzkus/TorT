--!strict
-- The streets, in road order (PROMPT §3.3). Starting numbers; tune with tests/economy_sim.luau.
-- enabled = false: the gate before it shows "COMING SOON" and nothing past it is built.
-- Colors are hex strings so this file stays pure data (Lune tests load it).

export type Lighting = {
	ambient: string,
	outdoorAmbient: string,
	fogColor: string, -- Atmosphere.Color
	fogDecay: string, -- Atmosphere.Decay
	fogDensity: number,
	tint: string, -- ColorCorrection.TintColor
	saturation: number,
	contrast: number,
}

export type Neighborhood = {
	id: string,
	name: string,
	tier: number, -- also the base mini-game difficulty
	enabled: boolean,
	unlock: { price: number, rebirths: number },
	candy: { min: number, max: number },
	houses: number,
	style: string, -- World/HouseStyles/<style>
	seed: number,
	turn: number, -- degrees the road bends after this street
	minigames: { [string]: number }, -- weights; ones not built yet are skipped
	rareCandy: { string },
	colors: { accent: string, ground: string, road: string, sidewalk: string },
	lighting: Lighting,
}

local list: { Neighborhood } = {
	{
		id = "CardboardCourt",
		name = "Cardboard Court",
		tier = 1,
		enabled = true,
		unlock = { price = 0, rebirths = 0 },
		candy = { min = 3, max = 7 },
		houses = 16,
		style = "Trailer",
		seed = 1101,
		turn = 14,
		minigames = { TimingBar = 60, CostumeLine = 40 },
		rareCandy = { "GlowGummy" },
		colors = { accent = "FF9A3C", ground = "41582A", road = "2E2C33", sidewalk = "6E6A64" },
		lighting = {
			ambient = "3A2F4A",
			outdoorAmbient = "7A6A8E",
			fogColor = "6E5A82",
			fogDecay = "3A2A4E",
			fogDensity = 0.28,
			tint = "FFF0E0",
			saturation = 0.05,
			contrast = 0.08,
		},
	},
	{
		id = "MapleLane",
		name = "Maple Lane",
		tier = 2,
		enabled = true,
		unlock = { price = 150, rebirths = 0 },
		candy = { min = 10, max = 20 },
		houses = 16,
		style = "Cottage",
		seed = 2202,
		turn = -16,
		minigames = { TimingBar = 40, KnockRhythm = 30, CostumeLine = 30 },
		rareCandy = { "GlowGummy", "WitchsTaffy" },
		colors = { accent = "FF6A2B", ground = "4A5626", road = "2C2A30", sidewalk = "7A7068" },
		lighting = {
			ambient = "3E2E3C",
			outdoorAmbient = "8A6A70",
			fogColor = "8A5A4A",
			fogDecay = "4A2A30",
			fogDensity = 0.32,
			tint = "FFE6D0",
			saturation = 0.1,
			contrast = 0.1,
		},
	},
	{
		id = "PumpkinHollow",
		name = "Pumpkin Hollow",
		tier = 3,
		enabled = false,
		unlock = { price = 2500, rebirths = 0 },
		candy = { min = 30, max = 60 },
		houses = 16,
		style = "Suburban",
		seed = 3303,
		turn = 18,
		minigames = { TimingBar = 30, KnockRhythm = 25, CostumeLine = 25, NerveHold = 20 },
		rareCandy = { "WitchsTaffy", "GhostJawbreaker" },
		colors = { accent = "FF7A00", ground = "33402A", road = "2A282E", sidewalk = "6A6660" },
		lighting = {
			ambient = "2E2A3E",
			outdoorAmbient = "6A6080",
			fogColor = "8A7A6A",
			fogDecay = "3A3040",
			fogDensity = 0.4,
			tint = "FFEAD6",
			saturation = 0.05,
			contrast = 0.12,
		},
	},
	{
		id = "RavenRidge",
		name = "Raven Ridge",
		tier = 4,
		enabled = false,
		unlock = { price = 25000, rebirths = 1 },
		candy = { min = 120, max = 240 },
		houses = 15,
		style = "Victorian",
		seed = 4404,
		turn = -14,
		minigames = { TimingBar = 30, KnockRhythm = 25, CostumeLine = 25, NerveHold = 20 },
		rareCandy = { "GhostJawbreaker", "VampireTruffle" },
		colors = { accent = "9A6BFF", ground = "2A3324", road = "26242A", sidewalk = "5E5A58" },
		lighting = {
			ambient = "26243A",
			outdoorAmbient = "585878",
			fogColor = "6A6A80",
			fogDecay = "2A2A3A",
			fogDensity = 0.5,
			tint = "E6E6FF",
			saturation = -0.1,
			contrast = 0.15,
		},
	},
	{
		id = "MansionHill",
		name = "Mansion Hill",
		tier = 5,
		enabled = false,
		unlock = { price = 250000, rebirths = 3 },
		candy = { min = 500, max = 1000 },
		houses = 14,
		style = "Mansion",
		seed = 5505,
		turn = 16,
		minigames = { TimingBar = 30, KnockRhythm = 25, CostumeLine = 25, NerveHold = 20 },
		rareCandy = { "VampireTruffle", "CursedCandyCorn" },
		colors = { accent = "FFD54A", ground = "2E3A26", road = "28262C", sidewalk = "7A7672" },
		lighting = {
			ambient = "2A2638",
			outdoorAmbient = "605A78",
			fogColor = "5A5A72",
			fogDecay = "2A2838",
			fogDensity = 0.42,
			tint = "FFF4E0",
			saturation = 0,
			contrast = 0.12,
		},
	},
	{
		id = "BlackwoodEstates",
		name = "Blackwood Estates",
		tier = 6,
		enabled = false,
		unlock = { price = 2500000, rebirths = 5 },
		candy = { min = 2000, max = 4000 },
		houses = 12,
		style = "Haunted",
		seed = 6606,
		turn = 0,
		minigames = { TimingBar = 30, KnockRhythm = 25, CostumeLine = 25, NerveHold = 20 },
		rareCandy = { "CursedCandyCorn", "GoldenKingSizeBar" },
		colors = { accent = "FF2A3A", ground = "262A20", road = "222026", sidewalk = "4E4A4A" },
		lighting = {
			ambient = "2A1A24",
			outdoorAmbient = "5A3A48",
			fogColor = "6A2A2E",
			fogDecay = "2A1014",
			fogDensity = 0.55,
			tint = "FFD6D6",
			saturation = -0.05,
			contrast = 0.18,
		},
	},
}

local byId: { [string]: Neighborhood } = {}
for index, neighborhood in list do
	assert(neighborhood.tier == index, `Neighborhoods: {neighborhood.id} is listed out of tier order`)
	byId[neighborhood.id] = neighborhood
end

return {
	list = list,
	byId = byId,
	-- Lighting while standing in the hub (Home Street).
	HUB_LIGHTING = {
		ambient = "3A3050",
		outdoorAmbient = "7E7096",
		fogColor = "6A5A8A",
		fogDecay = "362A50",
		fogDensity = 0.25,
		tint = "F4ECFF",
		saturation = 0.08,
		contrast = 0.08,
	} :: Lighting,
}
