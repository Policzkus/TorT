--!strict
-- Client side of doors: knock sound, the doorstep shot (when someone answers your knock you step
-- back off the door and look up at them), what homeowners say (a hello once they're out, then how
-- they took the mini-game; DialogController; get it wrong and they slap you first), and a
-- countdown ring on doors that have been visited. All of it is everyone's (the user wants it
-- synced): what they say, the slap, someone else's knock and scare come from the server, and a
-- house's cooldown is shared (its ReadyAt), so everyone near a door sees the same visit and the
-- same ring. With a full bucket the doors say so instead of "Knock" (the server won't let you).
-- Doors stream in and out, so state is kept by house id and reapplied.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Dialogue = require(ReplicatedStorage:WaitForChild("Shared").Config.Dialogue)
local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)
local Format = require(ReplicatedStorage:WaitForChild("Shared").Modules.Format)
local Formulas = require(ReplicatedStorage:WaitForChild("Shared").Modules.Formulas)
local Houses = require(ReplicatedStorage:WaitForChild("Shared").Modules.Houses)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Dialog = require(script.Parent.DialogController)
local Homeowner = require(script.Parent.HomeownerController)
local Minigame = require(script.Parent.MinigameController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local DoorController = {}

-- Where you stand to watch who answers: straight out from the door, far enough back to see all of
-- them (VIEW + their height * PER_HEIGHT, between NEAR and FAR studs: they stop 2-4 studs out from
-- the door, room to turn to you), on the porch or a step down (LEVEL under the sill) if there's
-- room, else as far down a stoop as DROP.
local DOORSTEP = { near = 6.5, far = 10.5, view = 4.2, perHeight = 0.6, level = 1, drop = 3.2 }
local LOOK_BELOW = 0.9 -- aim this far under the face, so it sits above the mini-game panel
local LOOK_AFTER = 0.8 -- seconds your view stays on them once the visit's over
local CLAP_FIRST = 1.0 -- seconds of a homeowner's slow clap (a PERFECT) before they hand over the candy
local LOOK_FREE = 40 -- pixels of mouse movement (or a stick's push) that take your view back
-- The cooldown ring on the door (the user's reference: a ring timer, the time left one colour and the
-- time gone another; here the HUD's): TICKS rounded segments round a dark disc (see-through like
-- the HUD's tiles) with the seconds in it, bright for the time left and dim for the time gone,
-- which sweeps round clockwise from the top, the segment at its edge fading as it goes. It's in the
-- world, flat on the door's face (the user wants things like this 3D), and only once whoever
-- answered has gone in and the door's shut; a ring that comes up after your own visit starts full
-- (the server's cooldown counts from about then too). RING studs across, `out` in front of the
-- door part's middle (its face is 0.47 out), `up` above it, drawn at `pixels` a stud.
local RING = { size = 2.3, out = 0.52, up = 0.9, ticks = 48, pixels = 120, radius = 0.44 }
local TICK_LEFT = { color = Theme.Colors.Text, transparency = 0 }
local TICK_GONE = { color = Theme.Colors.TextDim, transparency = 0.6 }
-- Slapped (a wrong answer): your head snaps round the way the hand was going (`turn` degrees,
-- tipping `tilt`, in `snap` seconds; held `hold`, back over `back`), a little shake, red closes in
-- from the edges, and you're shoved back.
local HIT = {
	turn = 30,
	tilt = 9,
	snap = 0.07,
	hold = 0.12,
	back = 0.55,
	shake = 0.25,
	strength = 0.25,
	knock = 22,
	lift = 6,
	push = 0.15, -- seconds you're shoved
}

local doors: { [string]: BasePart } = {}
local readyAt: { [string]: number } = {}
type Ring = { part: BasePart, door: BasePart, ticks: { Frame }, seconds: TextLabel, total: number }
local badges: { [string]: Ring } = {}
local fresh: { [string]: boolean } = {} -- houses you've just visited: their ring starts full
-- The rings live here, not in the doors: a door's model swings, and would carry them off.
local ringFolder: Folder
-- Your view, held on whoever answered for the whole visit (until `untilAt`, set when it's over).
local look: { house: Model, houseId: string, guess: Vector3, untilAt: number, moved: number }? = nil
local hitFlash: Frame

local function promptOf(door: BasePart): ProximityPrompt?
	return door:FindFirstChildOfClass("ProximityPrompt")
end

local function newRing(door: BasePart, total: number): Ring
	local frame = Homeowner.doorFrame(door) -- where it hangs closed (its front looks out)
	local part = create("Part", {
		Name = "CooldownRing",
		Size = Vector3.new(RING.size, RING.size, 0.05),
		CFrame = frame * CFrame.new(0, RING.up, -RING.out),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Parent = ringFolder,
	})
	local gui = create("SurfaceGui", {
		Name = "Cooldown",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = RING.pixels,
		LightInfluence = 0,
		MaxDistance = 70,
		Parent = part,
	})
	-- It fades in once the door's shut.
	local group = create("CanvasGroup", {
		Name = "Ring",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = gui,
	})
	TweenService:Create(group, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	}):Play()
	create("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = Theme.HairlineTransparency,
			Thickness = 1,
		}),
		Parent = group,
	})
	local seconds = create("TextLabel", {
		Name = "Seconds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.3),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		ZIndex = 2,
		Parent = group,
	})
	local ticks: { Frame } = {}
	for index = 1, RING.ticks do
		local angle = (index - 0.5) / RING.ticks * math.pi * 2 -- clockwise from the top
		table.insert(
			ticks,
			create("Frame", {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.sin(angle) * RING.radius, 0.5 - math.cos(angle) * RING.radius),
				Size = UDim2.fromScale(0.03, 0.1),
				Rotation = math.deg(angle),
				BackgroundColor3 = TICK_LEFT.color,
				BorderSizePixel = 0,
				create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Parent = group,
			})
		)
	end
	return { part = part, door = door, ticks = ticks, seconds = seconds, total = total }
