--!strict
-- First-person PSX horror look (PROMPT §V2.3): a cold, washed-out colour grade with crushed blacks,
-- the distance going soft (depth of field) like a low-res console, a heavy vignette, PS1 grain
-- (chunky noise flickering over everything, the user asked for it) and scanlines. No mouse cursor in
-- play (the HUD's dot is the aim); a cursor whenever a window or menu is open, so you can see what
-- you're pointing at. Settings → "PSX effects" switches the heavy parts off (grade/blur/grain).
-- How the view moves with you (MovementController's gait):
--   - The head-bob keeps time with your feet: the view dips as each foot lands (the step's sound
--     comes then, FootstepController), sways over onto the foot you're on and leans with it, and
--     nods a touch. Running: quicker and harder, but never higher (Shift used to read as a height
--     change: no widening of the view either). Creeping: slow, low, more side to side.
--   - Crouching lowers your eyes on a spring that settles with a little give, the head dipping
--     forward a touch as you go down and lifting as you come up.
--   - Strafing leans you into it. Landing: the view drops and nods with the impact and springs back
--     (harder falls, deeper); jumping, a little push-off.
--   - Standing still it's handheld, always a little alive; out of breath, it rises and falls with each breath.
--   - The view has weight: it trails where you're looking by a touch and catches up. Only the
--     picture: where you really look (your walk, what you face, what you aim at) turns the moment you
--     move the mouse. Stepping up a kerb or a stair the view rises after you instead of jolting.
-- Settings → "Head bob" off keeps all of it small and drops the trail (crouching still lowers your eyes).
-- Roblox's camera works out each frame's look from the last one we drew, so whatever turn we added is
-- taken back off first: what's left is where you really look (yaw, pitch), and the view is drawn
-- from that.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Images = require(ReplicatedStorage:WaitForChild("Shared").Config.Images)
local Motion = require(ReplicatedStorage:WaitForChild("Shared").Modules.Motion)
local MovementController = require(script.Parent.MovementController)
local StateController = require(script.Parent.StateController)
local create = require(script.Parent.Parent.UI.create)

local FOV = 70
local GRADE = {
	Saturation = -0.12,
	Contrast = 0.08,
	Brightness = 0.015,
	TintColor = Color3.fromRGB(226, 234, 228), -- a cold, slightly sick green
}
local DEPTH = { FarIntensity = 0.12, FocusDistance = 40, InFocusRadius = 70, NearIntensity = 0 }
local GRAIN_TRANSPARENCY = 0.8875 -- (0.8 was a quarter too strong, the user said; then 0.85 was too: a quarter less again)
local GRAIN_TILE = 384
local GRAIN_TINT = Color3.fromRGB(200, 200, 200) -- a touch dark, so the specks don't lift the blacks
local SCANLINE_TRANSPARENCY = 0.88
local SCANLINE_TILE = 128
-- The bob at each step: `dip` studs down as a foot lands, `sway` studs side to side over two steps
-- (onto the foot you're on), `roll` radians of lean with the sway, `nod` radians of pitch down as the
-- foot lands. Walking, running and creeping each have their own; in between they blend.
local BOB = {
	walk = { dip = 0.085, sway = 0.055, roll = math.rad(0.35), nod = math.rad(0.15) },
	run = { dip = 0.12, sway = 0.085, roll = math.rad(0.75), nod = math.rad(0.45) },
	creep = { dip = 0.045, sway = 0.075, roll = math.rad(0.55), nod = math.rad(0.1) },
}
local STRAFE_LEAN = math.rad(1.3) -- roll into a sideways walk, per walking speed of it
local IDLE = { sway = 0.012, rise = 0.01, roll = 0.0025 } -- studs, studs, radians: handheld, standing still
local BREATH_RISE = 0.035 -- studs the view rises and falls with each breath, fully out of breath
-- Landing and jumping kick springs that settle back (frequency radians/s, damping under 1 bounces a little).
local LAND = { frequency = 11, damping = 0.6, drop = { 0.6, 3.6 }, nod = { 0.15, 0.85 }, roll = 0.25, jump = 0.4 }
local REDUCED = 0.2 -- the bob's size with Settings → Head bob off
-- The view trailing where you look: moved back by each turn, sprung back onto it (`frequency`
-- radians/s, `damping`), never more than `most` radians behind. (It first was 24 rad/s and 4°, a
-- quarter too much, the user said; then 32 and 3°, a little too little.)
local TRAIL = { frequency = 28, damping = 0.85, most = math.rad(3.5) }
-- Stepping up (or down) a kerb or a stair moves you at once; the view is left behind by it and
-- catches up at `rate` a second. More than `most` studs in a frame is a teleport, followed straight
-- away. Jumps and falls aren't steps: in the air (and from the moment you jump) the view goes with
-- you, only what's left of a step catching up as before (it used to lag the jump, then snap up to it).
local STEP = { rate = 16, most = 2.5, jump = 0.3 }
local CROUCH_NOD = { down = 0.32, up = 0.14 } -- radians/s kicked into the nod going down, coming up

local CameraController = {}

local grade: ColorCorrectionEffect
local depth: DepthOfFieldEffect
local grain: ImageLabel
local scanlines: ImageLabel
local overlay: ScreenGui
local modals: { [GuiButton]: boolean } = {} -- buttons that free the mouse while they're on screen
local enabled = true
local bobOn = true -- Settings → Head bob
local fovOffset = 0 -- now (eases toward fovTarget)
local fovTarget = 0
-- Landing/jumping springs: how far down (studs), nodded (radians) and rolled the view is, and how fast.
local drop, dropSpeed = 0, 0
local nod, nodSpeed = 0, 0
-- How far the view trails where you're looking (radians), and how fast that's changing.
local trailYaw, trailYawSpeed, trailPitch, trailPitchSpeed = 0, 0, 0, 0
local lookYaw: number? = nil -- where you really looked last frame
local lookPitch: number? = nil
local addedYaw, addedPitch = 0, 0 -- the turn we drew on top of it (still on the camera)
local lastY: number? = nil -- the view's height last frame (before ours)
local stepLag = 0 -- studs the view is behind you, after a step up (-) or down (+)
local jumpedAt = -math.huge
local wasAirborne = false
local wasCrouching = false
local tilt, tiltSpeed = 0, 0

local function applySetting()
	grade.Enabled = enabled
	depth.Enabled = enabled
	overlay.Enabled = true
	grain.Visible = enabled
	scanlines.Visible = enabled
end

-- Widens the view by `degrees` (eased). (Sprinting used to; the user read it as a height change.)
function CameraController.setFovOffset(degrees: number)
	fovTarget = degrees
end

-- Called by JumpscareController etc. so effects don't fight a scripted camera.
function CameraController.isFirstPerson(): boolean
	return Players.LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson
end

-- Whether a window or menu is on screen: one of its Modal buttons is shown. (In first person the
-- mouse still reads as locked while a Modal frees it, so MouseBehavior can't tell.)
local function menuOpen(): boolean
	for button in modals do
		local shown = button.Visible
		local node: Instance? = button.Parent
		while shown and node and not node:IsA("LayerCollector") do
			if node:IsA("GuiObject") and not node.Visible then
				shown = false
			end
			node = node.Parent
		end
		if shown and node and node:IsA("LayerCollector") and node.Enabled then
			return true
		end
	end
	return false
end

-- The bob's size for `key`, between walking and running, and creeping.
local function bobOf(gait: MovementController.Gait, key: string): number
	local walk, run, creep = (BOB.walk :: any)[key], (BOB.run :: any)[key], (BOB.creep :: any)[key]
	local standing = walk + (run - walk) * gait.sprint
	return standing + (creep - standing) * math.clamp(gait.crouch, 0, 1)
end

-- You landed (impact 0..1): the view drops and nods with it, tipped a touch one way or the other.
local function onLanded(impact: number)
	local scale = if bobOn then 1 else 0.5
	dropSpeed -= (LAND.drop[1] + LAND.drop[2] * impact) * scale
	nodSpeed -= (LAND.nod[1] + LAND.nod[2] * impact) * scale
	tiltSpeed += (if math.random() < 0.5 then -1 else 1) * LAND.roll * impact * scale
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Whoever has the camera now set it outright: nothing of ours is on it, and nothing saved up.
local function letGo()
	addedYaw, addedPitch = 0, 0
	lookYaw, lookPitch, lastY, stepLag = nil, nil, nil, 0
	trailYaw, trailYawSpeed, trailPitch, trailPitchSpeed = 0, 0, 0, 0
	drop, dropSpeed, nod, nodSpeed, tilt, tiltSpeed = 0, 0, 0, 0, 0, 0
end

local function onRender(dt: number)
	UserInputService.MouseIconEnabled = menuOpen() or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	local camera = Workspace.CurrentCamera
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		letGo()
		return
	end
	fovOffset += (fovTarget - fovOffset) * math.min(1, dt * 5)
	camera.FieldOfView = FOV + fovOffset
	local gait = MovementController.gait()
	local crouching = MovementController.isCrouching()
	if crouching ~= wasCrouching then
		wasCrouching = crouching
		nodSpeed += (if crouching then -CROUCH_NOD.down else CROUCH_NOD.up) * (if bobOn then 1 else 0.5)
	end
	drop, dropSpeed = Motion.spring(drop, dropSpeed, 0, LAND.frequency, LAND.damping, dt)
	nod, nodSpeed = Motion.spring(nod, nodSpeed, 0, LAND.frequency, LAND.damping, dt)
	tilt, tiltSpeed = Motion.spring(tilt, tiltSpeed, 0, LAND.frequency, LAND.damping, dt)

	-- Where you really look: Roblox's camera turned last frame's view by your mouse; take off what we added.
	local at = camera.CFrame
	local seenPitch, seenYaw = at:ToEulerAnglesYXZ()
	local yaw, pitch = seenYaw - addedYaw, seenPitch - addedPitch
	-- The view trails it: put back by however far you turned, then sprung back on.
	if bobOn and lookYaw and lookPitch then
		trailYaw = math.clamp(trailYaw - wrap(yaw - lookYaw), -TRAIL.most, TRAIL.most)
		trailPitch = math.clamp(trailPitch - (pitch - lookPitch), -TRAIL.most, TRAIL.most)
	elseif not bobOn then
		trailYaw, trailPitch = 0, 0
	end
	lookYaw, lookPitch = yaw, pitch
	trailYaw, trailYawSpeed = Motion.spring(trailYaw, trailYawSpeed, 0, TRAIL.frequency, TRAIL.damping, dt)
	trailPitch, trailPitchSpeed = Motion.spring(trailPitch, trailPitchSpeed, 0, TRAIL.frequency, TRAIL.damping, dt)

	-- Up and down steps: the view is left behind and catches up over a moment (not in the air, nor
	-- jumping; and a teleport is followed at once).
	local position = at.Position
	local y = position.Y
	local before = lastY
	if before == nil or math.abs(y - before) > STEP.most then
		stepLag = 0
	elseif not gait.airborne and not wasAirborne and os.clock() - jumpedAt > STEP.jump then
		stepLag = math.clamp(stepLag - (y - before), -STEP.most, STEP.most)
	end
	lastY, wasAirborne = y, gait.airborne
	stepLag = Motion.ease(stepLag, 0, STEP.rate, dt)

	local bob = gait.moving * (if bobOn then 1 else REDUCED)
	local calm = if bobOn then 1 else 0.5
	local footfall = Motion.footfall(gait.phase)
	local side = math.sin(gait.phase) -- over onto the foot you're on, mid-stride
	local now = os.clock()
	local swayX = side * bobOf(gait, "sway") * bob + math.sin(now * 0.7) * IDLE.sway * calm
	local swayY = -footfall * bobOf(gait, "dip") * bob
		+ math.sin(now * 1.1) * IDLE.rise * calm
		+ math.sin(gait.breath) * BREATH_RISE * gait.winded * calm
		+ drop
	local roll = -side * bobOf(gait, "roll") * bob
		- gait.lateral * STRAFE_LEAN * (if bobOn then 1 else 0)
		+ math.sin(now * 0.5) * IDLE.roll * calm
		+ tilt
	local addYaw = trailYaw
	local shownPitch = math.clamp(pitch + trailPitch - footfall * bobOf(gait, "nod") * bob + nod, -1.45, 1.45)
	local height = stepLag - gait.drop * gait.crouch
	camera.CFrame = CFrame.new(position + Vector3.new(0, height, 0))
		* CFrame.Angles(0, yaw + addYaw, 0)
		* CFrame.Angles(shownPitch, 0, 0)
		* CFrame.new(swayX, swayY, 0)
		* CFrame.Angles(0, 0, roll)
	addedYaw, addedPitch = addYaw, shownPitch - pitch
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
		ImageColor3 = GRAIN_TINT,
		ResampleMode = Enum.ResamplerMode.Pixelated, -- hard-edged specks, not a soft blur
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
		bobOn = not (type(settings) == "table" and settings.headBob == false)
		applySetting()
	end)
	MovementController.landed:Connect(onLanded)
	MovementController.jumped:Connect(function()
		jumpedAt = os.clock()
		dropSpeed -= LAND.jump * (if bobOn then 1 else 0.5) -- pushing off
	end)
	applySetting()
	RunService:BindToRenderStep("PSXCamera", Enum.RenderPriority.Camera.Value + 1, onRender)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function track(item: Instance)
		if item:IsA("GuiButton") and item.Modal then
			modals[item] = true
		end
	end
	for _, item in playerGui:GetDescendants() do
		track(item)
	end
	playerGui.DescendantAdded:Connect(track)
	playerGui.DescendantRemoving:Connect(function(item)
		if item:IsA("GuiButton") then
			modals[item] = nil
		end
	end)
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
	-- The grain: jump the tiled noise to a random offset ~20 times a second, so it crawls.
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
