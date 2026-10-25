--!strict
-- Every sound in the game (SoundController plays them by name). PSX horror, not cartoon: real
-- recordings only. id = an uploaded sound (only IDs verified in the Creator Store and load-tested in
-- Studio); clip = a slice of one of our sprite files (Config/SoundSprites, built from Kenney's CC0
-- packs by art/scripts/sound_sprites.py; until a sprite is uploaded the clip falls back to `id`);
-- slice = play a random piece that many seconds long of the sound.
-- Sources: ProSoundEffects (Roblox-licensed), Kenney (CC0), DailySoundsFX (free, synthesized: the
-- few left are to be replaced).

export type Sound = {
	id: number?,
	clip: string?,
	slice: number?,
	volume: number,
	speed: number?,
	looped: boolean?,
}

local sounds: { [string]: Sound } = {
	-- Doors
	Knock = { id = 9120918417, volume = 0.9 }, -- ProSoundEffects "Wood Knock … Hits 3"
	KnockSingle = { id = 9119128908, volume = 0.8 }, -- ProSoundEffects "Shutter Bangs Single Wood Hits Knocks 7"
	Latch = { clip = "Latch", volume = 0.55 }, -- a bolt drawn back before the door opens
	Creak = { clip = "DoorOpen", id = 109033795658503, volume = 0.6 }, -- Kenney door open; fallback Daily Sounds "Creaky Door"
	DoorSlam = { id = 9114129572, volume = 0.7 }, -- ProSoundEffects "Door Bang Rattle 8"
	DoorShut = { clip = "DoorClose", id = 9114129572, volume = 0.55 }, -- Kenney door closing (falls back to the slam)
	-- Homeowners
	Voice = { id = 9126213744, slice = 0.085, volume = 0.6 }, -- ProSoundEffects "Whisper Bursts Eerie Unintelligible Phrases 2"
	Thud = { id = 9116908474, volume = 0.6, speed = 0.7 }, -- ProSoundEffects "Metal Whomps Deep Pounding Impacts 13"
	FloorCreak = { id = 9114495966, volume = 0.6 }, -- ProSoundEffects "Floor Creaks Short Med Wood Creaks 18"
	Breath = { id = 9113586144, volume = 0.5, speed = 0.8 }, -- ProSoundEffects "Breath Exhale 17"
	OwnerStep = { clip = "Plank", id = 9114495966, volume = 0.42 }, -- Kenney heavy plank impact: their weight on the boards
	BoardCreak = { clip = "Creak", id = 9114495966, volume = 0.3 }, -- Kenney creaks: a board giving under them
	Cloth = { clip = "Cloth", volume = 0.35 }, -- Kenney cloth: clothes moving as they start, stop, turn
	-- Mini-games and rewards
	Tick = { clip = "Tick", id = 106984966606682, volume = 0.45 }, -- Kenney tick
	Pop = { clip = "Drop", id = 106984966606682, volume = 0.5 }, -- Kenney drop (GOOD)
	Coin = { clip = "Coins", id = 130378474223829, volume = 0.5 }, -- Kenney coins in a hand: candy (GREAT)
	Perfect = { clip = "Bell", id = 138309872562566, volume = 0.45, speed = 0.75 }, -- Kenney bell, slowed: a deep toll (PERFECT)
	Miss = { clip = "Error", id = 96795857757261, volume = 0.4, speed = 0.7 }, -- Kenney error, low
	Overflow = { clip = "Glitch", id = 80890994815283, volume = 0.4 }, -- Kenney glitch
	-- Bucket and bank
	Stash = { id = 9117410302, volume = 0.8 }, -- ProSoundEffects "Plastic Bag … Crunchy Cellophane 13"
	-- UI
	Click = { clip = "Click", id = 106984966606682, volume = 0.35 }, -- Kenney click
	Hover = { clip = "Hover", volume = 0.18 }, -- Kenney select
	Open = { clip = "Open", volume = 0.3 }, -- Kenney: a menu opening
	Close = { clip = "Close", volume = 0.3 },
	Purchase = { clip = "Confirm", id = 138309872562566, volume = 0.45 }, -- Kenney confirmation
	Whoosh = { id = 80984744279155, volume = 0.4 }, -- Daily Sounds "Fast Whoosh"
	Unlock = { id = 94978851787238, volume = 0.5 }, -- Daily Sounds "Deep Impact Boom"
	Error = { clip = "Error", id = 96795857757261, volume = 0.3 }, -- Kenney error
	-- Footsteps and landings (FootstepController), by what's underfoot
	StepWood = { clip = "StepWood", volume = 0.32 },
	StepGrass = { clip = "StepGrass", volume = 0.3 },
	StepConcrete = { clip = "StepConcrete", volume = 0.3 },
	StepDirt = { clip = "StepDirt", volume = 0.3 },
	StepCarpet = { clip = "StepCarpet", volume = 0.3 },
	LandWood = { clip = "LandWood", volume = 0.35 },
	LandSoft = { clip = "LandSoft", volume = 0.35 },
	-- Ambience (AmbienceController)
	NightAmbience = { id = 9112777821, volume = 0.2, looped = true }, -- ProSoundEffects "Farmland Presence 2" (crickets)
	Wind = { id = 9114625552, volume = 0.22, looped = true }, -- ProSoundEffects "Gods Wind, Spooky, Eerie 3"
	Owl = { id = 9117181540, volume = 0.5 }, -- ProSoundEffects "Owl Hooting Reverberant Several 1"
	Thunder = { id = 9113169432, volume = 0.45, speed = 0.8 }, -- ProSoundEffects "Artillery Distant … Possible Use: Thunder"
	ChurchBell = { id = 9113804436, volume = 0.35 }, -- ProSoundEffects "Church Bell Tolling 1"
	Whispers = { id = 9126213995, volume = 0.25 }, -- ProSoundEffects "Whisper Bursts Unintelligible Eerie Evil Ghost 4"
	-- Scares
	Stinger = { id = 130018094603454, volume = 0.8 }, -- Daily Sounds "Horror Stinger"
	GhostWail = { id = 129823359634605, volume = 0.5 }, -- Daily Sounds "Ghost Wail"
	Heartbeat = { id = 132163421525060, volume = 0.6, looped = true }, -- Daily Sounds "Fast Heartbeat"
	Countdown = { id = 136924498052589, volume = 0.5 }, -- Daily Sounds "Countdown Beeps"
	Slurp = { id = 109679860270937, volume = 0.6 }, -- Daily Sounds "Slurp"
}

return sounds
