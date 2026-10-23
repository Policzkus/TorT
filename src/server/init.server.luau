--!strict
-- Server entry point.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Characters spawn only after the world exists (CharacterService.Start), never into the void.
Players.CharacterAutoLoads = false

local Loader = require(ReplicatedStorage.Shared.Modules.Loader)
local Net = require(ReplicatedStorage.Shared.Modules.Net)

-- Remotes must exist before any client asks for them.
Net.setup()

Loader.run(script.Services, {
	"DataService",
	"LeaderstatsService",
	"NotifyService",
	"WorldService", -- builds the world in Init, before anything asks about houses
	"WorldEventsService",
	"HingeService",
	"HomeownerService",
	"HouseService",
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
	"AdminService",
}, "Server")
