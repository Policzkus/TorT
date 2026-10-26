--!strict
-- The cars (Config/Traffic): every few minutes two drive down a street someone's on, one each way, the
-- second a moment after the first (or, now and then, the moment someone steps into the road). The server picks each trip and tells every client (CarTrip), and
-- checks it against everyone itself: whoever a car hits is thrown and ragdolled (RagdollService) and
-- loses everything in their bucket, and everyone sees it (CarHit, PlayerPop). Only runs once the car is in the place
-- (ReplicatedStorage.Assets.Vehicles.Car, tools/setup_car.luau): nobody gets hit by a car nobody
-- can see.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Traffic = require(ReplicatedStorage.Shared.Config.Traffic)
local World = require(ReplicatedStorage.Shared.Config.World)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CandyService = require(script.Parent.CandyService)
local HealthService = require(script.Parent.HealthService)
local RagdollService = require(script.Parent.RagdollService)
local WorldService = require(script.Parent.WorldService)

local TrafficService = {}

local ROAD_TOP = 0.2 -- studs over the street's start the road's top is, unless a ray says otherwise

type Active = { trip: Traffic.Trip, hit: { [Player]: boolean }, honks: number, honkedAt: number }

local random = Random.new()
local active: { [number]: Active } = {}
local nextAt: { [string]: number } = {} -- per street: when its next cars are due (os.clock)
local onStreet: { [string]: number } = {} -- per street: how many cars are on it now
local MOST = 2 -- cars on a street at once (one each way)
local trips = 0

local function between(range: { number }): number
	return random:NextNumber(range[1], range[2])
end

local function carReady(): boolean
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vehicles = assets and assets:FindFirstChild("Vehicles")
	return vehicles ~= nil and vehicles:FindFirstChild("Car") ~= nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The streets someone's on now.
local function occupied(): { [string]: boolean }
	local found = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local zone = root and WorldService.zoneAt(root.Position)
		if zone and WorldService.isBuilt(zone) then
			found[zone] = true
		end
	end
	return found
end

-- How far up the road's top is from the street's start (the slabs of every other street sit a hair higher).
local function roadTop(street: CFrame): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldService.info().folder }
	local from = street * CFrame.new(Traffic.LANE, 6, -Traffic.ENDS)
	local hit = Workspace:Raycast(from.Position, -street.UpVector * 12, params)
	if hit == nil then
		return ROAD_TOP
	end
	local top = street:PointToObjectSpace(hit.Position).Y
	return if math.abs(top - ROAD_TOP) < 0.5 then top else ROAD_TOP
end

-- Sends a car down `streetId` now (dir 1: down the street, -1: back up it; nil: either). Its id, or nil.
function TrafficService.send(streetId: string, dir: number?): number?
	local street = WorldService.info().streets[streetId]
	if street == nil or (onStreet[streetId] or 0) >= MOST or not carReady() then
		return nil
	end
	trips += 1
	local trip: Traffic.Trip = {
		id = trips,
		street = street.start,
		y = roadTop(street.start),
		length = street.length,
		dir = dir or (if random:NextNumber() < 0.5 then 1 else -1),
		speed = between(Traffic.SPEED),
		startAt = Workspace:GetServerTimeNow() + 0.25, -- a moment for it to reach everyone
		seed = random:NextInteger(1, 2 ^ 30),
	}
	active[trip.id] = { trip = trip, hit = {}, honks = 0, honkedAt = 0 }
	onStreet[streetId] = (onStreet[streetId] or 0) + 1
	task.delay(Traffic.duration(trip) + 0.6, function()
		active[trip.id] = nil
		onStreet[streetId] = math.max(0, (onStreet[streetId] or 1) - 1)
	end)
	Net.event("CarTrip"):FireAllClients(trip)
	return trip.id
end

-- Whether anyone (up and about) is out in the road of `streetId`, off the pavement, where a car
-- coming out of the mist would reach them.
local function inRoad(streetId: string): boolean
	local street = WorldService.info().streets[streetId]
	if street == nil then
		return false
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not RagdollService.isDown(player) and not HealthService.isFainting(player) then
			local p = street.start:PointToObjectSpace(root.Position)
			if
				math.abs(p.X) < World.ROAD_WIDTH / 2
				and -p.Z > Traffic.ENDS
				and -p.Z < street.length - Traffic.ENDS
				and math.abs(p.Y) < 8
			then
				return true
			end
		end
	end
	return false
end

