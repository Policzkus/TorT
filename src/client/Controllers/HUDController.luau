--!strict
-- Minimal HUD (PROMPT §V2.3, the user's Watch Dogs reference): a small cluster of monochrome chips
-- bottom-left (candy, bag, lives, souls, night clock), a quiet "next goal" line and streak above it,
-- a centre crosshair dot, and a menu hint bottom-right. Candy pops fly into the bag chip.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Images = require(Shared.Config.Images)
local Lives = require(Shared.Config.Lives)
local Neighborhoods = require(Shared.Config.Neighborhoods)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Modules.Format)
local Formulas = require(Shared.Modules.Formulas)
local Net = require(Shared.Modules.Net)
local DoorController = require(script.Parent.DoorController)
local RadialMenuController = require(script.Parent.RadialMenuController)
local ShopController = require(script.Parent.ShopController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local GRADE_COLORS: { [string]: Color3 } = {
	MISS = Theme.Colors.Danger,
	GOOD = Theme.Colors.Text,
	GREAT = Theme.Colors.OrangeLight,
	PERFECT = Theme.Colors.Slime,
}

local HUDController = {}

local gui: ScreenGui
local uiScale: UIScale
local candyChip: Frame
local candyLabel: TextLabel
local bagChip: Frame
local bagLabel: TextLabel
local bagFill: Frame
local hearts: { ImageLabel | TextLabel } = {}
local soulsLabel: TextLabel
local clockChip: Frame
local clockLabel: TextLabel
local streakChip: Frame
local streakLabel: TextLabel
local goalLabel: TextLabel
local goalFill: Frame
local menuDot: Frame
local popLayer: Frame
local shownCandy = Instance.new("NumberValue")

-- Chips --------------------------------------------------------------------------------------

local function icon(imageId: number, fallback: string): ImageLabel | TextLabel
	if imageId ~= 0 then
		return create("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. imageId,
			ImageColor3 = Theme.Colors.Text,
			LayoutOrder = 0,
		})
	end
	return create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = fallback,
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		LayoutOrder = 0,
	})
end

local function chip(name: string, order: number, imageId: number?, fallback: string?): Frame
	local frame = create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Name = "Outline", Color = Theme.Colors.Hairline, Transparency = 0.85, Thickness = 1 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9) }),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("UIScale", { Name = "Bump" }),
	})
	if imageId then
		icon(imageId, fallback or "").Parent = frame
	end
	return frame
end

local function chipText(parent: Instance, text: string, order: number?): TextLabel
	return create("TextLabel", {
		Name = "Value",
		LayoutOrder = order or 1,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		Parent = parent,
	})
end

local function bump(frame: GuiObject, amount: number?)
	local scale = frame:FindFirstChild("Bump") :: UIScale?
	if scale then
		scale.Scale = amount or 1.1
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
end

local function shake(frame: GuiObject)
	task.spawn(function()
		for _, angle in { -4, 4, -3, 3, -1, 0 } do
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

local function floatingText(text: string, color: Color3, at: Vector2, size: number, font: Font?): TextLabel
	return create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(300, size + 8),
		BackgroundTransparency = 1,
		FontFace = font or Theme.Fonts.Hud,
		Text = text,
		TextColor3 = color,
		TextSize = size,
		ZIndex = 10,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.4 }),
		create("UIScale", { Scale = 0.6 }),
		Parent = popLayer,
	})
end

-- "+12" rises at the door, then drifts into the bag chip.
local function flyPop(text: string, color: Color3, from: Vector2, target: GuiObject, onArrive: (() -> ())?)
	local label = floatingText(text, color, from, 24)
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(from.X, from.Y - 36),
	}):Play()
	task.delay(0.45, function()
		local goal = centreOf(target)
		local fly = TweenService:Create(label, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			TextTransparency = 0.4,
		})
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.5 })
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

