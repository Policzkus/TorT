--!strict
-- Draws each house's "tells" from the attributes HouseService sets (PROMPT §3.5), all locally:
--   preference badge over the door, dark windows for Lights Off, a flickering porch light for
--   Trick houses, string lights + extra pumpkins for Decorated houses, the front door standing
--   open on a lit hall for Open houses (with someone standing in the hall: it turns to whoever's
--   nearest, comes a spot closer each time the light blinks while someone watches, and is gone in a
--   blackout when anyone comes close; Services/HallFigureService decides, so everyone sees the same),
--   and the gold beam over the Full-Size Bar house (from ReplicatedStorage.WorldState).
--   Jack-o'-lantern candles on the Blender houses flicker.
--   A candy bowl's porch lamp bursts when someone takes the lot (LampBroken, the server time it went;
--   LampBrokenBy, who did it: DoorService): it buzzes and flickers, pops in a shower of sparks and
--   glass, and the porch stays dark till Dawn. Whoever took it hears something stir in the house.
--   When the homeowner comes out after them (OwnerAway, OwnerChaseService) the front door flies open
--   with a bang, and slams shut again when they're back in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Houses = require(Shared.Modules.Houses)
local Events = require(Shared.Config.Events)
local HouseTypes = require(Shared.Config.HouseTypes)
local Sound = require(script.Parent.SoundController)
local Chip = require(script.Parent.Parent.UI.Components.Chip)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local HouseVisualController = {}