-- Two cars down `streetId`: one now (either way), and a moment later (Traffic.PAIR) one the other
-- way, in the other lane; or that one waits for someone to step into the road (Traffic.LURK). False
-- if not even the first could go.
function TrafficService.pair(streetId: string): boolean
	local first = if random:NextNumber() < 0.5 then 1 else -1
	if TrafficService.send(streetId, first) == nil then
		return false
	end
	local lurks = random:NextNumber() < Traffic.LURK.chance
	task.spawn(function()
		if lurks then
			task.wait(Traffic.PAIR[1])
			local giveUp = os.clock() + Traffic.LURK.wait
			while os.clock() < giveUp and not inRoad(streetId) do
				task.wait(0.1)
			end
		else
			task.wait(between(Traffic.PAIR))
		end
		TrafficService.send(streetId, -first)
	end)
	return true
end

-- Hit: thrown the way the car was going (and up, and off to whichever side they were on),
-- ragdolled, and the bucket's gone.
local function knock(player: Player, car: CFrame, speed: number)
	local root = rootOf(player)
	if root == nil then
		return
	end
	local side = car:PointToObjectSpace(root.Position).X
	local away = car.RightVector * (if side >= 0 then 1 else -1)
	local push = car.LookVector * speed * Traffic.KNOCK.forward
		+ Vector3.new(0, Traffic.KNOCK.up, 0)
		+ away * Traffic.KNOCK.side
	if not RagdollService.knock(player, push, Traffic.DOWN) then
		return
	end
	local lost = CandyService.loseFromBucket(player, 1)
	Net.event("CarHit"):FireAllClients(player.UserId, lost, random:NextInteger(1, 2 ^ 30))
	local text = if lost > 0 then `RUN OVER  -{Format.number(lost)} 🍬` else "RUN OVER"
	Net.event("PlayerPop"):FireAllClients(player.UserId, text, "caught")
end

-- It honks at anyone in front of it (a couple of times a trip at most), for everyone to hear.
local function honk(car: Active, pose: CFrame, presence: number)
	local horn = Traffic.HORN
	local now = os.clock()
	if car.honks >= horn.most or now - car.honkedAt < horn.gap or presence < 0.5 then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local p = pose:PointToObjectSpace(root.Position)
			if p.Z < -Traffic.BODY.halfLength and p.Z > -horn.ahead and math.abs(p.X) < horn.wide then
				car.honks += 1
				car.honkedAt = now
				Net.event("CarHonk"):FireAllClients(car.trip.id)
				return
			end
		end
	end
end

-- Each frame: anyone in a car's way (it's solid once it's mostly out of the mist) is hit.
local function check()
	local now = Workspace:GetServerTimeNow()
	for _, car in active do
		local trip = car.trip
		local t = now - trip.startAt - Traffic.LAG
		if t < 0 then
			continue
		end
		local presence = Traffic.presence(trip, t)
		local pose = Traffic.pose(trip, t)
		honk(car, pose, presence)
		if presence < Traffic.SOLID then
			continue
		end
		local body = Traffic.BODY
		for _, player in Players:GetPlayers() do
			if car.hit[player] then
				continue
			end
			local root = rootOf(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root == nil or humanoid == nil or humanoid.Health <= 0 or humanoid.Sit then
				continue
			end
			local p = pose:PointToObjectSpace(root.Position)
			if
				math.abs(p.X) <= body.halfWidth + Traffic.PAD
				and math.abs(p.Z) <= body.halfLength + Traffic.PAD
				and p.Y > -2
				and p.Y < body.height + 2
				and not RagdollService.isDown(player)
				and not HealthService.isFainting(player)
			then
				car.hit[player] = true
				knock(player, pose, trip.speed)
			end
		end
	end
end

-- Every street someone's on gets a car every few minutes.
local function schedule()
	local now = os.clock()
	local on = occupied()
	for streetId in WorldService.info().streets do
		local due = nextAt[streetId]
		if due == nil then
			nextAt[streetId] = now + between(Traffic.FIRST)
		elseif now >= due and (onStreet[streetId] or 0) == 0 then
			if on[streetId] and TrafficService.pair(streetId) then
				nextAt[streetId] = now + between(Traffic.EVERY)
			else
				nextAt[streetId] = now + between(Traffic.RETRY)
			end
		end
	end
end

function TrafficService.Start()
	if not carReady() then
		warn("[TrafficService] no car yet (import art/export/car/Car.fbx, run tools/setup_car.luau): no traffic")
	end
	RunService.Heartbeat:Connect(check)
	task.spawn(function()
		while true do
			task.wait(1)
			schedule()
		end
	end)
end

return TrafficService
