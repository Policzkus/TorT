--!strict
-- The seller's things (Config/Items): buying them at his door (BuyItem: banked candy, while he's out
-- and you're near, at most Item.most of each, kept in PlayerData.consumables) and using them from the
-- bar (UseItem, Controllers/ItemsController):
--   Bandage: Items.BANDAGE.heal health back, if you're hurt (HealthService.heal): the only way back.
--   Bear trap: set at your feet (a model tagged "BearTrap"; every client hears it snap). A hunter
--     (AI/Hunter: the Knifer, a homeowner after you) whose feet come within TRAP.reach of it is held
--     there TRAP.hold seconds (its HeldUntil): it snaps shut on them (Sprung) and is gone after.
--   Firecracker: thrown ahead along where you look (short of a wall), it fizzes, then bangs (tagged
--     "Firecracker": BangAt, BangFor, for the clients' bangs and flashes). Every hunter within
--     FIRECRACKER.reach of it while it bangs goes to it, seeing and hearing no one till
--     FIRECRACKER.blind seconds after the first bang (LuredTo, LuredUntil).
--   Lockpick: nothing yet (the user).
-- Only out on the streets, up and about.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Health = require(ReplicatedStorage.Shared.Config.Health)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Hunter = require(script.Parent.Parent.AI.Hunter)
local Parts = require(script.Parent.Parent.World.Parts)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local HouseService = require(script.Parent.HouseService)
local NotifyService = require(script.Parent.NotifyService)
local RagdollService = require(script.Parent.RagdollService)
local WorldService = require(script.Parent.WorldService)

local ItemService = {}

local TRAP, FIRECRACKER = Items.TRAP, Items.FIRECRACKER
local CHECK = 0.1 -- seconds between looks at the traps

type Jaw = { part: BasePart, shut: CFrame, teeth: { { part: BasePart, offset: CFrame } } }
type Trap = { model: Model, at: Vector3, owner: Player, setAt: number, jaws: { Jaw } }

local traps: { Trap } = {}
local lastUse: { [Player]: number } = {}
local folder: Folder? = nil

local function things(): Folder
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "SellerThings"
		made.Parent = Workspace
		folder = made
	end
	return folder :: Folder
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- The ground under `at` (the world's, not people's), within `depth` studs below it.
local function ground(at: Vector3, depth: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldService.info().folder }
	local hit = Workspace:Raycast(at, Vector3.new(0, -depth, 0), params)
	return hit and hit.Position
end

-- Whether `position` is out on a street (where the hunters are).
local function onStreet(position: Vector3): boolean
	local zone = WorldService.zoneAt(position)
	return zone ~= nil and WorldService.info().streets[zone] ~= nil
end

-- Buying ---------------------------------------------------------------------------------------

local function buy(player: Player, houseId: any, itemId: any): (boolean, string)
	if type(houseId) ~= "string" or not Items.sells(itemId) then
		return false, "He doesn't sell that"
	end
	local item = (Items :: any)[itemId] :: Items.Item
	local house = WorldService.getHouse(houseId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if house == nil or HouseService.houseType(houseId) ~= "Seller" or house.model:GetAttribute("OwnerOut") ~= true then
		return false, "He's gone back in"
	end
	if root == nil or (root.Position - house.door.Position).Magnitude > Items.SELLER.RANGE then
		return false, "You're too far from the seller"
	end
	local data = DataService.get(player)
	if data == nil then
		return false, "Still loading your candy..."
	end
	if (data.consumables[itemId] or 0) >= item.most then
		return false, `You can't carry more than {item.most}`
	end
	local price = Items.price(itemId, house.neighborhood)
	if not CandyService.spend(player, price) then
		return false, `You need {Format.number(price - data.candy)} more 🍬`
	end
	DataService.mutate(player, "consumables", function(consumables)
		consumables[itemId] = (consumables[itemId] or 0) + 1
	end)
	return true, `{item.icon} {item.name} bought`
end

-- Bandage --------------------------------------------------------------------------------------

local function bandage(player: Player): (boolean, string?)
	if HealthService.get(player) >= Health.MAX then
		return false, "You're not hurt"
	end
	if not HealthService.heal(player, Items.BANDAGE.heal) then
		return false, nil
	end
	return true, nil
end

-- Bear trap ------------------------------------------------------------------------------------

-- An open trap at `feet`: a plate, a jaw either side lying open with its teeth, a spring. Returns it
-- with where each jaw goes when it snaps (stood up on its hinge, meeting over the plate).
local function buildTrap(feet: Vector3, yaw: number): (Model, { Jaw })
	local m = Instance.new("Model")
	m.Name = "BearTrap"
	local base = CFrame.new(feet) * CFrame.Angles(0, yaw, 0)
	local metal, dark = "6A6D72", "3A3C40"
	Parts.decor(Parts.disc(m, "Plate", 1.1, 0.12, base, dark, Enum.Material.Metal))
	Parts.decor(Parts.cylinder(m, "Spring", 1.9, 0.18, base * CFrame.new(0, 0.1, 0), metal, Enum.Material.Metal))
	local jaws: { Jaw } = {}
	for _, side in { -1, 1 } do
		local hinge = base * CFrame.new(0, 0.1, side * 0.55) -- at the plate's edge
		local open = hinge * CFrame.new(0, 0, side * 0.35) -- lying flat out to the side
		local jaw = Parts.decor(Parts.block(m, "Jaw", Vector3.new(1.8, 0.1, 0.7), open, metal, Enum.Material.Metal))
		local teeth = {}
		for k = -2, 2 do
			local offset = CFrame.new(k * 0.36, 0.13, -side * 0.3) -- along its inner edge
			local tooth = Parts.decor(
				Parts.wedge(m, "Tooth", Vector3.new(0.08, 0.16, 0.14), open * offset, metal, Enum.Material.Metal)
			)
			table.insert(teeth, { part = tooth, offset = offset })
		end
		local shut = hinge * CFrame.Angles(-side * math.rad(140), 0, 0) * CFrame.new(0, 0, side * 0.35)
		table.insert(jaws, { part = jaw, shut = shut, teeth = teeth })
	end
	return m, jaws
end

local function setTrap(player: Player, root: BasePart): (boolean, string?)
	if not onStreet(root.Position) then
		return false, "Set it out on the street"
	end
	local set = 0
	for _, trap in traps do
		if trap.owner == player then
			set += 1
		end
	end
	if set >= TRAP.set then
		return false, `You've {TRAP.set} out already`
	end
	local feet = ground(root.Position, root.Size.Y / 2 + 8)
	if feet == nil then
		return false, "Set it on the ground"
	end
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	local model, jaws = buildTrap(feet, yaw)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("SetAt", now())
	CollectionService:AddTag(model, "BearTrap")
	model.Parent = things()
	table.insert(traps, { model = model, at = feet, owner = player, setAt = os.clock(), jaws = jaws })
	return true, nil
end

-- It snaps shut on `hunter` and holds them.
local function spring(trap: Trap, hunter: Model)
	trap.model:SetAttribute("Sprung", now())
	for _, jaw in trap.jaws do
		jaw.part.CFrame = jaw.shut
		for _, tooth in jaw.teeth do
			tooth.part.CFrame = jaw.shut * tooth.offset
		end
	end
	hunter:SetAttribute("HeldUntil", now() + TRAP.hold)
	local who = if hunter.Name == "Knifer" then "the Knifer" else "a homeowner"
	if trap.owner.Parent == Players then
		NotifyService.send(trap.owner, `🪤 Your trap caught {who}!`, "success")
	end
	local model = trap.model
	task.delay(TRAP.hold + 1.5, function()
		model:Destroy()
	end)
end

local function checkTraps()
	local clock = os.clock()
	local hunters = Hunter.folder():GetChildren()
	for index = #traps, 1, -1 do
		local trap = traps[index]
		if trap.model.Parent == nil or clock - trap.setAt > TRAP.lasts then
			trap.model:Destroy()
			table.remove(traps, index)
			continue
		end
		for _, hunter in hunters do
			local root = hunter:IsA("Model") and hunter.PrimaryPart
			if
				root
				and flat(root.Position - trap.at).Magnitude <= TRAP.reach
				and math.abs(root.Position.Y - trap.at.Y) < 8
			then
				table.remove(traps, index)
				spring(trap, hunter :: Model)
				break
			end
		end
	end
end

-- Firecracker ----------------------------------------------------------------------------------

-- Every hunter near enough to `spot` is drawn to it, blind till `untilAt` (one already drawn to it
-- keeps its time).
local function lure(spot: Vector3, untilAt: number)
	for _, hunter in Hunter.folder():GetChildren() do
		local root = hunter:IsA("Model") and hunter.PrimaryPart
		if
			root
			and (root.Position - spot).Magnitude <= FIRECRACKER.reach
			and hunter:GetAttribute("LuredTo") ~= spot
		then
			hunter:SetAttribute("LuredTo", spot)
			hunter:SetAttribute("LuredUntil", untilAt)
		end
	end
end

local function throw(player: Player, root: BasePart, aim: any): (boolean, string?)
	if not onStreet(root.Position) then
		return false, "Throw it out on the street"
	end
	local along = flat(if typeof(aim) == "Vector3" and aim == aim then aim else root.CFrame.LookVector)
	if along.Magnitude < 0.1 then
		along = flat(root.CFrame.LookVector)
	end
	along = along.Unit
	local from = root.Position + Vector3.new(0, 1, 0)
	local params = RaycastParams.new()
	local ignore: { Instance } = { Hunter.folder(), things() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(from, along * FIRECRACKER.throw, params)
	local reach = if hit then math.max(2, (hit.Position - from).Magnitude - 1.5) else FIRECRACKER.throw
	local spot = ground(from + along * reach + Vector3.new(0, 4, 0), 30) or (from + along * reach)
	local m = Instance.new("Model")
	m.Name = "Firecracker"
	local stick = Parts.decor(
		Parts.cylinder(
			m,
			"Stick",
			0.7,
			0.16,
			CFrame.new(spot + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0),
			"C81E1A"
		)
	)
	Parts.decor(Parts.block(m, "Fuse", Vector3.new(0.25, 0.03, 0.03), stick.CFrame * CFrame.new(0.45, 0, 0), "D8C8A0"))
	m.PrimaryPart = stick
	local bangAt = now() + FIRECRACKER.fuse
	m:SetAttribute("From", from)
	m:SetAttribute("BangAt", bangAt)
	m:SetAttribute("BangFor", FIRECRACKER.bangs)
	m:SetAttribute("Owner", player.UserId)
	CollectionService:AddTag(m, "Firecracker")
	m.Parent = things()
	task.spawn(function()
		task.wait(FIRECRACKER.fuse)
		-- While it bangs, whoever comes near enough is drawn too.
		local untilAt = now() + FIRECRACKER.blind
		local stopAt = os.clock() + FIRECRACKER.bangs
		while os.clock() < stopAt and m.Parent do
			lure(spot, untilAt)
			task.wait(0.4)
		end
		task.wait(1)
		m:Destroy()
	end)
	return true, nil
end

-- Using ----------------------------------------------------------------------------------------

local function use(player: Player, itemId: any, aim: any)
	if not Items.sells(itemId) then
		return
	end
	local clock = os.clock()
	if clock - (lastUse[player] or -math.huge) < Items.COOLDOWN then
		return
	end
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		data == nil
		or (data.consumables[itemId] or 0) <= 0
		or root == nil
		or humanoid == nil
		or humanoid.Health <= 0
		or HealthService.isFainting(player)
		or RagdollService.isDown(player)
	then
		return
	end
	local used, problem = false, nil
	if itemId == "Bandage" then
		used, problem = bandage(player)
	elseif itemId == "BearTrap" then
		used, problem = setTrap(player, root)
	elseif itemId == "Firecracker" then
		used, problem = throw(player, root, aim)
	else
		NotifyService.send(player, "🗝️ No use for it yet. Hold on to it.", "info")
		return
	end
	if not used then
		if problem then
			NotifyService.send(player, problem, "error")
		end
		return
	end
	lastUse[player] = clock
	DataService.mutate(player, "consumables", function(consumables)
		local left = (consumables[itemId] or 1) - 1
		consumables[itemId] = if left > 0 then left else nil
	end)
	Net.event("ItemUsed"):FireAllClients(player.UserId, itemId)
end

function ItemService.Start()
	Net.handle("BuyItem", buy, { rate = 4, burst = 8 })
	Net.connect("UseItem", use, { rate = 4, burst = 6 })
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= CHECK then
			since = 0
			checkTraps()
		end
	end)
end

return ItemService
