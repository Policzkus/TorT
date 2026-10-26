--!strict
-- What the things that hunt kids on the streets share (Services/KniferService, the Knifer; and
-- Services/OwnerChaseService, a homeowner after the kid who emptied their bowl): how they see you
-- (in front of them, nothing in the way, not in a HideSpot; crouched, lower), how they hear you
-- (walking close by, running further off, creeping only right by them), how they walk (straight at
-- you when they can see you, else round things along a path, shoved on if wedged), how they stand
-- and look round, and where they look for you when they've lost you. Each brings its own numbers
-- (`rules`: Config/Knifer, Config/Bowl.CHASE). Their bodies all go in one folder, which their
-- sight looks through.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Motion = require(ReplicatedStorage.Shared.Modules.Motion)
local CollisionGroups = require(script.Parent.Parent.World.CollisionGroups)
local HealthService = require(script.Parent.Parent.Services.HealthService)
local WorldService = require(script.Parent.Parent.Services.WorldService)

local Hunter = {}

export type Rules = {
	SIGHT: { range: number, fov: number, near: number }, -- studs, degrees; within `near` they know you're there anyway
	HIDDEN_NEAR: number, -- in a HideSpot they only see you closer than this
	HEAR: { creep: number, walk: number, run: number, walking: number, running: number },
	SEARCH: { points: number, radius: number, pause: { number } },
}

export type Beat = { at: Vector3, pause: number?, look: Vector3? } -- walk to `at`, then stand `pause` seconds looking toward `look`

-- Places to look round where someone was lost: the gaps beside a house (looking on into the back
-- gardens) and the foot of its porch (looking at its door).
export type Lot = { door: Vector3, front: Vector3?, gaps: { { at: Vector3, look: Vector3 } } }

export type Hunter = {
	street: string,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	lift: number, -- the root's middle over the feet
	path: Path,
	rules: Rules,
	state: string,
	since: number, -- os.clock the state began
	born: number,
	target: Player?,
	lastSeen: number,
	lastKnown: Vector3?,
	goal: Vector3?, -- where it's walking
	points: { Beat }, -- searching: the hiding places left to look at
	pauseUntil: number,
	look: Vector3?, -- standing still: what it's looking toward (its gaze sweeps either side of it)
	lookFrom: number,
	waypoints: { Vector3 },
	waypoint: number,
	pathGoal: Vector3?,
	pathAt: number,
	direct: boolean,
	stuckSince: number?,
	gone: boolean,
}

-- The paths they walk keep this far off walls: slim enough for a yard gate (wider, and gates and the
-- gaps between houses close up, and every path goes round the block).
-- Round a candy bowl if there's room (they can walk through one: CollisionGroups, HouseService).
Hunter.AGENT = {
	AgentRadius = 1,
	AgentHeight = 7.5,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 5,
	Costs = { Bowl = 6 },
}

local random = Random.new()
local folder: Folder? = nil

function Hunter.between(range: { number }): number
	return random:NextNumber(range[1], range[2])
end

function Hunter.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local flat = Hunter.flat

function Hunter.rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local rootOf = Hunter.rootOf

-- Where the hunters' bodies go (made the first time it's asked for).
function Hunter.folder(): Folder
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "Hunters"
		made.Parent = Workspace
		folder = made
	end
	return folder :: Folder
end

