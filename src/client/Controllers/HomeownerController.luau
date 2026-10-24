--!strict
-- The homeowners who answer the door (PROMPT §V2.1/V2.3), built and animated on every client from
-- the attributes HomeownerService sets on each house (OwnerModel, OwnerSeed, OwnerOut, OwnerStyle).
-- Every knock plays one of five entrances (Config/Homeowners.STYLES). The door swings open on
-- darkness: a black void grows from the hinge, with a sickly light behind. The figure comes out of
-- the dark, ducking under the frame if it's too tall. While you play the door's mini-game they stand
-- there breathing, head following you, twitching, sometimes slowly reaching for you. Then they back
-- into the dark and the door slams. Each house's seed gives its homeowner a body of its own:
-- stretched legs, arms hanging too low, a head too small or too big. Poses update at a low frame
-- rate, like a 1990s console game.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Houses = require(Shared.Modules.Houses)
local Characters = require(Shared.Config.Characters)
local Homeowners = require(Shared.Config.Homeowners)
local CharacterRig = require(Shared.Modules.CharacterRig)
local MeshLibrary = require(Shared.Modules.MeshLibrary)
local Sound = require(script.Parent.SoundController)

local HomeownerController = {}

local POSE_FPS = 18
local INSIDE = 2.4 -- studs behind the door surface where they wait in the dark
local DOOR_FRONT = 0.47 -- the door part's front face, in front of its centre
local BODY_HALF_DEPTH = 0.8
local VIEW_DISTANCE = 220
local LEAVE_TIME = 0.8 -- backing into the dark
local CLOSE_TIME = 0.3 -- then the door slams
local GLOW_COLOR = Color3.fromRGB(214, 168, 120)

export type Look = {
	morph: CharacterRig.Morph,
	tilt: number,
	hinge: number, -- -1 / 1: which side of the door the hinge is on
	reach: boolean, -- slowly reaches for you while you play
	snapAt: number, -- Snap entrance: when they're suddenly there
}

