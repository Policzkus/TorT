--!strict
-- Every sound in the game. Only IDs verified in the Creator Store and load-tested in Studio.
-- id = 0 means "not chosen yet": SoundController skips it silently.
-- Sources: DailySoundsFX ("Daily Sounds", free, synthesized) and ProSoundEffects (Roblox-licensed).

export type Sound = {
	id: number,
	volume: number,
	speed: number?,
	looped: boolean?,
}

local sounds: { [string]: Sound } = {
	-- Doors
	Knock = { id = 9120918417, volume = 0.9 }, -- ProSoundEffects "Wood Knock … Hits 3"
	Creak = { id = 109033795658503, volume = 0.5 }, -- Daily Sounds "Creaky Door"
	-- Mini-games and rewards
	Tick = { id = 106984966606682, volume = 0.35, speed = 1.6 }, -- Daily Sounds "Cartoon Pop"
	Pop = { id = 106984966606682, volume = 0.55 }, -- Daily Sounds "Cartoon Pop"
	Coin = { id = 130378474223829, volume = 0.45 }, -- Daily Sounds "Coin Pickup"
	Perfect = { id = 138309872562566, volume = 0.5, speed = 1.15 }, -- Daily Sounds "Retro Coin Collect"
	Miss = { id = 96795857757261, volume = 0.35, speed = 1.3 }, -- Daily Sounds "Power Down"
	Overflow = { id = 80890994815283, volume = 0.3 }, -- Daily Sounds "Warning Beeps"
	-- Bucket and bank
	Stash = { id = 9117410302, volume = 0.8 }, -- ProSoundEffects "Plastic Bag … Crunchy Cellophane 13"
	-- UI
	Click = { id = 106984966606682, volume = 0.3, speed = 1.3 }, -- Daily Sounds "Cartoon Pop"
	Purchase = { id = 138309872562566, volume = 0.55 }, -- Daily Sounds "Retro Coin Collect"
	Whoosh = { id = 80984744279155, volume = 0.4 }, -- Daily Sounds "Fast Whoosh"
	Unlock = { id = 94978851787238, volume = 0.5 }, -- Daily Sounds "Deep Impact Boom"
	Error = { id = 96795857757261, volume = 0.25, speed = 1.6 }, -- Daily Sounds "Power Down"
	-- Ambience
	NightAmbience = { id = 9112777821, volume = 0.22, looped = true }, -- ProSoundEffects "Farmland Presence 2" (crickets)
	-- Later phases (verified, not wired up yet)
	Stinger = { id = 130018094603454, volume = 0.8 }, -- Daily Sounds "Horror Stinger"
	GhostWail = { id = 129823359634605, volume = 0.5 }, -- Daily Sounds "Ghost Wail"
	Heartbeat = { id = 132163421525060, volume = 0.6, looped = true }, -- Daily Sounds "Fast Heartbeat"
	Countdown = { id = 136924498052589, volume = 0.5 }, -- Daily Sounds "Countdown Beeps"
	Slurp = { id = 109679860270937, volume = 0.6 }, -- Daily Sounds "Slurp"
}

return sounds
