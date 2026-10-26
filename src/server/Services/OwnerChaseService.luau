--!strict
-- A homeowner after the kid who emptied their candy bowl (Config/Bowl; DoorService calls raid). Not
-- every time (CHASE_CHANCE): a moment after the porch lamp bursts, the front door flies open (OwnerAway
-- on the house: every client swings it, HouseVisualController) and out they come, shouting. Then they
-- hunt the thief the way the Knifer hunts (AI/Hunter): they see you in front of them with nothing in
-- the way (not in a HideSpot; crouched, lower), hear you walk close by and run from further off
-- (creeping, only right by them). Seen, they run at you, arms out to grab; lost, they go to where
-- they last saw you and look round the hiding places near it, then walk home, go in, and the door
-- slams. Catch you and you're thrown down (RagdollService) and they take back every piece of candy
-- in your bucket, for everyone to see (OwnerGrab, PlayerPop). They only want the thief, and go home
-- once the thief's off the street or down, or after CHASE.MOST seconds whatever.
-- The body is the server's: the house's homeowner (OwnerModel) rigged like a kid (CharacterRig
-- "player"), so CharacterAnimController walks and runs it on every client, in Workspace.Hunters,
-- tagged "OwnerChaser" (attributes House, Thief, Target, State, Shout: OwnerChaseController plays
-- their steps, their shouts and the chase music).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bowl = require(ReplicatedStorage.Shared.Config.Bowl)
local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Hunter = require(script.Parent.Parent.AI.Hunter)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local KniferService = require(script.Parent.KniferService)
local RagdollService = require(script.Parent.RagdollService)
local WorldService = require(script.Parent.WorldService)

local OwnerChaseService = {}

local TICK = 0.1
local CHASE = Bowl.CHASE

type State = "burst" | "chase" | "investigate" | "search" | "grab" | "home"
type Owner = Hunter.Hunter & {
	houseId: string,
	thief: Player,
	sill: Vector3, -- just outside the front door: where they came out, and go back in
}

local random = Random.new()
local chases: { [string]: Owner } = {} -- by house
local starting: { [string]: boolean } = {} -- the lamp's burst, the door's about to fly open

local flat = Hunter.flat

local function setState(owner: Owner, state: State)
	owner.state = state
	owner.since = os.clock()
	owner.model:SetAttribute("State", state)
	owner.model:SetAttribute("Reaching", state == "chase")
	if state ~= "chase" then
		owner.model:SetAttribute("Target", 0)
	end
end

