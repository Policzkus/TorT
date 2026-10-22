--!strict
-- The main HUD (PROMPT §3.18): banked candy with a rolling counter and Candy Box bar, the bucket
-- fill bar, the "next goal" bar, menu buttons, and all the candy pops that fly around.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Neighborhoods = require(Shared.Config.Neighborhoods)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Modules.Format)
local Formulas = require(Shared.Modules.Formulas)
local Net = require(Shared.Modules.Net)
local DoorController = require(script.Parent.DoorController)
local SettingsController = require(script.Parent.SettingsController)
local ShopController = require(script.Parent.ShopController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local ProgressBar = require(script.Parent.Parent.UI.Components.ProgressBar)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local GRADE_COLORS: { [string]: Color3 } = {
	MISS = Color3.fromHex("FF8A8A"),
	GOOD = Color3.fromHex("FFFFFF"),
	GREAT = Color3.fromHex("FFD23F"),
	PERFECT = Color3.fromHex("7CFF4F"),
}

local HUDController = {}

local gui: ScreenGui
local uiScale: UIScale
local candyPanel: Frame
local candyLabel: TextLabel
local boxBar: ProgressBar.ProgressBar
local bucketPanel: Frame
local bucketLabel: TextLabel
local bucketBar: ProgressBar.ProgressBar
local goalLabel: TextLabel
local goalBar: ProgressBar.ProgressBar
local shopBadge: TextLabel
local clockPanel: Frame
local clockLabel: TextLabel
local clockSub: TextLabel
local streakPill: TextLabel
local popLayer: Frame
local shownCandy = Instance.new("NumberValue")

local function panel(name: string, width: number, order: number): Frame
	return create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(width, 66),
		LayoutOrder = order,
		BackgroundColor3 = Theme.Colors.Panel,
		create("UICorner", { CornerRadius = UDim.new(0, 14) }),
		create("UIStroke", { Name = "Outline", Color = Theme.Colors.Stroke, Thickness = 3 }),
		create("UIScale", { Name = "Bump" }),
		create("TextLabel", {
			Name = "Icon",
			Position = UDim2.fromOffset(8, 9),
			Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			TextSize = 38,
			Text = "",
		}),
	})
end

local function bump(frame: GuiObject, amount: number?)
	local scale = frame:FindFirstChild("Bump") :: UIScale?
	if scale then
		scale.Scale = amount or 1.12
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
end

local function shake(frame: GuiObject)
	task.spawn(function()
		for _, angle in { -5, 5, -4, 4, -2, 0 } do
			frame.Rotation = angle
			task.wait(0.04)
		end
	end)
end

-- Converts a viewport point (camera:WorldToViewportPoint) into this HUD's offset units.
local function toGui(viewportPoint: Vector2): Vector2
	return (viewportPoint - gui.AbsolutePosition) / uiScale.Scale
end

local function centreOf(frame: GuiObject): Vector2
	return (frame.AbsolutePosition + frame.AbsoluteSize / 2 - gui.AbsolutePosition) / uiScale.Scale
end

local function floatingText(text: string, color: Color3, at: Vector2, size: number): TextLabel
	return create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(240, size + 8),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = text,
		TextColor3 = color,
		TextSize = size,
		ZIndex = 10,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
		create("UIScale", { Scale = 0.4 }),
		Parent = popLayer,
	})
end

-- Pops "+N 🍬" at `from`, then flies it into `target` and calls onArrive.
local function flyPop(text: string, color: Color3, from: Vector2, target: GuiObject, onArrive: (() -> ())?)
	local label = floatingText(text, color, from, 34)
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(from.X, from.Y - 50),
	}):Play()
	task.delay(0.42, function()
		local goal = centreOf(target)
		local fly = TweenService:Create(label, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
		})
		TweenService
			:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.45 })
			:Play()
		fly.Completed:Once(function()
			label:Destroy()
			if onArrive then
				onArrive()
			end
		end)
		fly:Play()
	end)
end

