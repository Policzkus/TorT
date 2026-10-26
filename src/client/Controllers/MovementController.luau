--!strict
-- How you move, in first person (Config/Movement has the numbers, Modules/Motion the maths).
-- A slow walk (a horror pace) that picks up over a moment and settles a moment after you let go (a
-- run carries a little further); turning takes a beat; in the air you can steer, and let go and your
-- momentum carries you; a big drop slows you for a moment.
-- Jumping: a little lower and quicker than Roblox's, costing a little stamina, and not again
-- straight after landing. A press a moment too soon still jumps once it can, and so does one just
-- after you walk off an edge.
-- Sprint: hold Shift (or click the left stick / the 🏃 button on a touch screen, on until you stop)
-- while your stamina lasts. It only counts going forward: less the further you turn from where you
-- look, none sideways or backwards. Run dry and you breathe hard and have to catch your breath before
-- sprinting again. A thin bar under the middle of the view shows stamina while it isn't full.
-- Crouch: C toggles it (B on a gamepad, the 🧎 button on a touch screen), Ctrl crouches while held.
-- You creep at half speed with soft steps; everyone sees you crouch, the Knifer only hears you right
-- by him and sees less of you over cover (the server checks you really are creeping). Jump stands
-- you up, and so does sprinting (and you run).
-- The gait (MovementController.gait) is what the camera's bob, the bucket in view and your own
-- footsteps keep time with: a foot lands each time its phase passes a multiple of π (`footfall`).
-- The walking speed itself comes from the server (Sneakers upgrade): Humanoid attribute BaseSpeed.
-- The easing: the PlayerModule's ControlModule hands each frame's input to its moveFunction, which we
-- wrap to ask the Humanoid for the eased walk instead (direction, and WalkSpeed for how fast). If
-- that hook isn't there you still walk, sprint and crouch, just without the easing.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Movement = require(ReplicatedStorage:WaitForChild("Shared").Config.Movement)
local Motion = require(ReplicatedStorage:WaitForChild("Shared").Modules.Motion)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Modules.Signal)
local Sound = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local MovementController = {}

local SPRINT_ACTION = "Sprint"
local CROUCH_ACTION = "Crouch"
local CROUCH_SPRING = { down = 15, up = 12, damping = 0.78 } -- radians/s: a touch of overshoot as you settle
local BREATH = { calm = 1.7, winded = 5.6 } -- radians a second round the breathing cycle
local STEP_LOUDNESS = { creep = 0.35, walk = 0.9, run = 1.25 } -- your footsteps (FootstepController)
local FIRST_STEP = 0.6 -- of a stride already done when you set off, so the first step comes quickly
local LAST_STEP = 0.35 -- stopping more than this far into a stride, your feet come together (a soft step)
local STAND_JUMP = 0.3 -- seconds after standing up from a crouch before you can jump (one press, not both)
local RESEND = 1 -- seconds before telling the server again that you're crouching, if it didn't take

export type Gait = {
	phase: number, -- radians, π a step: a foot lands each time it passes a multiple of π
	moving: number, -- 0..1: walking along the ground (how much bob)
	speed: number, -- studs/s along the ground
	walk: number, -- your walking speed
	sprint: number, -- 0..1: running
	crouch: number, -- 0..1, a spring (it overshoots a touch either way)
	drop: number, -- studs your eyes go down fully crouched
	lateral: number, -- strafing right (+) or left, in walking speeds
	breath: number, -- radians round the breathing cycle (in at 0, out from π/2)
	winded: number, -- 0..1: out of breath
	airborne: boolean,
}

local gait: Gait = {
	phase = 0,
	moving = 0,
	speed = 0,
	walk = 16,
	sprint = 0,
	crouch = 0,
	drop = 0,
	lateral = 0,
	breath = 0,
	winded = 0,
	airborne = false,
}

-- A foot landed: (loudness: number). FootstepController plays it.
MovementController.footfall = Signal.new()
-- You landed from a fall: (impact: 0..1).
MovementController.landed = Signal.new()
-- You jumped.
MovementController.jumped = Signal.new()

