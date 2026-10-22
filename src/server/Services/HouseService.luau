--!strict
-- Rolls every house's type, homeowner and preference at each Dawn (PROMPT §3.5) and publishes them
-- as attributes on the house model (HouseType, Owner, Preference) for the client to draw the tells.
-- Take-One Bowls get a bowl with two prompts; BowlTriggered tells DoorService what was picked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dialogue = require(ReplicatedStorage.Shared.Config.Dialogue)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local HouseTypes = require(ReplicatedStorage.Shared.Config.HouseTypes)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local Parts = require(script.Parent.Parent.World.Parts)
local WorldEventsService = require(script.Parent.WorldEventsService)
local WorldService = require(script.Parent.WorldService)

local HouseService = {}

HouseService.BowlTriggered = Signal.new() -- (player, houseId, mode: "one" | "all")
HouseService.Rerolled = Signal.new() -- () after every Dawn

type HouseState = {
	houseType: string,
	owner: string,
	preference: string,
	bowl: Model?,
}

local houses: { [string]: HouseState } = {}
local rng = Rng.new(Random.new():NextInteger(1, 2147483646))

function HouseService.houseType(houseId: string): string
	local house = houses[houseId]
	return if house then house.houseType else "Normal"
end

function HouseService.owner(houseId: string): string?
	local house = houses[houseId]
	return if house then house.owner else nil
end

function HouseService.preference(houseId: string): string?
	local house = houses[houseId]
	return if house then house.preference else nil
end

local function buildBowl(houseId: string): Model?
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return nil
	end
	local door = house.door
	-- On the porch, in front of the door, standing on the ground below it.
	local front = door.CFrame * CFrame.new(0, 0, -3.2)
	local base = CFrame.new(front.X, door.Position.Y - door.Size.Y / 2, front.Z) * door.CFrame.Rotation
	local m = Instance.new("Model")
	m.Name = "TakeOneBowl"
	Parts.pole(m, "Stand", 2.6, 1.2, base, "3A2A1E", Enum.Material.Wood)
	local bowl = Parts.cylinder(
		m,
		"Bowl",
		0.7,
		2.6,
		base * CFrame.new(0, 2.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
		"FF8A00",
		Enum.Material.SmoothPlastic
	)
	for i, color in { "FF3B5C", "FFD23F", "7CFF4F", "B06CFF", "3FC8FF" } do
		local angle = i / 5 * math.pi * 2
		Parts.decor(
			Parts.ball(
				m,
				"Candy",
				Vector3.one * 0.55,
				base * CFrame.new(math.cos(angle) * 0.6, 3.4, math.sin(angle) * 0.6),
				color,
				Enum.Material.SmoothPlastic
			)
		)
	end
	local sign = Parts.decor(
		Parts.block(
			m,
			"Sign",
			Vector3.new(2.6, 1.2, 0.15),
			base * CFrame.new(0, 4.4, 0.4),
			"F2EEE6",
			Enum.Material.SmoothPlastic
		)
	)
	Parts.sign(
		sign,
		Enum.NormalId.Front,
		"PLEASE TAKE ONE",
		{ color = Color3.fromHex("8A1E1E"), stroke = Color3.fromHex("F2EEE6") }
	)

	local takeOne = Parts.prompt(bowl, "Take one", "Candy bowl", 9)
	takeOne.Name = "TakeOne"
	local takeAll = Parts.prompt(bowl, "TAKE ALL (risky!)", "Candy bowl", 9, HouseTypes.BOWL_TAKE_ALL_HOLD)
	takeAll.Name = "TakeAll"
	takeAll.KeyboardKeyCode = Enum.KeyCode.F
	takeAll.GamepadKeyCode = Enum.KeyCode.ButtonY
	takeAll.UIOffset = Vector2.new(0, 80)
	takeOne.Triggered:Connect(function(player)
		HouseService.BowlTriggered:Fire(player, houseId, "one")
	end)
	takeAll.Triggered:Connect(function(player)
		HouseService.BowlTriggered:Fire(player, houseId, "all")
	end)
	m.Parent = house.model
	return m
end

local function apply(houseId: string, state: HouseState)
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return
	end
	local previous = houses[houseId]
	if previous and previous.bowl and state.houseType ~= "Bowl" then
		previous.bowl:Destroy()
	elseif previous and previous.bowl then
		state.bowl = previous.bowl
	end
	if state.houseType == "Bowl" and state.bowl == nil then
		state.bowl = buildBowl(houseId)
	end
	houses[houseId] = state
	house.model:SetAttribute("HouseType", state.houseType)
	house.model:SetAttribute("Owner", state.owner)
	house.model:SetAttribute("Preference", state.preference)
	local personality = Dialogue.personalities[state.owner]
	if state.houseType == "LightsOff" then
		house.prompt.ObjectText = "Nobody's home..."
	elseif personality then
		house.prompt.ObjectText = `{personality.emoji} {personality.name}`
	end
	-- Lights off and bowl houses don't answer the door.
	house.prompt.Enabled = state.houseType ~= "LightsOff" and state.houseType ~= "Bowl"
end

function HouseService.setType(houseId: string, houseType: string)
	local current = houses[houseId]
	if current then
		apply(houseId, {
			houseType = houseType,
			owner = current.owner,
			preference = current.preference,
		})
	end
end

-- Dawn: every house gets a new type, owner and preference.
function HouseService.reroll()
	for houseId, house in WorldService.info().houses do
		local neighborhood = Neighborhoods.byId[house.neighborhood]
		local weights = HouseTypes.WEIGHTS[math.clamp(neighborhood.tier, 1, #HouseTypes.WEIGHTS)]
		apply(houseId, {
			houseType = rng:weighted(weights) or "Normal",
			owner = rng:pick(Dialogue.ORDER),
			preference = rng:pick(HouseTypes.PREFERENCES),
		})
	end
	HouseService.Rerolled:Fire()
end

-- Witching Hour: the trick-house chance doubles, so some normal houses turn into tricks.
local function witching()
	for houseId, state in houses do
		local house = WorldService.getHouse(houseId)
		local neighborhood = house and Neighborhoods.byId[house.neighborhood]
		if neighborhood and state.houseType == "Normal" then
			local weights = HouseTypes.WEIGHTS[math.clamp(neighborhood.tier, 1, #HouseTypes.WEIGHTS)]
			local total = 0
			for _, weight in weights do
				total += weight
			end
			local extra = (weights.Trick or 0) * (Events.WITCHING_TRICK_BOOST - 1) / total
			if rng:chance(extra) then
				HouseService.setType(houseId, "Trick")
			end
		end
	end
end

function HouseService.Start()
	WorldEventsService.setFullSizeFilter(function(houseId)
		local houseType = HouseService.houseType(houseId)
		return houseType == "Normal" or houseType == "Decorated"
	end)
	HouseService.reroll()
	WorldEventsService.NightStarted:Connect(function(night: number)
		if night > 1 then
			HouseService.reroll()
		end
	end)
	WorldEventsService.WitchingStarted:Connect(witching)
end

return HouseService
