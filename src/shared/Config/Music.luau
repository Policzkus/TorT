--!strict
-- Background music (PROMPT §3.19). Licensed tracks from DistrokidOfficial (Roblox's music
-- partner), load-tested in Studio. Volume is scaled by the player's Music setting.
-- Priority: the Knifer chasing you > Blood Moon > Witching Hour > the zone you're in.

export type Track = { id: number, volume: number }

return {
	zones = {
		Hub = { id = 111631783838916, volume = 0.35 }, -- "Spooky cartoon music"
		CardboardCourt = { id = 115585877205328, volume = 0.35 }, -- "Spooky cartoon music, Pt. 4"
		MapleLane = { id = 128054415504948, volume = 0.35 }, -- "Autumn after Dark"
		PumpkinHollow = { id = 136130575549265, volume = 0.35 }, -- "Night at Graveyard"
	} :: { [string]: Track },
	witching = { id = 138856055860898, volume = 0.45 } :: Track, -- "Halloween haunted house, Pt. 2"
	bloodMoon = { id = 127648968320882, volume = 0.45 } :: Track, -- "The Blood Moon Rising"
	chase = { id = 1843040609, volume = 0.6 } :: Track, -- the Knifer's after you: APM "Pista Omicida 2nd vers."
	FADE = 2, -- seconds to crossfade
	CHASE_FADE = 0.4, -- into the chase music (and out of it)
}