end

local function setBadge(houseId: string, door: BasePart?, secondsLeft: number?)
	local ring = badges[houseId]
	if secondsLeft == nil or door == nil then
		if ring then
			ring.part:Destroy()
			badges[houseId] = nil
		end
		return
	end
	local left = secondsLeft :: number
	if ring == nil or ring.door ~= door or ring.part.Parent == nil then
		if ring then
			ring.part:Destroy()
		end
		-- Right after a visit it starts full, however long the door took to shut; a door you come
		-- back to shows how far it's got.
		local total = if fresh[houseId] then math.max(left, 1) else Economy.DOOR_COOLDOWN
		fresh[houseId] = nil
		ring = newRing(door, total)
		badges[houseId] = ring
	else
		fresh[houseId] = nil -- (a second visitor's result only stretched it)
	end
	local active = ring :: Ring
	active.seconds.Text = tostring(math.min(math.ceil(left), Economy.DOOR_COOLDOWN))
	-- The time gone sweeps round clockwise from the top, dimming the ring behind it; the segment at
	-- its edge fades over as it goes, so it creeps instead of ticking.
	local gone = math.clamp(1 - left / active.total, 0, 1) * RING.ticks
	for index, tick in active.ticks do
		local passed = math.clamp(gone - (index - 1), 0, 1)
		tick.BackgroundColor3 = TICK_LEFT.color:Lerp(TICK_GONE.color, passed)
		tick.BackgroundTransparency = TICK_LEFT.transparency
			+ (TICK_GONE.transparency - TICK_LEFT.transparency) * passed
	end
end

local function bucketFull(): boolean
	local upgrades = StateController.get("upgrades")
	return upgrades ~= nil and (StateController.get("bucket") or 0) >= Formulas.bucketCapacity(upgrades.bucketTier)
end

-- Bowl, open and seller houses have no door to knock on (a lights-off one has: nobody comes,
-- DoorService).
local function knockable(door: BasePart): boolean
	local model = Houses.of(door)
	local houseType = model and model:GetAttribute("HouseType")
	return houseType ~= "Bowl" and houseType ~= "Open" and houseType ~= "Seller"
end

-- A candy bowl's prompt: how much is left in it, or that your bucket's full.
local function applyBowl(model: Model, full: boolean)
	local bowl = model:FindFirstChild("CandyBowl")
	local take = bowl and bowl:FindFirstChild("TakeAll", true)
	if bowl == nil or take == nil or not take:IsA("ProximityPrompt") then
		return
	end
	local left = (bowl:GetAttribute("Candy") :: number?) or 0
	take.ActionText = if full then "Bucket full" else "Take it all"
	take.ObjectText = if full then "Empty it at your Candy Box" else `Candy bowl · {Format.number(left)} left`
end

local function apply(houseId: string)
	local door = doors[houseId]
	local left = (readyAt[houseId] or 0) - Workspace:GetServerTimeNow()
	local onCooldown = left > 0
	if door then
		local prompt = promptOf(door)
		if prompt then
			prompt.Enabled = not onCooldown and knockable(door)
			local full = bucketFull()
			prompt.ActionText = if full then "Bucket full" else "Knock"
			local model = Houses.of(door)
			local lightsOff = model ~= nil and model:GetAttribute("HouseType") == "LightsOff"
			prompt.ObjectText = if full
				then "Empty it at your Candy Box"
				elseif lightsOff then "Nobody's home..."
				else "Trick or treat!"
		end
	end
	local house = door and Houses.of(door)
	if house then
		applyBowl(house, bucketFull())
	end
	-- Not while they're still at the door: the ring comes once it's shut on them.
	local shut = house == nil or not Homeowner.atDoor(house)
	setBadge(houseId, door, if onCooldown and shut then left else nil)
	if not onCooldown then
		readyAt[houseId] = nil
	end
end

local function track(door: Instance)
	local houseId = door:GetAttribute("HouseId")
	if type(houseId) == "string" and door:IsA("BasePart") then
		doors[houseId] = door
		local model = Houses.of(door)
		if model then
			model:GetAttributeChangedSignal("HouseType"):Connect(function()
				apply(houseId)
			end)
			-- The house's cooldown, everyone's (DoorService): a new one starts its ring full.
			model:GetAttributeChangedSignal("ReadyAt"):Connect(function()
				readyAt[houseId] = model:GetAttribute("ReadyAt") :: number?
				fresh[houseId] = true
				apply(houseId)
			end)
			readyAt[houseId] = model:GetAttribute("ReadyAt") :: number?
			-- A bowl put out (every Dawn), and the candy going out of it.
			local function watchBowl(child: Instance)
				if child.Name == "CandyBowl" then
					child:GetAttributeChangedSignal("Candy"):Connect(function()
						apply(houseId)
					end)
					apply(houseId)
				end
			end
			model.ChildAdded:Connect(watchBowl)
			local bowl = model:FindFirstChild("CandyBowl")
			if bowl then
				watchBowl(bowl)
			end
		end
		apply(houseId)
	end
end

local function untrack(door: Instance)
	local houseId = door:GetAttribute("HouseId")
	if type(houseId) == "string" and doors[houseId] == door then
		doors[houseId] = nil
		setBadge(houseId, nil, nil)
	end
end

function DoorController.getDoor(houseId: string): BasePart?
	return doors[houseId]
end

-- The farthest clear spot straight out from the door, `near` to `far` studs, with floor about
-- level with its sill; failing that, the farthest down the stoop. Clear: nothing solid between it
-- and the door.
local function doorstep(bottom: Vector3, out: Vector3, character: Model, near: number, far: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true -- the houses' invisible colliders, not their meshes
	local from = bottom + out * 0.8 + Vector3.new(0, 2.5, 0)
	local below: Vector3? = nil
	for distance = far, near, -0.5 do
		local spot = bottom + out * distance
		local ground = Workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -3 - DOORSTEP.drop, 0), params)
		if ground == nil or ground.Position.Y > bottom.Y + 0.5 then
			continue
		end
		local to = Vector3.new(spot.X, bottom.Y + 2.5, spot.Z)
		if Workspace:Raycast(from, to - from, params) ~= nil then
			continue
		end
		local stand = Vector3.new(spot.X, ground.Position.Y, spot.Z)
		if ground.Position.Y >= bottom.Y - DOORSTEP.level then
			return stand
		end
		below = below or stand
	end
	return below
