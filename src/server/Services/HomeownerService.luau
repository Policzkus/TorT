--!strict
-- Who answers each door, and when they're out. The figure itself is built and animated on every
-- client (HomeownerController) from attributes on the house model, so it moves smoothly and friends
-- standing nearby all see the same homeowner:
--   OwnerModel - Config/Homeowners id (rolled per Night from the neighbourhood's pool)
--   OwnerSeed  - the client turns it into body proportions, tilt and idle quirks
--   OwnerOut   - true while someone's at the door
--   OwnerOutAt - when they came out (server time): a client arriving later shows them already out
--   OwnerVisit - counts visits; with OwnerSeed it picks how they come out (Config/Homeowners.STYLES)
--   OwnerStyle - that style, for late joiners and the jumpscare
--   OwnerVisitor - the UserId of whoever knocked last (or is being peeked at): everyone sees the
--                  homeowner face them
--   OwnerMood  - "pleased" / "displeased": how the last visit went
--   OwnerBye   - their goodbye going back in (HomeownerController.GOODBYES), picked to fit it
--   Glance     - true while they're peeking out at someone going by (the door cracked; nobody
--                knocked), GlanceSlam - it ended with the door slammed (someone came too close)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local WorldService = require(script.Parent.WorldService)

local HomeownerService = {}

-- Peeks at passers-by (the user wanted them looking out, but rarely): now and then (`every`
-- seconds) one of the houses someone's walking past (`near`..`far` studs from its door) cracks its
-- door to look at them, for `hold` seconds, slamming it if anyone comes within `near`; a house rests
-- `rest` seconds between peeks, and only `most` peek at once.
local GLANCE = { every = { 28, 55 }, near = 9, far = 38, hold = { 2.5, 4 }, rest = 180, most = 1 }

type Visit = { count: number, closing: number }
local visits: { [string]: Visit } = {}
local random = Random.new()
local decks: { [string]: { string } } = {} -- per street: the homeowners not dealt yet
local glancing: { [string]: number } = {} -- houses peeking out, and when they stop (os.clock)
local lastGlance: { [string]: number } = {}
local nextGlance = 0

-- A homeowner that can be shown: one whose meshes are in the place.
local function available(id: string): boolean
	return CharacterRig.ready(id)
end

