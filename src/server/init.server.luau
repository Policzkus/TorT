--!strict
-- Server entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Modules.Loader)
local Net = require(ReplicatedStorage.Shared.Modules.Net)

-- Remotes must exist before any client asks for them.
Net.setup()

Loader.run(script.Services, {
	"DataService",
	"LeaderstatsService",
	"NotifyService",
	"AdminService",
}, "Server")
