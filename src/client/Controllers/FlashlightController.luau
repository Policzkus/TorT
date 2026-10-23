--!strict
-- Your flashlight (PROMPT §V2: the streets are dark; light is what you carry). A spotlight from your
-- chest that lags a little behind where you look, like a torch in a nervous hand, plus a faint
-- glow around you. On by default; F toggles it (unless F is busy with a prompt you're looking at,
-- like a bowl's TAKE ALL). Now and then it flickers. Upgrades (data.upgrades.flashlight) will widen
-- and lengthen the beam.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)

local FlashlightController = {}

local BASE = { range = 46, angle = 44, brightness = 2.6 }
local PER_LEVEL = { range = 6, angle = 3 }
local COLOR = Color3.fromRGB(255, 232, 200)
local LAG = 10 -- how fast the beam catches up with the camera (higher = tighter)
local OFFSET = CFrame.new(0.55, -0.7, -0.4) -- held low and to the right

local holder: Part
local beam: SpotLight
local glow: PointLight
local on = true
local aim: CFrame? = nil
local flickerUntil = 0
local nextFlicker = 0
local shownF = 0 -- prompts on screen that use F

local function strength(): (number, number)
	local upgrades = StateController.get("upgrades")
	local level = if type(upgrades) == "table" then upgrades.flashlight or 0 else 0
	return BASE.range + level * PER_LEVEL.range, BASE.angle + level * PER_LEVEL.angle
end

local function toggle(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if shownF > 0 then
		return Enum.ContextActionResult.Pass -- F belongs to the prompt right now
	end
	on = not on
	Sound.play("Click", { speed = 0.7 })
	return Enum.ContextActionResult.Sink
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local target = camera.CFrame * OFFSET
	aim = if aim then aim:Lerp(target, math.min(1, dt * LAG)) else target
	holder.CFrame = aim :: CFrame
	local range, angle = strength()
	beam.Range = range
	beam.Angle = angle
	-- Every so often the bulb stutters.
	local now = os.clock()
	if now >= nextFlicker then
		nextFlicker = now + math.random(18, 45)
		flickerUntil = now + math.random(4, 12) / 10
	end
	local flicker = if now < flickerUntil then (if math.random() < 0.45 then 0.15 else 1) else 1
	beam.Enabled = on
	glow.Enabled = on
	beam.Brightness = BASE.brightness * flicker
	glow.Brightness = 0.35 * flicker
end

function FlashlightController.Start()
	holder = Instance.new("Part")
	holder.Name = "Flashlight"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Color = COLOR
	beam.Shadows = true
	beam.Parent = holder
	glow = Instance.new("PointLight")
	glow.Color = COLOR
	glow.Range = 9
	glow.Shadows = false
	glow.Parent = holder
	holder.Parent = Workspace.CurrentCamera

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.KeyboardKeyCode == Enum.KeyCode.F then
			shownF += 1
			prompt.PromptHidden:Once(function()
				shownF = math.max(0, shownF - 1)
			end)
		end
	end)
	ContextActionService:BindAction("Flashlight", toggle, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR3)
	RunService:BindToRenderStep("Flashlight", Enum.RenderPriority.Camera.Value + 3, step)
end

return FlashlightController