-- Deals a house its homeowner (called by HouseService at every Dawn): the street's pool shuffled
-- like a deck, so every one of them turns up before any comes round again, and a house rarely keeps
-- the one it had.
function HomeownerService.roll(model: Model, neighborhoodId: string)
	local deck = decks[neighborhoodId]
	if deck == nil or #deck == 0 then
		deck = {}
		for _, id in Homeowners.POOLS[neighborhoodId] or {} do
			if available(id) then
				table.insert(deck, id)
			end
		end
		for i = #deck, 2, -1 do
			local j = random:NextInteger(1, i)
			deck[i], deck[j] = deck[j], deck[i]
		end
		decks[neighborhoodId] = deck
	end
	if #deck == 0 then
		return
	end
	local previous = model:GetAttribute("OwnerModel")
	if deck[#deck] == previous and #deck > 1 then
		deck[#deck], deck[1] = deck[1], deck[#deck]
	end
	local pick = table.remove(deck) :: string
	model:SetAttribute("OwnerModel", pick)
	model:SetAttribute("OwnerSeed", random:NextInteger(1, 2 ^ 30))
	model:SetAttribute("OwnerOut", false)
end

-- Someone knocked: the homeowner comes out (safe to call for several visitors at once) and turns to
-- `visitor`.
function HomeownerService.appear(houseId: string, visitor: Player?): number
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return 0
	end
	if glancing[houseId] then
		glancing[houseId] = nil
		house.model:SetAttribute("GlanceSlam", false)
		house.model:SetAttribute("Glance", false) -- the peek turns into a visit
	end
	if visitor then
		house.model:SetAttribute("OwnerVisitor", visitor.UserId)
	end
	local visit = visits[houseId]
	if visit then
		visit.count += 1
		visit.closing += 1 -- cancels a pending "go back inside"
		return 0 -- already out
	end
	visits[houseId] = { count = 1, closing = 0 }
	local model = house.model
	model:SetAttribute("OwnerBye", nil) -- no goodbye unless this visit earns one
	local number = ((model:GetAttribute("OwnerVisit") :: number?) or 0) + 1
	model:SetAttribute("OwnerVisit", number)
	local style = Homeowners.STYLES[random:NextInteger(1, #Homeowners.STYLES)]
	model:SetAttribute("OwnerStyle", style)
	model:SetAttribute("OwnerOutAt", workspace:GetServerTimeNow())
	model:SetAttribute("OwnerOut", true)
	return Homeowners.OUT_AFTER[style] or 2.4
end

-- One visitor is done; the homeowner goes back inside `after` seconds (LEAVE_DELAY by default)
-- after the last one: long enough for what they've got to say to have gone.
function HomeownerService.leave(houseId: string, after: number?)
	local visit = visits[houseId]
	if visit == nil then
		return
	end
	visit.count -= 1
	if visit.count > 0 then
		return
	end
	visit.closing += 1
	local ticket = visit.closing
	task.delay(after or Homeowners.LEAVE_DELAY, function()
		if visits[houseId] ~= visit or visit.closing ~= ticket or visit.count > 0 then
			return
		end
		visits[houseId] = nil
		local house = WorldService.getHouse(houseId)
		if house then
			house.model:SetAttribute("OwnerOut", false)
		end
	end)
end

-- The nearest player to `at` (flat), and how far.
local function nearest(at: Vector3): (Player?, number)
	local best, distance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = ((root.Position - at) * Vector3.new(1, 0, 1)).Magnitude
			if d < distance then
				best, distance = player, d
			end
		end
	end
	return best, distance
end

local function endGlance(houseId: string, slam: boolean)
	glancing[houseId] = nil
	local house = WorldService.getHouse(houseId)
	if house then
		house.model:SetAttribute("GlanceSlam", slam)
		house.model:SetAttribute("Glance", false)
	end
end

-- Peeks: ends the ones that are due (slamming those someone's come close to) and now and then starts
-- one at a house someone's walking past.
local function glances()
	local now = os.clock()
	local active = 0
	for houseId, untilAt in glancing do
		local house = WorldService.getHouse(houseId)
		if house == nil then
			glancing[houseId] = nil
			continue
		end
		local _, distance = nearest(house.door.Position)
		if distance < GLANCE.near then
			endGlance(houseId, true)
		elseif now >= untilAt then
			endGlance(houseId, false)
		else
			active += 1
		end
	end
	if now < nextGlance or active >= GLANCE.most then
		return
	end
	nextGlance = now + random:NextNumber(GLANCE.every[1], GLANCE.every[2])
	local picks: { { houseId: string, player: Player } } = {}
	for houseId, house in WorldService.info().houses do
		local model = house.model
		local houseType = model:GetAttribute("HouseType")
		local answers = houseType == "Normal" or houseType == "Decorated" or houseType == "Trick"
		if
			answers
			and visits[houseId] == nil
			and glancing[houseId] == nil
			and model:GetAttribute("OwnerAway") ~= true -- out after a bowl thief (OwnerChaseService)
			and model:GetAttribute("OwnerModel") ~= nil
			and now - (lastGlance[houseId] or -math.huge) > GLANCE.rest
		then
			local player, distance = nearest(house.door.Position)
			if player and distance >= GLANCE.near + 2 and distance <= GLANCE.far then
				table.insert(picks, { houseId = houseId, player = player })
			end
		end
	end
	if #picks == 0 then
		return
	end
	local pick = picks[random:NextInteger(1, #picks)]
	local house = WorldService.getHouse(pick.houseId)
	if house == nil then
		return
	end
	lastGlance[pick.houseId] = now
	glancing[pick.houseId] = now + random:NextNumber(GLANCE.hold[1], GLANCE.hold[2])
	house.model:SetAttribute("OwnerVisitor", pick.player.UserId)
	house.model:SetAttribute("GlanceSlam", false)
	house.model:SetAttribute("Glance", true)
end

function HomeownerService.Start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			glances()
		end
	end)
end

return HomeownerService
