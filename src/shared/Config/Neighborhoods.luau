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
		style = "Victorian",
		seed = 1101,
		turn = 14,
		minigames = { TimingBar = 60, CostumeLine = 40 },
		rareCandy = { "GlowGummy" },
		colors = { accent = "FF9A3C", ground = "41582A", road = "2E2C33", sidewalk = "6E6A64" },
		lighting = {
			ambient = "2B2F36",
			outdoorAmbient = "76829B",
			fogColor = "515C6A",
			fogDecay = "2A323E",
			fogDensity = 0.3,
			tint = "EAF0EC",
			saturation = -0.05,
			contrast = 0.04,
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
			ambient = "2D2B2F",
			outdoorAmbient = "787680",
			fogColor = "5F5A57",
			fogDecay = "302B2A",
			fogDensity = 0.32,
			tint = "F0ECE4",
			saturation = -0.03,
			contrast = 0.043,
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
			ambient = "28292B",
			outdoorAmbient = "676E6A",
			fogColor = "575A4E",
			fogDecay = "2A2D24",
			fogDensity = 0.35,
			tint = "EEF0E2",
			saturation = -0.07,
			contrast = 0.045,
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
			ambient = "24242B",
			outdoorAmbient = "596073",
			fogColor = "4C5162",
			fogDecay = "222430",
			fogDensity = 0.38,
			tint = "E4E8F2",
			saturation = -0.11,
			contrast = 0.05,
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
			ambient = "242228",
			outdoorAmbient = "534F61",
			fogColor = "4C4954",
			fogDecay = "24222A",
			fogDensity = 0.4,
			tint = "F0EAE8",
			saturation = -0.09,
			contrast = 0.05,
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
			ambient = "281F20",
			outdoorAmbient = "544246",
			fogColor = "513E3E",
			fogDecay = "2A191C",
			fogDensity = 0.44,
			tint = "F2E2E0",
			saturation = -0.05,
			contrast = 0.055,
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
		ambient = "2F3138",
		outdoorAmbient = "828FA8",
		fogColor = "5A656F",
		fogDecay = "2D343B",
		fogDensity = 0.28,
		tint = "ECF0EE",
		saturation = -0.03,
		contrast = 0.037,
	} :: Lighting,
}
