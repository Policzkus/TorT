--!strict
-- Who answers each door, and when they're out. The figure itself is built and animated on every
-- client (HomeownerController) from attributes on the house model, so it moves smoothly and friends
-- standing nearby all see the same homeowner:
--   OwnerModel - Config/Homeowners id (rolled per Night from the neighbourhood's pool)
--   OwnerSeed  - the client turns it into body proportions, tilt and idle quirks
--   OwnerOut   - true while someone's at the door
--   OwnerVisit - counts visits; with OwnerSeed it picks how they come out (Config/Homeowners.STYLES)
--   OwnerStyle - that style, for late joiners and the jumpscare

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Config.Characters)
local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local Meshes = require(ReplicatedStorage.Shared.Config.Meshes)
local WorldService = require(script.Parent.WorldService)

local HomeownerService = {}

type Visit = { count: number, closing: number }
local visits: { [string]: Visit } = {}
local random = Random.new()

local function available(id: string): boolean
	return Characters[id] ~= nil or Meshes[id] ~= nil
end

-- Rolls a house's homeowner (called by HouseService at every Dawn).
function HomeownerService.roll(model: Model, neighborhoodId: string)
	local pool = {}
	for _, id in Homeowners.POOLS[neighborhoodId] or {} do
		if available(id) then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return
	end
	-- Neighbours on the same street rarely share a homeowner twice in a row.
	local previous = model:GetAttribute("OwnerModel")
	local pick = pool[random:NextInteger(1, #pool)]
	if pick == previous and #pool > 1 then
		pick = pool[random:NextInteger(1, #pool)]
	end
	model:SetAttribute("OwnerModel", pick)
	model:SetAttribute("OwnerSeed", random:NextInteger(1, 2 ^ 30))
	model:SetAttribute("OwnerOut", false)
end

-- Someone knocked: the homeowner comes out (safe to call for several visitors at once).
function HomeownerService.appear(houseId: string)
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return
	end
	local visit = visits[houseId]
	if visit then
		visit.count += 1
		visit.closing += 1 -- cancels a pending "go back inside"
		return
	end
	visits[houseId] = { count = 1, closing = 0 }
	local model = house.model
	local number = ((model:GetAttribute("OwnerVisit") :: number?) or 0) + 1
	model:SetAttribute("OwnerVisit", number)
	model:SetAttribute("OwnerStyle", Homeowners.STYLES[random:NextInteger(1, #Homeowners.STYLES)])
	model:SetAttribute("OwnerOut", true)
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