type Open = {
	hinge: Model,
	closed: CFrame,
	light: PointLight?,
	steady: number,
	glow: BasePart?, -- the HallLight marker (its children: the light, the chandelier's flames)
	spots: { BasePart }, -- where the figure stands, from the far end of the hall to the door
	index: number, -- which spot it's at
	figure: BasePart?,
	facing: CFrame?, -- its turn toward whoever's nearest (eased)
	gone: boolean,
	busy: boolean, -- in the middle of a blink
	connections: { RBXScriptConnection }, -- following HallSpot / HallGone
}

-- The front door flung open while the homeowner's out after someone.
type Away = { hinge: Model, closed: CFrame, angle: number, token: number }

type Tracked = {
	door: BasePart,
	model: Model,
	decor: Folder?,
	badge: BillboardGui?,
	open: Open?, -- standing open (an Open house)
	away: Away?, -- its door flung open: the homeowner's out
	saved: { [Instance]: { [string]: any } }, -- original properties of things we changed
}

local OPEN_SHARE = 0.92 -- of its OpenAngle an open house's door stands at
-- A bursting porch lamp: played if it went less than `recent` seconds ago and you're within `near`
-- studs (otherwise it's just dark); `flickers` buzzing flickers first; `sparks` and `shards` of glass.
local LAMP = { recent = 3, near = 160, flickers = 6, sparks = 34, shards = 7 }
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FIGURE_TURN = 2.2 -- how quickly it turns to face whoever's nearest
local FIGURE_LOOK = 60 -- studs: it turns to the nearest kid within this
local BLINK = 0.32 -- seconds the hall goes dark when it moves
local FIGURES = { "FigureWidow", "FigureTall", "FigureGirl" } -- Assets.Furniture (art/scripts/figures.py)

local tracked: { [Model]: Tracked } = {}
local opened: { [Model]: Tracked } = {}
local tricky: { [Model]: boolean } = {}
local candles: { [PointLight]: number } = {} -- jack-o'-lantern candles and their steady brightness
local beam: Model? = nil

local function save(entry: Tracked, instance: Instance, property: string)
	local list = entry.saved[instance]
	if list == nil then
		list = {}
		entry.saved[instance] = list
	end
	if list[property] == nil then
		list[property] = (instance :: any)[property]
	end
end

local function restore(entry: Tracked)
	for instance, properties in entry.saved do
		for property, value in properties do
			(instance :: any)[property] = value
		end
	end
	table.clear(entry.saved)
end

local function porchLights(model: Model): { PointLight }
	local lights = {}
	local porch = model:FindFirstChild("PorchLight", true)
	if porch then
		for _, child in porch:GetChildren() do
			if child:IsA("PointLight") then
				table.insert(lights, child)
			end
		end
	end
	return lights
end

-- Glowing parts that go dark with the lights (Blender Victorian: lantern, candles, room bulbs).
local GLOWS = { LanternGlow = true, PumpkinGlow = true, RoomBulb = true }

local function lightsOff(entry: Tracked)
	for _, descendant in entry.model:GetDescendants() do
		if descendant:IsA("BasePart") and (descendant.Name == "Window" or descendant.Name == "PorchLight") then
			save(entry, descendant, "Color")
			save(entry, descendant, "Material")
			descendant.Color = Color3.fromHex("161A26")
			descendant.Material = Enum.Material.Glass
		elseif descendant:IsA("BasePart") and GLOWS[descendant.Name] then
			-- The Blender house's lantern, jack-o'-lantern candles and room bulbs go out.
			save(entry, descendant, "Color")
			save(entry, descendant, "Material")
			descendant.Color = Color3.fromHex("1A1612")
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("PointLight") then
			save(entry, descendant, "Enabled")
			descendant.Enabled = false
		end
	end
end

-- The porch lamp: its glass (parts named PorchLight, the Blender lantern's LanternGlow) and the
-- lights in it.
local function lampOf(model: Model): ({ BasePart }, { Light })
	local parts, lights = {}, {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and (descendant.Name == "PorchLight" or descendant.Name == "LanternGlow") then
			table.insert(parts, descendant)
			for _, child in descendant:GetChildren() do
				if child:IsA("Light") then
					table.insert(lights, child)
				end
			end
		end
	end
	return parts, lights
end

-- A burst lamp: dark, the glass gone dull.
local function darkenLamp(entry: Tracked)
	local parts, lights = lampOf(entry.model)
	for _, part in parts do
		save(entry, part, "Color")
		save(entry, part, "Material")
		part.Color = Color3.fromHex("14120F")
		part.Material = Enum.Material.Glass
	end
	for _, light in lights do
		save(entry, light, "Enabled")
		light.Enabled = false
	end
end

-- The lamp goes: a buzz and a few flickers, then a pop, sparks showering down and bits of glass, and
-- dark. `thief`: you're the one who did it, and something in the house heard.
local function burstLamp(entry: Tracked, thief: boolean, done: () -> ())
	local parts, lights = lampOf(entry.model)
	local anchor = parts[1] or entry.door
	local at = if parts[1]
		then parts[1].Position
		else entry.door.Position + Vector3.new(0, entry.door.Size.Y / 2 + 1.5, 0)
	for _, light in lights do
		save(entry, light, "Enabled") -- (the flicker leaves them however; Dawn puts them back as they were)
		save(entry, light, "Brightness")
	end
	task.spawn(function()
		Sound.play("Overflow", { at = anchor, volume = 1.4, speed = 0.8 }) -- the buzz
		for i = 1, LAMP.flickers do
			local on = i % 2 == 0
			for _, light in lights do
				light.Enabled = on
				light.Brightness = (entry.saved[light] and entry.saved[light].Brightness or light.Brightness)
					* (if on then 1.6 else 1)
			end
			task.wait(0.04 + math.random() * 0.06)
		end
		-- The pop: a white flash, then nothing.
		for _, light in lights do
			light.Enabled = true
			light.Brightness = (entry.saved[light] and entry.saved[light].Brightness or 1) * 4
		end
		Sound.play("KnockSingle", { at = anchor, volume = 1, speed = 2.1 })
		Sound.play("Thud", { at = anchor, volume = 0.5, speed = 1.9 })
		for k = 1, 3 do
			task.delay(0.08 * k + math.random() * 0.06, function()
				Sound.play("Pop", { at = anchor, volume = 0.5, speed = 1.7 + math.random() * 0.6 }) -- glass on the boards
			end)
		end
		local burst = Instance.new("Part")
		burst.Name = "LampBurst"
		burst.Size = Vector3.one * 0.2
		burst.Transparency = 1
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.CFrame = CFrame.new(at)
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = SPARK_TEXTURE
		sparks.Color = ColorSequence.new(Color3.fromHex("FFE2A0"), Color3.fromHex("FF7A1A"))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(0.35, 0.9)
		sparks.Speed = NumberRange.new(8, 18)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Acceleration = Vector3.new(0, -60, 0)
		sparks.Drag = 2
		sparks.Rate = 0
		sparks.Parent = burst
		burst.Parent = Workspace
		sparks:Emit(LAMP.sparks)
		for _ = 1, LAMP.shards do
			local shard = Instance.new("Part")
			shard.Name = "LampGlass"
			shard.Size = Vector3.new(0.12 + math.random() * 0.15, 0.04, 0.1 + math.random() * 0.15)
			shard.Color = Color3.fromHex("C9C2A8")
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.3
			shard.CanQuery = false
			shard.CanTouch = false
			shard.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, 0)
			shard.AssemblyLinearVelocity =
				Vector3.new(math.random() * 12 - 6, math.random() * 6, math.random() * 12 - 6)
			shard.Parent = Workspace
			task.delay(4, function()
				shard:Destroy()
			end)
		end
		task.delay(1.5, function()
			burst:Destroy()
		end)
		task.wait(0.07)
		done()
		if thief then
			-- Something in the house heard it.
			task.delay(0.8, function()
				Sound.play("Whispers", { at = entry.door, volume = 1.1 })
			end)
			task.delay(1.3, function()
				Sound.play("GhostWail", { at = entry.door, volume = 0.45, speed = 0.6 })
			end)
		end
	end)
end

-- The Blender decorations (Assets.Decor, art/scripts/decor.py) hung at the anchors a house model
-- brings (DecorAnchors: attachments named after the piece). False if either is missing.
local function blenderDecor(entry: Tracked, folder: Folder): boolean
	local anchors = entry.model:FindFirstChild("DecorAnchors")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local set = assets and assets:FindFirstChild("Decor")
	if anchors == nil or set == nil then
		return false
	end
	local placed = false
	for _, anchor in anchors:GetChildren() do
		local piece = if anchor:IsA("Attachment") then set:FindFirstChild(anchor.Name) else nil
		if piece and piece:IsA("Model") then
			local copy = piece:Clone()
			copy:PivotTo(anchor.WorldCFrame)
			copy.Parent = folder
			placed = true
		end
	end
	return placed
end

local function decorate(entry: Tracked)
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	if blenderDecor(entry, folder) then
		folder.Parent = entry.model
		entry.decor = folder
		return
	end
	local door = entry.door
	local colors = { Color3.fromHex("FF8A00"), Color3.fromHex("8A3AFF"), Color3.fromHex("7CFF4F") }
	-- String lights along the top of the front wall, either side of the door.
	for i = -7, 7 do
		if math.abs(i) > 1 then
			local bulb = Instance.new("Part")
			bulb.Shape = Enum.PartType.Ball
			bulb.Size = Vector3.one * 0.5
			bulb.Material = Enum.Material.Neon
			bulb.Color = colors[(i % 3) + 1]
			bulb.Anchored = true
			bulb.CanCollide = false
			bulb.CanQuery = false
			bulb.CastShadow = false
			bulb.CFrame = door.CFrame * CFrame.new(i * 1.4, door.Size.Y / 2 + 1.6 + (i % 2) * 0.25, -0.4)
			bulb.Parent = folder
		end
	end
	-- A big glowing pumpkin by the door.
	local pumpkin = Instance.new("Part")
	pumpkin.Shape = Enum.PartType.Ball
	pumpkin.Size = Vector3.new(2.6, 2.1, 2.6)
	pumpkin.Color = Color3.fromHex("FF7A1A")
	pumpkin.Anchored = true
	pumpkin.CanCollide = false
	pumpkin.CFrame = door.CFrame * CFrame.new(3.2, -door.Size.Y / 2 + 1, -2.4)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex("FF8A00")
	glow.Range = 10
	glow.Brightness = 1.2
	glow.Parent = pumpkin
	pumpkin.Parent = folder
	folder.Parent = entry.model
	entry.decor = folder
end

-- The badge over the door: what kind of house it is and which costume they like. Never who lives
-- there: you find that out when the door opens.
local function badgeText(model: Model): (string, string)
	local houseType = model:GetAttribute("HouseType")
	local preference = model:GetAttribute("Preference") :: string?
	local icon = if preference then HouseTypes.PREFERENCE_ICONS[preference] or "" else ""
	if houseType == "LightsOff" then
		return "💤", "Lights off"
	elseif houseType == "Bowl" then
		return "🍬", "Please take one"
	elseif houseType == "Seller" then
		return "🏮", "Seller"
	end
	local tag = if houseType == "Decorated" then "  ✨" else ""
	return icon .. tag, ""
end

local function updateBadge(entry: Tracked)
	local top, bottom = badgeText(entry.model)
	local badge = entry.badge
	if badge == nil then
		badge = create("BillboardGui", {
			Name = "HouseBadge",
			Size = UDim2.fromOffset(170, 30),
			StudsOffsetWorldSpace = Vector3.new(0, entry.door.Size.Y / 2 + 2.6, 0),
			MaxDistance = 48,
			LightInfluence = 0,
			Adornee = entry.door,
			Parent = entry.door,
		})
		Chip.new({ name = "Chip", parent = badge })
		entry.badge = badge
	end
	local gui = badge :: BillboardGui
	local chip = gui:FindFirstChild("Chip") :: Frame
	local label = chip:FindFirstChild("Text") :: TextLabel
	-- One HUD chip: the icons, then the words for houses that won't answer.
	label.Text = if top ~= "" and bottom ~= "" then `{top}  {bottom}` else top .. bottom
	chip.Visible = label.Text ~= ""
	-- Hidden while they're at the door: it would hang right behind their head (and a real door
	-- carries it into the house as it swings open).
	gui.Enabled = entry.model:GetAttribute("OwnerOut") ~= true
end

local function frontHinge(model: Model): Model?
	local door = model:FindFirstChild("FrontDoor", true)
	if door and door:IsA("Model") and CollectionService:HasTag(door, "Hinged") and door.PrimaryPart then
		return door
	end
	return nil
end

-- The homeowner's out after someone: the front door flung open with a bang (`open`), or slammed shut
-- behind them when they're back in. `animate` false: just put it there (it streamed in that way).
local function swingFront(entry: Tracked, open: boolean, animate: boolean)
	local hinge = frontHinge(entry.model)
	if hinge == nil or entry.open then
		return -- no door that swings, or an open house's (standOpen has it)
	end
	local away = entry.away
	if away == nil then
		if not open then
			return
		end
		away = { hinge = hinge, closed = hinge:GetPivot(), angle = 0, token = 0 }
		entry.away = away
	end
	local swing = away :: Away
	swing.token += 1
	local token = swing.token
	local target = if open then math.rad(((hinge:GetAttribute("OpenAngle") :: number?) or 90) * 0.95) else 0
	if not animate then
		swing.angle = target
		hinge:PivotTo(swing.closed * CFrame.Angles(0, target, 0))
		if not open then
			entry.away = nil
		end
		return
	end
	local slab = hinge.PrimaryPart
	if slab then
		Sound.play("DoorSlam", { at = slab, volume = 1, speed = if open then 1.15 else 0.95 })
	end
	task.spawn(function()
		local from = swing.angle
		local duration = if open then 0.22 else 0.32
		local t = 0
		while t < 1 and swing.token == token and hinge.Parent do
			t = math.min(1, t + RunService.Heartbeat:Wait() / duration)
			local eased = if open then 1 - (1 - t) ^ 3 else t * t -- flung open; swung shut, faster and faster
			swing.angle = from + (target - from) * eased
			hinge:PivotTo(swing.closed * CFrame.Angles(0, swing.angle, 0))
		end
		if not open and swing.token == token and entry.away == swing then
			entry.away = nil
		end
	end)
end

-- The figure templates that have been imported (the old silhouette when none of the new are).
local function figureTemplate(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local furniture = assets and assets:FindFirstChild("Furniture")
	if furniture == nil then
		return nil
	end
	local found = {}
	for _, name in FIGURES do
		local template = furniture:FindFirstChild(name)
		if template and template:IsA("BasePart") then
			table.insert(found, template)
		end
	end
	if #found > 0 then
		return found[math.random(1, #found)]
	end
	return furniture:FindFirstChild("Figure") :: BasePart?
end

-- The spots a figure can stand at in an open house's hall (World/BlenderLot.dressHall), far to near.
local function figureSpots(model: Model): { BasePart }
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

local hallChanged: (entry: Tracked, open: Open) -> () -- (below: it blinks the light)

-- An Open house: the front door swings open (or already stands open if it just streamed in), the
-- hall light (HouseService switches it on) gutters like a candle, and someone stands in the hall
-- where the server says (HallSpot; not at all while HallGone).
local function standOpen(entry: Tracked, animate: boolean)
	local hinge = frontHinge(entry.model)
	if hinge == nil then
		return
	end
	local closed = hinge:GetPivot()
	local angle = math.rad(((hinge:GetAttribute("OpenAngle") :: number?) or 90) * OPEN_SHARE)
	local glow = entry.model:FindFirstChild("HallLight") :: BasePart?
	local light = glow and glow:FindFirstChildOfClass("PointLight")
	local open: Open = {
		hinge = hinge,
		closed = closed,
		light = light,
		steady = if light then light.Brightness else 1,
		glow = glow,
		spots = figureSpots(entry.model),
		index = math.clamp(
			(entry.model:GetAttribute("HallSpot") :: number?) or 1,
			1,
			math.max(1, #figureSpots(entry.model))
		),
		figure = nil,
		facing = nil,
		gone = entry.model:GetAttribute("HallGone") == true,
		busy = false,
		connections = {},
	}
	entry.open = open
	opened[entry.model] = entry
	if animate then
		Sound.play("Creak", { at = hinge.PrimaryPart, speed = 0.65, volume = 0.8 })
		task.spawn(function()
			local t = 0
			while t < 1 and entry.open == open do
				t = math.min(1, t + RunService.Heartbeat:Wait() / 2.2)
				hinge:PivotTo(closed * CFrame.Angles(0, angle * (1 - (1 - t) ^ 3), 0))
			end
		end)
	else
		hinge:PivotTo(closed * CFrame.Angles(0, angle, 0))
	end
	if light then
		candles[light] = open.steady
	end
	local template = figureTemplate()
	local spot = open.spots[open.index]
	if spot and template then
		local figure = template:Clone()
		figure:PivotTo(spot.CFrame)
		figure.Parent = if open.gone then nil else entry.model
		open.figure = figure
		open.facing = spot.CFrame.Rotation
	end
	-- The server moves it (HallFigureService); each move is a blink of the hall light.
	local function follow()
		hallChanged(entry, open)
	end
	table.insert(open.connections, entry.model:GetAttributeChangedSignal("HallSpot"):Connect(follow))
	table.insert(open.connections, entry.model:GetAttributeChangedSignal("HallGone"):Connect(follow))
end

local function closeUp(entry: Tracked)
	local open = entry.open
	if open == nil then
		return
	end
	entry.open = nil
	opened[entry.model] = nil
	for _, connection in open.connections do
		connection:Disconnect()
	end
	open.hinge:PivotTo(open.closed)
	if open.light then
		candles[open.light] = nil
		open.light.Brightness = open.steady
	end
	if open.figure then
		open.figure:Destroy()
	end
end

-- The hall goes dark for a moment (light, flames); `during` runs in the dark.
local function blink(entry: Tracked, open: Open, during: () -> ())
	if open.busy then
		return
	end
	open.busy = true
	local light = open.light
	local flames = {}
	if open.glow then
		for _, child in open.glow:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(flames, child)
			end
		end
	end
	if light then
		candles[light] = nil
		light.Enabled = false
	end
	for _, flame in flames do
		flame.LocalTransparencyModifier = 1
	end
	task.delay(BLINK * 0.5, during)
	task.delay(BLINK, function()
		open.busy = false
		if light and entry.open == open then
			light.Enabled = true
			candles[light] = open.steady
		end
		for _, flame in flames do
			flame.LocalTransparencyModifier = 0
		end
	end)
end

-- The server moved whoever's in the hall (HallFigureService): the light blinks and, in the dark,
-- they're a spot closer (a creak), gone (a whisper), or back at the far end.
function hallChanged(entry: Tracked, open: Open)
	blink(entry, open, function()
		local figure = open.figure
		if entry.open ~= open or figure == nil then
			return
		end
		local index = math.clamp((entry.model:GetAttribute("HallSpot") :: number?) or 1, 1, #open.spots)
		local gone = entry.model:GetAttribute("HallGone") == true
		local spot = open.spots[index]
		if gone then
			if not open.gone then
				Sound.play("Whispers", { at = open.spots[open.index], volume = 0.9 })
			end
			figure.Parent = nil
		else
			if not open.gone and index > open.index then
				Sound.play("FloorCreak", { at = spot, volume = 0.7 })
			end
			figure:PivotTo(CFrame.new(spot.Position) * (open.facing or spot.CFrame.Rotation))
			figure.Parent = entry.model
		end
		open.index, open.gone = index, gone
	end)
end

-- Whoever stands in an open house's hall, turned toward the nearest kid (you included), slowly.
-- Where it stands and whether it's there at all is the server's (hallChanged).
local function watchFigures(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local heads: { Vector3 } = { camera.CFrame.Position }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head and player ~= Players.LocalPlayer then
			table.insert(heads, head.Position)
		end
	end
	for model, entry in opened do
		local open = entry.open
		local figure = open and open.figure
		if open == nil or figure == nil or open.gone or #open.spots == 0 or model.Parent == nil then
			continue
		end
		local spot = open.spots[open.index]
		local nearest: Vector3? = nil
		for _, head in heads do
			local distance = (head - spot.Position).Magnitude
			if
				distance < FIGURE_LOOK
				and (nearest == nil or distance < ((nearest :: Vector3) - spot.Position).Magnitude)
			then
				nearest = head
			end
		end
		local flat = if nearest then ((nearest :: Vector3) - spot.Position) * Vector3.new(1, 0, 1) else Vector3.zero
		if flat.Magnitude > 0.5 then
			local want = CFrame.lookAt(Vector3.zero, flat.Unit)
			open.facing = (open.facing or want):Lerp(want, 1 - math.exp(-dt * FIGURE_TURN))
			figure:PivotTo(CFrame.new(spot.Position) * (open.facing :: CFrame))
		end
	end
end

local function apply(entry: Tracked, fresh: boolean?)
	closeUp(entry)
	restore(entry)
	if entry.decor then
		entry.decor:Destroy()
		entry.decor = nil
	end
	tricky[entry.model] = nil
	for _, light in porchLights(entry.model) do
		light.Enabled = true -- undo any trick-house flicker
	end
	local houseType = entry.model:GetAttribute("HouseType")
	if houseType == "LightsOff" then
		lightsOff(entry)
	elseif houseType == "Decorated" then
		decorate(entry)
	elseif houseType == "Trick" then
		tricky[entry.model] = true
	elseif houseType == "Open" then
		standOpen(entry, not fresh)
	end
	if entry.model:GetAttribute("LampBroken") ~= nil then
		darkenLamp(entry)
	end
	updateBadge(entry)
end

local function track(door: Instance)
	if not door:IsA("BasePart") then
		return
	end
	local model = Houses.of(door)
	if model == nil or tracked[model] then
		return
	end
	local entry: Tracked = { door = door, model = model, saved = {} }
	tracked[model] = entry
	for _, attribute in { "HouseType", "Owner", "Preference" } do
		model:GetAttributeChangedSignal(attribute):Connect(function()
			if tracked[model] == entry then
				apply(entry)
			end
		end)
	end
	model:GetAttributeChangedSignal("OwnerOut"):Connect(function()
		if tracked[model] == entry then
			updateBadge(entry)
		end
	end)
	-- A bowl's lamp burst just now (and you're near enough to see it go), or it's mended at Dawn.
	model:GetAttributeChangedSignal("LampBroken"):Connect(function()
		if tracked[model] ~= entry then
			return
		end
		local at = model:GetAttribute("LampBroken")
		local camera = Workspace.CurrentCamera
		local recent = type(at) == "number" and Workspace:GetServerTimeNow() - at < LAMP.recent
		local near = camera ~= nil and (camera.CFrame.Position - entry.door.Position).Magnitude < LAMP.near
		if recent and near then
			burstLamp(entry, model:GetAttribute("LampBrokenBy") == Players.LocalPlayer.UserId, function()
				if tracked[model] == entry then
					apply(entry)
				end
			end)
		else
			apply(entry)
		end
	end)
	model:GetAttributeChangedSignal("OwnerAway"):Connect(function()
		if tracked[model] == entry then
			swingFront(entry, model:GetAttribute("OwnerAway") == true, true)
		end
	end)
	apply(entry, true)
	if model:GetAttribute("OwnerAway") == true then
		swingFront(entry, true, false)
	end
end

local function untrack(door: Instance)
	local model = Houses.of(door)
	if model and tracked[model] then
		closeUp(tracked[model])
		tracked[model] = nil
		tricky[model] = nil
	end
end

-- Full-Size Bar beam ----------------------------------------------------------------------------

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
end

local function showBeam(position: Vector3)
	clearBeam()
	local m = Instance.new("Model")
	m.Name = "FullSizeBeam"
	local column = Instance.new("Part")
	column.Shape = Enum.PartType.Cylinder
	column.Size = Vector3.new(220, 5, 5)
	column.CFrame = CFrame.new(position.X, position.Y + 108, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	column.Color = Color3.fromHex("FFD23F")
	column.Material = Enum.Material.Neon
	column.Transparency = 0.45
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CastShadow = false
	column.Parent = m
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FFD23F")
	light.Range = 40
	light.Brightness = 3
	light.Parent = column
	create("BillboardGui", {
		Name = "Label",
		Size = UDim2.fromOffset(260, 70),
		StudsOffsetWorldSpace = Vector3.new(0, -96, 0),
		AlwaysOnTop = true,
		MaxDistance = 2000,
		LightInfluence = 0,
		Adornee = column,
		create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = `🍫 FULL-SIZE BAR ×{Events.FULL_SIZE_MULTIPLIER}`,
			TextColor3 = Color3.fromHex("FFD23F"),
			TextScaled = true,
			create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
		}),
		Parent = column,
	})
	m.Parent = Workspace
	beam = m
end

local function watchFullSize(state: Instance)
	local function refresh()
		local houseId = state:GetAttribute("FullSizeHouse")
		local position = state:GetAttribute("FullSizePosition")
		if type(houseId) == "string" and houseId ~= "" and typeof(position) == "Vector3" then
			showBeam(position)
		else
			clearBeam()
		end
	end
	state:GetAttributeChangedSignal("FullSizeHouse"):Connect(refresh)
	refresh()
end

function HouseVisualController.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Door"):Connect(untrack)
	for _, door in CollectionService:GetTagged("Door") do
		track(door)
	end
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("WorldState", 120)
		if state then
			watchFullSize(state)
		end
	end)

	-- Candles in the Blender house's jack-o'-lanterns (lights in a part named "PumpkinLight").
	local function watchCandle(instance: Instance)
		local holder = instance.Parent
		if instance:IsA("PointLight") and holder and holder.Name == "PumpkinLight" then
			candles[instance] = instance.Brightness
		end
	end
	Workspace.DescendantAdded:Connect(watchCandle)
	for _, instance in Workspace:GetDescendants() do
		watchCandle(instance)
	end

	-- Trick houses: a porch light that can't make up its mind. Candles gutter everywhere.
	while true do
		task.wait(0.12)
		watchFigures(0.12)
		for light, steady in candles do
			if light.Parent == nil then
				candles[light] = nil
			else
				light.Brightness = steady * (0.65 + math.random() * 0.45)
			end
		end
		for model in tricky do
			for _, light in porchLights(model) do
				if math.random() < 0.3 then
					light.Enabled = not light.Enabled
				end
			end
		end
		if beam then
			local column = beam:FindFirstChildOfClass("Part")
			if column then
				column.Transparency = 0.4 + math.sin(os.clock() * 4) * 0.12
			end
		end
	end
end

return HouseVisualController
