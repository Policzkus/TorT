--!strict
-- Costume Line UI: the homeowner greets you in their style; pick the answer they'd like before
-- the timer runs out. Big buttons for phones; number keys 1-4 on PC. Input: { time, choice }.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dialogue = require(Shared.Config.Dialogue)
local Rules = require(Shared.Modules.Minigames.CostumeLine)
local Button = require(script.Parent.Parent.Parent.UI.Components.Button)
local ProgressBar = require(script.Parent.Parent.Parent.UI.Components.ProgressBar)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.Parent.UI.create)

export type Callbacks = {
	onTap: (hit: number, grade: string, total: number) -> (),
	onDone: (input: { number }, spec: any) -> (),
}

local ACTION = "CostumeLineChoice"
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local CostumeLine = {}

function CostumeLine.run(parent: Frame, challenge: any, callbacks: Callbacks)
	local spec = Rules.generate(challenge.seed, challenge.difficulty, challenge.context)
	local personality = Dialogue.personalities[spec.personality]

	local bubble = create("Frame", {
		Name = "Bubble",
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = Theme.Colors.Text,
		create("UICorner", { CornerRadius = UDim.new(0, 18) }),
		create(
			"UIStroke",
			{ Color = Theme.Colors.Stroke, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
		),
		create("TextLabel", {
			Name = "Who",
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = `{personality.emoji} {personality.name}  <font color="#8A6BFF">(likes {personality.likes})</font>`,
			RichText = true,
			TextColor3 = Theme.Colors.Stroke,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		create("TextLabel", {
			Name = "Says",
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -32, 0, 60),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.BodyHeavy,
			Text = `"{spec.greeting}"`,
			TextColor3 = Theme.Colors.Panel,
			TextSize = 22,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
	local options = create("Frame", {
		Name = "Options",
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.new(1, 0, 0, #spec.options * 58),
		BackgroundTransparency = 1,
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local popScale = create("UIScale", { Scale = 0.6 })
	local root = create("Frame", {
		Name = "CostumeLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(640, 150 + #spec.options * 58),
		BackgroundTransparency = 1,
		popScale,
		bubble,
		options,
		Parent = parent,
	})
	local timer = ProgressBar.new({
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 122),
		color = Theme.Colors.Slime,
		textSize = 12,
		parent = root,
	})
	timer:set(1)
	TweenService:Create(popScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	local startedAt = os.clock()
	local done = false
	local connection: RBXScriptConnection
	local buttons: { TextButton } = {}

	local function finish(input: { number })
		if done then
			return
		end
		done = true
		connection:Disconnect()
		ContextActionService:UnbindAction(ACTION)
		callbacks.onDone(input, spec)
		task.delay(0.9, function()
			root:Destroy()
		end)
	end

	local function choose(index: number)
		if done or index < 1 or index > #spec.options then
			return
		end
		local t = os.clock() - startedAt
		local right = index == spec.correct
		buttons[index].BackgroundColor3 = if right then Theme.Colors.Slime else Theme.Colors.Danger
		if not right then
			buttons[spec.correct].BackgroundColor3 = Theme.Colors.Slime
		end
		finish({ t, index })
	end

	for index, text in spec.options do
		buttons[index] = Button.new({
			name = "Option" .. index,
			text = `{index}.  {text}`,
			size = UDim2.new(1, 0, 0, 50),
			color = Theme.Colors.PanelLight,
			textSize = 19,
			layoutOrder = index,
			parent = options,
			onClick = function()
				choose(index)
			end,
		})
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = buttons[1]
	end

	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local index = table.find(KEYS, input.KeyCode)
			if index then
				choose(index)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(KEYS))

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt
		local left = math.max(0, 1 - t / spec.timer)
		timer:set(left)
		timer:setColor(
			if left > 0.5 then Theme.Colors.Slime elseif left > 0.25 then Theme.Colors.Orange else Theme.Colors.Danger
		)
		if t > spec.timer then
			finish({})
		end
	end)

	return {
		usesOwnButtons = true,
		cancel = function()
			if not done then
				done = true
				connection:Disconnect()
				ContextActionService:UnbindAction(ACTION)
				root:Destroy()
			end
		end,
	}
end

return CostumeLine
