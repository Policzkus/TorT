--!strict
-- The Knifer (Config/Knifer): every few minutes he comes to a street someone's on, out of an open
-- house's doorway or round the back of a house, wherever nobody's looking. He stalks the street
-- like he means it (a patrol: down one pavement house by house, stepping into a front yard to stare
-- at a house, going down the side of one to look into the back gardens, crossing straight over,
-- turning back at the end), sees you in front of him if nothing's in the way (unless you're in a HideSpot), hears you walk
-- close by or run from further off. Seen: he runs at you, and if he gets to you you're dead
-- (LivesService.down). Lost: he goes to where he last saw you, checks the hiding places round it
-- (the gaps beside the houses, the front yards, bushes), and when his time's
-- up he walks back somewhere out of sight and is gone. He's the server's: one model in the
-- workspace (tag "Knifer", attributes Street/State/Target) that every client hears
-- (KniferController: the sting when he comes, his footsteps, the chase music).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knifer = require(ReplicatedStorage.Shared.Config.Knifer)
local World = require(ReplicatedStorage.Shared.Config.World)
local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local Motion = require(ReplicatedStorage.Shared.Modules.Motion)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local HouseService = require(script.Parent.HouseService)
local LivesService = require(script.Parent.LivesService)
local WorldService = require(script.Parent.WorldService)

local KniferService = {}

local TICK = 0.1
-- The stand-in block (only until the character is in the place): its invisible root floats HIP
-- studs up, so it walks up steps and kerbs, and is slim, so it doesn't snag on corners.
local HIP = 2
local ROOT = Vector3.new(1.4, 4, 1.4)

type State = "appear" | "roam" | "investigate" | "chase" | "search" | "kill" | "leave"
type Exit = { at: Vector3, out: Vector3, door: boolean } -- a place to come out of / go back into, the way out
type Beat = { at: Vector3, pause: number?, look: Vector3? } -- walk to `at`, then stand `pause` seconds looking toward `look`
-- What he knows of a house: where it is along the street (`z`, studs down it) and on which side, its
-- door, the foot of its porch steps (`front`), and the gaps down its sides with where to look from
-- them (into the back gardens).
type Lot = {
	id: string, -- the house
	z: number,
	side: number,
	door: Vector3,
	stop: Vector3?, -- the pavement in front of it
	front: Vector3?,
	gaps: { { at: Vector3, look: Vector3 } },
}

type Him = {
	street: string,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	lift: number, -- his root's middle over his feet
	path: Path,
	state: State,
	since: number, -- os.clock the state began
	born: number,
	stay: number,
	target: Player?,
	lastSeen: number,
	lastKnown: Vector3?,
	goal: Vector3?, -- where he's walking
	plan: { Beat }, -- roaming: his patrol's next steps
	heading: number, -- roaming: 1 down the street, -1 back up it
	beatSince: number,
	points: { Beat }, -- searching: the hiding places left to look at
	pauseUntil: number,
	look: Vector3?, -- standing still: what he's looking toward (his gaze sweeps either side of it)
	lookFrom: number,
	waypoints: { Vector3 },
	waypoint: number,
	pathGoal: Vector3?,
	pathAt: number,
	direct: boolean,
	stuckSince: number?,
	gone: boolean,
}

local WALK_X = World.ROAD_WIDTH / 2 + World.SIDEWALK_WIDTH / 2 -- studs out from the road's centre: the pavements' middle

local random = Random.new()
local active: { [string]: Him } = {} -- per street
local lotsCache: { [string]: { Lot } } = {}
local lotsBuilding: { [string]: boolean } = {}
-- The paths he walks keep this far off walls: slim enough for a yard gate (wider, and gates and the
-- gaps between houses close up, and every path goes round the block).
local AGENT = { AgentRadius = 1, AgentHeight = 7.5, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 5 }
local nextAt: { [string]: number } = {}
local folder: Folder

local function between(range: { number }): number
	return random:NextNumber(range[1], range[2])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Players on `street` who can still be hunted.