local player = Players.LocalPlayer
local sprintHeld = false -- Shift
local sprintToggled = false -- the stick click or the touch button: on until you stop moving
local crouchHeld = false -- Ctrl
local crouchToggled = false -- C, B, the touch button
local crouched = false -- crouching now (wanted, and allowed)
local stamina = 100
local exhausted = false
local restAt = 0 -- when stamina starts coming back
local share = 0 -- how much of a sprint you're pressing for (0..1)
local wantX, wantZ = 0, 0 -- what you're pressing, in the world, along the ground (length 0..1)
local walkX, walkZ = 0, 0 -- the walk we ask the Humanoid for (studs/s)
local hooked = false -- the ControlModule hands its input to onMove
local lastMove = 0
local airTime = 0
local jumpedAt = -math.huge
local jumpAskedAt = -math.huge -- the last jump press not yet answered
local groundedAt = 0 -- the last time your feet were on something
local fall = 0 -- fastest fall since you left the ground
local slowFrom, slowUntil = 1, 0 -- after a hard landing: your speed's share, recovering until then
local stepped = 0 -- footfalls so far (phase / π, rounded down, at the last one)
local wasMoving = false
local wasRunning = false
local crouchSpeed = 0 -- the crouch spring's velocity
local jumpFrom = 0 -- you can jump again from then (after standing up)
local jumpEnabled = true
local sentCrouch = false
local sentAt = 0
local crouchRemote: RemoteEvent? = nil
local bar: Frame
local fill: Frame
local barShown = false
local shownStamina = 100
local pulsing = false

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoid, root
end

-- The Humanoid's BaseSpeed (the server's: Sneakers): Config/Movement's speeds are shares of it.
local function baseSpeed(humanoid: Humanoid): number
	return (humanoid:GetAttribute("BaseSpeed") :: number?) or 16
end

-- Which way your view faces along the ground (x, z).
local function facing(): (number, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return 0, -1
	end
	local _, yaw = camera.CFrame:ToEulerAnglesYXZ()
	return -math.sin(yaw), -math.cos(yaw)
end

-- How much of a sprint going (x, z) gets you (0..1): pressing for one, able to, and going forward.
local function sprintShare(x: number, z: number): number
	local length = math.sqrt(x * x + z * z)
	if not (sprintHeld or sprintToggled) or exhausted or stamina <= 0 or crouched or length < 0.05 then
		return 0
	end
	local fx, fz = facing()
	return Motion.sprintShare((x * fx + z * fz) / length)
end

-- Your speed now, as a share of your BaseSpeed: a creep or a walk, a run (`runShare` of one), slowed
-- after landing.
local function pace(runShare: number): number
	local speed = if crouched then Movement.CROUCH else Movement.WALK + (Movement.SPRINT - Movement.WALK) * runShare
	local now = os.clock()
	if now < slowUntil then
		speed *= slowFrom + (1 - slowFrom) * (1 - (slowUntil - now) / Movement.LANDING.time)
	end
	return speed
end

-- Every frame, the ControlModule's input (camera-relative, or the world's for a scripted MoveTo):
-- ease our walk toward it and ask the Humanoid for that.
local function onMove(original: (Player, Vector3, boolean) -> (), who: Player, direction: Vector3, relative: boolean)
	local now = os.clock()
	local dt = math.clamp(now - lastMove, 0, 0.1)
	lastMove = now
	local humanoid, root = humanoidAndRoot()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if
		humanoid == nil
		or root == nil
		or camera == nil
		or character == nil
		or humanoid.Health <= 0
		or humanoid.Sit
		or character:GetAttribute("Ragdoll") == true
	then
		walkX, walkZ, wantX, wantZ, share = 0, 0, 0, 0, 0
		original(who, direction, relative)
		return
	end
	local world = direction
	if relative then
		local _, yaw = camera.CFrame:ToEulerAnglesYXZ()
		world = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(direction)
	end
	world = Vector3.new(world.X, 0, world.Z)
	if world.Magnitude > 1 then
		world = world.Unit
	end
	wantX, wantZ = world.X, world.Z
	share = sprintShare(wantX, wantZ)
	local base = baseSpeed(humanoid)
	local walk = base * Movement.WALK
	local top = base * pace(share)
	-- Off the ground a moment (not a kerb or a step), or a jump from the moment you leave it.
	local sinceJump = now - jumpedAt
	local inAir = airTime > Movement.AIR_GRACE or sinceJump < 0.15 or (airTime > 0 and sinceJump < 1)
	walkX, walkZ = Motion.accelerate(walkX, walkZ, wantX * top, wantZ * top, walk, inAir, dt)
	local speed = math.sqrt(walkX * walkX + walkZ * walkZ)
	if speed < 0.05 then
		-- Standing: hand on what came in (nothing, or a scripted MoveTo, which walks at your walking speed).
		walkX, walkZ = 0, 0
		humanoid.WalkSpeed = walk
		original(who, direction, relative)
		return
	end
	humanoid.WalkSpeed = speed
	original(who, Vector3.new(walkX / speed, 0, walkZ / speed), false)