-- A few candy emojis hopping from one place to another.
local function candyShower(from: Vector2, to: GuiObject, count: number)
	for i = 1, count do
		task.delay((i - 1) * 0.05, function()
			local start = from + Vector2.new(math.random(-30, 30), math.random(-20, 20))
			local label = floatingText("🍬", Color3.new(1, 1, 1), start, 26)
			local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 1
			local goal = centreOf(to)
			local tween =
				TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(goal.X, goal.Y),
					Rotation = math.random(-90, 90),
				})
			tween.Completed:Once(function()
				label:Destroy()
			end)
			tween:Play()
		end)
	end
end

local function doorPoint(houseId: string): Vector2
	local door = DoorController.getDoor(houseId)
	local camera = Workspace.CurrentCamera
	if door and camera then
		local point, onScreen = camera:WorldToViewportPoint(door.Position + Vector3.new(0, 3, 0))
		if onScreen then
			return toGui(Vector2.new(point.X, point.Y))
		end
	end
	local size = gui.AbsoluteSize / uiScale.Scale
	return Vector2.new(size.X / 2, size.Y * 0.45)
end

-- Refreshers ----------------------------------------------------------------------------------

local function refreshCandy()
	local candy = StateController.get("candy") or 0
	local rebirths = StateController.get("rebirths") or 0
	local capacity = Formulas.boxCapacity(rebirths)
	TweenService
		:Create(shownCandy, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = candy })
		:Play()
	boxBar:set(candy / capacity, true)
	boxBar:setText(`📦 {Format.number(candy)} / {Format.number(capacity)}`)
	boxBar:setColor(if candy >= capacity then Theme.Colors.Danger else Theme.Colors.Info)
end

local function refreshBucket()
	local bucket = StateController.get("bucket") or 0
	local upgrades = StateController.get("upgrades")
	if upgrades == nil then
		return
	end
	local capacity = Formulas.bucketCapacity(upgrades.bucketTier)
	local full = bucket >= capacity
	bucketLabel.Text = `{Format.number(bucket)} / {Format.number(capacity)}`
	bucketBar:set(bucket / capacity, true)
	bucketBar:setColor(
		if full
			then Theme.Colors.Danger
			elseif bucket / capacity > 0.75 then Theme.Colors.OrangeLight
			else Theme.Colors.Orange
	)
	bucketBar:setText(if full then "FULL! Stash it 📦" else Formulas.bucketTier(upgrades.bucketTier).name)
	local outline = bucketPanel:FindFirstChild("Outline") :: UIStroke
	outline.Color = if full then Theme.Colors.Danger else Theme.Colors.Stroke
end

-- The next thing to save for: the next street's gate, else the next bucket tier.
local function refreshGoal()
	local candy = StateController.get("candy") or 0
	local owned = StateController.get("neighborhoods") or {}
	local rebirths = StateController.get("rebirths") or 0
	local upgrades = StateController.get("upgrades")
	local text, cost, hint = nil, nil, nil
	for _, neighborhood in Neighborhoods.list do
		if not owned[neighborhood.id] then
			if neighborhood.enabled and neighborhood.unlock.rebirths <= rebirths then
				text = `🔓 Next: {neighborhood.name}`
				cost = neighborhood.unlock.price
				hint = "Unlock it at the gate at the end of the street!"
			end
			break
		end
	end
	if text == nil and upgrades then
		local level = upgrades.bucketTier
		local nextTier = (Upgrades.tracks.bucketTier.tiers :: { Upgrades.Tier })[level + 1]
		if nextTier and nextTier.rebirths <= rebirths then
			text = `🎃 Next: {nextTier.name}`
			cost = nextTier.cost
			hint = "Buy it in the Shop!"
		end
	end
	local frame = goalBar.frame.Parent :: Frame
	if text == nil or cost == nil then
		frame.Visible = false
		return
	end
	frame.Visible = true
	local ready = candy >= cost
	goalLabel.Text = if ready then `{text}  ✅ {hint}` else text
	goalBar:set(candy / cost, true)
	goalBar:setColor(if ready then Theme.Colors.Slime else Theme.Colors.Orange)
	goalBar:setText(`{Format.number(math.min(candy, cost))} / {Format.number(cost)} 🍬`)
