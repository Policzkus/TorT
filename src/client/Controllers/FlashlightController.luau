--!strict
-- Flashlights (Config/Items.FLASHLIGHT; ItemService keeps FlashlightOn and Battery on each player;
-- F / R3 switch yours, through the items bar: ItemsController).
-- Yours is held low on the left of your view: a dark torch, its lens glowing with what it gives. It's
-- raised when you switch it on and lowered when you switch it off, swings with your steps and
-- trails your turns a little, like a torch in a hand, and its beam comes from the lens along where it
-- points (a spotlight with shadows), with a faint spill round it. Knocked down, it shines from your
-- head instead. Everyone else's shines from beside their head along where they look (their head
-- turns with where they look for everyone: CharacterAnimController), its lens glowing so you see who
-- has one.
-- All of them dim, go yellow and stutter alike as their batteries run down (Modules/Flashlight: the
-- server's time and whose it is). Switched on, the bulb catches with a flicker; dead, it sputters
-- out and the filament glows orange a moment.
-- What's left in each runs down here between the server's word on it (every half second).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Flashlight = require(Shared.Modules.Flashlight)
local Motion = require(Shared.Modules.Motion)
local MovementController = require(script.Parent.MovementController)
local Sound = require(script.Parent.SoundController)

local FlashlightController = {}

local RULES = Items.FLASHLIGHT
local WHITE = Color3.fromRGB(255, 242, 222) -- a warm white
local AMBER = Color3.fromRGB(255, 168, 86) -- on its last
local GLOW = Color3.fromRGB(255, 120, 40) -- the filament, after it dies
-- Yours, in your view: where it's held (from the camera), how far ahead along where you look it's
-- pointed (aimed at what you're looking at, so the beam meets the middle of your view there), how far
-- down it goes when lowered, how fast it's raised and lowered, how fast it catches up with your
-- turns (a second), and its swing with your steps.
local HELD = Vector3.new(-0.95, -0.9, -1.75)
local AIM_AT = 28 -- studs
local LOWERED = 1.3 -- studs
local RAISE = 7 -- a second
local LAG = 20
local SWAY = { side = 0.035, dip = 0.03, roll = math.rad(2.5) }
local CATCH = { 0.06, 0.1, 0.16, 0.22 } -- seconds: the bulb catching (dark, lit, dark, lit)
local AFTERGLOW = 0.6 -- seconds the filament glows once it's died
-- Theirs: from beside their head.
local HEAD = CFrame.new(0.35, -0.15, -0.6)

type Light = {
	player: Player,
	holder: Part, -- what the beam shines from (its front)
	beam: SpotLight,
	spill: PointLight,
	lens: Part?, -- theirs: a glow you see on them
	on: boolean,
	seconds: number, -- battery left at `heardAt` (the server's last word)
	heardAt: number,
	switchedAt: number, -- os.clock(): when it went on (the bulb catching), or off
	diedAt: number?, -- went off dead (the afterglow)
}

local lights: { [Player]: Light } = {}
local torch: Model -- yours, in your view
local torchLens: BasePart
local raised = 0 -- 0 lowered, 1 up
local aim: CFrame? = nil -- where yours points, trailing the camera

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local made = Instance.new("Part")
	made.Name = name
	made.Size = size
	made.Color = color
	made.Material = material
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Parent = parent
	return made
end

local function newLight(player: Player): Light
	local camera = Workspace.CurrentCamera
	local holder = part("Flashlight", Vector3.one * 0.2, WHITE, Enum.Material.SmoothPlastic, camera)
	holder.Transparency = 1
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Angle = RULES.angle
	beam.Shadows = player == Players.LocalPlayer -- (everyone's with shadows would cost too much)
	beam.Enabled = false
	beam.Parent = holder
	local spill = Instance.new("PointLight")
	spill.Range = RULES.spill.range
	spill.Shadows = false
	spill.Enabled = false
	spill.Parent = holder
	local lens = nil
	if player ~= Players.LocalPlayer then
		lens = part("Lens", Vector3.new(0.24, 0.24, 0.08), WHITE, Enum.Material.Neon, camera)
		lens.Transparency = 1
	end
	return {
		player = player,
		holder = holder,
		beam = beam,
		spill = spill,
		lens = lens,
		on = false,
		seconds = RULES.battery,
		heardAt = os.clock(),
		switchedAt = -math.huge,
		diedAt = nil,
	}
end

local function dropLight(player: Player)
	local light = lights[player]
	lights[player] = nil
	if light then
		light.holder:Destroy()
		if light.lens then
			light.lens:Destroy()
		end
	end
end

-- What the server last said, for `player`.
local function hear(player: Player)
	local light = lights[player]
	if light == nil then
		light = newLight(player)
		lights[player] = light
	end
	local on = player:GetAttribute("FlashlightOn") == true
	local battery = player:GetAttribute("Battery")
	if type(battery) == "number" then
		light.seconds, light.heardAt = battery, os.clock()
	end
	if on ~= light.on then
		light.on = on
		light.switchedAt = os.clock()
		light.diedAt = if not on and light.seconds <= 0.6 then os.clock() else nil
		-- The click (theirs, from them).
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if player == Players.LocalPlayer then
			Sound.play("Click", { speed = if on then 0.75 else 0.6, volume = 1.2 })
		elseif head then
			Sound.play("Click", { at = head, speed = 0.7, volume = 0.8 })
		end
	end
end

-- What's in `light`'s battery now (0..1), run down since the server last said.
local function chargeOf(light: Light): number
	local seconds = light.seconds
	if light.on then
		seconds -= os.clock() - light.heardAt
	end
	return Flashlight.charge(seconds)
end

-- How bright it is now (0..1 of full) and how yellow, with the bulb catching as it's switched on.
local function outputOf(light: Light): (number, number)
	if not light.on then
		return 0, 1
	end
	local level, yellow = Flashlight.output(chargeOf(light), Workspace:GetServerTimeNow(), light.player.UserId)
	local since = os.clock() - light.switchedAt
	if since < CATCH[#CATCH] then
		local dark = since < CATCH[1] or (since >= CATCH[2] and since < CATCH[3])
		level *= if dark then 0.05 else 0.7
	end
	return level, yellow
end

-- Lights it to `level` (0..1), `yellow` (0..1).
local function shine(light: Light, level: number, yellow: number)
	local color = WHITE:Lerp(AMBER, yellow)
	local lit = level > 0.01
	light.beam.Enabled = lit
	light.spill.Enabled = lit
	light.beam.Brightness = RULES.brightness * level
	light.beam.Range = RULES.range * (0.55 + 0.45 * level)
	light.beam.Color = color
	light.spill.Brightness = RULES.spill.brightness * level
	light.spill.Color = color
end

-- How the lens looks: lit with the beam, or the filament's afterglow once it's died.
local function lensLook(light: Light, level: number, yellow: number): (Color3, number)
	if level > 0.01 then
		return WHITE:Lerp(AMBER, yellow), math.clamp(0.75 - level, 0, 0.6)
	end
	local died = light.diedAt
	if died then
		local fade = (os.clock() - died) / AFTERGLOW
		if fade < 1 then
			return GLOW, 0.2 + 0.8 * fade
		end
	end
	return Color3.fromRGB(40, 40, 44), 1
end

-- Yours, in your view: raised or lowered, swinging and trailing; the beam from its lens.
local function drawMine(dt: number, light: Light?)
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	if camera == nil then
		return
	end
	local down = character ~= nil
		and (character:GetAttribute("Ragdoll") == true or character:GetAttribute("Fainted") == true)
	local up = light ~= nil and (light.on or (light.diedAt ~= nil and os.clock() - light.diedAt < AFTERGLOW))
	raised = Motion.ease(raised, if up and not down then 1 else 0, RAISE, dt)
	local look = camera.CFrame.Rotation
	aim = if aim then (aim :: CFrame):Lerp(look, 1 - math.exp(-dt * LAG)) else look
	local gait = MovementController.gait()
	local side = math.sin(gait.phase)
	local swing = CFrame.new(
		side * SWAY.side * gait.moving,
		-Motion.footfall(gait.phase) * SWAY.dip * gait.moving - (1 - raised) * LOWERED,
		0
	) * CFrame.Angles(0, 0, side * SWAY.roll * gait.moving)
	local hand = camera.CFrame.Position + (aim :: CFrame):VectorToWorldSpace(HELD)
	local target = camera.CFrame.Position + (aim :: CFrame).LookVector * AIM_AT
	torch:PivotTo(CFrame.lookAt(hand, target, (aim :: CFrame).UpVector) * swing)
	local hidden = raised < 0.02
	for _, piece in torch:GetChildren() do
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
	if light == nil then
		return
	end
	local level, yellow = outputOf(light)
	local color, transparency = lensLook(light, level, yellow)
	torchLens.Color = color
	torchLens.Transparency = transparency
	-- Knocked down, it's in your hand on the ground: from your head, like everyone else's.
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if down and head then
		light.holder.CFrame = head.CFrame * HEAD
	else
		light.holder.CFrame = torchLens.CFrame
	end
	shine(light, level, yellow)
end

local function drawTheirs(light: Light)
	local character = light.player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local level, yellow = outputOf(light)
	if head == nil then
		shine(light, 0, 1)
		if light.lens then
			light.lens.Transparency = 1
		end
		return
	end
	light.holder.CFrame = head.CFrame * HEAD
	shine(light, level, yellow)
	local lens = light.lens
	if lens then
		lens.CFrame = light.holder.CFrame
		local color, transparency = lensLook(light, level, yellow)
		lens.Color = color
		lens.Transparency = transparency
	end
end

local function step(dt: number)
	local mine = lights[Players.LocalPlayer]
	drawMine(dt, mine)
	for player, light in lights do
		if player ~= Players.LocalPlayer then
			drawTheirs(light)
		end
	end
end

-- 0..1 left in your flashlight now (nil: it's off: then StateController's battery says), for the
-- items bar.
function FlashlightController.myCharge(): number?
	local light = lights[Players.LocalPlayer]
	return if light and light.on then chargeOf(light) else nil
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
		hear(player)
	end)
	player:GetAttributeChangedSignal("Battery"):Connect(function()
		hear(player)
	end)
	if player:GetAttribute("FlashlightOn") ~= nil then
		hear(player)
	end
end

function FlashlightController.Init()
	-- Yours: a dark body, a wider head, the lens at its front (-Z), held pointing where you look.
	torch = Instance.new("Model")
	torch.Name = "ViewmodelFlashlight"
	local camera = Workspace.CurrentCamera
	local body = part("Body", Vector3.new(0.26, 0.26, 1.05), Color3.fromRGB(34, 34, 38), Enum.Material.Metal, torch)
	local head = part("Head", Vector3.new(0.36, 0.36, 0.26), Color3.fromRGB(48, 48, 54), Enum.Material.Metal, torch)
	head.CFrame = CFrame.new(0, 0, -0.62)
	local rim =
		part("Switch", Vector3.new(0.08, 0.05, 0.16), Color3.fromRGB(150, 32, 28), Enum.Material.SmoothPlastic, torch)
	rim.CFrame = CFrame.new(0, 0.14, -0.1)
	torchLens = part("Lens", Vector3.new(0.3, 0.3, 0.03), Color3.fromRGB(40, 40, 44), Enum.Material.Neon, torch)
	torchLens.CFrame = CFrame.new(0, 0, -0.76)
	torch.PrimaryPart = body
	body.CFrame = CFrame.new()
	torch.WorldPivot = CFrame.new()
	torch.Parent = camera
end

function FlashlightController.Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(dropLight)
	-- After the camera and the bucket in view have moved (it's drawn from where they end up).
	RunService:BindToRenderStep("Flashlights", Enum.RenderPriority.Camera.Value + 3, step)
end

return FlashlightController
