--!strict
-- Runs door mini-games when the server sends a challenge: locks movement, routes input to the
-- active game (one big tap target on mobile, Space/click on PC, Ⓐ on gamepad; Costume Line uses
-- its own buttons), shows the grade instantly from the shared rules, and submits the raw input.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local ACTION = "MinigameInput"

type Session = {
	press: (() -> ())?,
	release: (() -> ())?,
	usesOwnButtons: boolean?,
	cancel: () -> (),
}

type Game = {
	run: (parent: Frame, challenge: any, callbacks: any) -> Session,
}

-- Client UI and shared rules per mini-game kind.
local GAMES: { [string]: { ui: Game, rules: any } } = {}
for _, kind in { "TimingBar", "KnockRhythm", "NerveHold", "CostumeLine" } do
	GAMES[kind] = {
		ui = require(script.Parent.Minigames:WaitForChild(kind)) :: any,
		rules = require(Shared.Modules.Minigames:WaitForChild(kind)) :: any,
	}
end

local GRADE_STYLE: { [string]: { text: string, color: Color3, sound: string } } = {
	MISS = { text = "MISS", color = Theme.Colors.Danger, sound = "Miss" },
	GOOD = { text = "GOOD", color = Theme.Colors.TextDim, sound = "Pop" },
	GREAT = { text = "GREAT", color = Theme.Colors.Text, sound = "Coin" },
	PERFECT = { text = "PERFECT", color = Theme.Colors.Success, sound = "Perfect" },
}

local MinigameController = {}

local stage: Frame
local catcher: TextButton
local gradeLabel: TextLabel
local session: Session? = nil
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
	gradeLabel.TextSize = if big then 34 else 24
	gradeLabel.Visible = true
	local scale = gradeLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	Sound.play(style.sound)
end

local function close()
	ContextActionService:UnbindAction(ACTION)
	catcher.Visible = false
	GuiService.SelectedObject = nil
	lockMovement(false)
	task.delay(0.7, function()
		if session == nil then
			gradeLabel.Visible = false
		end
	end)
end

local function bindInput()
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, state)
			local active = session
			if active then
				if state == Enum.UserInputState.Begin and active.press then
					active.press()
				elseif state == Enum.UserInputState.End and active.release then
					active.release()
				end
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

local function start(challenge: any)
	if session then
		session.cancel()
		session = nil
	end
	local entry = GAMES[challenge.kind]
	if entry == nil then
		-- Not built on the client: answer at once so the door doesn't hang.
		Net.event("MinigameSubmit"):FireServer(challenge.id, {})
		return
	end
	gradeLabel.Visible = false
	lockMovement(true)
	local current: Session
	current = entry.ui.run(stage, challenge, {
		onTap = function(hit: number, grade: string, total: number)
			Sound.play("Tick")
			if hit < total then
				showGrade(grade, false) -- per-hit feedback; the final grade comes at the end
			end
		end,
		onDone = function(input: { number }, spec: any)
			Net.event("MinigameSubmit"):FireServer(challenge.id, input)
			local final = entry.rules.grade(spec, input)
			if session == current then
				session = nil
			end
			showGrade(final, true)
			close()
		end,
	})
	session = current
	catcher.Visible = not current.usesOwnButtons
	if not current.usesOwnButtons then
		bindInput()
	end
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
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
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
			-- Over the homeowner's chest: their face is framed above it (DoorController), the panel below.
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(500, 80),
			BackgroundTransparency = 1,
			ZIndex = 5,
			gradeLabel,
		}),
	})
	local gui = create("ScreenGui", {
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

	local function pointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	catcher.InputBegan:Connect(function(input: InputObject)
		if session and session.press and pointer(input) then
			session.press()
		end
	end)
	catcher.InputEnded:Connect(function(input: InputObject)
		if session and session.release and pointer(input) then
			session.release()
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