end

local function refreshBadge()
	shopBadge.Visible = ShopController.cheapestAffordable() ~= nil
end

local function formatHour(hour: number): string
	local whole = math.floor(hour) % 24
	local minutes = math.floor((hour % 1) * 60)
	local suffix = if whole >= 12 then "PM" else "AM"
	local twelve = whole % 12
	return string.format("%d:%02d %s", if twelve == 0 then 12 else twelve, minutes, suffix)
end

local function refreshClock(state: Instance)
	local startedAt = (state:GetAttribute("NightStartedAt") :: number?) or Workspace:GetServerTimeNow()
	local elapsed = math.clamp(Workspace:GetServerTimeNow() - startedAt, 0, Events.NIGHT_LENGTH)
	local hour = Events.START_HOUR + elapsed / Events.NIGHT_LENGTH * (Events.END_HOUR - Events.START_HOUR)
	clockLabel.Text = formatHour(hour)
	local witchingAt = Events.NIGHT_LENGTH - Events.WITCHING_LENGTH
	local outline = clockPanel:FindFirstChild("Outline") :: UIStroke
	if state:GetAttribute("Witching") == true then
		clockSub.Text = `🩸 WITCHING ×2  {Format.clock(Events.NIGHT_LENGTH - elapsed)}`
		clockSub.TextColor3 = Theme.Colors.Danger
		clockLabel.TextColor3 = Color3.fromHex("FF8A8A")
		outline.Color = Theme.Colors.Danger
	elseif elapsed >= witchingAt - Events.WITCHING_WARNING then
		clockSub.Text = `⚠ Witching in {Format.clock(witchingAt - elapsed)}`
		clockSub.TextColor3 = Theme.Colors.OrangeLight
		clockLabel.TextColor3 = Theme.Colors.Text
		outline.Color = Theme.Colors.Orange
	elseif state:GetAttribute("BloodMoon") == true then
		clockSub.Text = "🌕 BLOOD MOON ×2"
		clockSub.TextColor3 = Theme.Colors.Danger
		clockLabel.TextColor3 = Theme.Colors.Text
		outline.Color = Theme.Colors.Danger
	else
		clockSub.Text = `Night {state:GetAttribute("Night") or 1}`
		clockSub.TextColor3 = Theme.Colors.TextDim
		clockLabel.TextColor3 = Theme.Colors.Text
		outline.Color = Theme.Colors.Stroke
	end
end

local function refreshStreak(streak: number)
	if streak < 2 then
		streakPill.Visible = false
		return
	end
	local bonus = math.round(Formulas.streakBonus(streak) * 100)
	streakPill.Visible = true
	streakPill.Text = `{if streak >= 5 then "🔥🔥" else "🔥"} x{streak}  +{bonus}%`
	streakPill.TextColor3 = if streak >= 5 then Theme.Colors.Slime else Theme.Colors.OrangeLight
	bump(streakPill, if streak >= 5 then 1.25 else 1.12)
end

-- Short callouts that rise from the door after the candy pop ("BRAVE!", "FULL-SIZE ×10"...).
local function callout(text: string, color: Color3, from: Vector2, delay: number)
	task.delay(delay, function()
		local label = floatingText(text, color, from - Vector2.new(0, 90), 30)
		local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
			Position = UDim2.fromOffset(from.X, from.Y - 150),
			TextTransparency = 1,
		}):Play()
		task.delay(1.4, function()
			label:Destroy()
		end)
	end)
end

-- Build ----------------------------------------------------------------------------------------

