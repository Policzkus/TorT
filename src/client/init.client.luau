--!strict
-- Client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared").Modules.Loader)

Loader.run(script.Controllers, {
	"StateController",
	"SoundController",
	"CameraController",
	"ViewmodelController",
	"MusicController",
	"TransitionController",
	"NotificationController",
	"CelebrationController",
	"ZoneLightingController",
	"DoorController",
	"HouseVisualController",
	"JumpscareController",
	"MinigameController",
	"ShopController",
	"BusController",
	"GateController",
	"SettingsController",
	"HUDController",
}, "Client")
