--!strict
-- Runs door mini-games when the server sends a challenge: locks movement, routes input to the
-- active game (one big tap target on mobile, Space/click on PC, Ⓐ on gamepad; Costume Line uses
-- its own buttons), shows the grade instantly from the shared rules, and submits the raw input.
-- From the moment the door is answered you're held where you stand (DoorController walks you back
-- to watch) so you see them come out. Hold a direction to break away: the visit is off
-- (`abandoned` fires with the house id; the server is told). Ending up past Economy.DOOR_LEAVE from
-- the door (pushed, teleported) calls it off too.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local ACTION = "MinigameInput"
local BREAK_AWAY = 0.35 -- seconds of holding a direction that breaks you away from a visit
local HINT_AFTER = 1.5 -- seconds into a visit before the "walk away" hint shows
local MOVE_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
}

type Session = {
	press: (() -> ())?,
	release: (() -> ())?,
	usesOwnButtons: boolean?,
	cancel: () -> (),
}

-- The visit a session belongs to: which challenge, which house, where its door is.
type Visit = { id: number, houseId: string?, door: Vector3? }

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

-- Fires (houseId) when you walk away from a door before or during its mini-game.
MinigameController.abandoned = Signal.new()

local stage: Frame
local catcher: TextButton
local gradeLabel: TextLabel
local session: Session? = nil
local visit: Visit? = nil
local visitStarted = 0
local pushing = 0 -- seconds you've been holding a direction during the visit
local hint: TextLabel
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
	hint.Visible = false
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

local function begin(challenge: any)
	lockMovement(true)
	local entry = GAMES[challenge.kind]
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
				visit = nil
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

-- Calls off the visit (challenge `id`): its game or the wait for it ends without a grade, you can
-- move again, and the server is told if it didn't tell us.
local function abandon(id: number, tellServer: boolean)
	local current = visit
	if current == nil or current.id ~= id then
		return
	end
	visit = nil
	if session then
		session.cancel()
		session = nil
	end
	close()
	if tellServer then
		Net.event("MinigameCancel"):FireServer(id)
	end
	MinigameController.abandoned:Fire(current.houseId)
end

-- Whether you're asking to move (a key or the stick); held movement doesn't move you.
local function wantsToMove(): boolean
	for _, key in MOVE_KEYS do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.6 then
			return true
		end
	end
	return false
end

-- Every frame of a visit: holding a direction breaks you away; so does ending up far from the door.
local function watchVisit(dt: number)
	local current = visit
	if current == nil then
		pushing = 0
		return
	end
	hint.Visible = os.clock() - visitStarted > HINT_AFTER
	pushing = if wantsToMove() then pushing + dt else 0
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local far = current.door and root and (root.Position - current.door).Magnitude > Economy.DOOR_LEAVE
	if pushing >= BREAK_AWAY or far then
		pushing = 0
		abandon(current.id, true)
	end
end

-- A challenge: whoever answers comes out and says hello first (its intro, DoorController), you
-- held where you can see them; then the game itself.
local function start(challenge: any)
	if session then
		session.cancel()
		session = nil
	end
	local context = if type(challenge.context) == "table" then challenge.context else {}
	visit = {
		id = challenge.id,
		houseId = if type(context.houseId) == "string" then context.houseId else nil,
		door = if typeof(context.door) == "Vector3" then context.door else nil,
	}
	local entry = GAMES[challenge.kind]
	if entry == nil then
		-- Not built on the client: answer at once so the door doesn't hang.
		visit = nil
		Net.event("MinigameSubmit"):FireServer(challenge.id, {})
		return
	end
	gradeLabel.Visible = false
	visitStarted = os.clock()
	pushing = 0
	lockMovement(true)
	local intro = if type(challenge.intro) == "number" then challenge.intro else 0
	if intro <= 0 then
		begin(challenge)
		return
	end
	local waiting: Session
	waiting = {
		cancel = function()
			if session == waiting then
				session = nil
			end
		end,
	}
	session = waiting
	task.delay(intro, function()
		if session == waiting then
			session = nil
			begin(challenge)
		end
	end)
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
	hint = create("TextLabel", {
		Name = "WalkAway",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(420, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		Text = "hold a direction to walk away",
		TextColor3 = Theme.Colors.TextDim,
		TextTransparency = 0.25,
		TextSize = 15,
		Visible = false,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.6 }),
	})
	local gui = create("ScreenGui", {
		Name = "Minigame",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		catcher,
		stage,
		hint,
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
	Net.event("MinigameCancelled").OnClientEvent:Connect(function(id: any)
		if type(id) == "number" then
			abandon(id, false)
		end
	end)
	RunService.Heartbeat:Connect(watchVisit)
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
