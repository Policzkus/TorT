--!strict
-- Your things from the seller (Config/Items, ItemService): a row of slots at the bottom of the view,
-- one a thing you've got (its icon, how many, its key), used with 1-4 (the d-pad on a gamepad, a tap
-- on a touch screen). The firecracker goes where you're looking. Everyone near hears them: a bandage
-- wrapped (ItemUsed), a bear trap set and snapping shut (its Sprung), a firecracker thrown, fizzing,
-- then banging and flashing (its BangAt, BangFor). The bar only shows in a run.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Mode = require(Shared.Modules.Mode)
local Net = require(Shared.Modules.Net)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local ItemsController = {}

local ACTION = "UseItem"
local SLOT = Vector2.new(58, 38)
local THROWN = 0.45 -- seconds a thrown firecracker is in the air (only the look: it's already there)
local BANG_GAP = { 0.12, 0.45 } -- seconds between bangs
local KEY_TEXT: { [string]: string } = { One = "1", Two = "2", Three = "3", Four = "4" }

local bar: Frame
local slots: { [string]: TextButton } = {}
local usedAt = 0

local function counts(): { [string]: number }
	return StateController.get("consumables") or {}
end

-- Uses `itemId`, if you've got one: the server says whether it worked.
local function use(itemId: string): boolean
	if (counts()[itemId] or 0) <= 0 or os.clock() - usedAt < 0.3 then
		return false
	end
	usedAt = os.clock()
	local camera = Workspace.CurrentCamera
	Net.event("UseItem"):FireServer(itemId, if camera then camera.CFrame.LookVector else nil)
	local slot = slots[itemId]
	local bump = slot and slot:FindFirstChild("Bump") :: UIScale?
	if bump then
		bump.Scale = 0.85
		TweenService:Create(bump, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	return true
end

-- The key on its slot (none on a touch screen: you tap it).
local function keyHint(item: Items.Item): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return ""
	end
	return KEY_TEXT[item.key] or ""
end

local function buildSlot(itemId: string, order: number): TextButton
	local item = (Items :: any)[itemId] :: Items.Item
	local slot = create("TextButton", {
		Name = itemId,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SLOT.X, SLOT.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = 0.85, Thickness = 1 }),
		create("UIScale", { Name = "Bump" }),
		create("TextLabel", {
			Name = "Icon",
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(26, SLOT.Y),
			BackgroundTransparency = 1,
			Text = item.icon,
			TextSize = 20,
		}),
		create("TextLabel", {
			Name = "Count",
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -36, 1, 0),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Hud,
			TextColor3 = Theme.Colors.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		create("TextLabel", {
			Name = "Key",
			Position = UDim2.fromOffset(3, 1),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Hud,
			Text = keyHint(item),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 10,
		}),
		Parent = bar,
	})
	slot.Activated:Connect(function()
		use(itemId)
	end)
	return slot
end

local function refresh()
	local have = counts()
	for itemId, slot in slots do
		local count = have[itemId] or 0
		slot.Visible = count > 0
		local label = slot:FindFirstChild("Count") :: TextLabel?
		if label then
			label.Text = `×{count}`
		end
	end
end

-- Bear traps ------------------------------------------------------------------------------------

local function plateOf(trap: Instance): BasePart?
	local plate = trap:FindFirstChild("Plate")
	return if plate and plate:IsA("BasePart") then plate else nil
end

local function onTrap(trap: Instance)
	local plate = plateOf(trap)
	if plate == nil then
		return
	end
	local setAt = trap:GetAttribute("SetAt")
	if type(setAt) == "number" and Workspace:GetServerTimeNow() - setAt < 1 then
		Sound.play("Latch", { at = plate, volume = 0.9, speed = 1.3 }) -- set, sprung open
	end
	trap:GetAttributeChangedSignal("Sprung"):Connect(function()
		local at = plateOf(trap)
		if at then
			Sound.play("CarHit", { at = at, volume = 0.55, speed = 2.3 }) -- steel jaws slamming
			Sound.play("Latch", { at = at, volume = 1.2, speed = 0.75 })
		end
	end)
end

-- Firecrackers -----------------------------------------------------------------------------------

-- Thrown from `from`: up and over to where it lies (it's already there on the server).
local function arc(model: Model, from: Vector3)
	local rest = model:GetPivot()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / THROWN, 0, 1)
		if model.Parent == nil or t >= 1 then
			connection:Disconnect()
			if model.Parent then
				model:PivotTo(rest)
			end
			return
		end
		local at = from:Lerp(rest.Position, t) + Vector3.new(0, 4 * t * (1 - t) * 3, 0)
		model:PivotTo(CFrame.new(at) * rest.Rotation * CFrame.Angles(0, 0, t * math.pi * 3))
	end)
