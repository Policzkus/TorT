--!strict
-- The run's big moments on screen. Fainting (HealthService): the screen goes black on whoever caught
-- you, a line about what it cost, and the view comes back with your new character wherever you come
-- to. Hurt (your Health attribute going down): red from the edges of the view (unless Settings say
-- no flashes), and while your health is low the edges pulse red. And the way out: LOBBY in the TAB
-- menu asks first, then sends you back to the lobby (RunExitService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Health = require(ReplicatedStorage.Shared.Config.Health)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Mode = require(ReplicatedStorage.Shared.Modules.Mode)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Theme = require(script.Parent.Parent.UI.Theme)
local Scale = require(script.Parent.Parent.UI.Scale)
local create = require(script.Parent.Parent.UI.create)
local RadialMenuController = require(script.Parent.RadialMenuController)
local NotificationController = require(script.Parent.NotificationController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local TransitionController = require(script.Parent.TransitionController)

local RunController = {}

local player = Players.LocalPlayer

local card: Frame
local heading: TextLabel
local body: TextLabel
local footer: TextLabel
local showing = 0 -- counts what's on the card (a countdown checks it's still its own)
local confirm: Frame -- "back to the lobby?"
local hurtEdge: Frame -- red at the edges of the view: hurt, and low on health
local flashed = 1 -- the hurt flash's transparency now (eases back to 1)
local lastHealth = Health.MAX

local FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function show(title: string, lines: string, foot: string)
	heading.Text = title
	body.Text = lines
	footer.Text = foot
	card.Visible = true
	for _, label in { heading, body, footer } do
		label.TextTransparency = 1
		TweenService:Create(label, FADE, { TextTransparency = 0 }):Play()
	end
	card.BackgroundTransparency = 1
	TweenService:Create(card, FADE, { BackgroundTransparency = Theme.TileTransparency }):Play()
end

local function hide()
	for _, label in { heading, body, footer } do
		TweenService:Create(label, FADE, { TextTransparency = 1 }):Play()
	end
	local t = TweenService:Create(card, FADE, { BackgroundTransparency = 1 })
	t:Play()
	t.Completed:Wait()
	card.Visible = false
end

local function onFainted(lostBucket: any, wakeIn: any)
	showing += 1
	local mine = showing
	Sound.play("Thud")
	TransitionController.fadeOut(0.35)
	local lost = tonumber(lostBucket) or 0
	local lines = if lost > 0
		then `<font color="#D84A4A">-{Format.number(lost)}</font> candy from your bucket`
		else "Your bucket was empty."
	show("YOU FAINTED", lines, "")
	task.delay((tonumber(wakeIn) or 3) + 0.4, function()
		if showing ~= mine then
			return
		end
		hide()
		TransitionController.fadeIn(0.8)
	end)
end

-- Killed and down as a ragdoll (the Knifer, HealthService.down): no card, no black screen, you see it
-- from your own eyes. What it cost goes in a toast; just as the new body comes, a quick fade, so the
-- jump to the spawn isn't a cut.
local function onDowned(lostBucket: any, wakeIn: any)
	local lost = tonumber(lostBucket) or 0
	local cost = if lost > 0 then ` · -{Format.number(lost)} candy from your bucket` else ""
	NotificationController.show("The Knifer got you" .. cost, "error")
	local wake = tonumber(wakeIn) or 4
	task.delay(math.max(0, wake - 0.25), function()
		TransitionController.fadeOut(0.25)
		task.wait(0.35)
		TransitionController.fadeIn(0.6)
	end)
end

-- Your health went down (a stab): red from the edges, and a thud.
local function onHealth()
	local value = player:GetAttribute("Health")
	local health = if type(value) == "number" then value else Health.MAX
	if health < lastHealth - 1 and health > 0 then
		Sound.play("Thud", { volume = 0.7, speed = 1.3 })
		local settings = StateController.get("settings") or {}
		if settings.reduceFlash ~= true then
			flashed = 0.1
		end
	end
	lastHealth = health
end

-- The red at the edges: the hurt flash dying away, and under Health.LOW a slow pulse (your heart).
local function drawHurt(dt: number)
	flashed = math.min(1, flashed + dt * 1.3)
	local low = 1
	if lastHealth > 0 and lastHealth < Health.LOW then
		local settings = StateController.get("settings") or {}
		local strength = if settings.reduceFlash == true then 0.15 else 0.35
		low = 1 - strength * (0.5 + 0.5 * math.sin(os.clock() * 5)) * (1 - lastHealth / Health.LOW * 0.5)
	end
	hurtEdge.BackgroundTransparency = math.min(flashed, low)
end

local function leave()
	confirm.Visible = false
	Net.event("RunLeave"):FireServer()
	TransitionController.fadeOut(0.6)
	task.delay(8, function() -- still here (Studio, or the teleport failed): the view comes back
		TransitionController.fadeIn(0.4)
	end)
end

-- "Back to the lobby?": a window (with a cursor) before leaving the run.
local function buildConfirm(parent: Instance)
	local buttons = create("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})
	Button.new({ text = "LEAVE", size = UDim2.fromOffset(170, 48), parent = buttons, onClick = leave })
	Button.new({
		text = "STAY",
		size = UDim2.fromOffset(170, 48),
		parent = buttons,
		onClick = function()
			confirm.Visible = false
		end,
	})
	confirm = create("Frame", {
		Name = "LeaveConfirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = Theme.HairlineTransparency }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 22),
			PaddingRight = UDim.new(0, 22),
		}),
		create("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = "BACK TO THE LOBBY?",
			TextColor3 = Theme.Colors.Text,
			TextSize = 30,
			LayoutOrder = 1,
		}),
		create("TextLabel", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Hud,
			Text = "You leave this run. Your bucket comes with you: nothing is lost.",
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 19,
			TextWrapped = true,
			LayoutOrder = 2,
		}),
		buttons,
		create("TextButton", { -- frees the mouse (and shows the cursor) while the window's up
			Name = "MouseUnlock",
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = "",
			Modal = true,
		}),
		Parent = parent,
	})