type Figure = {
	house: Model,
	door: BasePart,
	doorFrame: CFrame, -- the door where it hangs closed (a real door swings; this doesn't)
	hinge: Model?, -- a real hinged front door (World/HouseStyles) the homeowner opens
	hingeClosed: CFrame,
	hingeAngle: number,
	model: Model,
	root: BasePart,
	rootOffset: CFrame, -- root relative to the feet
	joints: { [string]: Motor6D },
	rigged: boolean,
	height: number,
	look: Look,
	style: string,
	leaving: boolean,
	clock: number, -- seconds since the entrance started
	leaveClock: number,
	leaveFrom: number, -- how far out they were when they started leaving
	poseClock: number,
	void: Part,
	glow: PointLight,
	porch: { PointLight },
	headYaw: number,
	headPitch: number,
	twitchAt: number,
	twitchNeck: number,
	twitchArm: number,
	twitchArmSide: string,
	twitchBody: number,
	cues: { [string]: boolean },
	rng: Random,
	slammed: boolean,
}

local figures: { [Model]: Figure } = {}
local hiddenHouses: { [Model]: boolean } = {}

local function ease(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The body, tilt and quirks of a house's homeowner: the same on every client.
function HomeownerController.look(seed: number, creep: number): Look
	local rng = Random.new(seed)
	local M = Homeowners.MORPH
	local power = 1.8 - 1.4 * creep -- creepier neighbourhoods roll toward the extremes
	local function biased(range: Homeowners.Range): number
		return range.min + (range.max - range.min) * rng:NextNumber() ^ power
	end
	local headAmount = rng:NextNumber() ^ power
	local head = if rng:NextNumber() < 0.55
		then 1 - (1 - M.head.min) * headAmount
		else 1 + (M.head.max - 1) * headAmount
	local morph: CharacterRig.Morph = {
		scale = lerp(M.scale.min, M.scale.max, rng:NextNumber()),
		stretch = biased(M.stretch),
		arms = biased(M.arms),
		head = head,
		thin = M.thin.max - (biased(M.thin) - M.thin.min),
		neck = biased(M.neck),
	}
	return {
		morph = morph,
		tilt = math.rad(rng:NextNumber(-1, 1) * Homeowners.TILT * (0.3 + 0.7 * creep)),
		hinge = if rng:NextNumber() < 0.5 then -1 else 1,
		reach = rng:NextNumber() < 0.3 + 0.5 * creep,
		snapAt = rng:NextNumber(0.8, 1.6),
	}
end

local function houseLook(house: Model, door: BasePart): Look?
	local seed = house:GetAttribute("OwnerSeed")
	if type(seed) ~= "number" then
		return nil
	end
	local neighborhood = door:GetAttribute("Neighborhood")
	local creep = if type(neighborhood) == "string" then Homeowners.CREEP[neighborhood] or 0.5 else 0.5
	return HomeownerController.look(seed, creep)
end

-- A standalone copy of a house's homeowner with its feet at the origin (also used by the
-- jumpscare). Returns the model, the part to move, the root's offset from the feet and whether it
-- has joints.
function HomeownerController.build(house: Model): (Model?, BasePart?, CFrame?, boolean)
	local id = house:GetAttribute("OwnerModel")
	local door = house:FindFirstChild("Door", true)
	if type(id) ~= "string" or door == nil or not door:IsA("BasePart") then
		return nil, nil, nil, false
	end
	local look = houseLook(house, door) or HomeownerController.look(1, 0.5)
	if Characters[id] then
		local rig = CharacterRig.build(id, "puppet", look.morph)
		if rig and rig.PrimaryPart then
			return rig, rig.PrimaryPart, rig.PrimaryPart.CFrame, true
		end
	end
	local part = MeshLibrary.get(id)
	if part == nil then
		return nil, nil, nil, false
	end
	local m = look.morph
	local scale = m.scale or 1
	part.Size = Vector3.new(
		part.Size.X * scale * (m.thin or 1),
		part.Size.Y * scale * (m.stretch or 1),
		part.Size.Z * scale * (m.thin or 1)
	)
	part.Name = "Body"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local model = Instance.new("Model")
	model.Name = id
	part.Parent = model
	model.PrimaryPart = part
	return model, part, CFrame.new(0, part.Size.Y / 2, 0), false
end

local function porchLights(house: Model): { PointLight }
	local lights = {}
	local porch = house:FindFirstChild("PorchLight", true)
	if porch then
		for _, child in porch:GetChildren() do
			if child:IsA("PointLight") then
				table.insert(lights, child)
			end
		end
	end
	return lights
end

local function cue(figure: Figure, key: string, at: number, play: () -> ())
	if figure.clock >= at and not figure.cues[key] then
		figure.cues[key] = true
		play()
	end
end

local function create(house: Model, door: BasePart, skipEntrance: boolean)
	if figures[house] then
		return
	end
	local look = houseLook(house, door)
	local model, root, rootOffset, rigged = HomeownerController.build(house)
	if look == nil or model == nil or root == nil or rootOffset == nil then
		return
	end
	local joints: { [string]: Motor6D } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			joints[descendant.Name] = descendant
		end
	end
	local void = Instance.new("Part")
	void.Name = "DoorVoid"
	void.Anchored = true
	void.CanCollide = false
	void.CanQuery = false
	void.CanTouch = false
	void.CastShadow = false
	void.Material = Enum.Material.SmoothPlastic
	void.Color = Color3.new(0, 0, 0)
	void.Size = Vector3.new(0.05, door.Size.Y, 0.05)
	void.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = GLOW_COLOR
	glow.Range = 11
	glow.Brightness = 0
	glow.Shadows = true
	glow.Parent = void
	void.Parent = model
	local style = house:GetAttribute("OwnerStyle")
	local hingeModel = door.Parent
	local hinge = if hingeModel
			and hingeModel:IsA("Model")
			and CollectionService:HasTag(hingeModel, "Hinged")
			and hingeModel:GetAttribute("Kind") == "FrontDoor"
		then hingeModel
		else nil
	local figure: Figure = {
		house = house,
		door = door,
		doorFrame = door.CFrame,
		hinge = hinge,
		hingeClosed = if hinge then hinge:GetPivot() else CFrame.identity,
		hingeAngle = if hinge then (hinge:GetAttribute("OpenAngle") :: number?) or 100 else 0,
		model = model,
		root = root,
		rootOffset = rootOffset,
		joints = joints,
		rigged = rigged,
		height = (model:GetAttribute("Height") :: number?) or root.Size.Y,
		look = look,
		style = if type(style) == "string" then style else "Creep",
		leaving = false,
		clock = if skipEntrance then 30 else 0,
		leaveClock = 0,
		leaveFrom = 1,
		poseClock = 1,
		void = void,
		glow = glow,
		porch = porchLights(house),
		headYaw = 0,
		headPitch = 0,
		twitchAt = 30 + math.random() * 2,
		twitchNeck = 0,
		twitchArm = 0,
		twitchArmSide = "Left",
		twitchBody = 0,
		cues = {},
		rng = Random.new(),
		slammed = false,
	}
	figure.twitchAt = (if skipEntrance then 30 else 3) + figure.rng:NextNumber(0.5, 2)
	figures[house] = figure
	if not skipEntrance then
		Sound.play("Latch", { at = door }) -- the bolt drawn back before the door moves
	end
	model.Parent = if hiddenHouses[house] then nil else Workspace
end

local function destroy(house: Model)
	local figure = figures[house]
	if figure then
		figures[house] = nil
		for _, light in figure.porch do
			light.Enabled = true
		end
		if figure.hinge then
			figure.hinge:PivotTo(figure.hingeClosed)
		end
		figure.model:Destroy()
	end
end

-- How the entrance looks at `c` seconds: how open the door is (0..1), how far out they are (0 =
-- inside in the dark, 1 = on the porch), sideways lean (Peek), head bow, inside light, porch light.
type Pose = { open: number, out: number, roll: number, bow: number, glow: number, porch: boolean }

local function entrance(figure: Figure): Pose
	local c = figure.clock
	local door = figure.door
	local style = figure.style
	if style == "Snap" then
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 1.5, at = door })
		end)
		local snapAt = figure.look.snapAt
		cue(figure, "thud", snapAt, function()
			Sound.play("Thud", { at = door })
		end)
		local after = c - snapAt
		return {
			open = ease(c / 0.35),
			out = if after < 0 then 0 else lerp(1.15, 1, ease(after / 0.6)),
			roll = 0,
			bow = if after < 0 then 0 else -0.7 * (1 - ease(after / 0.5)),
			glow = ease(c / 0.6) * 0.7,
			porch = true,
		}
	elseif style == "Peek" then
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 1.2, volume = 0.6, at = door })
		end)
		cue(figure, "creak2", 1.9, function()
			Sound.play("Creak", { speed = 0.85, at = door })
		end)
		local open = if c < 0.5 then 0.35 * ease(c / 0.5) else 0.35 + 0.65 * ease((c - 1.9) / 0.5)
		local out = if c < 0.5
			then 0
			elseif c < 1.9 then 0.3 * ease((c - 0.5) / 0.4)
			else lerp(0.3, 1, ease((c - 1.9) / 1))
		local lean = if c < 0.5 then 0 elseif c < 1.9 then ease((c - 0.5) / 0.4) else 1 - ease((c - 1.9) / 0.7)
		return {
			open = open,
			out = out,
			roll = figure.look.hinge * 0.85 * lean,
			bow = 0,
			glow = open * 0.6,
			porch = true,
		}
	elseif style == "Waiting" then
		cue(figure, "creak", 0, function()
			Sound.play("Creak", { speed = 0.7, at = door })
		end)
		cue(figure, "breath", 1.8, function()
			Sound.play("Breath", { at = door })
		end)
		return {
			open = ease(c / 1.1),
			out = lerp(0.8, 1, ease((c - 2.4) / 0.8)),
			roll = 0,
			bow = -0.95 * (1 - ease((c - 1.6) / 1.4)),
			glow = ease(c / 1.1) * 0.5,
			porch = true,
		}
	elseif style == "Blackout" then
		local porch = true
		if c < 0.6 then
			porch = math.random() < 0.55 -- flickering
		elseif c < 1.3 then
			porch = false
		elseif c < 1.6 then
			porch = math.random() < 0.7
		end
		cue(figure, "breath", 1.25, function()
			Sound.play("Breath", { volume = 1.3, at = door })
		end)
		local there = c >= 1
		return {
			open = if there then 1 else 0,
			out = if there then 1 else 0,
			roll = 0,
			bow = 0,
			glow = if there and c > 1.3 then 0.5 else 0,
			porch = porch,
		}
	end
	-- Creep (default): the door eases open, they drift out of the dark.
	cue(figure, "creak", 0, function()
		Sound.play("Creak", { speed = 0.8, at = door })
	end)
	cue(figure, "steps", 1.1, function()
		Sound.play("FloorCreak", { at = door })
	end)
	return {
		open = ease(c / 1.6),
		out = ease((c - 1) / 2.4),
		roll = 0,
		bow = -0.3 * (1 - ease((c - 1) / 2.4)),
		glow = ease(c / 1.6) * 0.6,
		porch = true,
	}
