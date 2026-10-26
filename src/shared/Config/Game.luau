--!strict
-- Global, game-wide settings that are not part of the economy.
return {
	VERSION = "0.1.0",

	-- Changing the store name starts everyone from scratch. Use migrations instead.
	DATA_STORE_NAME = "PlayerData_v1",
	DATA_KEY_PREFIX = "Player_",
	-- true = Studio sessions use a throwaway in-memory store (live data is never touched).
	USE_MOCK_DATA_IN_STUDIO = false,

	-- Seconds between batched state pushes to each client.
	STATE_FLUSH_INTERVAL = 0.15,
	-- Seconds between server-side playtime accumulations.
	PLAYTIME_TICK = 10,

	-- Which kind of server Studio plays as: "run" (the streets, one Night) or "lobby" (shop,
	-- costumes, the party buses). Live servers know from how they were started (Modules/Mode).
	-- Teleports don't work in Studio, so each side is tested on its own there.
	STUDIO_MODE = "run",
}