-- Short callouts that rise from the door after the candy pop ("BRAVE", "FULL-SIZE"...).
local function callout(text: string, color: Color3, from: Vector2, delay: number)
	task.delay(delay, function()
		local label = floatingText(text, color, from - Vector2.new(0, 70), 22, Theme.Fonts.Heading)
		local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
			Position = UDim2.fromOffset(from.X, from.Y - 120),
			TextTransparency = 1,
		}):Play()
		task.delay(1.5, function()
			label:Destroy()
		end)
	end)
end

local function doorPoint(houseId: string): Vector2
	local door = DoorController.getDoor(houseId)
	local camera = Workspace.CurrentCamera
	if door and camera then
		local point, onScreen = camera:WorldToViewportPoint(door.Position + Vector3.new(0, 2, 0))
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
	TweenService
		:Create(shownCandy, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = candy })
		:Play()
	local rebirths = StateController.get("rebirths") or 0
	local outline = candyChip:FindFirstChild("Outline") :: UIStroke
	outline.Color = if candy >= Formulas.boxCapacity(rebirths) then Theme.Colors.Danger else Theme.Colors.Hairline
end

local function refreshBag()
	local bucket = StateController.get("bucket") or 0
	local upgrades = StateController.get("upgrades")
	if upgrades == nil then
		return
	end
	local capacity = Formulas.bucketCapacity(upgrades.bucketTier)
	local full = bucket >= capacity
	bagLabel.Text = `{Format.number(bucket)}/{Format.number(capacity)}`
	bagLabel.TextColor3 = if full then Theme.Colors.Danger else Theme.Colors.Text
	TweenService
		:Create(bagFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(math.clamp(bucket / capacity, 0, 1), 1) })
		:Play()
	bagFill.BackgroundColor3 = if full then Theme.Colors.Danger else Theme.Colors.Text
end

local function refreshLives()
	local lives = StateController.get("lives") or Lives.MAX
	for index, heart in hearts do
		local alive = index <= lives
		if heart:IsA("ImageLabel") then
			heart.ImageTransparency = if alive then 0 else 0.8
		else
			heart.TextTransparency = if alive then 0 else 0.8
		end
	end
end

local function refreshSouls()
	soulsLabel.Text = Format.number(StateController.get("souls") or 0)
end

-- The next thing to save for: the next street, else the next bucket tier.
local function refreshGoal()
	local candy = StateController.get("candy") or 0
	local owned = StateController.get("neighborhoods") or {}
	local rebirths = StateController.get("rebirths") or 0
	local upgrades = StateController.get("upgrades")
	local text, cost = nil, nil
	for _, neighborhood in Neighborhoods.list do
		if not owned[neighborhood.id] then
			if neighborhood.enabled and neighborhood.unlock.rebirths <= rebirths then
				text = string.upper(neighborhood.name)
				cost = neighborhood.unlock.price
			end
			break
		end
	end
	if text == nil and upgrades then
		local nextTier = (Upgrades.tracks.bucketTier.tiers :: { Upgrades.Tier })[upgrades.bucketTier + 1]
		if nextTier and nextTier.rebirths <= rebirths then
			text = string.upper(nextTier.name)
			cost = nextTier.cost
		end
	end
	local frame = goalLabel.Parent :: Frame
	if text == nil or cost == nil then
		frame.Visible = false
		return
	end
	frame.Visible = true
	local ready = candy >= cost
	local amounts = `{Format.number(math.min(candy, cost))} / {Format.number(cost)}`
	goalLabel.Text = `NEXT  ·  {text}   {amounts}{if ready then "  ✓" else ""}`
	goalLabel.TextColor3 = if ready then Theme.Colors.Slime else Theme.Colors.TextDim
	TweenService:Create(goalFill, TweenInfo.new(0.35), { Size = UDim2.fromScale(math.clamp(candy / cost, 0, 1), 1) })
		:Play()
end