end

local function setJoint(figure: Figure, name: string, value: CFrame)
	local motor = figure.joints[name]
	if motor then
		motor.Transform = value
	end
end

local function pose(figure: Figure, dt: number, camera: Camera)
	local door = figure.door
	local p = entrance(figure)
	local idle = math.max(0, figure.clock - 4)
	local lean = math.min(idle / 30, 0.16) -- they slowly lean in toward you while you play
	local out = p.out
	if figure.leaving then
		local t = figure.leaveClock
		out = lerp(figure.leaveFrom, 0, ease(t / LEAVE_TIME))
		p.open = 1 - ease((t - LEAVE_TIME) / CLOSE_TIME)
		p.glow = p.glow * (1 - ease(t / LEAVE_TIME))
		p.porch = true
		if t >= LEAVE_TIME + CLOSE_TIME and not figure.slammed then
			figure.slammed = true
			Sound.play("DoorSlam", { at = door })
		end
	end

	local doorFrame = figure.doorFrame
	if figure.hinge then
		-- A real door: it swings open onto the dark hall, where the light comes from.
		figure.hinge:PivotTo(
			figure.hingeClosed * CFrame.Angles(0, math.rad(figure.hingeAngle * math.clamp(p.open, 0, 1)), 0)
		)
		figure.void.Transparency = 1
		figure.void.CFrame = doorFrame * CFrame.new(0, 1, 2.5)
	else
		-- A painted-on door: darkness grows from the hinge side instead.
		local width = door.Size.X * math.clamp(p.open, 0, 1)
		local hingeX = figure.look.hinge * door.Size.X / 2
		figure.void.Size = Vector3.new(math.max(width, 0.05), door.Size.Y, 0.05)
		figure.void.Transparency = if width < 0.06 then 1 else 0
		figure.void.CFrame = doorFrame * CFrame.new(hingeX - figure.look.hinge * width / 2, 0, -DOOR_FRONT + 0.03)
	end
	figure.glow.Brightness = p.glow
	for _, light in figure.porch do
		light.Enabled = p.porch
	end

	-- The body pose updates at a low frame rate.
	figure.poseClock += dt
	if figure.poseClock < 1 / POSE_FPS then
		return
	end
	local step = figure.poseClock
	figure.poseClock = 0

	local standZ = -(DOOR_FRONT + Homeowners.STAND_OFF + BODY_HALF_DEPTH)
	local z = lerp(INSIDE, standZ, out)
	-- Too tall for the door: duck under the frame on the way out.
	local over = figure.height - door.Size.Y + 0.4
	local duck = if over > 0 then math.min(0.75, over / figure.height * 2.4) else 0
	duck *= 1 - ease((out - 0.75) / 0.3)
	local feet = doorFrame * CFrame.new(0, -door.Size.Y / 2, z)

	-- Twitches: something jerks, then settles.
	if figure.clock >= figure.twitchAt and not figure.leaving then
		figure.twitchAt = figure.clock + figure.rng:NextNumber(Homeowners.TWITCH_EVERY.min, Homeowners.TWITCH_EVERY.max)
		local kind = figure.rng:NextInteger(1, 3)
		if kind == 1 then
			figure.twitchNeck = figure.rng:NextNumber(-0.6, 0.6)
		elseif kind == 2 then
			figure.twitchArm = figure.rng:NextNumber(0.3, 0.9)
			figure.twitchArmSide = if figure.rng:NextNumber() < 0.5 then "Left" else "Right"
		else
			figure.twitchBody = figure.rng:NextNumber(-0.18, 0.18)
		end
	end
	local decay = math.exp(-step * 7)
	figure.twitchNeck *= decay
	figure.twitchArm *= decay
	figure.twitchBody *= decay

	local t = os.clock()
	local breathe = math.sin(t * 1.4) * 0.025
	local tilt = figure.look.tilt

	if not figure.rigged then
		local body = CFrame.Angles(
			-duck - lean + breathe,
			0,
			tilt * 0.5 + p.roll * 0.6 + figure.twitchBody + figure.twitchNeck * 0.3
		)
		figure.root.CFrame = feet * body * figure.rootOffset
		return
	end

	figure.root.CFrame = feet * figure.rootOffset
	setJoint(
		figure,
		"RootJoint",
		CFrame.Angles(-duck - lean + breathe + p.bow * 0.25, 0, p.roll + tilt * 0.3 + figure.twitchBody)
	)

	-- Head: follows the camera, slowly, with sudden snaps when it twitches.
	local torso = figure.model:FindFirstChild("Torso") :: BasePart?
	local head = figure.model:FindFirstChild("Head") :: BasePart?
	if torso and head then
		local dir = torso.CFrame:VectorToObjectSpace(camera.CFrame.Position - head.Position)
		local yaw = math.clamp(math.atan2(-dir.X, -dir.Z), -1.2, 1.2)
		local pitch = math.clamp(math.atan2(dir.Y, math.sqrt(dir.X * dir.X + dir.Z * dir.Z)), -0.6, 0.6)
		local follow = math.min(1, step * (if math.abs(figure.twitchNeck) > 0.3 then 12 else 2.2))
		figure.headYaw = lerp(figure.headYaw, yaw, follow)
		figure.headPitch = lerp(figure.headPitch, pitch, follow)
	end
	setJoint(
		figure,
		"Neck",
		CFrame.fromEulerAnglesYXZ(figure.headPitch + p.bow, figure.headYaw, tilt + figure.twitchNeck)
	)

	-- Arms hang (a little wrong); some homeowners slowly reach out while you play.
	local reach = if figure.look.reach and not figure.leaving then ease((figure.clock - 6) / 4) * 1.25 else 0
	local reachSide = if figure.look.hinge > 0 then "Right" else "Left"
	for _, side in { "Left", "Right" } do
		local lift = if side == reachSide then reach else 0
		local jerk = if side == figure.twitchArmSide then figure.twitchArm else 0
		local sway = math.sin(t * 0.9 + (if side == "Left" then 0 else 1.7)) * 0.04
		setJoint(
			figure,
			side .. " Shoulder",
			CFrame.Angles(lift + jerk + sway, 0, if side == "Left" then -0.05 else 0.05)
		)
		setJoint(figure, side .. " Hip", CFrame.identity)
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	for house, figure in figures do
		if house.Parent == nil or figure.door.Parent == nil then
			destroy(house)
			continue
		end
		figure.clock += dt
		if figure.leaving then
			figure.leaveClock += dt
			if figure.leaveClock > LEAVE_TIME + CLOSE_TIME + 0.2 then
				destroy(house)
				continue
			end
		end
		pose(figure, dt, camera)
	end
