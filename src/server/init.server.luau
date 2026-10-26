--!strict
-- Server entry point.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Characters spawn only after the world exists (CharacterService.Start), never into the void.
Players.CharacterAutoLoads = false

local Loader = require(ReplicatedStorage.Shared.Modules.Loader)
local Mode = require(ReplicatedStorage.Shared.Modules.Mode)
local Net = require(ReplicatedStorage.Shared.Modules.Net)

-- The public lobby or a party's private run (decided before anything is built).
local mode = Mode.decide()

-- Remotes must exist before any client asks for them.
Net.setup()

-- What only the run has: the streets' doors, homeowners and Candy Boxes.
local RUN_ONLY = {
	"HingeService",
	"HomeownerService",
	"HouseService",
	"HallFigureService",
	"MinigameService",
	"NeighborhoodService",
	"DoorService",
	"StashService",
	"TrafficService",
	"KniferService",
	"RunExitService",
}
-- What only the lobby has: the party buses.
local LOBBY_ONLY = { "PartyService" }

local order = {
	"DataService",
	"LeaderstatsService",
	"NotifyService",
	"WorldService", -- builds the world (the streets or the lobby) in Init, before anything asks about it
	"WorldEventsService",
	"HingeService",
	"HomeownerService",
	"HouseService",
	"HallFigureService",
	"CandyService",
	"BucketService",
	"UpgradeService",
	"MinigameService",
	"NeighborhoodService",
	"DoorService",
	"StashService",
	"SettingsService",
	"CharacterService",
	"CostumeService",
	"LivesService",
	"RagdollService",
	"TrafficService",
	"KniferService",
	"RunExitService",
	"PartyService",
	"AdminService",
}
local unused = if mode == "lobby" then RUN_ONLY else LOBBY_ONLY
local skip = {}
for _, name in unused do
	skip[name] = true
end
local services = {}
for _, name in order do
	if not skip[name] then
		table.insert(services, name)
	end
end
Loader.run(script.Services, services, `Server ({mode})`, unused)