end

local function build()
	heading = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextSize = 36,
		LayoutOrder = 1,
	})
	body = create("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 19,
		LineHeight = 1.25,
		RichText = true,
		LayoutOrder = 2,
	})
	footer = create("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 17,
		TextWrapped = true,
		LayoutOrder = 3,
	})
	card = create("Frame", {
		Name = "RunCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(500, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 1,
		Visible = false,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = Theme.HairlineTransparency,
			Thickness = Theme.StrokeThickness,
		}),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 22),
			PaddingRight = UDim.new(0, 22),
		}),
		create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		heading,
		body,
		footer,
	})
	-- Above the black of TransitionController (DisplayOrder 100), so the card reads over it.
	local gui = create("ScreenGui", {
		Name = "RunCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 110,
		card,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
	buildConfirm(gui)
	hurtEdge = create("Frame", {
		Name = "Hurt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("B0101A"),
		BackgroundTransparency = 1,
		-- Red at the edges, clear in the middle.
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.85),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	create("ScreenGui", {
		Name = "Hurt",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 84, -- under the door slap's (the same red), over the HUD
		hurtEdge,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

function RunController.Start()
	build()
	Net.event("Fainted").OnClientEvent:Connect(onFainted)
	Net.event("Downed").OnClientEvent:Connect(onDowned)
	player:GetAttributeChangedSignal("Health"):Connect(onHealth)
	onHealth()
	RunService.RenderStepped:Connect(drawHurt)
	if Mode.get() == "run" then
		RadialMenuController.register({
			id = "Lobby",
			label = "LOBBY",
			order = 9,
			glyph = "🚌",
			onSelect = function()
				confirm.Visible = true
			end,
		})
	end
end

return RunController