local function huntable(street: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			root
			and humanoid
			and humanoid.Health > 0
			and not LivesService.isFainting(player)
			and WorldService.zoneAt(root.Position) == street
		then
			table.insert(list, player)
		end
	end
	return list
end

-- What blocks sight: everything solid but people and him.
local function sightParams(): RaycastParams
	local ignore: { Instance } = { folder }
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

local function clear(from: Vector3, to: Vector3, params: RaycastParams): boolean
	return Workspace:Raycast(from, to - from, params) == nil
end

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

local function eyeOf(him: Him): Vector3
	local head = him.model:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else him.root.Position + Vector3.new(0, 1.4, 0)
end

local function sees(him: Him, player: Player, params: RaycastParams): boolean
	local root = rootOf(player)
	if root == nil then
		return false
	end
	local eye = eyeOf(him)
	local offset = root.Position - eye
	local distance = offset.Magnitude
	if distance > Knifer.SIGHT.range or (distance > Knifer.HIDDEN_NEAR and hidden(root.Position)) then
		return false
	end
	if distance > Knifer.SIGHT.near then
		local facing = flat(him.root.CFrame.LookVector)
		local toward = flat(offset)
		if
			facing.Magnitude > 0.01
			and toward.Magnitude > 0.01
			and facing.Unit:Dot(toward.Unit) < math.cos(math.rad(Knifer.SIGHT.fov / 2))
		then
			return false
		end
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	-- Crouched, your body and head are lower: he can't see you behind what you'd stand up over.
	local down = Vector3.new(0, crouchDrop(player, root), 0)
	return clear(eye, root.Position - down / 2, params) or (head ~= nil and clear(eye, head.Position - down, params))
end

-- The nearest player he can hear (walking close by, running further off), and where.
local function hears(him: Him, players: { Player }): Vector3?
	local best, bestDistance = nil, math.huge
	for _, player in players do
		local root = rootOf(player)
		if root then
			local speed = flat(root.AssemblyLinearVelocity).Magnitude
			local distance = (root.Position - him.root.Position).Magnitude
			local range = if speed >= Knifer.HEAR.running
				then Knifer.HEAR.run
				elseif speed < Knifer.HEAR.walking then 0
				elseif creeping(player, root) then Knifer.HEAR.creep
				else Knifer.HEAR.walk
			if distance <= range and distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best
end

-- Ground under `at` (the world's, not people's), or nil.
local function groundAt(at: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldService.info().folder }
	local hit = Workspace:Raycast(at + Vector3.new(0, 14, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position
end

-- Does anyone near see the spot?
local function watched(at: Vector3, params: RaycastParams): boolean
	local chest = at + Vector3.new(0, 3, 0)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head and (head.Position - chest).Magnitude < Knifer.SPAWN.unseen and clear(head.Position, chest, params) then
			return true
		end
	end
	return false
end

local function configure(humanoid: Humanoid)
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = Knifer.SPEED.roam
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

-- Who he is: the sack-mask homeowner (Config/Knifer.CHARACTER, a Blender character rigged like
-- everyone else's, so CharacterAnimController walks and runs him on every client), standing at
-- `at` facing `out`. Until those meshes are in the place, a tall dark block with a red slit for
-- eyes on a floating invisible root. Also returns how high his root's middle is over his feet.
-- His knife (ReplicatedStorage.Assets.Props.Knife, tools/setup_knife.luau) in his right hand: the
-- grip in his fist, the blade out of the side of it along the arm's back (+Z: raised over his head,
-- it points down at you), the edge down. Held by a "Wrist" joint that every client turns
-- (KniferController): with the arm low the blade's turned to hang point down by his leg. Nothing
-- until the knife's in the place.
local function arm(model: Model)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local knife = props and props:FindFirstChild("Knife")
	local hand = model:FindFirstChild("Right Arm")
	if
		knife == nil
		or not knife:IsA("Model")
		or knife.PrimaryPart == nil
		or hand == nil
		or not hand:IsA("BasePart")
	then
		return
	end
	local copy = knife:Clone()
	local inHand = CFrame.new(0, -hand.Size.Y / 2 + Knifer.KNIFE.grip, 0)
		* CFrame.Angles(math.pi / 2, 0, 0)
		* CFrame.Angles(0, math.pi, 0)
	copy:PivotTo(hand.CFrame * inHand)
	local wrist = Instance.new("Motor6D")
	wrist.Name = "Wrist"
	wrist.Part0 = hand
	wrist.Part1 = copy.PrimaryPart
	wrist.C0 = inHand
	wrist.Parent = copy.PrimaryPart
	copy.Parent = model
end

local function build(at: Vector3, out: Vector3): (Model, BasePart, Humanoid, number)
	local rig = CharacterRig.build(Knifer.CHARACTER, "player")
	local rigRoot = rig and rig.PrimaryPart
	local rigHumanoid = rig and rig:FindFirstChildOfClass("Humanoid")
	if rig and rigRoot and rigHumanoid then
		local lift = rigRoot.Position.Y -- (built standing on the origin)
		rig.Name = "Knifer"
		rig:PivotTo(CFrame.lookAt(at + Vector3.new(0, lift, 0), at + Vector3.new(0, lift, 0) + out))
		configure(rigHumanoid)
		-- Slim where he collides (his body doesn't): yard gates and the gaps between houses fit him.
		rigRoot.Size = Vector3.new(math.min(rigRoot.Size.X, 1.4), rigRoot.Size.Y, math.min(rigRoot.Size.Z, 1))
		arm(rig)
		return rig, rigRoot, rigHumanoid, lift
	elseif rig then
		rig:Destroy()
	end

	local lift = HIP + ROOT.Y / 2
	local model = Instance.new("Model")
	model.Name = "Knifer"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = CFrame.lookAt(at + Vector3.new(0, lift, 0), at + Vector3.new(0, lift, 0) + out)
	root.Parent = model
	model.PrimaryPart = root
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Knifer.BODY
	body.Color = Color3.fromRGB(18, 14, 14)
	body.Material = Enum.Material.SmoothPlastic
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.Massless = true
	body.CFrame = root.CFrame * CFrame.new(0, Knifer.BODY.Y / 2 - lift, 0)
	body.Parent = model
	local eyes = Instance.new("Part")
	eyes.Name = "Eyes"
	eyes.Size = Vector3.new(1.3, 0.16, 0.1)
	eyes.Color = Color3.fromRGB(200, 20, 16)
	eyes.Material = Enum.Material.Neon
	eyes.CanCollide = false
	eyes.CanTouch = false
	eyes.CanQuery = false
	eyes.Massless = true
	eyes.CFrame = body.CFrame * CFrame.new(0, Knifer.BODY.Y / 2 - 0.7, -Knifer.BODY.Z / 2 - 0.04)
	eyes.Parent = model
	for _, part in { body, eyes } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HIP
	configure(humanoid)
	humanoid.Parent = model
	return model, root, humanoid, lift
end

local function setState(him: Him, state: State)
	him.state = state
	him.since = os.clock()
	him.model:SetAttribute("State", state)
	if state ~= "chase" then
		him.model:SetAttribute("Target", 0)
	end
end

-- Walks toward `goal` at `speed`: straight at it when `straight` (he can see it), else along a path
-- round whatever's in the way (worked out again as the goal moves, or if he gets stuck). True when
-- he was wedged and had to be shoved free (a wanderer should pick somewhere else to go).
local function walk(him: Him, goal: Vector3, speed: number, straight: boolean): boolean
	local now = os.clock()
	him.humanoid.WalkSpeed = speed
	him.goal = goal
	local moving = flat(him.root.AssemblyLinearVelocity).Magnitude
	if moving < 1 and (flat(goal - him.root.Position)).Magnitude > 3 then
		him.stuckSince = him.stuckSince or now
	else
		him.stuckSince = nil
	end
	local stuckFor = if him.stuckSince then now - him.stuckSince else 0
	if stuckFor > 2.5 then
		-- Wedged where the path says he fits (a box's corner by a kerb): shoved a step on, think again.
		local point = him.waypoints[him.waypoint] or goal
		local toward = flat(point - him.root.Position)
		if toward.Magnitude > 0.1 then
			him.root.CFrame += toward.Unit * 1.5
		end
		him.stuckSince = nil
		him.pathGoal = nil
		return true
	end
	local stuck = stuckFor > 0.8
	if straight and not stuck and (goal - him.root.Position).Magnitude < 40 then
		him.direct = true
		him.humanoid:MoveTo(goal)
		return false
	end
	him.direct = false
	local stale = him.pathGoal == nil
		or (goal - (him.pathGoal :: Vector3)).Magnitude > 5
		or now - him.pathAt > (if him.state == "chase" then 1 else 5)
		or (stuck and now - him.pathAt > 0.8)
		or him.waypoint > #him.waypoints
	if stale then
		him.pathGoal = goal
		him.pathAt = now
		-- Paths run along the ground: a goal up in the air (where someone's chest was) has none.
		local target = groundAt(goal) or goal
		local ok = pcall(function()
			him.path:ComputeAsync(him.root.Position - Vector3.new(0, him.lift - 0.5, 0), target)
		end)
		if him.gone then
			return false
		end
		him.waypoints = {}
		if ok and him.path.Status == Enum.PathStatus.Success then
			for _, waypoint in him.path:GetWaypoints() do
				table.insert(him.waypoints, waypoint.Position)
			end
			him.waypoint = math.min(2, #him.waypoints)
		else
			him.waypoints = { goal } -- nowhere to go round: straight at it
			him.waypoint = 1
		end
	end
	local point = him.waypoints[him.waypoint]
	while point and flat(point - him.root.Position).Magnitude < 2.5 and him.waypoint < #him.waypoints do
		him.waypoint += 1
		point = him.waypoints[him.waypoint]
	end
	if point then
		him.humanoid:MoveTo(point)
	end
	return false
end

local function stand(him: Him)
	him.humanoid:MoveTo(him.root.Position)
	him.goal = nil
end

local function arrived(him: Him, goal: Vector3, within: number): boolean
	return flat(goal - him.root.Position).Magnitude <= within
end

-- How far he'd walk from `from` to `to` (along a path round things), or nil if he can't get there.
local function walkLength(path: Path, from: Vector3, to: Vector3): number?
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local total, last = 0, nil
	for _, waypoint in path:GetWaypoints() do
		if last then
			total += (waypoint.Position - last).Magnitude
		end
		last = waypoint.Position
	end
	return total
end

-- The middle of the pavement on `side` (+1 right, -1 left), `z` studs down the street.
local function pavement(streetId: string, side: number, z: number): Vector3?
	local street = WorldService.info().streets[streetId]
	if street == nil then
		return nil
	end
	local ground =
		groundAt((street.start * CFrame.new(side * WALK_X, 0, -math.clamp(z, 15, street.length - 15))).Position)
	return ground
end

-- The houses of `street` as he knows them (worked out once, in the background at the start: houses
-- don't move). A front yard or a side gap only counts if he can walk to it from the pavement in
-- front of the house without going round the block (PATROL.reach).
local function lotsOf(streetId: string): { Lot }
	while lotsBuilding[streetId] do
		task.wait(0.1)
	end
	local cached = lotsCache[streetId]
	if cached then
		return cached
	end
	local street = WorldService.info().streets[streetId]
	local list: { Lot } = {}
	if street == nil then
		return list
	end
	lotsBuilding[streetId] = true
	local path = PathfindingService:CreatePath(AGENT)
	local function reachable(from: Vector3?, to: Vector3?): boolean
		if from == nil or to == nil then
			return false
		end
		local length = walkLength(path, from :: Vector3, to :: Vector3)
		return length ~= nil and length <= Knifer.PATROL.reach
	end
	for _, house in WorldService.info().houses do
		local out = flat(house.door.CFrame.LookVector)
		if house.neighborhood ~= streetId or out.Magnitude < 0.1 then
			continue
		end
		out = out.Unit
		local across = out:Cross(Vector3.yAxis)
		local here = street.start:PointToObjectSpace(house.door.Position)
		local side = if here.X >= 0 then 1 else -1
		local stop = pavement(streetId, side, -here.Z)
		local front = groundAt(house.door.Position + out * Knifer.PATROL.front)
		local lot: Lot = {
			id = house.id,
			z = -here.Z,
			side = side,
			door = house.door.Position,
			stop = stop,
			front = if reachable(stop, front) then front else nil,
			gaps = {},
		}
		for _, s in { -1, 1 } do
			local at = groundAt(house.door.Position - out * Knifer.PATROL.gapIn + across * s * Knifer.PATROL.gapOut)
			if at and reachable(stop, at) then
				table.insert(lot.gaps, { at = at :: Vector3, look = (at :: Vector3) - out * 20 }) -- on into the back gardens
			end
		end
		table.insert(list, lot)
	end
	lotsCache[streetId] = list
	lotsBuilding[streetId] = nil
	return list
end

-- His patrol's next few steps: on along his side of the street to the next house the way he's
-- heading, and there maybe into its front yard to stare at it, or down the side of it to look into the
-- back gardens, or straight across the road, or just a stop to look round. At the end of the street
-- he crosses over and comes back up the other side. Walking with sense, not wandering.
local function planPatrol(him: Him): { Beat }
	local street = WorldService.info().streets[him.street]
	local plan: { Beat } = {}
	if street == nil then
		return plan
	end
	local patrol = Knifer.PATROL
	local here = street.start:PointToObjectSpace(him.root.Position)
	local z = -here.Z
	local side = if here.X >= 0 then 1 else -1
	local forward = street.start.LookVector * him.heading -- the way he's going, along the street
	local nextLot, nearest = nil, math.huge
	for _, lot in lotsOf(him.street) do
		local ahead = (lot.z - z) * him.heading
		if lot.side == side and ahead > 5 and ahead < nearest then
			nextLot, nearest = lot, ahead
		end
	end
	if nextLot == nil then
		-- The end of his side: straight across, and back up the other side.
		him.heading = -him.heading
		local over = pavement(him.street, -side, z)
		if over then
			table.insert(
				plan,
				{ at = over, pause = between(patrol.look), look = over + street.start.LookVector * 30 * him.heading }
			)
		end
		return plan
	end
	local stop = pavement(him.street, side, nextLot.z)
	if stop then
		table.insert(plan, { at = stop })
	end
	local roll = random:NextNumber()
	if roll < patrol.yard and nextLot.front then
		-- Up the path to the foot of the porch, staring at the house.
		table.insert(plan, { at = nextLot.front :: Vector3, pause = between(patrol.stare), look = nextLot.door })
		if stop then
			table.insert(plan, { at = stop })
		end
	elseif roll < patrol.yard + patrol.gap and #nextLot.gaps > 0 then
		-- Down the side of the house, looking into the back gardens (where people hide).
		local gap = nextLot.gaps[random:NextInteger(1, #nextLot.gaps)]
		table.insert(plan, { at = gap.at, pause = between(patrol.peek), look = gap.look })
		if stop then
			table.insert(plan, { at = stop })
		end
	elseif roll < patrol.yard + patrol.gap + patrol.cross then
		-- Straight across the road, then on up that side.
		local over = pavement(him.street, -side, nextLot.z)
		if over then
			table.insert(plan, { at = over, pause = between(patrol.look), look = over + forward * 30 })
		end
	elseif stop and random:NextNumber() < patrol.halt then
		-- Just a stop, looking round.
		plan[#plan] = { at = stop, pause = between(patrol.look), look = stop + forward * 30 }
	end
	return plan
end

-- The hiding places round where he lost you, nearest first: the gaps beside the houses, the front
-- yards, anything tagged HideSpot (bushes), and the spot itself.
local function hidingPlaces(him: Him, around: Vector3): { Beat }
	local found: { { beat: Beat, distance: number } } = {}
	local function consider(at: Vector3, look: Vector3)
		local distance = flat(at - around).Magnitude
		if distance <= Knifer.SEARCH.radius then
			table.insert(
				found,
				{ beat = { at = at, pause = between(Knifer.SEARCH.pause), look = look }, distance = distance }
			)
		end
	end
	for _, lot in lotsOf(him.street) do
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
				consider(ground + flat(him.root.Position - ground).Unit * (spot.Size.X / 2 + 2), spot.Position)
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
			{ at = ground, pause = between(Knifer.SEARCH.pause), look = ground + flat(ground - him.root.Position) }
		)
	end
	for i = 1, math.min(Knifer.SEARCH.points, #found) do
		table.insert(beats, found[i].beat)
	end
	return beats
end

-- Standing still, looking: turned toward `him.look`, his gaze slowly sweeping either side of it.
local function lookAround(him: Him)
	stand(him)
	local look = him.look
	local toward = if look then flat(look - him.root.Position) else flat(him.root.CFrame.LookVector)
	if toward.Magnitude < 0.1 then
		return
	end
	local base = math.atan2(-toward.X, -toward.Z)
	local sweep = math.sin((os.clock() - him.lookFrom) * 1.3) * Knifer.PATROL.sweep
	him.root.CFrame = CFrame.new(him.root.Position) * CFrame.Angles(0, base + sweep, 0)
end

local function pause(him: Him, beat: Beat)
	him.pauseUntil = os.clock() + (beat.pause or 0)
	him.look = beat.look
	him.lookFrom = os.clock()
end

-- Places on `street` he can come out of (and go back into): open houses' doorways, and the gaps
-- down the sides of the houses (the ones that lead out to the street: lotsOf).
local function exits(street: string): { Exit }
	local list: { Exit } = {}
	for _, lot in lotsOf(street) do
		-- An open house's doorway, if its yard lets him out onto the street (a front he can walk to).
		local house = WorldService.getHouse(lot.id)
		local out = if house then flat(house.door.CFrame.LookVector) else Vector3.zero
		if house and lot.front and out.Magnitude > 0.1 and HouseService.houseType(lot.id) == "Open" then
			local sill = house.door.Position - Vector3.new(0, house.door.Size.Y / 2, 0) + out.Unit * 1.2
			table.insert(list, { at = sill, out = out.Unit, door = true })
		end
		for _, gap in lot.gaps do
			local toward = if lot.stop then flat((lot.stop :: Vector3) - gap.at) else Vector3.zero
			if toward.Magnitude > 0.1 then
				table.insert(list, { at = gap.at, out = toward.Unit, door = false })
			end
		end
	end
	return list
end

local function vanish(him: Him)
	if him.gone then
		return
	end
	him.gone = true
	him.model:Destroy()
	if active[him.street] == him then
		active[him.street] = nil
	end
	nextAt[him.street] = os.clock() + between(Knifer.EVERY)
end

-- Caught: dead on the spot, no second chance. Shoved down away from him, a ragdoll (LivesService.down).
local function kill(him: Him, player: Player)
	setState(him, "kill")
	stand(him)
	him.target = nil
	local root = rootOf(player)
	local away = if root then flat(root.Position - him.root.Position) else Vector3.zero
	local push = (if away.Magnitude > 0.1 then away.Unit else flat(him.root.CFrame.LookVector)) * Knifer.SHOVE.away
		+ Vector3.new(0, Knifer.SHOVE.up, 0)
	if LivesService.down(player, push) then
		Net.event("KniferStruck"):FireAllClients(player.UserId)
		Net.event("PlayerPop"):FireAllClients(player.UserId, "KNIFED", "caught")
	end
end

-- The nearest place out of sight to go back into.
local function exitFor(him: Him, params: RaycastParams): Vector3?
	local best, bestDistance = nil, math.huge
	for _, exit in exits(him.street) do
		local distance = (exit.at - him.root.Position).Magnitude
		if distance < bestDistance and not watched(exit.at, params) then
			best, bestDistance = exit.at, distance
		end
	end
	return best
end

local function think(him: Him)
	local now = os.clock()
	local age = now - him.born
	if age > him.stay + Knifer.MOST then
		vanish(him)
		return
	end
	local params = sightParams()
	local players = huntable(him.street)

	-- What he sees: the nearest one in view.
	local seen, seenDistance = nil, math.huge
	for _, player in players do
		local root = rootOf(player)
		if root and sees(him, player, params) then
			local distance = (root.Position - him.root.Position).Magnitude
			if distance < seenDistance then
				seen, seenDistance = player, distance
			end
		end
	end
	if seen and him.state ~= "kill" and him.state ~= "appear" then
		local root = rootOf(seen) :: BasePart
		him.target = seen
		him.lastSeen = now
		him.lastKnown = root.Position
		if him.state ~= "chase" then
			setState(him, "chase")
		end
		him.model:SetAttribute("Target", seen.UserId)
		if
			flat(root.Position - him.root.Position).Magnitude <= Knifer.CATCH
			and math.abs(root.Position.Y - him.root.Position.Y) < 5
		then
			kill(him, seen)
			return
		end
	elseif him.state ~= "chase" and him.state ~= "kill" and him.state ~= "leave" and him.state ~= "appear" then
		local noise = hears(him, players)
		if noise then
			him.lastKnown = noise
			if him.state ~= "investigate" then
				setState(him, "investigate")
			end
		end
	end

	local state = him.state
	if state == "appear" then
		stand(him) -- stood in the doorway, at the corner: let them see him first
		if now - him.since > 0.7 then
			setState(him, "roam")
		end
	elseif state == "roam" then
		if age > him.stay then
			setState(him, "leave")
			return
		end
		if #players == 0 then
			setState(him, "leave")
			return
		end
		-- On his patrol (he doesn't know where anyone is until he sees or hears them, so hiding works).
		if now < him.pauseUntil then
			lookAround(him)
			return
		end
		local beat = him.plan[1]
		if beat == nil then
			him.plan = planPatrol(him)
			him.beatSince = now
			beat = him.plan[1]
			if beat == nil then
				stand(him)
				return
			end
		end
		if arrived(him, beat.at, 3) then
			table.remove(him.plan, 1)
			him.beatSince = now
			if beat.pause then
				pause(him, beat)
			end
			return
		end
		local far = flat(beat.at - him.root.Position).Magnitude > Knifer.PATROL.replan
		if walk(him, beat.at, Knifer.SPEED.roam, false) or far or now - him.beatSince > 15 then
			him.plan = {} -- wedged, or it went wrong (a detour): plan again from where he is
			him.beatSince = now
		end
	elseif state == "chase" then
		local target = him.target
		local root = target and rootOf(target)
		if root == nil or target == nil or not table.find(players, target) then
			him.target = nil
			setState(him, "search")
			him.points = hidingPlaces(him, him.lastKnown or him.root.Position)
			return
		end
		if now - him.lastSeen > Knifer.LOSE then
			setState(him, "investigate") -- lost you: to where he last saw you
			return
		end
		walk(
			him,
			if seen == target then root.Position else him.lastKnown :: Vector3,
			Knifer.SPEED.chase,
			seen == target
		)
	elseif state == "investigate" then
		local spot = him.lastKnown
		if spot == nil then
			setState(him, "roam")
			return
		end
		if arrived(him, spot :: Vector3, 4) or now - him.since > 20 then
			setState(him, "search")
			him.points = hidingPlaces(him, spot :: Vector3)
			return
		end
		walk(him, spot :: Vector3, Knifer.SPEED.investigate, false)
	elseif state == "search" then
		if now < him.pauseUntil then
			lookAround(him)
			return
		end
		local beat = him.points[1]
		if beat == nil then
			setState(him, if age > him.stay then "leave" else "roam")
			him.goal = nil
			him.plan = {}
			return
		end
		if arrived(him, beat.at, 3) or now - him.since > 10 then
			table.remove(him.points, 1)
			him.since = now
			pause(him, beat)
			return
		end
		walk(him, beat.at, Knifer.SPEED.search, false)
	elseif state == "kill" then
		stand(him)
		if now - him.since > Knifer.KILL_PAUSE then
			setState(him, if age > him.stay then "leave" else "roam")
			him.goal = nil
			him.plan = {}
		end
	elseif state == "leave" then
		if him.goal == nil or now - him.since > 25 then
			him.goal = exitFor(him, params)
			him.since = now
			if him.goal == nil then
				vanish(him) -- nowhere unseen to go: he's just gone
				return
			end
		end
		if arrived(him, him.goal :: Vector3, 3) then
			vanish(him)
			return
		end
		walk(him, him.goal :: Vector3, Knifer.SPEED.roam, false)
	end
end

-- Sends him to `street` now, out of a place nobody's watching, near one of its players (near
-- `near` if given). True if he came.
function KniferService.summon(street: string, near: Player?): boolean
	if active[street] or WorldService.info().streets[street] == nil then
		return false
	end
	local players = huntable(street)
	local target = near or players[random:NextInteger(1, math.max(#players, 1))]
	local targetRoot = target and rootOf(target)
	if targetRoot == nil then
		return false
	end
	local params = sightParams()
	local doors, corners = {}, {}
	for _, exit in exits(street) do
		local distance = (exit.at - targetRoot.Position).Magnitude
		if distance >= Knifer.SPAWN.near and distance <= Knifer.SPAWN.far and not watched(exit.at, params) then
			table.insert(if exit.door then doors else corners, exit)
		end
	end
	local pool = if #doors > 0 and random:NextNumber() < 0.5 then doors else corners
	if #pool == 0 then
		pool = doors
	end
	local exit = pool[random:NextInteger(1, math.max(#pool, 1))]
	if exit == nil then
		return false
	end
	local model, root, humanoid, lift = build(exit.at, exit.out)
	model:SetAttribute("Street", street)
	model:SetAttribute("Target", 0)
	model:SetAttribute("Seed", random:NextInteger(1, 2 ^ 30)) -- his head snaps, his breaths: the same on every client
	model:SetAttribute("OwnAnimator", true) -- KniferController moves him, not CharacterAnimController
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- every client always has him (his steps, the chase)
	CollectionService:AddTag(model, "Knifer")
	model.Parent = folder
	pcall(root.SetNetworkOwner, root, nil) -- the server walks him
	local now = os.clock()
	local him: Him = {
		street = street,
		model = model,
		root = root,
		humanoid = humanoid,
		lift = lift,
		path = PathfindingService:CreatePath(AGENT),
		state = "appear",
		since = now,
		born = now,
		stay = between(Knifer.STAY),
		target = nil,
		lastSeen = 0,
		lastKnown = nil,
		goal = nil,
		plan = {},
		heading = 1,
		beatSince = now,
		points = {},
		pauseUntil = 0,
		look = nil,
		lookFrom = now,
		waypoints = {},
		waypoint = 1,
		pathGoal = nil,
		pathAt = 0,
		direct = false,
		stuckSince = nil,
		gone = false,
	}
	-- Heading into the street from wherever he came out, not off its end.
	local streetInfo = WorldService.info().streets[street]
	local along = -streetInfo.start:PointToObjectSpace(exit.at).Z
	him.heading = if along < streetInfo.length / 2 then 1 else -1
	setState(him, "appear")
	active[street] = him
	Net.event("KniferCame"):FireAllClients(street)
	task.spawn(function()
		while not him.gone do
			local ok, err = pcall(think, him)
			if not ok then
				warn("[KniferService]", err)
			end
			task.wait(TICK)
		end
	end)
	return true
end

-- What he knows of `street` (admin): its houses, the yards and side gaps he can walk to from the
-- pavement, and the places he can come out of (and of those, the ones near `near` nobody can see).
function KniferService.describe(street: string, near: Player?): string
	local lots = lotsOf(street)
	local fronts, gaps = 0, 0
	for _, lot in lots do
		fronts += if lot.front then 1 else 0
		gaps += #lot.gaps
	end
	local list = exits(street)
	local close, unseen = 0, 0
	local root = near and rootOf(near)
	local params = sightParams()
	for _, exit in list do
		local distance = if root then (exit.at - root.Position).Magnitude else 0
		if distance >= Knifer.SPAWN.near and distance <= Knifer.SPAWN.far then
			close += 1
			if not watched(exit.at, params) then
				unseen += 1
			end
		end
	end
	return `{#lots} houses, {fronts} yards and {gaps} side gaps he can walk to; {#list} places to come out of, {close} the right distance from you, {unseen} of those unseen`
end

-- Sends him away now (admin).
function KniferService.dismiss(street: string): boolean
	local him = active[street]
	if him == nil then
		return false
	end
	vanish(him)
	return true
end

local function schedule()
	local now = os.clock()
	for street in WorldService.info().streets do
		if active[street] then
			continue
		end
		local due = nextAt[street]
		if due == nil then
			nextAt[street] = now + between(Knifer.FIRST)
		elseif now >= due then
			if #huntable(street) > 0 and KniferService.summon(street) then
				nextAt[street] = math.huge -- set again when he's gone
			else
				nextAt[street] = now + between(Knifer.RETRY)
			end
		end
	end
end

function KniferService.Start()
	folder = Instance.new("Folder")
	folder.Name = "Knifers"
	folder.Parent = Workspace
	-- Learn the streets in the background (which yards and gaps he can walk to), before he's needed.
	task.spawn(function()
		for streetId in WorldService.info().streets do
			lotsOf(streetId)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			schedule()
		end
	end)
end

return KniferService
