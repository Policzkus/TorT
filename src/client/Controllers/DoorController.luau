--!strict
-- Client side of doors: knock sound, the doorstep shot (when someone answers your knock you step
-- back off the door and look up at them), what they say to you (a hello once they're out, then how
-- they took your mini-game; DialogController), and a 💤 countdown over houses you've already
-- visited (only you see it). Doors stream in and out, so state is kept by house id and reapplied.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Dialogue = require(ReplicatedStorage:WaitForChild("Shared").Config.Dialogue)
local Homeowners = require(ReplicatedStorage:WaitForChild("Shared").Config.Homeowners)
local Houses = require(ReplicatedStorage:WaitForChild("Shared").Modules.Houses)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Dialog = require(script.Parent.DialogController)
local Homeowner = require(script.Parent.HomeownerController)
local Minigame = require(script.Parent.MinigameController)
local Sound = require(script.Parent.SoundController)
local Chip = require(script.Parent.Parent.UI.Components.Chip)
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

local doors: { [string]: BasePart } = {}
local readyAt: { [string]: number } = {}
local badges: { [string]: BillboardGui } = {}
-- Your view, held on whoever answered for the whole visit (until `untilAt`, set when it's over).
local look: { house: Model, houseId: string, guess: Vector3, untilAt: number }? = nil

local function promptOf(door: BasePart): ProximityPrompt?
	return door:FindFirstChildOfClass("ProximityPrompt")
end

local function setBadge(houseId: string, door: BasePart?, secondsLeft: number?)
	local badge = badges[houseId]
	if secondsLeft == nil or door == nil then
		if badge then
			badge:Destroy()
			badges[houseId] = nil
		end
		return
	end
	if badge == nil or badge.Parent ~= door then
		if badge then
			badge:Destroy()
		end
		badge = create("BillboardGui", {
			Name = "Cooldown",
			Size = UDim2.fromOffset(120, 30),
			StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0),
			MaxDistance = 90,
			LightInfluence = 0,
			Adornee = door,
			Parent = door,
		})
		Chip.new({ name = "Chip", color = Theme.Colors.TextDim, parent = badge })
		badges[houseId] = badge
	end
	local text = (badge :: BillboardGui):FindFirstChild("Text", true) :: TextLabel
	text.Text = `💤 {math.ceil(secondsLeft :: number)}s`
end

-- Lights-off, bowl and open houses never answer the door.
local function answers(door: BasePart): boolean
	local model = Houses.of(door)
	local houseType = model and model:GetAttribute("HouseType")
	return houseType ~= "LightsOff" and houseType ~= "Bowl" and houseType ~= "Open"
end

local function apply(houseId: string)
	local door = doors[houseId]
	local left = (readyAt[houseId] or 0) - Workspace:GetServerTimeNow()
	local onCooldown = left > 0
	if door then
		local prompt = promptOf(door)
		if prompt then
			prompt.Enabled = not onCooldown and answers(door)
		end
	end
	setBadge(houseId, door, if onCooldown then left else nil)
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

-- Once they're out (`outIn` seconds after the knock was answered), they say hello; the mini-game
-- waits for it (Costume Line's question does that job itself).
local greetings: { [Model]: number } = {} -- the hello each house is about to say (cancelled if you leave)

local function greet(house: Model, outIn: number?)
	local style = house:GetAttribute("OwnerStyle")
	local wait = outIn or Homeowners.OUT_AFTER[if type(style) == "string" then style else "Creep"] or 2.4
	local ticket = (greetings[house] or 0) + 1
	greetings[house] = ticket
	task.delay(wait + 0.3, function()
		local still = Homeowner.arrivesIn(house) -- a long hall can keep them: the hello waits for them
		if still and still > 0 then
			task.wait(math.min(still, 2) + 0.2)
		end
		local personality = personalityOf(house)
		if personality and greetings[house] == ticket and house:GetAttribute("OwnerOut") == true then
			Dialog.say(house, personality.hello[math.random(1, #personality.hello)], personality.voice)
		end
	end)
end

-- What they make of how it went. A trick house's Nerve Hold ends in the jumpscare instead.
local function react(result: any)
	if result.houseType == "Trick" or result.bowl ~= nil then
		return
	end
	local door = doors[result.houseId]
	local house = door and Houses.of(door)
	local personality = house and personalityOf(house)
	if house and personality then
		local lines = if result.grade == "MISS" then personality.displeased else personality.pleased
		task.delay(0.35, function()
			Dialog.say(house, lines[math.random(1, #lines)], personality.voice)
		end)
	end
end

-- Your knock was answered: step back to where you'll see all of whoever opens it (held there: the
-- mini-game holds your movement), and keep your eyes on them.
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
		humanoid:MoveTo(spot) -- walks there with movement held; your view stays on the door
	end
	-- Until they're out, look about where a face will be: in the doorway, at their height.
	look = {
		house = house,
		houseId = houseId,
		guess = bottom + out * 1.2 + Vector3.new(0, math.min(height, door.Size.Y) * 0.85, 0),
		untilAt = math.huge,
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

function DoorController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Door"):Connect(untrack)
	for _, door in CollectionService:GetTagged("Door") do
		track(door)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "Door") then
			Sound.play("Knock")
		end
	end)

	-- A door mini-game starting means your knock was answered.
	Net.event("MinigameStart").OnClientEvent:Connect(function(challenge: any)
		local context = type(challenge) == "table" and challenge.context
		if type(context) == "table" and type(context.houseId) == "string" then
			onAnswered(context.houseId)
			local door = doors[context.houseId]
			local house = door and Houses.of(door)
			if house and challenge.kind ~= "CostumeLine" then
				greet(house, if type(context.outIn) == "number" then context.outIn else nil)
			end
		end
	end)
	-- You walked away: no hello, nothing more said, your view is yours again.
	Minigame.abandoned:Connect(function(houseId: string?)
		local door = if houseId then doors[houseId] else nil
		local house = door and Houses.of(door)
		look = nil -- you broke away: your view is yours at once
		if house then
			greetings[house] = (greetings[house] or 0) + 1
			Dialog.hush(house)
		end
	end)
	-- After the camera (and its PSX sway) has moved, so the camera picks up where this leaves it.
	RunService:BindToRenderStep("DoorstepLook", Enum.RenderPriority.Camera.Value + 2, steerLook)

	Net.event("DoorResult").OnClientEvent:Connect(function(result: any)
		releaseLook(result.houseId, LOOK_AFTER)
		readyAt[result.houseId] = result.cooldownUntil
		apply(result.houseId)
		react(result)
	end)
	-- Dawn: every door is ready again.
	Net.event("CooldownsReset").OnClientEvent:Connect(function()
		local ids = {}
		for houseId in readyAt do
			table.insert(ids, houseId)
		end
		table.clear(readyAt)
		for _, houseId in ids do
			apply(houseId)
		end
	end)

	while true do
		task.wait(0.5)
		for houseId in readyAt do
			apply(houseId)
		end
	end
end

return DoorController
