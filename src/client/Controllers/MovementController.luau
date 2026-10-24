--!strict
-- How you move: walking picks up over a moment instead of snapping to full speed, and you can
-- sprint (hold Shift, click the left stick, or the 🏃 button on a touch screen) while your stamina
-- lasts. Sprinting widens the view a little (CameraController) and runs the head-bob faster; when
-- you're winded you breathe hard and have to catch your breath before sprinting again. A thin bar
-- under the middle of the view shows stamina while it isn't full.
-- The walking speed itself comes from the server (Sneakers upgrade): Humanoid attribute BaseSpeed.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CameraController = require(script.Parent.CameraController)
local Sound = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local MovementController = {}

local SPRINT_SPEED = 1.6 -- times the walking speed
local SPRINT_FOV = 8 -- degrees added while sprinting
local STAMINA = { drain = 17, regen = 26, delay = 0.9, recover = 30 } -- per second; recover: needed after running dry
local RAMP = 0.22 -- seconds from standing to full walking speed
local START_SPEED = 0.55 -- of full speed, the moment you start walking
local WINDED = 25 -- stamina under which you breathe hard
local ACTION = "Sprint"

local holding = false -- Shift held
local toggled = false -- the stick click or the touch button: on until you stop moving
local stamina = 100
local exhausted = false
local restAt = 0 -- when stamina starts coming back
local ramp = 1 -- 0..1: how far into the walking ramp
local current = 1 -- speed multiplier now (eases toward the target)
local breathAt = 0
local bar: Frame
local fill: Frame
local barShown = false

local function humanoidOf(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function showBar(visible: boolean)
	if visible == barShown then
		return
	end
	barShown = visible
	local info = TweenInfo.new(if visible then 0.15 else 0.6)
	TweenService:Create(bar, info, { BackgroundTransparency = if visible then 0.7 else 1 }):Play()
	TweenService:Create(fill, info, { BackgroundTransparency = if visible then 0.1 else 1 }):Play()
end

local function step(dt: number)
	local humanoid = humanoidOf()
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local base = (humanoid:GetAttribute("BaseSpeed") :: number?) or 16
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if not moving then
		toggled = false
	end
	local sprinting = (holding or toggled) and moving and not exhausted and stamina > 0

	if sprinting and grounded then
		stamina = math.max(0, stamina - STAMINA.drain * dt)
		restAt = os.clock() + STAMINA.delay
		if stamina == 0 then
			exhausted = true
		end
	elseif os.clock() >= restAt then
		stamina = math.min(100, stamina + STAMINA.regen * dt)
		if exhausted and stamina >= STAMINA.recover then
			exhausted = false
		end
	end

	-- Walking builds up from a slower first step; letting go stops you at once.
	ramp = if moving then math.min(1, ramp + dt / RAMP) else 0
	local target = (START_SPEED + (1 - START_SPEED) * ramp) * (if sprinting then SPRINT_SPEED else 1)
	current += (target - current) * math.min(1, dt * (if target > current then 6 else 10))
	humanoid.WalkSpeed = base * current

	CameraController.setFovOffset(if sprinting then SPRINT_FOV else 0)

	if stamina < WINDED and os.clock() >= breathAt then
		breathAt = os.clock() + 1.1 + stamina / 40
		Sound.play("Breath", { volume = 0.35 + (WINDED - stamina) / WINDED * 0.4, speed = 1.15 })
	end

	showBar(stamina < 99.5)
	fill.Size = UDim2.fromScale(stamina / 100, 1)
	fill.BackgroundColor3 = if exhausted then Theme.Colors.Danger else Theme.Colors.Text
end

local function onAction(_, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.Keyboard then
		holding = state == Enum.UserInputState.Begin
	elseif state == Enum.UserInputState.Begin then
		toggled = not toggled
	end
	return Enum.ContextActionResult.Pass
end

function MovementController.isSprinting(): boolean
	return (holding or toggled) and not exhausted and stamina > 0
end

function MovementController.Init()
	bar = create("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -54),
		Size = UDim2.fromOffset(160, 3),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Text,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = bar,
	})
	create("ScreenGui", {
		Name = "Movement",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2,
		bar,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

function MovementController.Start()
	ContextActionService:BindAction(
		ACTION,
		onAction,
		UserInputService.TouchEnabled, -- a button on touch screens
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	local button = ContextActionService:GetButton(ACTION)
	if button then
		ContextActionService:SetTitle(ACTION, "🏃")
		ContextActionService:SetPosition(ACTION, UDim2.new(1, -170, 1, -150))
	end
	RunService.Heartbeat:Connect(step)
end

return MovementController