end

local function onOutChanged(house: Model, door: BasePart)
	local out = house:GetAttribute("OwnerOut") == true
	local figure = figures[house]
	if out then
		if figure and figure.leaving then
			destroy(house) -- knocked again while they were going back in: start over
			figure = nil
		end
		if figure == nil then
			local camera = Workspace.CurrentCamera
			if camera and (camera.CFrame.Position - door.Position).Magnitude <= VIEW_DISTANCE then
				create(house, door, false)
			end
		end
	elseif figure and not figure.leaving then
		figure.leaving = true
		figure.leaveClock = 0
		figure.leaveFrom = math.max(entrance(figure).out, 0.5)
	end
end

local function watch(door: Instance)
	if not door:IsA("BasePart") then
		return
	end
	local house = Houses.of(door)
	if house == nil or house:GetAttribute("HouseId") == nil then
		return
	end
	house:GetAttributeChangedSignal("OwnerOut"):Connect(function()
		onOutChanged(house, door)
	end)
end

-- Hides a house's homeowner (the jumpscare uses its own copy) or shows it again.
function HomeownerController.hide(house: Model, hidden: boolean)
	hiddenHouses[house] = if hidden then true else nil
	local figure = figures[house]
	if figure then
		figure.model.Parent = if hidden then nil else Workspace
	end