local function build()
	candyPanel = panel("Candy", 270, 1);
	(candyPanel:FindFirstChild("Icon") :: TextLabel).Text = "🍬"
	candyLabel = create("TextLabel", {
		Name = "Amount",
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.fromOffset(200, 34),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "0",
		TextColor3 = Theme.Colors.Text,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
		Parent = candyPanel,
	})
	boxBar = ProgressBar.new({
		size = UDim2.fromOffset(198, 18),
		position = UDim2.fromOffset(60, 40),
		color = Theme.Colors.Info,
		textSize = 12,
		parent = candyPanel,
	})

	clockPanel = panel("Night", 210, 3);
	(clockPanel:FindFirstChild("Icon") :: TextLabel).Text = "🌙"
	clockLabel = create("TextLabel", {
		Name = "Time",
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.fromOffset(140, 32),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "6:00 PM",
		TextColor3 = Theme.Colors.Text,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
		Parent = clockPanel,
	})
	clockSub = create("TextLabel", {
		Name = "Sub",
		Position = UDim2.fromOffset(60, 38),
		Size = UDim2.fromOffset(140, 20),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.BodyHeavy,
		Text = "Night 1",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1.5 }),
		Parent = clockPanel,
	})

	bucketPanel = panel("Bucket", 250, 2);
	(bucketPanel:FindFirstChild("Icon") :: TextLabel).Text = "🎃"
	bucketLabel = create("TextLabel", {
		Name = "Amount",
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.fromOffset(180, 34),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "0 / 15",
		TextColor3 = Theme.Colors.Text,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
		Parent = bucketPanel,
	})
	bucketBar = ProgressBar.new({
		size = UDim2.fromOffset(178, 18),
		position = UDim2.fromOffset(60, 40),
		textSize = 12,
		parent = bucketPanel,
	})

	create("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, 66),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		candyPanel,
		bucketPanel,
		clockPanel,
		Parent = gui,
	})

	streakPill = create("TextLabel", {
		Name = "Streak",
		Position = UDim2.new(0.5, 222, 0, 82),
		Size = UDim2.fromOffset(160, 34),
		BackgroundColor3 = Theme.Colors.Panel,
		FontFace = Theme.Fonts.Heading,
		Text = "",
		TextColor3 = Theme.Colors.OrangeLight,
		TextSize = 20,
		Visible = false,
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", {
			Name = "Outline",
			Color = Theme.Colors.Orange,
			Thickness = 2.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
		create("UIScale", { Name = "Bump" }),
		Parent = gui,
	})

	goalLabel = create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextSize = 19,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2.5 }),
	})
	local goalFrame = create("Frame", {
		Name = "Goal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.fromOffset(420, 44),
		BackgroundTransparency = 1,
		goalLabel,
		Parent = gui,
	})
	goalBar = ProgressBar.new({
		size = UDim2.new(0.8, 0, 0, 16),
		position = UDim2.new(0.1, 0, 0, 25),
		textSize = 12,
		parent = goalFrame,
	})

	local menu = create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(84, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		Parent = gui,
	})
	local shopButton = Button.new({
		name = "Shop",
		text = "🛒\nShop",
		size = UDim2.fromOffset(84, 84),
		color = Theme.Colors.Orange,
		textSize = 22,
		layoutOrder = 1,
		parent = menu,
		onClick = ShopController.toggle,
	})
	shopBadge = create("TextLabel", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.Colors.Slime,
		FontFace = Theme.Fonts.Heading,
		Text = "!",
		TextColor3 = Theme.Colors.Stroke,
		TextSize = 22,
		Visible = false,
		ZIndex = 3,
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create(
			"UIStroke",
			{ Color = Theme.Colors.Stroke, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
		),
		Parent = shopButton,
	})
	TweenService:Create(
		shopBadge,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 12 }
	):Play()

	Button.new({
		name = "Settings",
		text = "⚙️\nSettings",
		size = UDim2.fromOffset(84, 84),
		color = Theme.Colors.PanelLight,
		textSize = 18,
		layoutOrder = 9,
		parent = menu,
		onClick = SettingsController.toggle,
	})

	popLayer = create("Frame", {
		Name = "Pops",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = gui,
	})