end

local function personalityOf(house: Model): Dialogue.Personality?
	return Dialogue.personalities[house:GetAttribute("Owner") :: string]
end

-- A homeowner says something (the server decides what and when, for everyone near the door): at
-- `showAt` (server time), once they're out on the porch (a long hall can keep them: the line waits
-- for them). A newer line replaces one still to come; walking away from your visit drops it.
local lines: { [Model]: number } = {} -- each house's latest line to come (a ticket)

local function onSay(houseId: any, text: any, showAt: any, except: any)
	if type(houseId) ~= "string" or type(text) ~= "string" or type(showAt) ~= "number" then
		return
	end
	if except == Players.LocalPlayer.UserId then
		return -- yours comes another way (the Costume Line question, with its answers)
	end
	local door = doors[houseId]
	local house = door and Houses.of(door)
	if house == nil then
		return
	end
	local ticket = (lines[house] or 0) + 1
	lines[house] = ticket
	task.delay(math.max(0, showAt - Workspace:GetServerTimeNow()), function()
		local still = Homeowner.arrivesIn(house)
		if still and still > 0 then
			task.wait(math.min(still, 2) + 0.2)
		end
		local personality = personalityOf(house)
		if personality and lines[house] == ticket and house:GetAttribute("OwnerOut") == true then
			Dialog.say(house, text, personality.voice)
			Homeowner.talk(house, Dialogue.lineTime(text) * 0.75) -- gesturing while the words come
		end
	end)