end

local function onFirecracker(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local stick = model:FindFirstChild("Stick") :: BasePart?
	local bangAt = model:GetAttribute("BangAt")
	local bangFor = model:GetAttribute("BangFor")
	if stick == nil or type(bangAt) ~= "number" or type(bangFor) ~= "number" then
		return
	end
	local from = model:GetAttribute("From")
	local fresh = bangAt - Workspace:GetServerTimeNow() > THROWN
	if fresh and typeof(from) == "Vector3" then
		Sound.play("Whoosh", { at = stick, volume = 0.8, speed = 1.3 })
		arc(model, from)
	end
	-- The fuse fizzing, then sparks with every bang.
	local sparks = create("ParticleEmitter", {
		Name = "Sparks",
		Color = ColorSequence.new(Color3.fromHex("FFD27A"), Color3.fromHex("FF6A2A")),
		LightEmission = 1,
		Size = NumberSequence.new(0.12, 0),
		Lifetime = NumberRange.new(0.15, 0.35),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(70, 70),
		Rate = 30,
		Parent = stick,
	})
	local flash = create("PointLight", {
		Name = "Flash",
		Color = Color3.fromHex("FFC070"),
		Range = 18,
		Brightness = 0,
		Shadows = false,
		Parent = stick,
	})
	task.spawn(function()
		local wait = bangAt - Workspace:GetServerTimeNow()
		if wait > 0 then
			task.wait(wait)
		end
		local stopAt = bangAt + bangFor
		local count = 0
		while model.Parent and Workspace:GetServerTimeNow() < stopAt do
			count += 1
			Sound.play("Slap", { at = stick, volume = 2.2, speed = 1.3 + math.random() * 0.6 })
			if count % 2 == 1 then
				Sound.play("Thunder", { at = stick, volume = 0.5, speed = 2.4 + math.random() * 0.4 })
			end
			sparks:Emit(14)
			flash.Brightness = 5
			task.delay(0.05, function()
				flash.Brightness = 0
			end)
			task.wait(BANG_GAP[1] + math.random() * (BANG_GAP[2] - BANG_GAP[1]))
		end
		sparks.Enabled = false
	end)
end

local function watchTag(tag: string, handler: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		task.defer(handler, instance) -- (its parts and attributes are there by then)
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(handler, instance)
	end
end

function ItemsController.Init()
	bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(0, SLOT.Y),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	create("ScreenGui", {
		Name = "Items",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 3,
		Enabled = Mode.get() == "run",
		bar,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

function ItemsController.Start()
	for order, itemId in Items.ORDER do
		slots[itemId] = buildSlot(itemId, order)
	end
	StateController.observe("consumables", refresh)
	refresh()
	local byKey: { [Enum.KeyCode]: string } = {}
	local keys = {}
	for _, itemId in Items.ORDER do
		local item = (Items :: any)[itemId] :: Items.Item
		for _, name in { item.key, item.pad } do
			local key = (Enum.KeyCode :: any)[name] :: Enum.KeyCode
			byKey[key] = itemId
			table.insert(keys, key)
		end
	end
	if Mode.get() == "run" then
		ContextActionService:BindAction(ACTION, function(_, state, input)
			local itemId = byKey[input.KeyCode]
			if state == Enum.UserInputState.Begin and itemId and use(itemId) then
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(keys))
	end
	Net.event("ItemUsed").OnClientEvent:Connect(function(userId: any, itemId: any)
		local who = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		local character = who and who.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and itemId == "Bandage" then
			Sound.play("Cloth", { at = root, volume = 1.4, speed = 0.8 })
			Sound.play("Stash", { at = root, volume = 0.35, speed = 1.4 })
		end
	end)
	watchTag("BearTrap", onTrap)
	watchTag("Firecracker", onFirecracker)
end

return ItemsController