end

-- Events ---------------------------------------------------------------------------------------

local function onDoorResult(result: any)
	local from = doorPoint(result.houseId)
	local color = GRADE_COLORS[result.grade] or GRADE_COLORS.GOOD
	refreshStreak(result.streak or 0)
	local delay = 0.15
	if result.bowl == "caught" then
		callout(`CAUGHT! -{Format.number(result.lost or 0)} 🍬`, Theme.Colors.Danger, from, 0.9)
		task.delay(1, function()
			shake(bucketPanel)
			Sound.play("Miss")
		end)
		return
	end
	if result.bowl == "all" then
		callout("🤑 TAKE ALL ×12!", Theme.Colors.Slime, from, delay)
		delay += 0.35
	end
	if result.brave then
		callout("😤 BRAVE! ×2.5", Theme.Colors.Slime, from, delay)
		delay += 0.35
	end
	if result.fullSize then
		callout(`🍫 FULL-SIZE ×{Events.FULL_SIZE_MULTIPLIER}!`, Color3.fromHex("FFD23F"), from, delay)
		delay += 0.35
	end
	if (result.event or 1) > 1 then
		callout(`🩸 ×{result.event} EVENT`, Theme.Colors.Danger, from, delay)
	end
	if result.added > 0 then
		flyPop(`+{Format.number(result.added)} 🍬`, color, from, bucketPanel, function()
			bump(bucketPanel)
			Sound.play("Pop")
		end)
		candyShower(from, bucketPanel, math.clamp(math.ceil(result.added / 3), 2, 6))
	end
	if result.overflow > 0 then
		task.delay(0.6, function()
			local at = centreOf(bucketPanel) + Vector2.new(bucketPanel.AbsoluteSize.X / uiScale.Scale / 2 + 150, 0)
			local label = floatingText(`OVERFLOW -{Format.number(result.overflow)} 🍬`, Theme.Colors.Danger, at, 26)
			local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 1
			shake(bucketPanel)
			Sound.play("Overflow")
			TweenService
				:Create(
					label,
					TweenInfo.new(1.2),
					{ TextTransparency = 1, Position = UDim2.fromOffset(at.X, at.Y + 30) }
				)
				:Play()
			task.delay(1.2, function()
				label:Destroy()
			end)
		end)
	end
end

local function onStashed(moved: number, boxFull: boolean)
	Sound.play("Stash")
	candyShower(centreOf(bucketPanel), candyPanel, math.clamp(math.ceil(moved / 10), 4, 10))
	task.delay(0.5, function()
		bump(candyPanel, 1.15)
		Sound.play("Coin")
		local at = centreOf(candyPanel) - Vector2.new(candyPanel.AbsoluteSize.X / uiScale.Scale / 2 + 130, 0)
		local label = floatingText(`+{Format.number(moved)} STASHED!`, Theme.Colors.Slime, at, 26)
		local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		task.delay(1, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.delay(0.4, function()
				label:Destroy()
			end)
		end)
	end)
	if boxFull then
		shake(candyPanel)
	end
end

function HUDController.Start()
	gui = create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	uiScale = Scale.attach(gui)
	build()

	shownCandy.Changed:Connect(function(value: number)
		candyLabel.Text = Format.number(math.floor(value + 0.5))
	end)
	StateController.observe("candy", function()
		refreshCandy()
		refreshGoal()
		refreshBadge()
	end)
	StateController.observe("rebirths", refreshCandy)
	StateController.observe("bucket", refreshBucket)
	StateController.observe("upgrades", function()
		refreshBucket()
		refreshGoal()
		refreshBadge()
	end)
	StateController.observe("neighborhoods", refreshGoal)

	Net.event("DoorResult").OnClientEvent:Connect(onDoorResult)
	Net.event("Stashed").OnClientEvent:Connect(onStashed)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("WorldState")
		while true do
			refreshClock(state)
			task.wait(0.5)
		end
	end)
end

return HUDController
