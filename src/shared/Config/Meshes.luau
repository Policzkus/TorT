--!strict
-- AI-generated meshes (Roblox Studio generate_mesh, created on the owner's account) used by the
-- procedural models. Loaded on the server at boot by Modules/MeshLibrary; if one fails to load,
-- the part-built fallback is used instead. size = studs after scaling.

export type Mesh = {
	mesh: number,
	texture: number,
	size: { number }, -- x, y, z
}

local meshes: { [string]: Mesh } = {
	-- Glossy carved jack-o'-lantern bucket with a black handle (2026-10-22).
	PlasticPumpkin = { mesh = 132519254685102, texture = 75260871453897, size = { 1.105, 1.238, 1.019 } },
}

return meshes