-- Players on `street` who can still be hunted.
function Hunter.huntable(street: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			root
			and humanoid
			and humanoid.Health > 0
			and not HealthService.isFainting(player)
			and WorldService.zoneAt(root.Position) == street
		then
			table.insert(list, player)
		end
	end
	return list
end

-- What blocks sight: everything solid but people and the hunters.
function Hunter.sightParams(): RaycastParams
	local ignore: { Instance } = { Hunter.folder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

function Hunter.clear(from: Vector3, to: Vector3, params: RaycastParams): boolean
	return Workspace:Raycast(from, to - from, params) == nil
end
local clear = Hunter.clear

-- In a hiding place (a part tagged HideSpot: a bush, a hedge)?
local function hidden(at: Vector3): boolean
	for _, spot in CollectionService:GetTagged("HideSpot") do
		if spot:IsA("BasePart") then
			local p = spot.CFrame:PointToObjectSpace(at)
			local half = spot.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- Crouched and creeping: the client says it's crouching (Crouching, CharacterService), and it's
-- moving no faster than a crouch walk, so it's true.
local function creeping(player: Player, root: BasePart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil then
		return false
	end
	local base = (humanoid:GetAttribute("BaseSpeed") :: number?) or 16
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	return Motion.creeping(character:GetAttribute("Crouching") == true, speed, base)
end

-- How much lower a crouched player's eyes (and the rest of them) are than standing: 0 standing up.
local function crouchDrop(player: Player, root: BasePart): number
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or not creeping(player, root) then
		return 0
	end
	return Motion.crouchDrop(humanoid.HipHeight, root.Size.Y)
end

local function eyeOf(hunter: Hunter): Vector3
	local head = hunter.model:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else hunter.root.Position + Vector3.new(0, 1.4, 0)
end

function Hunter.sees(hunter: Hunter, player: Player, params: RaycastParams): boolean
	local root = rootOf(player)
	if root == nil then
		return false
	end
	local rules = hunter.rules
	local eye = eyeOf(hunter)
	local offset = root.Position - eye
	local distance = offset.Magnitude
	if distance > rules.SIGHT.range or (distance > rules.HIDDEN_NEAR and hidden(root.Position)) then
		return false
	end
	if distance > rules.SIGHT.near then
		local facing = flat(hunter.root.CFrame.LookVector)
		local toward = flat(offset)
		if
			facing.Magnitude > 0.01
			and toward.Magnitude > 0.01
			and facing.Unit:Dot(toward.Unit) < math.cos(math.rad(rules.SIGHT.fov / 2))
		then
			return false
		end
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	-- Crouched, your body and head are lower: they can't see you behind what you'd stand up over.
	local down = Vector3.new(0, crouchDrop(player, root), 0)
	return clear(eye, root.Position - down / 2, params) or (head ~= nil and clear(eye, head.Position - down, params))
end

-- The nearest player it can hear (walking close by, running further off), and where.
function Hunter.hears(hunter: Hunter, players: { Player }): Vector3?
	local hear = hunter.rules.HEAR
	local best, bestDistance = nil, math.huge
	for _, player in players do
		local root = rootOf(player)
		if root then
			local speed = flat(root.AssemblyLinearVelocity).Magnitude
			local distance = (root.Position - hunter.root.Position).Magnitude
			local range = if speed >= hear.running
				then hear.run
				elseif speed < hear.walking then 0
				elseif creeping(player, root) then hear.creep
				else hear.walk
			if distance <= range and distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best
end

-- Ground under `at` (the world's, not people's), or nil.
function Hunter.groundAt(at: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldService.info().folder }
	local hit = Workspace:Raycast(at + Vector3.new(0, 14, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position
end
local groundAt = Hunter.groundAt

function Hunter.stand(hunter: Hunter)
	hunter.humanoid:MoveTo(hunter.root.Position)
	hunter.goal = nil
end

function Hunter.arrived(hunter: Hunter, goal: Vector3, within: number): boolean
	return flat(goal - hunter.root.Position).Magnitude <= within
end

-- Walks toward `goal` at `speed`: straight at it when `straight` (it can see it), else along a path
-- round whatever's in the way (worked out again as the goal moves, or if it gets stuck). True when
-- it was wedged and had to be shoved free (a wanderer should pick somewhere else to go).
function Hunter.walk(hunter: Hunter, goal: Vector3, speed: number, straight: boolean): boolean
	local now = os.clock()
	hunter.humanoid.WalkSpeed = speed
	hunter.goal = goal
	local moving = flat(hunter.root.AssemblyLinearVelocity).Magnitude
	if moving < 1 and (flat(goal - hunter.root.Position)).Magnitude > 3 then
		hunter.stuckSince = hunter.stuckSince or now
	else
		hunter.stuckSince = nil
	end
	local stuckFor = if hunter.stuckSince then now - hunter.stuckSince else 0
	if stuckFor > 2.5 then
		-- Wedged where the path says it fits (a box's corner by a kerb): shoved a step on, think again.
		local point = hunter.waypoints[hunter.waypoint] or goal
		local toward = flat(point - hunter.root.Position)
		if toward.Magnitude > 0.1 then
			hunter.root.CFrame += toward.Unit * 1.5
		end
		hunter.stuckSince = nil
		hunter.pathGoal = nil
		return true
	end
	local stuck = stuckFor > 0.8
	if straight and not stuck and (goal - hunter.root.Position).Magnitude < 40 then
		hunter.direct = true
		hunter.humanoid:MoveTo(goal)
		return false
	end
	hunter.direct = false
	local stale = hunter.pathGoal == nil
		or (goal - (hunter.pathGoal :: Vector3)).Magnitude > 5
		or now - hunter.pathAt > (if hunter.state == "chase" then 1 else 5)
		or (stuck and now - hunter.pathAt > 0.8)
		or hunter.waypoint > #hunter.waypoints
	if stale then
		hunter.pathGoal = goal
		hunter.pathAt = now
		-- Paths run along the ground: a goal up in the air (where someone's chest was) has none.
		local target = groundAt(goal) or goal
		local ok = pcall(function()
			hunter.path:ComputeAsync(hunter.root.Position - Vector3.new(0, hunter.lift - 0.5, 0), target)
		end)
		if hunter.gone then
			return false
		end
		hunter.waypoints = {}
		if ok and hunter.path.Status == Enum.PathStatus.Success then
			for _, waypoint in hunter.path:GetWaypoints() do
				table.insert(hunter.waypoints, waypoint.Position)
			end
			hunter.waypoint = math.min(2, #hunter.waypoints)
		else
			hunter.waypoints = { goal } -- nowhere to go round: straight at it
			hunter.waypoint = 1
		end
	end
	local point = hunter.waypoints[hunter.waypoint]
	while point and flat(point - hunter.root.Position).Magnitude < 2.5 and hunter.waypoint < #hunter.waypoints do
		hunter.waypoint += 1
		point = hunter.waypoints[hunter.waypoint]
	end
	if point then
		hunter.humanoid:MoveTo(point)
	end
	return false
end

-- Standing still, looking: turned toward `hunter.look`, its gaze slowly sweeping `sweep` radians
-- either side of it.
function Hunter.lookAround(hunter: Hunter, sweep: number)
	Hunter.stand(hunter)
	local look = hunter.look
	local toward = if look then flat(look - hunter.root.Position) else flat(hunter.root.CFrame.LookVector)
	if toward.Magnitude < 0.1 then
		return
	end
	local base = math.atan2(-toward.X, -toward.Z)
	local turn = math.sin((os.clock() - hunter.lookFrom) * 1.3) * sweep
	hunter.root.CFrame = CFrame.new(hunter.root.Position) * CFrame.Angles(0, base + turn, 0)
end

function Hunter.pause(hunter: Hunter, beat: Beat)
	hunter.pauseUntil = os.clock() + (beat.pause or 0)
	hunter.look = beat.look
	hunter.lookFrom = os.clock()
end

-- The hiding places round where it lost you, nearest first: the gaps beside the houses, the front
-- yards (`lots`), anything tagged HideSpot (bushes), and the spot itself.
function Hunter.hidingPlaces(hunter: Hunter, around: Vector3, lots: { Lot }): { Beat }
	local search = hunter.rules.SEARCH
	local found: { { beat: Beat, distance: number } } = {}
	local function consider(at: Vector3, look: Vector3)
		local distance = flat(at - around).Magnitude
		if distance <= search.radius then
			table.insert(
				found,
				{ beat = { at = at, pause = Hunter.between(search.pause), look = look }, distance = distance }
			)
		end
	end
	for _, lot in lots do
		for _, gap in lot.gaps do
			consider(gap.at, gap.look)
		end
		if lot.front then
			consider(lot.front :: Vector3, lot.door)
		end
	end
	for _, spot in CollectionService:GetTagged("HideSpot") do
		if spot:IsA("BasePart") then
			local ground = groundAt(spot.Position)
			if ground then
				consider(ground + flat(hunter.root.Position - ground).Unit * (spot.Size.X / 2 + 2), spot.Position)
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local beats: { Beat } = {}
	local ground = groundAt(around)
	if ground then
		table.insert(
			beats,
			{ at = ground, pause = Hunter.between(search.pause), look = ground + flat(ground - hunter.root.Position) }
		)
	end
	for i = 1, math.min(search.points, #found) do
		table.insert(beats, found[i].beat)
	end
	return beats
end

-- Sets up a Humanoid to walk a hunter: it can't be hurt, jump, climb or fall over, and shows no name
-- or health.
-- Their whole body walks through candy bowls (CollisionGroups).
function Hunter.ghost(model: Model)
	CollisionGroups.put(model, CollisionGroups.HUNTERS)
end

function Hunter.configure(humanoid: Humanoid, speed: number)
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = speed
	for _, state in
		{
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Swimming,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
end

return Hunter
