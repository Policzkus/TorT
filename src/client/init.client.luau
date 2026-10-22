--!strict
-- Client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared").Modules.Loader)

Loader.run(script.Controllers, {
	"LoadingController",
	"StateController",
	"SoundController",
	"CameraController",
	"ViewmodelController",
	"CharacterAnimController",
	"MusicController",
	"TransitionController",
	"NotificationController",
	"CelebrationController",
	"ZoneLightingController",
	"DoorController",
	"HouseVisualController",
	"JumpscareController",
	"MinigameController",
	"RadialMenuController",
	"ShopController",
	"CostumeController",
	"BusController",
	"GateController",
	"SettingsController",
	"HUDController",
}, "Client")