local function refreshMenuDot()
	menuDot.Visible = ShopController.cheapestAffordable() ~= nil
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
	local witchingAt = Events.NIGHT_LENGTH - Events.WITCHING_LENGTH
	local outline = clockChip:FindFirstChild("Outline") :: UIStroke
	local time = formatHour(hour)
	if state:GetAttribute("Witching") == true then
		clockLabel.Text = `{time}  ·  WITCHING HOUR ×2  {Format.clock(Events.NIGHT_LENGTH - elapsed)}`
		clockLabel.TextColor3 = Theme.Colors.Danger
		outline.Color = Theme.Colors.Danger
	elseif elapsed >= witchingAt - Events.WITCHING_WARNING then
		clockLabel.Text = `{time}  ·  WITCHING IN {Format.clock(witchingAt - elapsed)}`
		clockLabel.TextColor3 = Theme.Colors.OrangeLight
		outline.Color = Theme.Colors.Hairline
	elseif state:GetAttribute("BloodMoon") == true then
		clockLabel.Text = `{time}  ·  BLOOD MOON ×2`
		clockLabel.TextColor3 = Theme.Colors.Danger
		outline.Color = Theme.Colors.Danger
	else
		clockLabel.Text = `{time}  ·  NIGHT {state:GetAttribute("Night") or 1}`
		clockLabel.TextColor3 = Theme.Colors.Text
		outline.Color = Theme.Colors.Hairline
	end
end

local function refreshStreak(streak: number)
	if streak < 2 then
		streakChip.Visible = false
		return
	end
	streakChip.Visible = true
	streakLabel.Text = `x{streak} STREAK  +{math.round(Formulas.streakBonus(streak) * 100)}%`
	streakLabel.TextColor3 = if streak >= 5 then Theme.Colors.Slime else Theme.Colors.Text
	bump(streakChip, if streak >= 5 then 1.2 else 1.1)
end

-- Build ----------------------------------------------------------------------------------------

