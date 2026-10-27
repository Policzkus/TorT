--!strict
-- Blackouts (Config/Knifer.BLACKOUT). When the Knifer comes onto a street its power goes
-- (KniferService: WorldState's Blackout_<street> is when, BlackoutFrom_<street> where he came out):
-- every electric light on it dies, in a wave from where he came out, each one stuttering a moment
-- first. Porch lights, windows and the rooms behind them, street lamps (each with a pop as it goes),
-- string lights, hall lights, the light of a hall behind an opening door (HomeownerController asks
-- isOut). A deep thud as the power goes, for whoever's on the street, and the night itself darker
-- (ZoneLightingController). What's left: candles and jack-o'-lanterns (they burn on), the seller's
-- lantern, the Candy Boxes' glow (you need to find them), the moon, the passing cars (Traffic), the
-- Knifer's eyes, and flashlights (their own batteries). When the power's back the lights come on
-- again one by one, stuttering as they catch.
-- What counts as on a street: everything in its folder of the world, and its houses wherever they
-- stand. What's electric: every PointLight, SpotLight and SurfaceLight, and every glowing (Neon)
-- part, but what's kept above. Whatever changes them meanwhile (a trick house's porch light, a house
-- put out at Dawn) is remembered and comes back with the power, not overridden.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Knifer = require(Shared.Config.Knifer)
local Houses = require(Shared.Modules.Houses)
local Sound = require(script.Parent.SoundController)

local BlackoutController = {}

local RULES = Knifer.BLACKOUT
local CANDLES = { PumpkinLight = true, PumpkinGlow = true } -- they burn on
local KEPT = { SellerLantern = true, Hunters = true } -- whole models/folders that keep their light
local DARK = Color3.fromRGB(14, 14, 18)
local FRESH = 3 -- seconds: a blackout older than this when you see it (you've just joined) is just dark
local STUTTER = { 0.05, 0.12, 0.17 } -- seconds: off, back on, off again... then out for good

type Held = {
	instance: Instance,
	enabled: boolean?, -- a light's, from before (or what something else has set it to since)
	material: Enum.Material?, -- a glowing part's
	color: Color3?,
	watch: RBXScriptConnection?,
	stuttering: boolean,
}
type Street = { out: boolean, held: { [Instance]: Held }, added: { RBXScriptConnection }, cut: number }

local streets: { [string]: Street } = {}
local streetOfHouse: { [Instance]: string } = {}
local worldState: Instance? = nil

local function streetOf(id: string): Street
	local street = streets[id]
	if street == nil then
		street = { out = false, held = {}, added = {}, cut = 0 }
		streets[id] = street
	end
	return street
end

-- Whether `instance` keeps its light whatever (a candle, the Candy Box, the moon's fill...).
local function kept(instance: Instance): boolean
	local node: Instance? = instance
	while node and node ~= Workspace do
		local name = node.Name
		if
			CANDLES[name]
			or KEPT[name]
			or string.sub(name, 1, 9) == "CandyBox_"
			or string.sub(name, 1, 9) == "MoonFill_"
			or CollectionService:HasTag(node, "Knifer")
		then
			return true
		end
		node = node.Parent
	end
	return false
end

local function electric(instance: Instance): boolean
	if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		return not kept(instance)
	end
	return instance:IsA("BasePart") and instance.Material == Enum.Material.Neon and not kept(instance)
end

-- Everything on street `id`: its folder in the world, its houses, its handmade lots.
local function rootsOf(id: string): { Instance }
	local roots: { Instance } = {}
	local world = Workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild(id)
	if folder then
		table.insert(roots, folder)
	end
	local handmade = Workspace:FindFirstChild("Handmade")
	local lots = handmade and handmade:FindFirstChild(id)
	if lots then
		table.insert(roots, lots)
	end
	for _, door in CollectionService:GetTagged("Door") do
		local house = if door:GetAttribute("Neighborhood") == id then Houses.of(door) else nil
		if house then
			streetOfHouse[house] = id
			local inside = false
			for _, root in roots do
				if house:IsDescendantOf(root) then
					inside = true
				end
			end
			if not inside then
				table.insert(roots, house)
			end
		end
	end
	return roots
end

local function positionOf(instance: Instance): Vector3?
	local holder = if instance:IsA("BasePart") then instance else instance.Parent
	if holder and holder:IsA("BasePart") then
		return holder.Position
	elseif holder and holder:IsA("Attachment") then
		return holder.WorldPosition
	end
	return nil
end

-- Dark (a light off, a glowing part dull), or as it was.
local function dark(held: Held, on: boolean)
	local instance = held.instance
	if instance:IsA("Light") then
		instance.Enabled = if on then held.enabled == true else false
	elseif instance:IsA("BasePart") then
		instance.Material = if on then held.material or Enum.Material.Neon else Enum.Material.SmoothPlastic
		local color = held.color or instance.Color
		instance.Color = if on then color else color:Lerp(DARK, 0.8)
	end
end

-- `instance` goes out on `street`, and stays out (stuttering first unless `now`).
local function hold(street: Street, instance: Instance, now: boolean)
	if street.held[instance] then
		return
	end
	local held: Held = { instance = instance, stuttering = not now }
	if instance:IsA("Light") then
		held.enabled = instance.Enabled
		-- Something else switching it while the power's off (a trick house's porch light): that's what
		-- it'll be when the power's back; it stays off till then.
		held.watch = instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if street.out and not held.stuttering and instance.Enabled then
				held.enabled = true
				instance.Enabled = false
			end
		end)
	elseif instance:IsA("BasePart") then
		held.material, held.color = instance.Material, instance.Color
		held.watch = instance:GetPropertyChangedSignal("Material"):Connect(function()
			if street.out and not held.stuttering and instance.Material ~= Enum.Material.SmoothPlastic then
				held.material, held.color = instance.Material, instance.Color
				if instance.Material == Enum.Material.Neon then
					dark(held, false)
				end
			end
		end)
	end
	street.held[instance] = held
	if now then
		dark(held, false)
		return
	end
	-- A stutter: off, on, off... out.
	dark(held, false)
	task.delay(STUTTER[1], dark, held, true)
	task.delay(STUTTER[2], dark, held, false)
	task.delay(STUTTER[3], function()
		dark(held, true)
		task.wait(0.06)
		held.stuttering = false
		if street.out then
			dark(held, false)
		end
	end)
