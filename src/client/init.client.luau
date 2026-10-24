--!strict
-- Client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared").Modules.Loader)

Loader.run(script.Controllers, {
	"LoadingController",
	"StateController",
	"SoundController",
	"FootstepController",
	"AmbienceController",
	"CameraController",
	"MovementController",
	"FlashlightController",
	"ViewmodelController",
	"CharacterAnimController",
	"MusicController",
	"TransitionController",
	"NotificationController",
	"CelebrationController",
	"ZoneLightingController",
	"DialogController",
	"DoorController",
	"HouseVisualController",
	"HomeownerController",
	"HingeController",
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