local function build()
	local cluster = create("Frame", {
		Name = "Cluster",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Parent = gui,
	})

	candyChip = chip("Candy", 1, Images.Candy, "C")
	candyLabel = chipText(candyChip, "0")
	candyChip.Parent = cluster

	bagChip = chip("Bag", 2, Images.Bag, "B")
	bagLabel = chipText(bagChip, "0/15")
	bagFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
	})
	create("Frame", {
		Name = "Bar",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(46, 4),
		BackgroundColor3 = Theme.Colors.Text,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		bagFill,
		Parent = bagChip,
	})
	bagChip.Parent = cluster

	local livesChip = chip("Lives", 3)
	for index = 1, Lives.MAX do
		local heart = icon(Images.Life, "♥")
		heart.LayoutOrder = index
		heart.Size = UDim2.fromOffset(16, 16)
		heart.Parent = livesChip
		hearts[index] = heart
	end
	livesChip.Parent = cluster

	local soulsChip = chip("Souls", 4, Images.Soul, "S")
	soulsLabel = chipText(soulsChip, "0")
	soulsChip.Parent = cluster

	clockChip = chip("Clock", 5)
	clockLabel = chipText(clockChip, "6:00 PM  ·  NIGHT 1")
	clockLabel.TextSize = 15
	clockChip.Parent = cluster

	-- Next goal, one quiet line above the cluster; streak above that.
	goalFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
	})
	goalLabel = create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.5 }),
	})
	create("Frame", {
		Name = "Goal",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -54),
		Size = UDim2.fromOffset(420, 24),
		BackgroundTransparency = 1,
		Visible = false,
		goalLabel,
		create("Frame", {
			Name = "Bar",
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.fromOffset(200, 2),
			BackgroundColor3 = Theme.Colors.Text,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			goalFill,
		}),
		Parent = gui,
	})
	streakChip = chip("Streak", 6)
	streakLabel = chipText(streakChip, "")
	streakLabel.TextSize = 15
	streakChip.AnchorPoint = Vector2.new(0, 1)
	streakChip.Position = UDim2.new(0, 16, 1, -84)
	streakChip.Visible = false
	streakChip.Parent = gui

	-- Crosshair dot (first person).
	create("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Theme.Colors.Text,
		BackgroundTransparency = 0.35,
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Parent = gui,
	})

	-- Menu hint bottom-right (a real button on touch screens).
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hint = create("TextButton", {
		Name = "MenuHint",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Hud,
		Text = if touch then "   MENU   " else "   [TAB]  MENU   ",
		TextColor3 = Theme.Colors.Text,
		TextSize = 15,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = 0.85,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Parent = gui,
	})
	menuDot = create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Theme.Colors.Slime,
		Visible = false,
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Parent = hint,
	})
	hint.Activated:Connect(function()
		RadialMenuController.toggle()
	end)

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
	local color = GRADE_COLORS[result.grade] or Theme.Colors.Text
	refreshStreak(result.streak or 0)
	if result.bowl == "caught" then
		callout(`CAUGHT  -{Format.number(result.lost or 0)}`, Theme.Colors.Danger, from, 0.9)
		task.delay(1, function()
			shake(bagChip)
			Sound.play("Miss")
		end)
		return
	end
	local delay = 0.15
	if result.bowl == "all" then
		callout("TOOK IT ALL  ×12", Theme.Colors.Slime, from, delay)
		delay += 0.35
	end
	if result.brave then
		callout("BRAVE  ×2.5", Theme.Colors.Slime, from, delay)
		delay += 0.35
	end
	if result.fullSize then
		callout(`FULL-SIZE BAR  ×{Events.FULL_SIZE_MULTIPLIER}`, Theme.Colors.OrangeLight, from, delay)
		delay += 0.35
	end
	if (result.event or 1) > 1 then
		callout(`EVENT  ×{result.event}`, Theme.Colors.Danger, from, delay)
	end
	if result.added > 0 then
		flyPop(`+{Format.number(result.added)}`, color, from, bagChip, function()
			bump(bagChip)
			Sound.play("Pop", { volume = 0.7 })
		end)
	end
	if result.overflow > 0 then
		task.delay(0.6, function()
			local at = centreOf(bagChip) - Vector2.new(0, 34)
			local label = floatingText(`OVERFLOW  -{Format.number(result.overflow)}`, Theme.Colors.Danger, at, 16)
			local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 1
			shake(bagChip)
			Sound.play("Overflow")
			TweenService:Create(label, TweenInfo.new(1.2), {
				TextTransparency = 1,
				Position = UDim2.fromOffset(at.X, at.Y - 24),
			}):Play()
			task.delay(1.2, function()
				label:Destroy()
			end)
		end)
	end
end

local function onStashed(moved: number, boxFull: boolean)
	Sound.play("Stash")
	task.delay(0.35, function()
		bump(candyChip, 1.15)
		Sound.play("Coin")
		local at = centreOf(candyChip) - Vector2.new(0, 34)
		local label = floatingText(`+{Format.number(moved)} STASHED`, Theme.Colors.Slime, at, 16)
		local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		task.delay(1, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.delay(0.4, function()
				label:Destroy()
			end)
		end)
	end)
	if boxFull then
		shake(candyChip)
	end
end

function HUDController.Start()
	for _, coreGui in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health } do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGui, false)
	end
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
		candyLabel.Text = Format.commas(math.floor(value + 0.5))
	end)
	StateController.observe("candy", function()
		refreshCandy()
		refreshGoal()
		refreshMenuDot()
	end)
	StateController.observe("rebirths", refreshCandy)
	StateController.observe("bucket", refreshBag)
	StateController.observe("upgrades", function()
		refreshBag()
		refreshGoal()
		refreshMenuDot()
	end)
	StateController.observe("neighborhoods", refreshGoal)
	StateController.observe("lives", refreshLives)
	StateController.observe("souls", refreshSouls)
	refreshLives()

	Net.event("DoorResult").OnClientEvent:Connect(onDoorResult)
	Net.event("Stashed").OnClientEvent:Connect(onStashed)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("WorldState", 120)
		if state == nil then
			return
		end
		while true do
			refreshClock(state)
			task.wait(0.5)
		end
	end)
end

return HUDController
