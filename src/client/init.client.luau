--!strict
-- Client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared").Modules.Loader)

Loader.run(script.Controllers, {
	"StateController",
	"SoundController",
	"TransitionController",
	"NotificationController",
	"CelebrationController",
	"ZoneLightingController",
	"DoorController",
	"MinigameController",
	"ShopController",
	"BusController",
	"GateController",
	"HUDController",
}, "Client")