end

-- How far round your head is turned, `t` seconds after a slap (0..1 of HIT.turn).
local function headTurn(t: number): number
	if t < HIT.snap then
		return 1 - (1 - t / HIT.snap) ^ 2
	elseif t < HIT.snap + HIT.hold then
		return 1
	end
	local back = math.clamp((t - HIT.snap - HIT.hold) / HIT.back, 0, 1)
	return 1 - back * back * (3 - 2 * back)
end

-- The slap lands: your head snaps round the way the hand was going (their `hand`: their right hand
-- comes from your left, so you're turned to your right), a small shake, red from the edges (unless
-- Settings say no flashes), and you're shoved back off the door.
local function hit(door: BasePart, hand: string?)
	look = nil -- your head goes with the slap, not back to them
	Sound.play("Slap")
	local camera = Workspace.CurrentCamera
	if camera then
		local direction = if hand == "Left" then 1 else -1 -- +1 turns you left
		local started = os.clock()
		local turned = 0 -- how far round the view has been turned so far (the camera keeps it)
		local name = "SlapTurn" .. tostring(started)
		-- After the camera has moved: the turn goes on its look (it keeps that, so only what's
		-- changed since last frame is added), the tilt and shake on top (it drops those).
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
			local t = os.clock() - started
			local amount = headTurn(t)
			local want = math.rad(HIT.turn) * amount * direction
			local at = camera.CFrame
			camera.CFrame = CFrame.new(at.Position) * CFrame.Angles(0, want - turned, 0) * at.Rotation
			turned = want
			local fade = math.max(0, 1 - t / HIT.shake) * HIT.strength
			camera.CFrame *= CFrame.new((math.random() - 0.5) * fade, (math.random() - 0.5) * fade, 0) * CFrame.Angles(
				0,
				0,
				-math.rad(HIT.tilt) * amount * direction
			)
			if t > HIT.snap + HIT.hold + HIT.back then
				RunService:UnbindFromRenderStep(name)
			end
		end)
	end
	local settings = StateController.get("settings") or {}
	if settings.reduceFlash ~= true then
		hitFlash.BackgroundTransparency = 0.2
		TweenService:Create(hitFlash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	end
	-- Shoved back for a moment (one push alone, the walk controller cancels at once).
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local away = if root then (root.Position - door.Position) * Vector3.new(1, 0, 1) else Vector3.zero
	if root and away.Magnitude > 0.1 then
		local direction = away.Unit
		root.AssemblyLinearVelocity = direction * HIT.knock + Vector3.new(0, HIT.lift, 0)
		local started = os.clock()
		local push: RBXScriptConnection
		push = RunService.Heartbeat:Connect(function()
			local t = os.clock() - started
			if t > HIT.push or root.Parent == nil then
				push:Disconnect()
				return
			end
			local velocity = root.AssemblyLinearVelocity
			local speed = HIT.knock * (1 - t / HIT.push)
			root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, velocity.Y, 0)
		end)
	end