end

local function hook()
	local scripts = player:WaitForChild("PlayerScripts")
	local module = scripts:WaitForChild("PlayerModule", 15)
	local ok, controls = pcall(function()
		return (require :: any)(module):GetControls()
	end)
	if not ok or type(controls) ~= "table" or type(controls.moveFunction) ~= "function" then
		warn("[Movement] couldn't reach the PlayerModule's controls: walking won't ease in and out")
		return
	end
	local original = controls.moveFunction
	local warned = false
	controls.moveFunction = function(who: Player, direction: Vector3, relative: boolean)
		-- Never let a mistake here stop you walking: hand the input straight on instead.
		local fine, problem = pcall(onMove, original, who, direction, relative)
		if not fine then
			original(who, direction, relative)
			if not warned then
				warned = true
				warn(`[Movement] {problem}`)
			end
		end
	end
	hooked = true
end

-- Crouching or not (wanted, and allowed). No jumping while down, nor for a moment after standing up
-- (the press that stood you up isn't also a jump).
local function setCrouched(humanoid: Humanoid, on: boolean)
	if on ~= crouched then
		crouched = on
		Sound.play("Cloth", { volume = if on then 0.7 else 0.5, speed = if on then 0.9 else 1.05 })
		if on then
			sprintToggled = false
		else
			jumpFrom = os.clock() + STAND_JUMP
		end
	end
	local canJump = not crouched and os.clock() >= jumpFrom
	if canJump ~= jumpEnabled then
		jumpEnabled = canJump
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, canJump)
	end
end

-- The server keeps "Crouching" on your character (everyone sees it, the Knifer hears less): tell it
-- when that changes, and again if it didn't take.
local function tellServer(character: Model)
	local remote = crouchRemote
	if remote == nil then
		return
	end
	local now = os.clock()
	local says = character:GetAttribute("Crouching") == true
	if crouched ~= sentCrouch or (says ~= crouched and now - sentAt > RESEND) then
		sentCrouch, sentAt = crouched, now
		remote:FireServer(crouched)
	end
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

local function drawStamina(dt: number)
	shownStamina = Motion.ease(shownStamina, stamina, 14, dt)
	showBar(stamina < 99.5)
	fill.Size = UDim2.fromScale(shownStamina / 100, 1)
	fill.BackgroundColor3 = if exhausted then Theme.Colors.Danger else Theme.Colors.Text
	if barShown and exhausted then
		-- Pulsing while you get your breath back.
		pulsing = true
		fill.BackgroundTransparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 7))
	elseif pulsing then
		pulsing = false
		fill.BackgroundTransparency = if barShown then 0.1 else 1
	end
end

