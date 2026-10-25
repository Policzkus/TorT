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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local WorldService = require(script.Parent.WorldService)

local HomeownerService = {}

type Visit = { count: number, closing: number }
local visits: { [string]: Visit } = {}
local random = Random.new()
local decks: { [string]: { string } } = {} -- per street: the homeowners not dealt yet

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

-- Someone knocked: the homeowner comes out (safe to call for several visitors at once).
function HomeownerService.appear(houseId: string): number
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return 0
	end
	local visit = visits[houseId]
	if visit then
		visit.count += 1
		visit.closing += 1 -- cancels a pending "go back inside"
		return 0 -- already out
	end
	visits[houseId] = { count = 1, closing = 0 }
	local model = house.model
	local number = ((model:GetAttribute("OwnerVisit") :: number?) or 0) + 1
	model:SetAttribute("OwnerVisit", number)
	local style = Homeowners.STYLES[random:NextInteger(1, #Homeowners.STYLES)]
	model:SetAttribute("OwnerStyle", style)
	model:SetAttribute("OwnerOutAt", workspace:GetServerTimeNow())
	model:SetAttribute("OwnerOut", true)
	return Homeowners.OUT_AFTER[style] or 2.4
end

-- One visitor is done; the homeowner goes back inside a moment after the last one.
function HomeownerService.leave(houseId: string)
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
	task.delay(Homeowners.LEAVE_DELAY, function()
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

return HomeownerService
