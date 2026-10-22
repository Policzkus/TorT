--!strict
-- Which AI house models (Config/Meshes keys) each neighbourhood uses. Every run rolls one per lot,
-- so streets look different each playthrough. Models that fail to load are skipped; if none load,
-- the street falls back to its part-built style.

local models: { [string]: { string } } = {
	CardboardCourt = { "CardboardCourt_A", "CardboardCourt_B", "CardboardCourt_C" },
	MapleLane = { "MapleLane_A", "MapleLane_B", "MapleLane_C" },
	PumpkinHollow = { "PumpkinHollow_A", "PumpkinHollow_B", "PumpkinHollow_C" },
	RavenRidge = { "RavenRidge_A", "RavenRidge_B", "RavenRidge_C" },
	MansionHill = { "MansionHill_A", "MansionHill_B", "MansionHill_C" },
	BlackwoodEstates = { "BlackwoodEstates_A", "BlackwoodEstates_B", "BlackwoodEstates_C" },
}

return models