-- Stamina: drains running flat out, comes back a moment after you stop.
local function breathe(dt: number, running: number)
	local now = os.clock()
	local rules = Movement.STAMINA
	if running > 0 then
		stamina = math.max(0, stamina - rules.drain * running * dt)
		restAt = now + rules.delay
		if stamina == 0 and not exhausted then
			exhausted = true
			sprintToggled = false
			Sound.play("Breath", { volume = 0.9, speed = 1.3 }) -- the gasp as you run dry
		end
	elseif now >= restAt then
		stamina = math.min(100, stamina + rules.regen * dt)
		if exhausted and stamina >= rules.recover then
			exhausted = false
		end
	end
	-- Out of breath: the breathing quickens and you hear each breath out (the camera rises and falls with it).
	local target = if exhausted then 1 else math.clamp((rules.winded - stamina) / rules.winded, 0, 1)
	gait.winded = Motion.ease(gait.winded, target, if target > gait.winded then 3 else 0.5, dt)
	local before = gait.breath
	gait.breath += dt * (BREATH.calm + (BREATH.winded - BREATH.calm) * gait.winded)
	local out = math.pi / 2
	if
		gait.winded > 0.3
		and math.floor((gait.breath - out) / (2 * math.pi)) > math.floor((before - out) / (2 * math.pi))
	then
		Sound.play("Breath", { volume = 0.35 + 0.45 * gait.winded, speed = 1.15 })
	end
end

-- The gait: footfalls by the ground you cover (longer strides the faster you go), and how much you're
-- walking, running and strafing. `walk`: your walking speed.
local function walkOn(dt: number, root: BasePart, walk: number)
	local run = walk / Movement.WALK * Movement.SPRINT
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	local onGround = not gait.airborne
	gait.speed = speed
	gait.walk = walk
	local moving = if onGround then math.clamp((speed - 0.5) / (walk * 0.3), 0, 1) else 0
	gait.moving = Motion.ease(gait.moving, moving, if moving > gait.moving then 10 else 7, dt)
	local running = if onGround then math.clamp((speed - walk * 1.05) / ((run - walk) * 0.8), 0, 1) else gait.sprint
	gait.sprint = Motion.ease(gait.sprint, running, 6, dt)
	local loudness = if crouched
		then STEP_LOUDNESS.creep
		else STEP_LOUDNESS.walk + (STEP_LOUDNESS.run - STEP_LOUDNESS.walk) * gait.sprint

	if onGround and speed > 0.8 then
		if not wasMoving then
			wasMoving = true
			if gait.moving < 0.15 then
				gait.phase = (stepped + FIRST_STEP) * math.pi
			end
		end
		gait.phase += speed * dt / Motion.stride(speed, gait.crouch) * math.pi
		local step = math.floor(gait.phase / math.pi)
		if step > stepped then
			stepped = step
			MovementController.footfall:Fire(loudness)
		end
	elseif wasMoving then
		wasMoving = false
		-- Stopping: your feet come together, a softer last step if you were well into a stride.
		if onGround and gait.phase / math.pi - stepped > LAST_STEP then
			stepped += 1
			gait.phase = stepped * math.pi
			MovementController.footfall:Fire(loudness * 0.6)
		end
	end
	-- Breaking into a run: clothes rustle.
	local isRunning = gait.sprint > 0.5
	if isRunning and not wasRunning then
		Sound.play("Cloth", { volume = 0.45, speed = 1.15 })
	end
	wasRunning = isRunning

	local camera = Workspace.CurrentCamera
	if camera then
		local right = camera.CFrame.RightVector
		local side = Vector3.new(right.X, 0, right.Z)
		local lateral = if side.Magnitude > 0.1 then flat:Dot(side.Unit) / walk else 0
		gait.lateral = Motion.ease(gait.lateral, math.clamp(lateral, -1.5, 1.5), 8, dt)
	end
end

