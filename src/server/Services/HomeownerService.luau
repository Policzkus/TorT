--!strict
-- The homeowner who appears in the doorway while you play a door's mini-game. Server-side, so
-- friends standing nearby see the same figure. Each house's homeowner (mesh, stretch, scale,
-- tilt) is rolled at every Dawn by HouseService and stored as attributes on the house model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local MeshLibrary = require(ReplicatedStorage.Shared.Modules.MeshLibrary)
local WorldService = require(script.Parent.WorldService)

local HomeownerService = {}

type Visit = { figure: BasePart, count: number, alive: boolean }
local visits: { [string]: Visit } = {}
local random = Random.new()

-- Rolls the look of a house's homeowner (called by HouseService at Dawn).
function HomeownerService.roll(model: Model)
	if #Homeowners.ROSTER == 0 then
		return
	end
	model:SetAttribute("OwnerModel", Homeowners.ROSTER[random:NextInteger(1, #Homeowners.ROSTER)])
	model:SetAttribute("OwnerStretch", random:NextNumber(Homeowners.STRETCH.min, Homeowners.STRETCH.max))
	model:SetAttribute("OwnerScale", random:NextNumber(Homeowners.SCALE.min, Homeowners.SCALE.max))
	model:SetAttribute("OwnerTilt", random:NextNumber(-Homeowners.TILT, Homeowners.TILT))
end

local function standing(door: BasePart, figure: BasePart, depth: number): CFrame
	local ground = door.Position.Y - door.Size.Y / 2
	local spot = door.CFrame * CFrame.new(0, 0, depth)
	return CFrame.new(spot.X, ground + figure.Size.Y / 2, spot.Z) * door.CFrame.Rotation
end

-- Shows the homeowner in the doorway. Safe to call for several visitors at once.
function HomeownerService.appear(houseId: string)
	local existing = visits[houseId]
	if existing and existing.alive then
		existing.count += 1
		return
	end
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return
	end
	local name = house.model:GetAttribute("OwnerModel")
	local figure = if type(name) == "string" then MeshLibrary.get(name) else nil
	if figure == nil then
		return
	end
	local scale = (house.model:GetAttribute("OwnerScale") :: number?) or 1
	local stretch = (house.model:GetAttribute("OwnerStretch") :: number?) or 1
	local tilt = math.rad((house.model:GetAttribute("OwnerTilt") :: number?) or 0)
	figure.Name = "Homeowner"
	figure.Size = Vector3.new(figure.Size.X * scale, figure.Size.Y * scale * stretch, figure.Size.Z * scale)
	figure.Anchored = true
	figure.CanCollide = false
	figure.CanQuery = false
	figure.CanTouch = false
	-- Starts hidden inside the house, slides out to just in front of the door.
	figure.CFrame = standing(house.door, figure, 2.5) * CFrame.Angles(0, 0, tilt)
	figure.Parent = house.model
	local visit: Visit = { figure = figure, count = 1, alive = true }
	visits[houseId] = visit
	TweenService
		:Create(figure, TweenInfo.new(Homeowners.APPEAR_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = standing(house.door, figure, -0.3) * CFrame.Angles(0, 0, tilt),
		})
		:Play()

	-- Unsettling twitches while they wait for your answer.
	task.spawn(function()
		task.wait(Homeowners.APPEAR_TIME)
		while visit.alive and figure.Parent do
			task.wait(random:NextNumber(Homeowners.TWITCH_EVERY.min, Homeowners.TWITCH_EVERY.max))
			if not visit.alive then
				break
			end
			local jerk =
				CFrame.Angles(0, math.rad(random:NextNumber(-14, 14)), tilt + math.rad(random:NextNumber(-6, 6)))
			TweenService:Create(figure, TweenInfo.new(0.08), {
				CFrame = standing(house.door, figure, -0.3) * jerk,
			}):Play()
		end
	end)
end

-- One visitor is done; the homeowner goes back inside when the last one is.
function HomeownerService.leave(houseId: string)
	local visit = visits[houseId]
	if visit == nil or not visit.alive then
		return
	end
	visit.count -= 1
	if visit.count > 0 then
		return
	end
	visit.alive = false
	visits[houseId] = nil
	local house = WorldService.getHouse(houseId)
	task.delay(Homeowners.LEAVE_DELAY, function()
		if house and visit.figure.Parent then
			local back =
				TweenService:Create(visit.figure, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = standing(house.door, visit.figure, 2.5),
				})
			back.Completed:Once(function()
				visit.figure:Destroy()
			end)
			back:Play()
		else
			visit.figure:Destroy()
		end
	end)
end

return HomeownerService
