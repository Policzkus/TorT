--!strict
-- The lobby's party buses and the runs they start (PROMPT §V2.2/V2.3): a party of 1-4 boards a bus
-- in the public lobby and is teleported to its own private server of the same place, where the run
-- goes on until the players choose to go back to the lobby (RunExitService).
return {
	PARTY_MAX = 4,
	COUNTDOWN = 5, -- seconds after the host presses Start before the bus leaves
	TELEPORT_TRIES = 3,
	FAINT_TIME = 3, -- seconds you're out after being caught, before you come to at the bus stop
	DOWN_TIME = 4, -- seconds you lie there as a ragdoll, killed by the Knifer, before you wake at the spawn
}