local function shout(owner: Owner, lines: { string })
	owner.model:SetAttribute("Shout", lines[random:NextInteger(1, #lines)])
	owner.model:SetAttribute("ShoutAt", workspace:GetServerTimeNow())
end

-- Back in, and the door slams behind them.
local function finish(owner: Owner)
	if owner.gone then
		return
	end
	owner.gone = true
	owner.model:Destroy()
	if chases[owner.houseId] == owner then
		chases[owner.houseId] = nil
	end
	local house = WorldService.getHouse(owner.houseId)
	if house then
		house.model:SetAttribute("OwnerAway", false)
	end
end

local function goHome(owner: Owner)
	owner.target = nil
	owner.points = {}
	setState(owner, "home")
end

-- Got them: thrown down away from the homeowner, and every piece of candy in their bucket taken back.
local function grab(owner: Owner, player: Player)
	setState(owner, "grab")
	Hunter.stand(owner)
	owner.target = nil
	local root = Hunter.rootOf(player)
	local away = if root then flat(root.Position - owner.root.Position) else Vector3.zero
	local push = (if away.Magnitude > 0.1 then away.Unit else flat(owner.root.CFrame.LookVector)) * CHASE.THROW.away
		+ Vector3.new(0, CHASE.THROW.up, 0)
	if not RagdollService.knock(player, push, CHASE.DOWN) then
		return
	end
	shout(owner, Bowl.GOTCHA)
	local lost = CandyService.loseFromBucket(player, 1)
	DataService.mutate(player, "stats", function(stats)
		stats.caught += 1
	end)
	Net.event("OwnerGrab"):FireAllClients(owner.houseId, player.UserId, lost, random:NextInteger(1, 2 ^ 30))
	local text = if lost > 0 then `CAUGHT  -{Format.number(lost)} 🍬` else "CAUGHT"
	Net.event("PlayerPop"):FireAllClients(player.UserId, text, "caught")
end

local function think(owner: Owner)
	local now = os.clock()
	local state = owner.state
	if state == "burst" then
		Hunter.stand(owner) -- in the doorway, shouting: you see who's coming first
		if now - owner.since > CHASE.BURST then
			setState(owner, "investigate") -- to where the thief was, unless they see them first (below)
		end
		return
	elseif state == "grab" then
		Hunter.stand(owner)
		if now - owner.since > CHASE.STAND_OVER then
			goHome(owner)
		end
		return
	elseif state == "home" then
		if Hunter.arrived(owner, owner.sill, 2.5) or now - owner.since > 30 then
			finish(owner)
			return
		end
		Hunter.walk(owner, owner.sill, CHASE.SPEED.home, false)
		return
	end

	-- Hunting: only the thief, only while they're on the street and up, and not for ever.
	local thief = owner.thief
	local root = Hunter.rootOf(thief)
	if
		root == nil
		or now - owner.born > CHASE.MOST
		or RagdollService.isDown(thief)
		or not table.find(Hunter.huntable(owner.street), thief)
	then
		goHome(owner)
		return
	end
	local seen = Hunter.sees(owner, thief, Hunter.sightParams())
	if seen then
		owner.target = thief
		owner.lastSeen = now
		owner.lastKnown = root.Position
		if state ~= "chase" then
			setState(owner, "chase")
		end
		owner.model:SetAttribute("Target", thief.UserId)
		if
			flat(root.Position - owner.root.Position).Magnitude <= CHASE.CATCH
			and math.abs(root.Position.Y - owner.root.Position.Y) < 5
		then
			grab(owner, thief)
			return
		end
	elseif state ~= "chase" then
		local noise = Hunter.hears(owner, { thief })
		if noise then
			owner.lastKnown = noise
			if state ~= "investigate" then
				setState(owner, "investigate")
			end
		end
	end

	state = owner.state
	if state == "chase" then
		if now - owner.lastSeen > CHASE.LOSE then
			setState(owner, "investigate") -- lost you: to where they last saw you
			return
		end
		Hunter.walk(owner, if seen then root.Position else owner.lastKnown :: Vector3, CHASE.SPEED.chase, seen)
	elseif state == "investigate" then
		local spot = owner.lastKnown or owner.sill
		if Hunter.arrived(owner, spot, 4) or now - owner.since > 15 then
			setState(owner, "search")
			owner.points = Hunter.hidingPlaces(owner, spot, KniferService.lots(owner.street))
			return
		end
		Hunter.walk(owner, spot, CHASE.SPEED.investigate, false)
	elseif state == "search" then
		if now < owner.pauseUntil then
			Hunter.lookAround(owner, CHASE.SWEEP)
			return
		end
		local beat = owner.points[1]
		if beat == nil then
			goHome(owner) -- nowhere left to look: back in
			return
		end
		if Hunter.arrived(owner, beat.at, 3) or now - owner.since > 10 then
			table.remove(owner.points, 1)
			owner.since = now
			Hunter.pause(owner, beat)
			return
		end
		Hunter.walk(owner, beat.at, CHASE.SPEED.search, false)
	end
end

-- Out of the door at `houseId` after `thief`, now. False if they can't come (no homeowner there to
-- build, the house gone, someone already out).
local function start(houseId: string, thief: Player): boolean
	local house = WorldService.getHouse(houseId)
	local ownerId = house and house.model:GetAttribute("OwnerModel")
	local thiefRoot = Hunter.rootOf(thief)
	if house == nil or type(ownerId) ~= "string" or thiefRoot == nil or chases[houseId] then
		return false
	end
	local out = flat(house.door.CFrame.LookVector)
	if out.Magnitude < 0.1 then
		return false
	end
	out = out.Unit
	local rig = CharacterRig.build(ownerId, "player")
	local root = rig and rig.PrimaryPart
	local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
	if rig == nil or root == nil or humanoid == nil then
		if rig then
			rig:Destroy()
		end
		return false
	end
	local sill = house.door.Position - Vector3.new(0, house.door.Size.Y / 2, 0) + out * 1.2
	local lift = root.Position.Y -- (built standing on the origin)
	rig.Name = "Homeowner"
	rig:PivotTo(CFrame.lookAt(sill + Vector3.new(0, lift, 0), sill + Vector3.new(0, lift, 0) + out))
	Hunter.configure(humanoid, CHASE.SPEED.chase)
	-- Slim where they collide (their body doesn't): yard gates and the gaps between houses fit them.
	root.Size = Vector3.new(math.min(root.Size.X, 1.4), root.Size.Y, math.min(root.Size.Z, 1))
	rig:SetAttribute("House", houseId)
	rig:SetAttribute("Thief", thief.UserId)
	rig:SetAttribute("Target", 0)
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- everyone hears them coming
	CollectionService:AddTag(rig, "OwnerChaser")
	local now = os.clock()
	local owner: Owner = {
		street = house.neighborhood,
		model = rig,
		root = root,
		humanoid = humanoid,
		lift = lift,
		path = PathfindingService:CreatePath(Hunter.AGENT),
		rules = CHASE,
		state = "burst",
		since = now,
		born = now,
		target = nil,
		lastSeen = 0,
		lastKnown = thiefRoot.Position, -- they saw who it was
		goal = nil,
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
		houseId = houseId,
		thief = thief,
		sill = sill,
	}
	chases[houseId] = owner
	setState(owner, "burst")
	shout(owner, Bowl.SHOUTS)
	rig.Parent = Hunter.folder() -- (with its state and shout already on it, for every client)
	pcall(root.SetNetworkOwner, root, nil) -- the server walks them
	house.model:SetAttribute("OwnerAway", true)
	task.spawn(function()
		while not owner.gone do
			local ok, err = pcall(think, owner)
			if not ok then
				warn("[OwnerChaseService]", err)
			end
			task.wait(TICK)
		end
	end)
	return true
end

-- `thief` emptied `houseId`'s bowl (its lamp's just burst): maybe the homeowner comes out after them.
-- `certain`: they do (admin).
function OwnerChaseService.raid(thief: Player, houseId: string, certain: boolean?)
	if chases[houseId] or starting[houseId] then
		return
	end
	if not certain and random:NextNumber() >= Bowl.CHASE_CHANCE then
		return
	end
	starting[houseId] = true
	task.delay(CHASE.WAIT, function()
		starting[houseId] = nil
		if thief.Parent == Players then
			start(houseId, thief)
		end
	end)
end

-- Whether `houseId`'s homeowner is out after someone (nobody answers that door meanwhile).
function OwnerChaseService.away(houseId: string): boolean
	return chases[houseId] ~= nil or starting[houseId] == true
end

-- Sends every homeowner who's out back in, now (admin).
function OwnerChaseService.dismiss(): number
	local count = 0
	for _, owner in chases do
		finish(owner)
		count += 1
	end
	return count
end

function OwnerChaseService.Start()
	Players.PlayerRemoving:Connect(function(player)
		for _, owner in chases do
			if owner.thief == player and owner.state ~= "home" then
				goHome(owner)
			end
		end
	end)
end

return OwnerChaseService
