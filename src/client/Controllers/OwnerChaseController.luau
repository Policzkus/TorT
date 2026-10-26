--!strict
-- A homeowner out after the kid who emptied their candy bowl (OwnerChaseService runs them;
-- Config/Bowl), as you see and hear them: their heavy steps wherever they go, what they shout over
-- their head (coming out of the door, and when they've got you), the sting as they come out and the
-- chase music while it's you they're after, and the catch: the thief thrown down and the candy flying
-- out of their bucket (TrafficController.spill), and if it's you, red at the edges and what it cost.
-- How they move is CharacterAnimController's (a kid's walk and run; arms out to grab while chasing).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local MusicController = require(script.Parent.MusicController)
local NotificationController = require(script.Parent.NotificationController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local TrafficController = require(script.Parent.TrafficController)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local OwnerChaseController = {}

local STEP = { walk = 3, run = 4.4, running = 14 } -- studs between their steps walking and running (faster than `running` studs/s)
local SHOUT = { time = 2.6, recent = 2, blips = 4 } -- seconds over their head; a shout older than `recent` isn't shown; voice blips
local HUNTING = { burst = true, chase = true, investigate = true, search = true } -- states while they're after the thief

type Tracked = {
	model: Model,
	root: BasePart,
	last: Vector3,
	travelled: number, -- since their last step
	speed: number,
	bubble: BillboardGui?,
}

local tracked: { [Model]: Tracked } = {}
local flash: Frame
local random = Random.new()

-- What they shouted, over their head for a moment, the voice blipping out the words.
local function shout(him: Tracked)
	local text = him.model:GetAttribute("Shout")
	local at = him.model:GetAttribute("ShoutAt")
	if type(text) ~= "string" or type(at) ~= "number" or Workspace:GetServerTimeNow() - at > SHOUT.recent then
		return
	end
	if him.bubble then
		him.bubble:Destroy()
	end
	local head = him.model:FindFirstChild("Head")
	local label = create("TextLabel", {
		Name = "Line",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = text,
		TextColor3 = Theme.Colors.Danger,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		TextScaled = true,
	})
	local bubble = create("BillboardGui", {
		Name = "Shout",
		Size = UDim2.fromOffset(320, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
		MaxDistance = 90,
		LightInfluence = 0,
		Adornee = if head and head:IsA("BasePart") then head else him.root,
		label,
		Parent = him.model,
	})
	him.bubble = bubble
	for k = 0, SHOUT.blips - 1 do
		task.delay(k * 0.09, function()
			if him.root.Parent then
				Sound.play("Voice", { at = him.root, volume = 1.4, speed = random:NextNumber(0.6, 0.75) })
			end
		end)
	end
	task.delay(SHOUT.time, function()
		if him.bubble == bubble then
			him.bubble = nil
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.3, function()
				bubble:Destroy()
			end)
		end
	end)
end

local function add(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	local model = instance
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root == nil or model.Parent == nil then
		return
	end
	local him: Tracked = { model = model, root = root, last = root.Position, travelled = 0, speed = 0, bubble = nil }
	tracked[model] = him
	model:GetAttributeChangedSignal("ShoutAt"):Connect(function()
		shout(him)
	end)
	shout(him)
	-- Out of the door after you: the sting.
	if model:GetAttribute("Thief") == Players.LocalPlayer.UserId and model:GetAttribute("State") == "burst" then
		Sound.play("Stinger")
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer.UserId
	local chased = false
	for model, him in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			continue
		end
		-- Heavy steps, longer strides running.
		local moved = (him.root.Position - him.last) * Vector3.new(1, 0, 1)
		him.last = him.root.Position
		if moved.Magnitude < 8 then
			him.travelled += moved.Magnitude
			him.speed += (moved.Magnitude / math.max(dt, 1e-3) - him.speed) * math.min(1, dt * 8)
		end
		local stride = if him.speed > STEP.running then STEP.run else STEP.walk
		if him.travelled >= stride then
			him.travelled = 0
			Sound.play("OwnerStep", {
				at = him.root,
				volume = if him.speed > STEP.running then 1.5 else 1.1,
				speed = random:NextNumber(0.85, 1.05),
			})
		end
		if model:GetAttribute("Thief") == me and HUNTING[model:GetAttribute("State") :: string] then
			chased = true
		end
	end
	MusicController.setChase("owner", chased)
end

-- A homeowner got the kid who took their bowl: down they go, and the candy flies out of their bucket.
local function onGrab(_houseId: any, userId: any, lost: any, seed: any)
	local victim = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local amount = if type(lost) == "number" then lost else 0
	local character = victim and victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and root then
		Sound.play("Slap", { at = root, volume = 1.2 })
		Sound.play("Thud", { at = root, volume = 0.8, speed = 0.9 })
		if amount > 0 then
			TrafficController.spill(character, amount, if type(seed) == "number" then seed else 0)
		end
	end
	if victim ~= Players.LocalPlayer then
		return
	end
	local settings = StateController.get("settings") or {}
	if settings.reduceFlash ~= true then
		flash.BackgroundTransparency = 0.15
		TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	end
	NotificationController.show(
		if amount > 0
			then `Caught! They took back all your candy: -{Format.number(amount)}`
			else "Caught! Lucky your bucket was empty",
		"error"
	)
end

function OwnerChaseController.Init()
	flash = create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("B0101A"),
		BackgroundTransparency = 1,
		-- Red at the edges, clear in the middle.
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.75),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	create("ScreenGui", {
		Name = "OwnerChase",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 85,
		flash,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

function OwnerChaseController.Start()
	CollectionService:GetInstanceAddedSignal("OwnerChaser"):Connect(function(model)
		task.spawn(add, model)
	end)
	for _, model in CollectionService:GetTagged("OwnerChaser") do
		task.spawn(add, model)
	end
	Net.event("OwnerGrab").OnClientEvent:Connect(onGrab)
	RunService.Heartbeat:Connect(step)
end

return OwnerChaseController