-- Your eyes going down or up as you crouch or stand, on a spring.
local function crouchDown(dt: number, humanoid: Humanoid, root: BasePart)
	gait.drop = Motion.crouchDrop(humanoid.HipHeight, root.Size.Y)
	local target = if crouched then 1 else 0
	gait.crouch, crouchSpeed = Motion.spring(
		gait.crouch,
		crouchSpeed,
		target,
		if target > gait.crouch then CROUCH_SPRING.down else CROUCH_SPRING.up,
		CROUCH_SPRING.damping,
		dt
	)
end

-- Off the ground and back: how far you fell, and the landing (the camera dips, a hard one slows you).
-- A body thrown about (`limp`: ragdolled, fainted) or sat down doesn't land on its feet.
local function airborne(dt: number, humanoid: Humanoid, root: BasePart, limp: boolean)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		if gait.airborne and fall > Movement.LANDING.felt and not limp then
			MovementController.landed:Fire(Motion.landingImpact(fall))
			local slow = Motion.landingSlow(fall)
			if slow < 1 then
				slowFrom, slowUntil = slow, os.clock() + Movement.LANDING.time
			end
		end
		if gait.airborne then
			jumpFrom = math.max(jumpFrom, os.clock() + Movement.JUMP.rest) -- find your feet first
		end
		airTime, fall = 0, 0
		groundedAt = os.clock()
	else
		airTime += dt
		fall = math.max(fall, -root.AssemblyLinearVelocity.Y)
	end
	gait.airborne = airTime > Movement.AIR_GRACE
end

-- A jump pressed too soon (coming down, or finding your feet) happens as soon as it can, and one
-- pressed just after walking off an edge still counts: Roblox's own jump only answers a press held
-- down while you're standing.
local function jumpIfAsked(humanoid: Humanoid, down: boolean)
	local now = os.clock()
	if now - jumpAskedAt > Movement.JUMP.buffer or not jumpEnabled or down or humanoid.Sit then
		return
	end
	local state = humanoid:GetState()
	if
		state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming
	then
		return
	end
	local onGround = humanoid.FloorMaterial ~= Enum.Material.Air
	local walkedOff = not onGround and now - groundedAt < Movement.JUMP.coyote and now - jumpedAt > 0.3
	if onGround or walkedOff then
		jumpAskedAt = -math.huge
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function step(dt: number)
	local humanoid, root = humanoidAndRoot()
	local character = player.Character
	if humanoid == nil or root == nil or character == nil or humanoid.Health <= 0 then
		gait.moving, gait.speed, gait.sprint = 0, 0, 0
		return
	end
	local down = character:GetAttribute("Ragdoll") == true or character:GetAttribute("Fainted") == true
	if down or humanoid.Sit then
		crouchToggled = false
	end
	setCrouched(humanoid, (crouchHeld or crouchToggled) and not down and not humanoid.Sit)
	tellServer(character)

	local base = baseSpeed(humanoid)
	local walk = base * Movement.WALK
	if not hooked then
		-- No eased walk: steer the speed instead.
		local direction = humanoid.MoveDirection
		wantX, wantZ = direction.X, direction.Z
		share = sprintShare(wantX, wantZ)
		humanoid.WalkSpeed = Motion.ease(humanoid.WalkSpeed, base * pace(share), 8, dt)
	end
	if wantX * wantX + wantZ * wantZ < 0.01 then
		sprintToggled = false
	end
	airborne(dt, humanoid, root, down or humanoid.Sit)
	jumpIfAsked(humanoid, down)
	crouchDown(dt, humanoid, root)
	if down or humanoid.Sit then
		-- Thrown about, fainted or sat down: no walking (and no footsteps from a body tumbling along).
		gait.moving, gait.sprint, gait.lateral = 0, 0, 0
		wasMoving = false
	else
		walkOn(dt, root, walk)
	end
	-- Only running flat out on the ground costs stamina (not pressing Shift into a wall).
	local running = if not gait.airborne and gait.speed > walk * 1.05 then share else 0
	breathe(dt, running)
	drawStamina(dt)
end

