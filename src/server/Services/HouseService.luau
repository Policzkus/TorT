--!strict
-- Rolls every house's type, homeowner and preference at each Dawn (PROMPT §3.5) and publishes them
-- as attributes on the house model (HouseType, Owner, Preference) for the client to draw the tells.
-- Bowl houses (Config/Bowl) get a candy bowl on the porch (its Candy attribute: how much is left, of
-- Full) with one prompt, held to take what your bucket can hold (BowlTriggered tells DoorService);
-- come back with room for the rest. Its pieces of candy go as it empties; empty, it stands that way
-- until the next Dawn, when every bowl is put out full again and every burst porch lamp
-- (LampBroken) is mended.
-- Every street has one seller (Config/Items), at a random house, a different one each Dawn: house
-- type "Seller", a lantern by his door. He's its homeowner (OwnerModel: Items.SELLER.CHARACTER):
-- knock and he comes to the door like any of them, and his window opens (DoorService,
-- Controllers/SellerController); ItemService sells.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bowl = require(ReplicatedStorage.Shared.Config.Bowl)
local Dialogue = require(ReplicatedStorage.Shared.Config.Dialogue)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local HouseTypes = require(ReplicatedStorage.Shared.Config.HouseTypes)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local CandyPiece = require(ReplicatedStorage.Shared.Modules.CandyPiece)
local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local CollisionGroups = require(script.Parent.Parent.World.CollisionGroups)
local Parts = require(script.Parent.Parent.World.Parts)
local HomeownerService = require(script.Parent.HomeownerService)
local WorldEventsService = require(script.Parent.WorldEventsService)
local WorldService = require(script.Parent.WorldService)

local HouseService = {}

HouseService.BowlTriggered = Signal.new() -- (player, houseId) someone held the bowl's prompt through
HouseService.Rerolled = Signal.new() -- () after every Dawn

type HouseState = {
	houseType: string,
	owner: string,
	preference: string,
	bowl: Model?,
	lantern: Model?, -- the seller's
}

local houses: { [string]: HouseState } = {}
local BOWL_COLORS = { "FF3B5C", "FFD23F", "7CFF4F", "B06CFF", "3FC8FF" } -- the pieces in a full bowl
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

-- What stands right in front of the door, where a homeowner comes out after you: they walk through
-- it (CollisionGroups), and their paths go round it if there's room, else through.
local function passable(m: Model)
	CollisionGroups.put(m, CollisionGroups.PORCH)
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			local modifier = Instance.new("PathfindingModifier")
			modifier.Label = "Porch"
			modifier.PassThrough = true
			modifier.Parent = part
		end
	end
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
	m.Name = "CandyBowl"
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
	for i, color in BOWL_COLORS do
		local angle = i / #BOWL_COLORS * math.pi * 2
		local at = base * CFrame.new(math.cos(angle) * 0.6, 3.4, math.sin(angle) * 0.6)
		local piece = Parts.candy(m, "Candy", 0.55, at * CandyPiece.tumble(i), color)
		piece:SetAttribute("Order", i) -- (the last ones go first as it empties)
	end
	local candy = rng:int(Bowl.CANDY[1], Bowl.CANDY[2])
	m:SetAttribute("Candy", candy)
	m:SetAttribute("Full", candy)
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

	-- One thing to do with it: take the lot (held, so you have time to think better of it). Its words
	-- are the client's (DoorController: how much is left, or that your bucket's full).
	local takeAll = Parts.prompt(bowl, "Take it all", "Candy bowl", 9, Bowl.HOLD)
	takeAll.Name = "TakeAll"
	takeAll.Triggered:Connect(function(player)
		HouseService.BowlTriggered:Fire(player, houseId)
	end)
	passable(m)
	m.Parent = house.model
	return m
end

-- The seller's lantern at `houseId`, hung beside his door so you can pick his house out from the
-- street. He's inside: knock and he comes to the door like any homeowner (DoorService).
local function hangLantern(houseId: string): Model?
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return nil
	end
	local door = house.door
	local m = Instance.new("Model")
	m.Name = "SellerLantern"
	local side = door.CFrame * CFrame.new(door.Size.X / 2 + 0.9, door.Size.Y * 0.15, -0.45)
	Parts.decor(
		Parts.block(
			m,
			"Bracket",
			Vector3.new(0.12, 0.12, 0.6),
			side * CFrame.new(0, 0.55, 0.15),
			"2A1E16",
			Enum.Material.Metal
		)
	)
	local lantern =
		Parts.decor(Parts.block(m, "Lantern", Vector3.new(0.5, 0.7, 0.5), side, "FFB45A", Enum.Material.Neon))
	Parts.light(lantern, 18, 1.6, "FF9A40")
	m.Parent = house.model
	return m
end

