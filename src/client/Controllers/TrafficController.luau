--!strict
-- Draws the car (Config/Traffic) wherever the server sends one (CarTrip): a copy of
-- ReplicatedStorage.Assets.Vehicles.Car comes out of the mist at one end of the street, its
-- headlights wavering, the engine rumbling, wheels turning, drives the street's length on the same
-- path the server checks for hits (Traffic.pose, on server time) and goes back into the mist at the
-- other end. It honks when the server says (CarHonk: someone's in front of it). Someone hit
-- (CarHit): a deep thud, their candy thrown out of their bucket across the road, and if it's you a
-- red flash and what it cost you. Everything left to chance (the flicker, the engine, the thrown
-- candy) comes from the server's seeds, so every player sees and hears the same car.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Traffic = require(Shared.Config.Traffic)
local CandyPiece = require(Shared.Modules.CandyPiece)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local NotificationController = require(script.Parent.NotificationController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Scale = require(script.Parent.Parent.UI.Scale)
local create = require(script.Parent.Parent.UI.create)

local TrafficController = {}

local ENGINE = { near = 14, far = 260, speed = 0.92 } -- studs it rolls off over; its pitch
local FLICKER = { every = 0.07, low = 0.72 } -- the old headlights waver this often, down to this
local BURST = { most = 14, out = { 10, 20 }, up = { 18, 30 }, life = 1.8, fade = 0.4, gravity = 75, bounce = 0.35 }
local CANDY_COLORS = { "FF3B5C", "7CFF4F", "FFD23F", "B06CFF", "3FC8FF", "FF8A00" }

type Piece = { part: BasePart, offset: CFrame, base: number, wheel: number? }
type Car = {
	trip: Traffic.Trip,
	model: Model,
	parts: { BasePart }, -- the same order as pieces (for BulkMoveTo)
	pieces: { Piece },
	wheels: { { offset: CFrame, radius: number } },
	lights: { { light: Light, brightness: number } },
	engine: Sound?,
	body: BasePart,
	shown: number, -- how far out of the mist it's drawn
	flicker: number,
	flickerStep: number,
}

local cars: { [number]: Car } = {}
local folder: Folder
local flash: Frame

local function template(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vehicles = assets and assets:FindFirstChild("Vehicles")
	local car = vehicles and vehicles:FindFirstChild("Car")
	return if car and car:IsA("Model") then car else nil
end

local function remove(id: number)
	local car = cars[id]
	if car then
		car.model:Destroy()
		cars[id] = nil
	end
end

local function onTrip(trip: any)
	if type(trip) ~= "table" or type(trip.id) ~= "number" or typeof(trip.street) ~= "CFrame" or cars[trip.id] then
		return
	end
	local source = template()
	if source == nil then
		return
	end
	local model = source:Clone()
	local pivot = model:GetPivot()
	local wheels: { { offset: CFrame, radius: number } } = {}
	local wheelOf: { [Instance]: number } = {}
	for _, child in model:GetChildren() do
		local radius = child:GetAttribute("Radius")
		if child:IsA("Model") and type(radius) == "number" then
			table.insert(wheels, { offset = pivot:ToObjectSpace(child:GetPivot()), radius = radius })
			wheelOf[child] = #wheels
		end
	end
	local pieces: { Piece } = {}
	local parts: { BasePart } = {}
	local lights: { { light: Light, brightness: number } } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local wheel = item.Parent and wheelOf[item.Parent]
			local frame = if wheel then (item.Parent :: Model):GetPivot() else pivot
			table.insert(
				pieces,
				{ part = item, offset = frame:ToObjectSpace(item.CFrame), base = item.Transparency, wheel = wheel }
			)
			table.insert(parts, item)
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Transparency = 1
		elseif item:IsA("Light") then
			table.insert(lights, { light = item, brightness = item.Brightness })
			item.Brightness = 0
		end
	end
	local body = (model.PrimaryPart or parts[1]) :: BasePart
	local engine: Sound? = nil
	local cfg = Sounds.CarEngine
	if cfg and cfg.id then
		local sound = Instance.new("Sound")
		sound.Name = "Engine"
		sound.SoundId = "rbxassetid://" .. cfg.id
		sound.Looped = true
		sound.Volume = 0
		sound.PlaybackSpeed = ENGINE.speed * (trip.speed / Traffic.SPEED[2]) ^ 0.5
		sound.TimePosition = Random.new(trip.seed or 0):NextNumber(0, 20)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ENGINE.near
		sound.RollOffMaxDistance = ENGINE.far
		sound.SoundGroup = Sound.group("SFX")
		sound.Parent = body
		engine = sound
	end
	model.Parent = folder
	if engine then
		engine:Play()
	end
	cars[trip.id] = {
		trip = trip :: Traffic.Trip,
		model = model,
		parts = parts,
		pieces = pieces,
		wheels = wheels,
		lights = lights,
		engine = engine,
		body = body,
		shown = 0,
		flicker = 1,
		flickerStep = -1,
	}
end

-- The server heard it honk (someone's in front of it).
local function onHonk(id: any)
	local car = if type(id) == "number" then cars[id] else nil
	if car then
		Sound.play("CarHorn", { at = car.body })
	end
end

local function step()
	local now = Workspace:GetServerTimeNow()
	for id, car in cars do
		local t = now - car.trip.startAt
		if t > Traffic.duration(car.trip) + 0.2 or car.model.Parent == nil then
			remove(id)
			continue
		end
		local presence = if t < 0 then 0 else Traffic.presence(car.trip, t)
		local pose, driven = Traffic.pose(car.trip, math.max(t, 0))
		-- The body where the path says, each wheel turned by how far it's rolled.
		local turned = table.create(#car.wheels)
		for i, wheel in car.wheels do
			turned[i] = pose * wheel.offset * CFrame.Angles(-driven / wheel.radius, 0, 0)
		end
		local frames = table.create(#car.pieces)
		for i, piece in car.pieces do
			frames[i] = (if piece.wheel then turned[piece.wheel] else pose) * piece.offset
		end
		Workspace:BulkMoveTo(car.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		if presence ~= car.shown then
			car.shown = presence
			for _, piece in car.pieces do
				piece.part.Transparency = 1 - (1 - piece.base) * presence
			end
		end
		-- The old headlights waver: the same waver on every screen (the trip's seed, server time).
		local flickerStep = math.floor(now / FLICKER.every)
		if flickerStep ~= car.flickerStep then
			car.flickerStep = flickerStep
			car.flicker = Random.new((car.trip.seed or 0) + flickerStep):NextNumber(FLICKER.low, 1)
		end
		for _, entry in car.lights do
			entry.light.Brightness = entry.brightness * presence * car.flicker
		end
		if car.engine then
			car.engine.Volume = Sounds.CarEngine.volume * presence
		end
	end
end

-- Candy flying out of a hit bucket, bouncing across the road, then gone (thrown the same way on
-- every screen: the server's `seed`).
local function burst(character: Model, lost: number, seed: number)
	local throw = Random.new(seed)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local bucket = character:FindFirstChild("Bucket")
	if root == nil then
		return
	end
	local sources: { BasePart } = {}
	if bucket then
		for _, item in bucket:GetDescendants() do
			if item:IsA("BasePart") and item.Name:sub(1, 5) == "Candy" then
				table.insert(sources, item)
			end
		end
	end
	local from = if bucket and bucket:IsA("Model") then bucket:GetPivot().Position else root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder }
	local hit = Workspace:Raycast(from, Vector3.new(0, -30, 0), params)
	local floor = if hit then hit.Position.Y + 0.2 else from.Y - 3
	type Flying = { part: BasePart, at: Vector3, velocity: Vector3, spin: CFrame }
	local flying: { Flying } = {}
	for i = 1, math.clamp(3 + math.floor(lost / 4), 3, BURST.most) do
		local source = if #sources > 0 then sources[(i - 1) % #sources + 1] else nil
		local candy: BasePart
		if source then
			candy = source:Clone()
			for _, item in candy:GetDescendants() do
				if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
					item:Destroy() -- (it was held in the bucket)
				end
			end
		else
			candy = CandyPiece.make(0.45, Color3.fromHex(CANDY_COLORS[(i - 1) % #CANDY_COLORS + 1]))
		end
		candy.Name = "ThrownCandy"
		candy.Anchored = true
		candy.CanCollide = false
		candy.CanQuery = false
		candy.CanTouch = false
		candy.Transparency = 0
		candy.LocalTransparencyModifier = 0
		candy.Parent = folder
		local angle = throw:NextNumber(0, math.pi * 2)
		local out = throw:NextNumber(BURST.out[1], BURST.out[2])
		table.insert(flying, {
			part = candy,
			at = from,
			velocity = Vector3.new(
				math.cos(angle) * out,
				throw:NextNumber(BURST.up[1], BURST.up[2]),
				math.sin(angle) * out
			),
			spin = CFrame.Angles(throw:NextNumber(-0.3, 0.3), throw:NextNumber(-0.3, 0.3), throw:NextNumber(-0.3, 0.3)),
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		local fade = math.clamp((t - (BURST.life - BURST.fade)) / BURST.fade, 0, 1)
		for _, piece in flying do
			piece.velocity -= Vector3.new(0, BURST.gravity * dt, 0)
			local at = piece.at + piece.velocity * dt
			if at.Y < floor then
				at = Vector3.new(at.X, floor, at.Z)
				piece.velocity =
					Vector3.new(piece.velocity.X * 0.5, -piece.velocity.Y * BURST.bounce, piece.velocity.Z * 0.5)
			end
			piece.at = at
			piece.part.CFrame = CFrame.new(at) * piece.part.CFrame.Rotation * piece.spin
			piece.part.Transparency = fade
		end
		if t >= BURST.life then
			connection:Disconnect()
			for _, piece in flying do
				piece.part:Destroy()
			end
		end
	end)
end

-- `lost` candy thrown out of `character`'s bucket (the same throw for everyone from the same `seed`):
-- also a homeowner taking back their bowl's candy (OwnerChaseController).
function TrafficController.spill(character: Model, lost: number, seed: number)
	burst(character, lost, seed)
end

local function onHit(userId: any, lost: any, seed: any)
	local victim = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local amount = if type(lost) == "number" then lost else 0
	local character = victim and victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and root then
		Sound.play("CarHit", { at = root })
		Sound.play("Thud", { at = root, volume = 0.7, speed = 0.8 })
		if amount > 0 then
			burst(character, amount, if type(seed) == "number" then seed else 0)
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
		if amount > 0 then `Run over! -{Format.number(amount)} candy from your bucket` else "Run over!",
		"error"
	)
end

function TrafficController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = Workspace
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
	local gui = create("ScreenGui", {
		Name = "CarHit",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 85,
		flash,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
end

function TrafficController.Start()
	Net.event("CarTrip").OnClientEvent:Connect(onTrip)
	Net.event("CarHit").OnClientEvent:Connect(onHit)
	Net.event("CarHonk").OnClientEvent:Connect(onHonk)
	RunService.RenderStepped:Connect(step)
end

return TrafficController