end

local function release(street: Street, held: Held)
	if held.watch then
		held.watch:Disconnect()
	end
	street.held[held.instance] = nil
	if held.instance.Parent then
		dark(held, true)
	end
end

-- A street lamp's bulb pops as it goes (and clicks back on).
local function lampSound(instance: Instance, speed: number)
	local holder = instance.Parent
	if holder and holder:IsA("BasePart") and CollectionService:HasTag(holder, "StreetLamp") then
		Sound.play("Tick", { at = holder, speed = speed, volume = 1.4 })
	end
end

-- The power goes on `id`: from `from` outward (all at once if `instant`: you've only just come).
local function cut(id: string, from: Vector3?, instant: boolean)
	local street = streetOf(id)
	if street.out then
		return
	end
	street.out = true
	street.cut += 1
	local mine = street.cut
	if not instant and Players.LocalPlayer:GetAttribute("Zone") == id then
		Sound.play("Unlock", { speed = 0.5, volume = 0.9 }) -- the power dying: a deep thud
	end
	for _, root in rootsOf(id) do
		for _, instance in root:GetDescendants() do
			if electric(instance) then
				local at = positionOf(instance)
				local delay = if instant
						or from == nil
						or at == nil
					then 0
					else (at - from).Magnitude / RULES.wave + math.random() * RULES.stagger
				if instant then
					hold(street, instance, true)
				else
					task.delay(delay, function()
						if street.out and street.cut == mine and instance.Parent then
							hold(street, instance, false)
							lampSound(instance, 0.55)
						end
					end)
				end
			end
		end
		-- Anything put up meanwhile (decorations at Dawn, a hall light) is out too.
		table.insert(
			street.added,
			root.DescendantAdded:Connect(function(instance)
				task.defer(function()
					if street.out and instance.Parent and electric(instance) then
						hold(street, instance, true)
					end
				end)
			end)
		)
	end
end

-- The power's back on `id`: the lights come on again one by one, stuttering as they catch.
local function restore(id: string)
	local street = streets[id]
	if street == nil or not street.out then
		return
	end
	street.out = false
	street.cut += 1
	for _, connection in street.added do
		connection:Disconnect()
	end
	table.clear(street.added)
	for _, held in street.held do
		held.stuttering = true
		task.delay(math.random() * RULES.backOver, function()
			if street.out then
				held.stuttering = false -- it went again: still out, and kept out
				return
			end
			dark(held, true)
			task.wait(0.07)
			dark(held, false)
			task.wait(0.05)
			release(street, held)
			lampSound(held.instance, 0.8)
		end)
	end
end

local function onAttribute(name: string)
	local state = worldState
	if state == nil or string.sub(name, 1, 9) ~= "Blackout_" then
		return
	end
	local id = string.sub(name, 10)
	local since = state:GetAttribute(name)
	if type(since) == "number" then
		local from = state:GetAttribute("BlackoutFrom_" .. id)
		cut(id, if typeof(from) == "Vector3" then from else nil, Workspace:GetServerTimeNow() - since > FRESH)
	else
		restore(id)
	end
end

-- Whether the power's off where `house` stands (HomeownerController: no light from its hall).
function BlackoutController.isOut(house: Instance): boolean
	local id = streetOfHouse[house]
	if id == nil then
		for _, door in CollectionService:GetTagged("Door") do
			if Houses.of(door) == house then
				local neighborhood = door:GetAttribute("Neighborhood")
				if type(neighborhood) == "string" then
					id = neighborhood
					streetOfHouse[house] = neighborhood
				end
				break
			end
		end
	end
	local street = if id then streets[id] else nil
	return street ~= nil and street.out
end

-- Whether the power's off on street `id` (ZoneLightingController: the night darker).
function BlackoutController.streetOut(id: string): boolean
	local street = streets[id]
	return street ~= nil and street.out
end

function BlackoutController.Start()
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("WorldState", 30)
		if state == nil then
			return
		end
		worldState = state
		state.AttributeChanged:Connect(onAttribute)
		for name in state:GetAttributes() do
			onAttribute(name)
		end
	end)
end

return BlackoutController