-- `refill`: a new night, so a bowl that stays a bowl is put out full again.
local function apply(houseId: string, state: HouseState, refill: boolean?)
	local house = WorldService.getHouse(houseId)
	if house == nil then
		return
	end
	local previous = houses[houseId]
	if previous and previous.bowl and (state.houseType ~= "Bowl" or refill) then
		previous.bowl:Destroy()
	elseif previous and previous.bowl then
		state.bowl = previous.bowl
	end
	if state.houseType == "Bowl" and state.bowl == nil then
		state.bowl = buildBowl(houseId)
	end
	if previous and previous.lantern and state.houseType ~= "Seller" then
		previous.lantern:Destroy()
	elseif previous and previous.lantern then
		state.lantern = previous.lantern
	end
	if state.houseType == "Seller" and state.lantern == nil then
		state.lantern = hangLantern(houseId)
	end
	-- The seller is his house's homeowner (if his meshes are in the place; else whoever lives there sells).
	if state.houseType == "Seller" and CharacterRig.ready(Items.SELLER.CHARACTER) then
		house.model:SetAttribute("OwnerModel", Items.SELLER.CHARACTER)
	end
	if state.houseType == "Seller" then
		house.model:SetAttribute("ReadyAt", nil) -- no cooldown at his door (nor a ring left from before)
	end
	houses[houseId] = state
	house.model:SetAttribute("HouseType", state.houseType)
	house.model:SetAttribute("Owner", state.owner)
	house.model:SetAttribute("Preference", state.preference)
	-- Never who lives there: you find out when the door opens.
	house.prompt.ObjectText = if state.houseType == "LightsOff"
		then "Nobody's home..."
		elseif state.houseType == "Seller" then "Seller"
		else "Trick or treat!"
	-- Bowl and open houses don't answer the door, and there's no knocking at them; a lights-off one
	-- takes your knock, but nobody comes (DoorService).
	house.prompt.Enabled = state.houseType ~= "Bowl" and state.houseType ~= "Open"
	-- An open house's hall is lit, the chandelier's candles too (World/BlenderLot.dressHall); the
	-- client swings its door open.
	local open = state.houseType == "Open"
	local hallLight = house.model:FindFirstChild("HallLight")
	if hallLight then
		for _, child in hallLight:GetChildren() do
			if child:IsA("PointLight") then
				child.Enabled = open
			elseif child:IsA("BasePart") then
				child.Transparency = if open then 0.1 else 1
			end
		end
	end
end

-- Changes one house's type (the Witching Hour, admin). Made a bowl, it gets a full one and its lamp
-- mended.
function HouseService.setType(houseId: string, houseType: string)
	local current = houses[houseId]
	local house = WorldService.getHouse(houseId)
	if current and current.houseType == "Seller" and houseType ~= "Seller" and house then
		HomeownerService.roll(house.model, house.neighborhood) -- someone else lives there again
	end
	if current then
		local bowl = houseType == "Bowl"
		apply(houseId, {
			houseType = houseType,
			owner = current.owner,
			preference = current.preference,
		}, bowl)
		if bowl and house then
			house.model:SetAttribute("LampBroken", nil)
			house.model:SetAttribute("LampBrokenBy", nil)
		end
	end
end

-- Only a house with a real front door that swings and a hall behind it can stand open.
local function canOpen(model: Model): boolean
	local door = model:FindFirstChild("FrontDoor", true)
	return door ~= nil
		and door:IsA("Model")
		and CollectionService:HasTag(door, "Hinged")
		and model:FindFirstChild("HallLight") ~= nil
end

-- Dawn: every house gets a new type, owner and preference. Every street that can have an open
-- house gets at least one.
function HouseService.reroll()
	local openable: { [string]: { string } } = {} -- neighbourhood -> houses that could be open
	local opened: { [string]: boolean } = {}
	for houseId, house in WorldService.info().houses do
		local neighborhood = Neighborhoods.byId[house.neighborhood]
		local weights = HouseTypes.WEIGHTS[math.clamp(neighborhood.tier, 1, #HouseTypes.WEIGHTS)]
		local houseType = rng:weighted(weights) or "Normal"
		local able = canOpen(house.model)
		if houseType == "Open" and not able then
			houseType = "Normal"
		end
		if able and houseType == "Normal" then
			openable[house.neighborhood] = openable[house.neighborhood] or {}
			table.insert(openable[house.neighborhood], houseId)
		end
		if houseType == "Open" then
			opened[house.neighborhood] = true
		end
		apply(houseId, {
			houseType = houseType,
			owner = rng:pick(Dialogue.ORDER),
			preference = rng:pick(HouseTypes.PREFERENCES),
		}, true)
		house.model:SetAttribute("LampBroken", nil) -- mended for the new night
		house.model:SetAttribute("LampBrokenBy", nil)
		HomeownerService.roll(house.model, house.neighborhood)
	end
	for neighborhood, ids in openable do
		if not opened[neighborhood] then
			HouseService.setType(rng:pick(ids), "Open")
		end
	end
	-- One seller a street, at any house that isn't open or a bowl.
	local sellable: { [string]: { string } } = {}
	for houseId, state in houses do
		local house = WorldService.getHouse(houseId)
		if house and state.houseType ~= "Open" and state.houseType ~= "Bowl" then
			sellable[house.neighborhood] = sellable[house.neighborhood] or {}
			table.insert(sellable[house.neighborhood], houseId)
		end
	end
	for _, ids in sellable do
		table.sort(ids) -- (the same pick for the same roll)
		HouseService.setType(rng:pick(ids), "Seller")
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
	WorldEventsService.WitchingEnded:Connect(HouseService.reroll) -- the town changes
	WorldEventsService.WitchingStarted:Connect(witching)
end

return HouseService
