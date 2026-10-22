--!strict
-- Runs door mini-games when the server sends a challenge: locks movement, captures input
-- (one big tap target on mobile, Space/click on PC, Ⓐ on gamepad), shows the grade, submits taps.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Rules = require(Shared.Modules.Minigames.TimingBar)
local Sound = require(script.Parent.SoundController)
local TimingBar = require(script.Parent.Minigames.TimingBar)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local ACTION = "MinigameTap"

local GRADE_STYLE: { [string]: { text: string, color: Color3, sound: string } } = {
	MISS = { text = "MISS", color = Color3.fromHex("FF4D5E"), sound = "Miss" },
	GOOD = { text = "GOOD", color = Color3.fromHex("FFFFFF"), sound = "Pop" },
	GREAT = { text = "GREAT!", color = Color3.fromHex("FFD23F"), sound = "Coin" },
	PERFECT = { text = "PERFECT!!", color = Color3.fromHex("7CFF4F"), sound = "Perfect" },
}

local MinigameController = {}

local gui: ScreenGui
local stage: Frame
local catcher: TextButton
local gradeLabel: TextLabel
local session: TimingBar.Session? = nil
local controls: any = nil

local function lockMovement(locked: boolean)
	if controls then
		if locked then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	ProximityPromptService.Enabled = not locked
end

local function showGrade(grade: string, big: boolean)
	local style = GRADE_STYLE[grade] or GRADE_STYLE.MISS
	gradeLabel.Text = style.text
	gradeLabel.TextColor3 = style.color
	gradeLabel.TextSize = if big then 64 else 44
	gradeLabel.Visible = true
	local scale = gradeLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 1.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	Sound.play(style.sound)
end

local function close()
	ContextActionService:UnbindAction(ACTION)
	catcher.Visible = false
	lockMovement(false)
	task.delay(0.6, function()
		if session == nil then
			gradeLabel.Visible = false
		end
	end)
end

local function start(challenge: any)
	if session then
		session.cancel()
		session = nil
	end
	if challenge.kind ~= "TimingBar" then
		-- Not built on the client yet: answer immediately so the door doesn't hang.
		Net.event("MinigameSubmit"):FireServer(challenge.id, {})
		return
	end
	gradeLabel.Visible = false
	lockMovement(true)
	catcher.Visible = true
	local current: TimingBar.Session
	current = TimingBar.run(stage, challenge, {
		onTap = function(hit, grade, total)
			Sound.play("Tick")
			if hit < total then
				showGrade(grade, false) -- multi-hit: per-hit feedback, the final grade comes at the end
			end
		end,
		onDone = function(taps, spec)
			Net.event("MinigameSubmit"):FireServer(challenge.id, taps)
			local final = Rules.grade(spec, taps)
			if session == current then
				session = nil
			end
			showGrade(final, true)
			close()
		end,
	})
	session = current
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, state)
			if state == Enum.UserInputState.Begin and session then
				session.tap()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
end

function MinigameController.isActive(): boolean
	return session ~= nil
end

function MinigameController.Init()
	gradeLabel = create("TextLabel", {
		Name = "Grade",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 80),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "",
		TextSize = 56,
		Visible = false,
		ZIndex = 5,
		create("UIScale", {}),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 4 }),
	})
	catcher = create("TextButton", {
		Name = "TapCatcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		AutoButtonColor = false,
	})
	stage = create("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("Frame", {
			Name = "GradeAnchor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.fromOffset(500, 80),
			BackgroundTransparency = 1,
			gradeLabel,
		}),
	})
	gui = create("ScreenGui", {
		Name = "Minigame",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		catcher,
		stage,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)

	catcher.InputBegan:Connect(function(input: InputObject)
		if
			session
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			session.tap()
		end
	end)
	Net.event("MinigameStart").OnClientEvent:Connect(start)
end

function MinigameController.Start()
	local playerModule = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
	if playerModule then
		local ok, module = pcall(require, playerModule)
		if ok then
			controls = (module :: any):GetControls()
		end
	end
end

return MinigameController