local function onSprint(_, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.Keyboard then
		sprintHeld = state == Enum.UserInputState.Begin
		if sprintHeld then
			crouchToggled = false -- sprinting stands you up
		end
	elseif state == Enum.UserInputState.Begin then
		sprintToggled = not sprintToggled
		if sprintToggled then
			crouchToggled = false
		end
	end
	return Enum.ContextActionResult.Pass
end

local function onCrouch(_, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		crouchHeld = state == Enum.UserInputState.Begin
	elseif state == Enum.UserInputState.Begin then
		crouchToggled = not crouchToggled
	end
	if crouchHeld or crouchToggled then
		sprintToggled = false
	end
	return Enum.ContextActionResult.Pass
end

-- The touch button shows whether you're crouched.
local function paintCrouchButton()
	local button = ContextActionService:GetButton(CROUCH_ACTION)
	if button then
		button.ImageColor3 = if crouched then Theme.Colors.Success else Color3.new(1, 1, 1)
	end
end

local function onCharacter(character: Model)
	crouchToggled, crouched, sprintToggled = false, false, false
	stamina, exhausted, shownStamina = 100, false, 100
	walkX, walkZ, airTime, fall, slowUntil = 0, 0, 0, 0, 0
	gait.crouch, crouchSpeed, gait.winded, gait.moving, gait.sprint = 0, 0, 0, 0, 0
	jumpEnabled, jumpFrom, jumpAskedAt = true, 0, -math.huge -- a new Humanoid can jump
	sentCrouch = false
	sentAt = 0
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = Movement.JUMP.height
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and player.Character == character then
				jumpedAt = os.clock()
				jumpAskedAt = -math.huge
				-- A jump's an effort: it costs stamina, and stamina waits to come back as after a run.
				stamina = math.max(0, stamina - Movement.JUMP.cost)
				restAt = os.clock() + Movement.STAMINA.delay
				MovementController.jumped:Fire()
			end
		end)
	end
end

-- The eased-in-and-out walk, for the camera (CameraController), the bucket in view and footsteps.
function MovementController.gait(): Gait
	return gait
end

function MovementController.isSprinting(): boolean
	return share > 0 and gait.sprint > 0.1
end

function MovementController.isCrouching(): boolean
	return crouched
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
		Parent = player:WaitForChild("PlayerGui"),
	})
end

function MovementController.Start()
	ContextActionService:BindAction(
		SPRINT_ACTION,
		onSprint,
		UserInputService.TouchEnabled, -- a button on touch screens
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:BindAction(
		CROUCH_ACTION,
		onCrouch,
		UserInputService.TouchEnabled,
		Enum.KeyCode.C,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl,
		Enum.KeyCode.ButtonB
	)
	if ContextActionService:GetButton(SPRINT_ACTION) then
		ContextActionService:SetTitle(SPRINT_ACTION, "🏃")
		ContextActionService:SetPosition(SPRINT_ACTION, UDim2.new(1, -170, 1, -150))
	end
	if ContextActionService:GetButton(CROUCH_ACTION) then
		ContextActionService:SetTitle(CROUCH_ACTION, "🧎")
		ContextActionService:SetPosition(CROUCH_ACTION, UDim2.new(1, -245, 1, -150))
	end
	-- Jump while crouched: you stand up instead. Otherwise remember the press (jumpIfAsked).
	UserInputService.JumpRequest:Connect(function()
		if crouchToggled then
			crouchToggled = false
		elseif not crouched then
			jumpAskedAt = os.clock()
		end
	end)
	-- Let go of everything if the window loses focus mid-press (the key-up never comes).
	UserInputService.WindowFocusReleased:Connect(function()
		sprintHeld, crouchHeld = false, false
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	local wasCrouched = false
	RunService:BindToRenderStep("Movement", Enum.RenderPriority.Input.Value + 1, function(dt)
		step(dt)
		if crouched ~= wasCrouched then
			wasCrouched = crouched
			paintCrouchButton()
		end
	end)
	task.spawn(hook)
	crouchRemote = Net.event("Crouch")
end

return MovementController