end

-- Someone got it wrong at a door (the server says, for everyone near): its homeowner slaps them.
-- If it's you, your head goes with it; everyone else hears it land.
local function onStrike(houseId: any, userId: any)
	local door = if type(houseId) == "string" then doors[houseId] else nil
	local house = door and Houses.of(door)
	if door == nil or house == nil then
		return
	end
	local landsIn, hand = Homeowner.strike(house)
	if landsIn == nil then
		return
	end
	if userId == Players.LocalPlayer.UserId then
		task.delay(landsIn, hit, door, hand)
		return
	end
	local victim = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local character = victim and victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		task.delay(landsIn, function()
			Sound.play("Slap", { at = root })
		end)
	end
end

-- Your knock was answered: step back to where you'll see all of whoever opens it, and keep your eyes
-- on them (until you look or walk away yourself: you're free to move about the doorstep).
local function onAnswered(houseId: string)
	local door = doors[houseId]
	local house = door and Houses.of(door)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if door == nil or house == nil or character == nil or humanoid == nil or root == nil then
		return
	end
	local frame = Homeowner.doorFrame(door) -- where it hangs closed (a real door may be swinging)
	local bottom = (frame * CFrame.new(0, -door.Size.Y / 2, 0)).Position
	local out = (frame.LookVector * Vector3.new(1, 0, 1)).Unit
	local owner = house:GetAttribute("OwnerModel")
	local height = Homeowner.heightOf(if type(owner) == "string" then owner else "")
	local want = math.clamp(DOORSTEP.view + height * DOORSTEP.perHeight, DOORSTEP.near, DOORSTEP.far)
	local spot = doorstep(bottom, out, character, math.max(DOORSTEP.near, want - 1.5), want)
	if spot and (Vector3.new(root.Position.X, spot.Y, root.Position.Z) - spot).Magnitude > 0.6 then
		humanoid:MoveTo(spot) -- walks there unless you walk yourself; your view stays on the door
	end
	-- Until they're out, look about where a face will be: in the doorway, at their height.
	look = {
		house = house,
		houseId = houseId,
		guess = bottom + out * 1.2 + Vector3.new(0, math.min(height, door.Size.Y) * 0.85, 0),
		untilAt = math.huge,
		moved = 0,
	}
end

-- The visit's over (a result, or you walked away): your view is yours again shortly after.
local function releaseLook(houseId: string?, after: number)
	local active = look
	if active and (houseId == nil or active.houseId == houseId) then
		active.untilAt = math.min(active.untilAt, os.clock() + after)
	end
end

local function steerLook(dt: number)
	local active = look
	if active == nil then
		return
	end
	local camera = Workspace.CurrentCamera
	if os.clock() > active.untilAt or camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		look = nil
		return
	end
	local target = (Homeowner.face(active.house) or active.guess) - Vector3.new(0, LOOK_BELOW, 0)
	if active.house:GetAttribute("OwnerOut") ~= true and Homeowner.face(active.house) == nil then
		active.untilAt = math.min(active.untilAt, os.clock() + LOOK_AFTER) -- they've gone back in
	end
	local at = camera.CFrame
	local want = CFrame.lookAt(at.Position, target)
	camera.CFrame = CFrame.new(at.Position) * at.Rotation:Lerp(want.Rotation, 1 - math.exp(-dt * 6))
end

function DoorController.Init()
	ringFolder = create("Folder", { Name = "DoorRings", Parent = Workspace })
	hitFlash = create("Frame", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("B0101A"),
		BackgroundTransparency = 1,
		-- Red at the edges, clear in the middle.
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.8),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	local gui = create("ScreenGui", {
		Name = "DoorHit",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 85,
		hitFlash,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
end

function DoorController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Door"):Connect(untrack)
	for _, door in CollectionService:GetTagged("Door") do
		track(door)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "Door") then
			Sound.play(if bucketFull() then "Miss" else "Knock")
		end
	end)

	-- A door mini-game starting means your knock was answered.
	Net.event("MinigameStart").OnClientEvent:Connect(function(challenge: any)
		local context = type(challenge) == "table" and challenge.context
		if type(context) == "table" and type(context.houseId) == "string" then
			onAnswered(context.houseId)
		end
	end)
	Net.event("HomeownerSay").OnClientEvent:Connect(onSay)
	Net.event("HomeownerStrike").OnClientEvent:Connect(onStrike)
	-- Someone did well at a door: its homeowner hands them their candy (you: it flies to your bucket
	-- down at the bottom of your view; anyone else: to theirs).
	Net.event("HomeownerGive").OnClientEvent:Connect(function(houseId: any, userId: any, grade: any)
		local door = if type(houseId) == "string" then doors[houseId] else nil
		local house = door and Houses.of(door)
		local receiver = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		if house == nil or receiver == nil then
			return
		end
		if grade == "PERFECT" then
			-- A slow clap first, then your candy.
			Homeowner.clap(house)
			task.wait(CLAP_FIRST)
		end
		local character = receiver.Character
		local bucket = character and character:FindFirstChild("Bucket") :: Model?
		Homeowner.give(house, function(): Vector3?
			if receiver == Players.LocalPlayer then
				local camera = Workspace.CurrentCamera
				return camera and (camera.CFrame * CFrame.new(0.9, -1.1, -1.6)).Position
			end
			local root = receiver.Character and receiver.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			return root and root.Position
		end, bucket)
	end)
	-- You walked away: no hello, nothing more said, your view is yours again.
	Minigame.abandoned:Connect(function(houseId: string?)
		local door = if houseId then doors[houseId] else nil
		local house = door and Houses.of(door)
		look = nil -- you broke away: your view is yours at once
		if house then
			lines[house] = (lines[house] or 0) + 1
			Dialog.hush(house)
		end
	end)
	-- Look about (the mouse, the right stick) and your view is yours again; their lines go too.
	UserInputService.InputChanged:Connect(function(input)
		local active = look
		if active == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			active.moved += input.Delta.Magnitude
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.5 then
			active.moved = LOOK_FREE
		end
		if active.moved >= LOOK_FREE then
			look = nil
		end
	end)
	-- After the camera (and its PSX sway) has moved, so the camera picks up where this leaves it.
	RunService:BindToRenderStep("DoorstepLook", Enum.RenderPriority.Camera.Value + 2, steerLook)

	Net.event("DoorResult").OnClientEvent:Connect(function(result: any)
		releaseLook(result.houseId, LOOK_AFTER)
	end)
	-- Someone else knocked: you hear it at their door.
	Net.event("DoorKnocked").OnClientEvent:Connect(function(houseId: any, userId: any)
		local door = if type(houseId) == "string" then doors[houseId] else nil
		if door and userId ~= Players.LocalPlayer.UserId then
			Sound.play("Knock", { at = door })
		end
	end)
	-- Someone else got a scare: whoever's at their door goes for them (a "caught" scare only gets
	-- the scream), loud from the door. Theirs is the jumpscare (JumpscareController).
	Net.event("ScareSeen").OnClientEvent:Connect(function(houseId: any, userId: any, kind: any)
		local door = if type(houseId) == "string" then doors[houseId] else nil
		local house = door and Houses.of(door)
		if door == nil or house == nil or userId == Players.LocalPlayer.UserId then
			return
		end
		Homeowner.lunge(house)
		Sound.play(if kind == "caught" then "GhostWail" else "Stinger", { at = door, volume = 0.6 })
	end)

	-- The bucket filling up (or emptied at the Candy Box) changes what every door says.
	local wasFull: boolean? = nil
	local function onBucket()
		local full = bucketFull()
		if full ~= wasFull then
			wasFull = full
			for houseId in doors do
				apply(houseId)
			end
		end
	end
	StateController.observe("bucket", onBucket)
	StateController.observe("upgrades", onBucket)

	while true do
		task.wait(0.25)
		for houseId in readyAt do
			apply(houseId)
		end
	end
end

return DoorController
