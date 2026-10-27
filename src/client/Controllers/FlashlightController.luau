--!strict
-- Flashlights (Config/Items.FLASHLIGHT; ItemService keeps FlashlightOn and Battery on each player;
-- F / R3 switch yours, through the items bar: ItemsController). The user: "it needs to be better
-- more realistic".
-- A real torch's light: a bright hotspot inside a dim, wide corona (two spotlights from the lens;
-- yours throws shadows), light coming back off whatever it's pointed at and lighting round it
-- (bounce: a wall close up throws a lot back over a small patch, something far off a faint glow;
-- tinted by what it hits), and the beam itself seen in the fog, fading out along it (shaft).
-- Yours is a torch in your left hand, low in your view: a ribbed metal body, a flared head, a bezel,
-- the reflector glowing behind the glass. It's raised when you switch it on and lowered when you
-- switch it off, swings with your steps, rises and falls with your breath, trails your turns (it
-- has weight), and shakes a little in your hand (more walking, more again running). Up against a
-- wall you draw it in, and the light never comes from the other side of one. Knocked down, it's in
-- your hand on the ground.
-- Everyone else holds theirs in their left hand, the arm raised along where they look
-- (CharacterAnimController), the beam from its lens: you see where they're pointing it, and the
-- beam in the fog from far off. Pointed at your eyes it dazzles you: a flare on the lens, and your
-- view washes out for as long as it's in them (less with Settings' reduce flashes).
-- All of them dim, go yellow and stutter alike as their batteries run down (Modules/Flashlight: the
-- server's time and whose it is); a dying one left off a while picks up a little. Switched on, the
-- bulb catches with a flicker; dead, it sputters out and the filament glows orange a moment.
-- What's left in each runs down here between the server's word on it (every half second).

local Lighting = game:GetService("Lighting")
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
local StateController = require(script.Parent.StateController)

local FlashlightController = {}

local RULES = Items.FLASHLIGHT
local WHITE = Color3.fromRGB(255, 240, 216) -- a warm white: a filament bulb
local AMBER = Color3.fromRGB(255, 160, 78) -- on its last
local GLOW = Color3.fromRGB(255, 120, 40) -- the filament, after it dies
local DARK_GLASS = Color3.fromRGB(40, 40, 44)
-- Yours, in your view: where it's held (from the camera), how far ahead along where you look it's
-- pointed (aimed at what you're looking at, so the beam meets the middle of your view there), how far
-- down it goes when lowered, how fast it's raised and lowered, and its swing with your steps.
local HELD = Vector3.new(-0.95, -0.9, -1.75)
local AIM_AT = 28 -- studs
local LOWERED = 1.3 -- studs
local RAISE = 7 -- a second
local SWAY = { side = 0.035, dip = 0.03, roll = math.rad(2.5), breath = 0.012 }
-- Up against a wall (nearer than `near` studs ahead) you draw it in: back toward you, a little up.
local DRAW_IN = { near = 2.6, back = 0.95, up = 0.22, rate = 10 }
local TREMBLE = 1.7 -- (math.noise seldom goes past ±0.6: this brings the shake up to Items.FLASHLIGHT.tremor)
local CATCH = { 0.06, 0.1, 0.16, 0.22 } -- seconds: the bulb catching (dark, lit, dark, lit)
local AFTERGLOW = 0.6 -- seconds the filament glows once it's died
-- Theirs: the torch's size in their hand, and where it's held off the end of their arm.
local THEIRS = { scale = 0.5, grip = 0.25 }
local HEAD = CFrame.new(0.35, -0.15, -0.6) -- (no left arm: from beside their head)
local BOUNCE_EVERY = 0.1 -- seconds between looks at what theirs is pointed at
-- The beam in the fog: three layers, wide and faint to narrow and denser, so it's soft at the edges.
local SHAFT = { { width = 1, alpha = 0.35 }, { width = 0.55, alpha = 0.6 }, { width = 0.25, alpha = 1 } }
local DAZZLE = { rise = 14, fall = 3.5, brightness = 0.32, contrast = -0.18, calm = 0.35 } -- calm: reduce flashes

type Torch = { model: Model, reflector: BasePart, lens: Vector3 } -- lens: from its pivot

type Light = {
	player: Player,
	holder: Part, -- what the beam shines from (its front: -Z)
	hotspot: SpotLight,
	corona: SpotLight,
	bounce: Part, -- where the light comes back off what it's pointed at
	bounceLight: PointLight,
	tip: Attachment, -- the shaft's far end (on the holder)
	shaft: { Beam },
	shaftKey: number, -- its look last set (to skip resetting it every frame)
	torch: Torch?, -- theirs: in their hand
	flare: BillboardGui?, -- theirs: on the lens when it's in your eyes
	flareParts: { Frame },
	on: boolean,
	seconds: number, -- battery left at `heardAt` (the server's last word)
	heardAt: number,
	switchedAt: number, -- os.clock(): when it went on (the bulb catching), or off
	rested: number, -- seconds it was off before it went on (a tired battery picks up)
	diedAt: number?, -- went off dead (the afterglow)
	castAt: number, -- when we last looked at what it's pointed at
	hit: RaycastResult?,
}

local lights: { [Player]: Light } = {}
local torch: Torch -- yours, in your view
local raised = 0 -- 0 lowered, 1 up
local drawn = 0 -- 0..1 drawn in, up against a wall
local aim: CFrame? = nil -- where yours points, trailing the camera
local dazzled = 0
local dazzle: ColorCorrectionEffect

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

-- A torch, `scale` times the size of yours, pointing along -Z from its pivot (the middle of its
-- grip): a ribbed metal body, a tail cap, a flared head with a bright bezel, the reflector behind the
-- glass (it glows with the light), a rubber switch.
local function buildTorch(scale: number, parent: Instance): Torch
	local model = Instance.new("Model")
	model.Name = "Flashlight"
	local metal = Color3.fromRGB(32, 32, 36)
	local function round(
		name: string,
		length: number,
		across: number,
		z: number,
		color: Color3,
		material: Enum.Material
	): Part
		local made = part(name, Vector3.new(length, across, across) * scale, color, material, model)
		made.Shape = Enum.PartType.Cylinder -- (a cylinder runs along X: turned to run along Z)
		made.CFrame = CFrame.new(0, 0, z * scale) * CFrame.Angles(0, math.pi / 2, 0)
		return made
	end
	local body = round("Body", 0.95, 0.24, 0, metal, Enum.Material.Metal)
	for i, z in { 0.12, 0.22, 0.32 } do
		round("Grip" .. i, 0.035, 0.255, z, Color3.fromRGB(46, 46, 50), Enum.Material.Metal)
	end
	round("Tail", 0.08, 0.265, 0.5, Color3.fromRGB(22, 22, 24), Enum.Material.SmoothPlastic)
	round("Neck", 0.12, 0.3, -0.53, metal, Enum.Material.Metal)
	round("Head", 0.22, 0.38, -0.69, Color3.fromRGB(42, 42, 46), Enum.Material.Metal)
	local bezel = round("Bezel", 0.045, 0.41, -0.81, Color3.fromRGB(150, 150, 156), Enum.Material.Metal)
	bezel.Reflectance = 0.25
	local reflector = round("Reflector", 0.02, 0.32, -0.815, DARK_GLASS, Enum.Material.Neon)
	local glass = round("Glass", 0.015, 0.34, -0.83, Color3.fromRGB(220, 230, 240), Enum.Material.Glass)
	glass.Transparency = 0.55
	local switch = part(
		"Switch",
		Vector3.new(0.08, 0.05, 0.15) * scale,
		Color3.fromRGB(120, 28, 24),
		Enum.Material.SmoothPlastic,
		model
	)
	switch.CFrame = CFrame.new(0, 0.125 * scale, -0.2 * scale)
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	model.Parent = parent
	return { model = model, reflector = reflector, lens = Vector3.new(0, 0, -0.84 * scale) }
end

local function showTorch(t: Torch, shown: boolean)
	for _, piece in t.model:GetChildren() do
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = if shown then 0 else 1
		end
	end
end

local function spot(angle: number, shadows: boolean, parent: Instance): SpotLight
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = angle
	light.Shadows = shadows
	light.Enabled = false
	light.Parent = parent
	return light
end

local function circle(size: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size)
	frame.BackgroundColor3 = WHITE
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function newLight(player: Player): Light
	local camera = Workspace.CurrentCamera
	local mine = player == Players.LocalPlayer
	local holder = part("FlashlightBeam", Vector3.one * 0.2, WHITE, Enum.Material.SmoothPlastic, camera)
	holder.Transparency = 1
	local hotspot = spot(RULES.hotspot.angle, mine, holder) -- (everyone's with shadows would cost too much)
	local corona = spot(RULES.corona.angle, false, holder)
	local bounce = part("FlashlightBounce", Vector3.one * 0.2, WHITE, Enum.Material.SmoothPlastic, camera)
	bounce.Transparency = 1
	local bounceLight = Instance.new("PointLight")
	bounceLight.Shadows = false
	bounceLight.Enabled = false
	bounceLight.Parent = bounce
	local from = Instance.new("Attachment")
	from.Parent = holder
	local tip = Instance.new("Attachment")
	tip.Parent = holder
	local shaft = {}
	for _ in SHAFT do
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = from, tip
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Texture = ""
		beam.Enabled = false
		beam.Parent = holder
		table.insert(shaft, beam)
	end
	local light: Light = {
		player = player,
		holder = holder,
		hotspot = hotspot,
		corona = corona,
		bounce = bounce,
		bounceLight = bounceLight,
		tip = tip,
		shaft = shaft,
		shaftKey = -1,
		torch = nil,
		flare = nil,
		flareParts = {},
		on = false,
		seconds = RULES.battery,
		heardAt = os.clock(),
		switchedAt = -math.huge,
		rested = 0,
		diedAt = nil,
		castAt = -math.huge,
		hit = nil,
	}
	if not mine then
		local held = buildTorch(THEIRS.scale, camera)
		showTorch(held, false)
		light.torch = held
		-- A flare on the lens, for when it's pointed in your eyes: a hot core, a halo, a wide glow, a
		-- streak across.
		local flare = Instance.new("BillboardGui")
		flare.Name = "Flare"
		flare.Adornee = held.reflector
		flare.Size = UDim2.fromScale(1, 1)
		flare.LightInfluence = 0
		flare.AlwaysOnTop = false
		flare.Enabled = false
		flare.Parent = held.reflector
		light.flareParts = { circle(1, flare), circle(0.55, flare), circle(0.25, flare) }
		local streak = Instance.new("Frame")
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Position = UDim2.fromScale(0.5, 0.5)
		streak.Size = UDim2.fromScale(1.8, 0.05)
		streak.BackgroundColor3 = WHITE
		streak.BackgroundTransparency = 1
		streak.BorderSizePixel = 0
		streak.Parent = flare
		table.insert(light.flareParts, streak)
		light.flare = flare
	end
	return light
end

local function dropLight(player: Player)
	local light = lights[player]
	lights[player] = nil
	if light then
		light.holder:Destroy()
		light.bounce:Destroy()
		if light.torch then
			light.torch.model:Destroy()
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
		local now = os.clock()
		light.rested = if on and light.switchedAt > -math.huge then now - light.switchedAt else 0
		light.on = on
		light.switchedAt = now
		light.diedAt = if not on and light.seconds <= 0.6 then now else nil
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
	local since = os.clock() - light.switchedAt
	local recovery = Flashlight.recovery(light.rested, since)
	local level, yellow =
		Flashlight.output(chargeOf(light), Workspace:GetServerTimeNow(), light.player.UserId, recovery)
	if since < CATCH[#CATCH] then
		local dark = since < CATCH[1] or (since >= CATCH[2] and since < CATCH[3])
		level *= if dark then 0.05 else 0.7
	end
	return level, yellow
end

-- How the reflector looks: lit with the beam, or the filament's afterglow once it's died.
local function lensLook(light: Light, level: number, yellow: number): (Color3, number)
	if level > 0.01 then
		return WHITE:Lerp(AMBER, yellow), math.clamp(0.7 - level, 0, 0.6)
	end
	local died = light.diedAt
	if died then
		local fade = (os.clock() - died) / AFTERGLOW
		if fade < 1 then
			return GLOW, 0.2 + 0.8 * fade
		end
	end
	return DARK_GLASS, 0
end

-- How thick the fog is (the beam shows more in more of it).
local function fogginess(): number
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	return if atmosphere then math.clamp(atmosphere.Density / 0.3, 0.5, 1.6) else 0.6
end

local function luminance(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- Lights it from `origin` (its lens, facing along -Z) to `level` (0..1), `yellow` (0..1): the
-- hotspot and corona, the light bounced off what it's pointed at (looked for again if `look`), and
-- the beam in the fog (`shaft`: how strong, Items.FLASHLIGHT.shaft).
local function shine(
	light: Light,
	origin: CFrame,
	level: number,
	yellow: number,
	look: boolean,
	ignore: { Instance },
	shaft: number
)
	light.holder.CFrame = origin
	local color = WHITE:Lerp(AMBER, yellow)
	local lit = level > 0.01
	local hot, wide = RULES.hotspot, RULES.corona
	light.hotspot.Enabled = lit
	light.corona.Enabled = lit
	light.hotspot.Brightness = hot.brightness * level
	light.hotspot.Range = hot.range * (0.55 + 0.45 * level)
	light.hotspot.Color = color
	light.corona.Brightness = wide.brightness * level
	light.corona.Range = wide.range * (0.55 + 0.45 * level)
	light.corona.Color = color:Lerp(AMBER, 0.15) -- (the edge of a reflector's beam is warmer)
	-- What it's pointed at, and the light that comes back off it.
	if look then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		light.hit = if lit then Workspace:Raycast(origin.Position, origin.LookVector * hot.range, params) else nil
		light.castAt = os.clock()
	end
	local hit = light.hit
	local reach = if hit then hit.Distance else RULES.shaft.length
	if hit and lit then
		local surface = if hit.Instance:IsA("BasePart") then hit.Instance.Color else Color3.new(0.5, 0.5, 0.5)
		local strength, radius =
			Flashlight.bounce(hit.Distance, hot.range, math.clamp(luminance(surface) * 1.4, 0.15, 1))
		light.bounce.CFrame = CFrame.new(hit.Position + hit.Normal * 0.6 - origin.LookVector * 0.3)
		light.bounceLight.Range = radius
		light.bounceLight.Brightness = RULES.bounce.brightness * level * strength
		light.bounceLight.Color = color:Lerp(surface, 0.45)
		light.bounceLight.Enabled = strength * level > 0.01
	else
		light.bounceLight.Enabled = false
	end
	-- The beam in the fog, as far as it goes (to what it hits), soft at the edges, fading out.
	local length = math.min(reach, RULES.shaft.length)
	local strength = if lit then shaft * level * fogginess() else 0
	light.tip.Position = Vector3.new(0, 0, -length)
	local key = math.floor(strength * 200) + math.floor(length) * 1000 + math.floor(yellow * 20) * 100000
	if key ~= light.shaftKey then
		light.shaftKey = key
		local spread = 2 * math.tan(math.rad(hot.angle / 2)) * 1.15
		for i, layer in SHAFT do
			local beam = light.shaft[i]
			local alpha = math.clamp(strength * layer.alpha, 0, 1)
			beam.Enabled = alpha > 0.002 and length > 1
			beam.Color = ColorSequence.new(color)
			beam.Width0 = 0.3 * layer.width + 0.05
			beam.Width1 = length * spread * layer.width
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - alpha * 0.5),
				NumberSequenceKeypoint.new(0.12, 1 - alpha),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
end

-- How much your hand shakes now (radians), with how you're moving.
local function tremor(gait: MovementController.Gait): number
	local t = RULES.tremor
	return math.rad(t.still + (t.moving - t.still) * gait.moving + (t.running - t.moving) * gait.sprint)
end

local function ignoreFor(character: Model?): { Instance }
	local list: { Instance } = { Workspace.CurrentCamera :: Instance }
	if character then
		table.insert(list, character)
	end
	return list
end

-- Where a torch is in someone's left hand (nil: no arm), pointing down along it.
local function inHand(character: Model?): CFrame?
	local arm = character and character:FindFirstChild("Left Arm") :: BasePart?
	if arm == nil then
		return nil
	end
	local along = -arm.CFrame.UpVector -- from the shoulder to the hand
	local hand = arm.Position + along * (arm.Size.Y / 2 - THEIRS.grip * 0.5)
	return CFrame.lookAt(hand + along * THEIRS.grip, hand + along * 2, arm.CFrame.LookVector)
end

-- Yours, in your view: raised or lowered, swinging, breathing, trailing, shaking, drawn in at a
-- wall; the beam from its lens.
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
	aim = if aim then (aim :: CFrame):Lerp(look, 1 - math.exp(-dt * RULES.lag)) else look
	local gait = MovementController.gait()
	-- The hand: a slow drift and a fine tremble.
	local t = os.clock()
	local shake = tremor(gait)
	local held = (aim :: CFrame)
		* CFrame.Angles(
			(math.noise(t * 0.6, 1.3) * 0.7 + math.noise(t * 9, 7.1) * 0.3) * shake * TREMBLE,
			(math.noise(t * 0.6, 5.9) * 0.7 + math.noise(t * 9, 2.4) * 0.3) * shake * TREMBLE,
			0
		)
	-- Up against a wall: drawn in.
	local ignore = ignoreFor(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local origin = camera.CFrame.Position
	local ahead = Workspace:Raycast(origin, camera.CFrame.LookVector * DRAW_IN.near, params)
	drawn = Motion.ease(drawn, if ahead then 1 - ahead.Distance / DRAW_IN.near else 0, DRAW_IN.rate, dt)
	local side = math.sin(gait.phase)
	local swing = CFrame.new(
		side * SWAY.side * gait.moving,
		-Motion.footfall(gait.phase) * SWAY.dip * gait.moving
			- (1 - raised) * LOWERED
			+ math.sin(gait.breath) * SWAY.breath,
		0
	) * CFrame.Angles(0, 0, side * SWAY.roll * gait.moving)
	local hand = origin + held:VectorToWorldSpace(HELD + Vector3.new(0.1, DRAW_IN.up, DRAW_IN.back) * drawn)
	local target = origin + held.LookVector * AIM_AT
	torch.model:PivotTo(CFrame.lookAt(hand, target, held.UpVector) * swing)
	showTorch(torch, raised >= 0.02)
	if light == nil then
		return
	end
	local level, yellow = outputOf(light)
	local color, transparency = lensLook(light, level, yellow)
	torch.reflector.Color = color
	torch.reflector.Transparency = transparency
	-- Knocked down, it's in your hand on the ground; else from its lens (never through a wall).
	local lens: CFrame
	local fallen = if down then inHand(character) else nil
	if fallen then
		lens = fallen * CFrame.new(torch.lens * THEIRS.scale)
	elseif down and character and character:FindFirstChild("Head") then
		lens = (character:FindFirstChild("Head") :: BasePart).CFrame * HEAD
	else
		lens = torch.model:GetPivot() * CFrame.new(torch.lens)
		local toLens = lens.Position - origin
		local blocked = Workspace:Raycast(origin, toLens, params)
		if blocked then
			lens = lens.Rotation + (blocked.Position - toLens.Unit * 0.1)
		end
	end
	shine(light, lens, level, yellow, true, ignore, RULES.shaft.yours)
end

-- Someone else's: in their left hand, along their arm; a flare and a dazzle when it's in your eyes.
-- Returns how much it dazzles you (0..1).
local function drawTheirs(light: Light, camera: Camera): number
	local character = light.player.Character
	local level, yellow = outputOf(light)
	local held = light.torch :: Torch
	local hand = inHand(character)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local up = light.on or (light.diedAt ~= nil and os.clock() - light.diedAt < AFTERGLOW)
	if (hand == nil and head == nil) or not up then
		shine(light, light.holder.CFrame, 0, 1, false, {}, 0)
		showTorch(held, false)
		if light.flare then
			light.flare.Enabled = false
		end
		return 0
	end
	local pivot = hand or (head :: BasePart).CFrame * HEAD
	held.model:PivotTo(pivot)
	showTorch(held, hand ~= nil)
	local color, transparency = lensLook(light, level, yellow)
	held.reflector.Color = color
	held.reflector.Transparency = transparency
	local lens = pivot * CFrame.new(held.lens)
	local look = os.clock() - light.castAt >= BOUNCE_EVERY
	shine(light, lens, level, yellow, look, ignoreFor(character), RULES.shaft.theirs)
	-- In your eyes?
	local toYou = camera.CFrame.Position - lens.Position
	local distance = toYou.Magnitude
	local glare = if distance > 0.5
		then Flashlight.glare(lens.LookVector:Dot(toYou / distance), distance) * level
		else 0
	if glare > 0.01 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local through = ignoreFor(character)
		if Players.LocalPlayer.Character then
			table.insert(through, Players.LocalPlayer.Character :: Model)
		end
		params.FilterDescendantsInstances = through
		if Workspace:Raycast(lens.Position, toYou, params) then
			glare = 0 -- something's in the way
		end
	end
	local flare = light.flare
	if flare then
		flare.Enabled = glare > 0.01
		if flare.Enabled then
			local size = 0.5 + 5.5 * glare
			flare.Size = UDim2.fromScale(size, size)
			local looks = { 0.3, 0.6, 0.95, 0.5 } -- wide glow, halo, core, streak
			for i, frame in light.flareParts do
				frame.BackgroundColor3 = WHITE:Lerp(AMBER, yellow)
				frame.BackgroundTransparency = 1 - glare * looks[i]
			end
		end
	end
	return glare
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	drawMine(dt, lights[Players.LocalPlayer])
	local glare = 0
	for player, light in lights do
		if player ~= Players.LocalPlayer then
			glare = math.max(glare, drawTheirs(light, camera))
		end
	end
	-- Dazzled: your eyes wash out while a light's in them, and come back slower.
	dazzled = Motion.ease(dazzled, glare, if glare > dazzled then DAZZLE.rise else DAZZLE.fall, dt)
	local settings = StateController.get("settings") or {}
	local k = dazzled * (if settings.reduceFlash == true then DAZZLE.calm else 1)
	dazzle.Enabled = k > 0.005
	dazzle.Brightness = DAZZLE.brightness * k
	dazzle.Contrast = DAZZLE.contrast * k
	dazzle.Saturation = -0.3 * k
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
	torch = buildTorch(1, Workspace.CurrentCamera)
	torch.model.Name = "ViewmodelFlashlight"
	showTorch(torch, false)
	dazzle = Instance.new("ColorCorrectionEffect")
	dazzle.Name = "FlashlightDazzle"
	dazzle.Enabled = false
	dazzle.Parent = Lighting
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
