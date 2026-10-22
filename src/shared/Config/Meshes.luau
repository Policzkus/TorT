--!strict
-- AI-generated meshes (Roblox Studio generate_mesh, created on the owner's account) used by the
-- procedural world. Loaded on the server at boot by Modules/MeshLibrary; if one fails to load,
-- the part-built fallback is used instead. size = studs after scaling.
-- collision: "Box" | "Hull" | "Default" (default "Default").

export type Mesh = {
	mesh: number,
	texture: number,
	size: { number }, -- x, y, z
	collision: string?,
}

local meshes: { [string]: Mesh } = {
	-- Glossy carved jack-o'-lantern bucket with a black handle (2026-10-22).
	PlasticPumpkin = {
		mesh = 132519254685102,
		texture = 75260871453897,
		size = { 1.105, 1.238, 1.019 },
		collision = "Box",
	},
	-- Boxy cartoon sheet ghost, arms up, screaming mouth (jumpscare monster).
	Ghost = { mesh = 105282263287818, texture = 72144604826180, size = { 4, 3.615, 1.886 }, collision = "Box" },

	-- Homeowners in the doorways (PSX uncanny; heights normalised to ~7.5 studs).
	Owner_Cardigan = { mesh = 110342999988230, texture = 127878523963013, size = { 3, 7.67, 1.6 }, collision = "Box" },
	Owner_Nightgown = {
		mesh = 127687999129495,
		texture = 86212640620879,
		size = { 2.65, 7.25, 4.16 },
		collision = "Box",
	},
	Owner_Lanky = { mesh = 125298729762873, texture = 139517769524169, size = { 3.9, 7.84, 3.22 }, collision = "Box" },
	Owner_Bathrobe = { mesh = 98223054872920, texture = 86103850659105, size = { 4.2, 7.43, 2.97 }, collision = "Box" },
	Owner_Grinner = { mesh = 134976304923085, texture = 80638457446594, size = { 5.46, 7, 4.4 }, collision = "Box" },

	-- Houses (front faces -Z, door roughly front-centre). Scarier every neighbourhood.
	CardboardCourt_A = { mesh = 139857200522321, texture = 85835037275708, size = { 16.1, 15.5, 20.8 } }, -- dented trailer
	MapleLane_A = { mesh = 124962910036920, texture = 114034936887052, size = { 18.5, 26, 20.1 } }, -- crooked brick cottage
	PumpkinHollow_A = { mesh = 117889583550104, texture = 96873346256909, size = { 32, 29, 25.1 } }, -- stacked Halloween house
	RavenRidge_A = { mesh = 127560543088686, texture = 77050219127257, size = { 28.1, 35.3, 28 } }, -- spired Victorian
	MansionHill_A = { mesh = 117406777732108, texture = 135921489828261, size = { 31.4, 34, 22.1 } }, -- red-window mansion
	CardboardCourt_B = { mesh = 71078052007165, texture = 92781725308885, size = { 20.7, 15.7, 18 } }, -- tarp-roof shack
	MapleLane_B = { mesh = 135267446864473, texture = 97918696879809, size = { 20, 21.5, 19.2 } }, -- leaning clapboard house
	RavenRidge_B = { mesh = 85684412884034, texture = 100563502725884, size = { 19.3, 40, 22.8 } }, -- tall leaning townhouse
	MansionHill_B = { mesh = 76521085928903, texture = 86615246508276, size = { 30.1, 28, 29.9 } }, -- jagged modern mansion
	BlackwoodEstates_B = { mesh = 118381010426596, texture = 107564045536175, size = { 38, 33, 21.9 } }, -- abandoned manor
	CardboardCourt_C = { mesh = 75263963956540, texture = 85099252097046, size = { 16.4, 15, 16.8 } }, -- mossy double-wide
	MapleLane_C = { mesh = 105685104520686, texture = 118147286703971, size = { 16, 20, 19.6 } }, -- quirky brick bungalow
	PumpkinHollow_B = { mesh = 125747752274661, texture = 133906369382313, size = { 21.7, 28, 21.8 } }, -- tall house, deflated ghost
	MansionHill_C = { mesh = 79038639590997, texture = 134280920639838, size = { 33.6, 24.1, 32 } }, -- columns, statue, fountain
	BlackwoodEstates_C = { mesh = 84079240499769, texture = 93130001134407, size = { 27.1, 40, 26.9 } }, -- witch house
	PumpkinHollow_C = { mesh = 126268134765143, texture = 125735808964360, size = { 31, 26.8, 24 } }, -- grey house, one red window
	RavenRidge_C = { mesh = 77859538188945, texture = 121718697953857, size = { 30, 30.4, 23.7 } }, -- charcoal turret Victorian
	BlackwoodEstates_A = { mesh = 105308668217060, texture = 115690373426571, size = { 40, 32.5, 30.5 } }, -- manor + dead tree
}

return meshes
