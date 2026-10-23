--!strict
-- First-person PSX horror look (PROMPT §V2.3): a cold, washed-out colour grade with crushed blacks,
-- the distance going soft (depth of field) like a low-res console, a heavy vignette, faint film
-- grain and scanlines, head-bob while walking and a gentle handheld sway.
-- Settings → "PSX effects" switches the heavy parts off (grade/blur/grain); the bob stays.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Images = require(ReplicatedStorage:WaitForChild("Shared").Config.Images)
local StateController = require(script.Parent.StateController)
local create = require(script.Parent.Parent.UI.create)

local FOV = 70
local GRADE = {
	Saturation = -0.32,
	Contrast = 0.24,
	Brightness = 0.015,
	TintColor = Color3.fromRGB(226, 234, 228), -- a cold, slightly sick green
}
local DEPTH = { FarIntensity = 0.42, FocusDistance = 12, InFocusRadius = 26, NearIntensity = 0 }
local GRAIN_TRANSPARENCY = 0.9
local GRAIN_TILE = 256
local SCANLINE_TRANSPARENCY = 0.88
local SCANLINE_TILE = 128
local BOB_SPEED = 9 -- radians per second at walking speed 16
local BOB_AMOUNT = Vector2.new(0.07, 0.09)

local CameraController = {}

local grade: ColorCorrectionEffect
local depth: DepthOfFieldEffect
local grain: ImageLabel
local scanlines: ImageLabel
local overlay: ScreenGui
local enabled = true
local bobTime = 0
local bobWeight = 0

local function applySetting()
	grade.Enabled = enabled
	depth.Enabled = enabled
	overlay.Enabled = true
	grain.Visible = enabled
	scanlines.Visible = enabled
end

-- Called by JumpscareController etc. so effects don't fight a scripted camera.
function CameraController.isFirstPerson(): boolean
	return Players.LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson
end

local function onRender(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	camera.FieldOfView = FOV
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local moving = humanoid ~= nil
		and humanoid.MoveDirection.Magnitude > 0.1
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local speed = if humanoid then humanoid.WalkSpeed / 16 else 1
	bobWeight += ((if moving then 1 else 0) - bobWeight) * math.min(1, dt * 8)
	bobTime += dt * BOB_SPEED * speed * bobWeight
	local now = os.clock()
	-- Walking bob + a slow handheld breathing sway, always a little alive.
	local x = math.sin(bobTime) * BOB_AMOUNT.X * bobWeight + math.sin(now * 0.7) * 0.012
	local y = math.abs(math.cos(bobTime)) * BOB_AMOUNT.Y * bobWeight + math.sin(now * 1.1) * 0.01
	local roll = math.sin(bobTime) * 0.006 * bobWeight + math.sin(now * 0.5) * 0.0025
	camera.CFrame *= CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

function CameraController.Init()
	grade = create("ColorCorrectionEffect", {
		Name = "PSXGrade",
		Saturation = GRADE.Saturation,
		Contrast = GRADE.Contrast,
		Brightness = GRADE.Brightness,
		TintColor = GRADE.TintColor,
		Parent = Lighting,
	})
	depth = create("DepthOfFieldEffect", {
		Name = "PSXDepth",
		FarIntensity = DEPTH.FarIntensity,
		FocusDistance = DEPTH.FocusDistance,
		InFocusRadius = DEPTH.InFocusRadius,
		NearIntensity = DEPTH.NearIntensity,
		Parent = Lighting,
	})

	local vignette = create("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = if Images.Vignette ~= 0 then "rbxassetid://" .. Images.Vignette else "",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Stretch,
	})
	grain = create("ImageLabel", {
		Name = "Grain",
		Size = UDim2.new(1, GRAIN_TILE, 1, GRAIN_TILE),
		Position = UDim2.fromOffset(-GRAIN_TILE / 2, -GRAIN_TILE / 2),
		BackgroundTransparency = 1,
		Image = if Images.Grain ~= 0 then "rbxassetid://" .. Images.Grain else "",
		ImageTransparency = GRAIN_TRANSPARENCY,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(GRAIN_TILE, GRAIN_TILE),
	})
	scanlines = create("ImageLabel", {
		Name = "Scanlines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = if Images.Scanlines ~= 0 then "rbxassetid://" .. Images.Scanlines else "",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = SCANLINE_TRANSPARENCY,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(SCANLINE_TILE, SCANLINE_TILE),
	})
	overlay = create("ScreenGui", {
		Name = "PSXOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1, -- under every other UI
		create("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			grain,
		}),
		scanlines,
		vignette,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

function CameraController.Start()
	StateController.observe("settings", function(settings: any)
		enabled = not (type(settings) == "table" and settings.psx == false)
		applySetting()
	end)
	applySetting()
	RunService:BindToRenderStep("PSXCamera", Enum.RenderPriority.Camera.Value + 1, onRender)
	-- Costume swaps replace the character in place (CharacterService); Roblox only re-targets the
	-- camera for characters it spawned itself, so follow every new one here.
	local function follow(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		local camera = Workspace.CurrentCamera
		if humanoid and camera and Players.LocalPlayer.Character == character then
			camera.CameraSubject = humanoid
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	Players.LocalPlayer.CharacterAdded:Connect(follow)
	if Players.LocalPlayer.Character then
		task.spawn(follow, Players.LocalPlayer.Character)
	end
	-- Film grain: jump the tiled noise to a random offset ~20 times a second.
	task.spawn(function()
		while true do
			task.wait(0.05)
			if grain.Visible then
				grain.Position = UDim2.fromOffset(-math.random(0, GRAIN_TILE), -math.random(0, GRAIN_TILE))
			end
		end
	end)
end

return CameraController
