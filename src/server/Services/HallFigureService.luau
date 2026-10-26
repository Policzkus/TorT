--!strict
-- Whoever stands in an open house's hall (World/BlenderLot.dressHall), decided here so everyone sees
-- the same thing (the user wants everything synced): a spot closer each time the hall light blinks
-- while someone stands watching the door, gone in a blackout when anyone comes close, maybe back at
-- the far end once everyone has walked off. It's on the house model for the clients to draw
-- (HouseVisualController, which blinks the light when it changes and turns the figure to whoever's
-- nearest): HallSpot (1 = the far end of the hall) and HallGone.

local Players = game:GetService("Players")

local HouseService = require(script.Parent.HouseService)
local WorldService = require(script.Parent.WorldService)

local HallFigureService = {}

local WATCH = 36 -- studs: within this of the door, facing it, you're watching
local GONE = 13 -- studs: anyone this close to where it stands and it's gone
local BACK = 40 -- studs: everyone this far off and it may come back
local STEP = { min = 3.5, max = 7 } -- seconds of someone watching before it comes a spot closer
local TICK = 0.12

type Hall = { model: Model, door: BasePart, spots: { BasePart }, watched: number, nextStep: number }

local halls: { [string]: Hall } = {}
local random = Random.new()

local function nextStep(): number
	return random:NextNumber(STEP.min, STEP.max)
end

-- The spots it can stand at in the hall, far to near.
local function spotsOf(model: Model): { BasePart }
	local spots = {}
	local first = model:FindFirstChild("HallFigure") :: BasePart?
	if first then
		table.insert(spots, first)
	end
	for k = 2, 9 do
		local spot = model:FindFirstChild("HallFigure" .. k) :: BasePart?
		if spot == nil then
			break
		end
		table.insert(spots, spot)
	end
	return spots
end

-- A house became open (or stopped being): someone's at the far end of its hall again.
local function refresh(houseId: string)
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return
	end
	if HouseService.houseType(houseId) ~= "Open" then
		halls[houseId] = nil
		return
	end
	local spots = spotsOf(house.model)
	if #spots == 0 then
		return
	end
	halls[houseId] = { model = house.model, door = house.door, spots = spots, watched = 0, nextStep = nextStep() }
	house.model:SetAttribute("HallGone", false)
	house.model:SetAttribute("HallSpot", 1)
end

local function step()
	local roots: { BasePart } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(roots, root)
		end
	end
	for _, hall in halls do
		local model = hall.model
		local index = (model:GetAttribute("HallSpot") :: number?) or 1
		local spot = hall.spots[index] or hall.spots[1]
		local nearest = math.huge
		local watching = false
		for _, root in roots do
			nearest = math.min(nearest, (root.Position - spot.Position).Magnitude)
			local toDoor = (hall.door.Position - root.Position) * Vector3.new(1, 0, 1)
			if
				toDoor.Magnitude < WATCH
				and toDoor.Magnitude > 0.1
				and root.CFrame.LookVector:Dot(toDoor.Unit) > 0.82
			then
				watching = true
			end
		end
		if model:GetAttribute("HallGone") == true then
			if nearest > BACK and random:NextNumber() < 0.03 then
				hall.watched = 0
				model:SetAttribute("HallSpot", 1)
				model:SetAttribute("HallGone", false)
			end
		elseif nearest < GONE then
			model:SetAttribute("HallGone", true)
		elseif watching then
			hall.watched += TICK
			if hall.watched >= hall.nextStep then
				hall.watched = 0
				hall.nextStep = nextStep()
				-- A spot closer, unless that's right on top of someone: then it's just gone.
				local closer = hall.spots[index + 1]
				local clear = closer ~= nil
				if closer then
					for _, root in roots do
						if (root.Position - closer.Position).Magnitude <= GONE + 2 then
							clear = false
						end
					end
				end
				if clear then
					model:SetAttribute("HallSpot", index + 1)
				else
					model:SetAttribute("HallGone", true)
				end
			end
		end
	end
end

function HallFigureService.Start()
	for houseId, house in WorldService.info().houses do
		house.model:GetAttributeChangedSignal("HouseType"):Connect(function()
			refresh(houseId)
		end)
		refresh(houseId)
	end
	task.spawn(function()
		while true do
			task.wait(TICK)
			step()
		end
	end)
end

return HallFigureService