end

-- Where a house's front door hangs when closed (a real door may be swung open right now).
function HomeownerController.doorFrame(door: BasePart): CFrame
	local house = Houses.of(door)
	local figure = house and figures[house]
	return if figure then figure.doorFrame else door.CFrame
end

-- The homeowner's root part at a house right now, if one is out (for the jumpscare to start from).
function HomeownerController.current(house: Model): BasePart?
	local figure = figures[house]
	return if figure and not figure.leaving then figure.root else nil
end

-- Where the face of whoever answered a house's door is right now (DoorController looks up at it).
function HomeownerController.face(house: Model): Vector3?
	local figure = figures[house]
	if figure == nil or figure.leaving then
		return nil
	end
	local head = figure.model:FindFirstChild("Head") :: BasePart?
	if head then
		return head.Position
	end
	return (figure.root.CFrame * CFrame.new(0, figure.root.Size.Y * 0.4, 0)).Position
end

function HomeownerController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(watch)
	for _, door in CollectionService:GetTagged("Door") do
		watch(door)
	end
	RunService.RenderStepped:Connect(step)
	-- Someone else's homeowner was already out when we arrived, or we walked into view of one.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local camera = Workspace.CurrentCamera
			if camera then
				for _, door in CollectionService:GetTagged("Door") do
					local house = Houses.of(door)
					if
						house
						and door:IsA("BasePart")
						and figures[house] == nil
						and house:GetAttribute("OwnerOut") == true
						and (camera.CFrame.Position - door.Position).Magnitude <= VIEW_DISTANCE
					then
						create(house, door, true)
					end
				end
			end
		end
	end)
end

return HomeownerController
