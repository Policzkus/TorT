--!strict
-- Knock Rhythm UI: the door plays a knock pattern (sound + bouncing door + lighting dots), then
-- the player repeats it. Raw tap times are sent; the server grades with the shared rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Minigames = require(Shared.Config.Minigames)
local Rules = require(Shared.Modules.Minigames.KnockRhythm)
local Sound = require(script.Parent.Parent.SoundController)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.Parent.UI.create)

export type Callbacks = {
	onTap: (hit: number, grade: string, total: number) -> (),
	onDone: (input: { number }, spec: any) -> (),
}

-- HUD style: dark tiles that flash white as the knocks play; your taps go green to red.
local DOT_IDLE = Theme.Colors.Panel
local DOT_PLAY = Theme.Colors.Text
local GRADE_COLOR = {
	PERFECT = Theme.Colors.Success,
	GREAT = Theme.Colors.Text,
	GOOD = Theme.Colors.TextDim,
	MISS = Theme.Colors.Danger,
}

local KnockRhythm = {}

local function bump(object: GuiObject)
	local scale = object:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.35
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
end

function KnockRhythm.run(parent: Frame, challenge: any, callbacks: Callbacks)
	local spec = Rules.generate(challenge.seed, challenge.difficulty, challenge.context)
	local count = #spec.pattern

	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "LISTEN",
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local door = create("TextLabel", {
		Name = "Door",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false, -- the dots carry the rhythm now
		create("UIScale", {}),
	})
	local row = create("Frame", {
		Name = "Dots",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(count * 28, 18),
		BackgroundTransparency = 1,
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	local dots: { Frame } = {}
	for i = 1, count do
		dots[i] = create("Frame", {
			Name = "Dot" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = DOT_IDLE,
			BackgroundTransparency = 0.2,
			create("UICorner", { CornerRadius = Theme.Corner }),
			create("UIStroke", {
				Color = Theme.Colors.Hairline,
				Transparency = 0.6,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("UIScale", {}),
			Parent = row,
		})
	end
	local hint = create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		Text = "Remember the rhythm",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local popScale = create("UIScale", { Scale = 1 }) -- grows a little as it appears
	local root = create("Frame", {
		Name = "KnockRhythm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(460, 80),
		BackgroundTransparency = 1,
		popScale,
		title,
		door,
		row,
		hint,
		Parent = parent,
	})
	TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.2 })
		:Play()

	local startedAt = os.clock()
	local taps: { number } = {}
	local played, fakesPlayed = 0, 0
	local yourTurn = false
	local done = false
	local connection: RBXScriptConnection

	local function finish()
		if done then
			return
		end
		done = true
		connection:Disconnect()
		callbacks.onDone(taps, spec)
		task.delay(0.7, function()
			root:Destroy()
		end)
	end

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt
		-- Listen phase: play each knock on time.
		while played < count and t >= spec.listenAt + spec.pattern[played + 1] do
			played += 1
			Sound.play("KnockSingle")
			bump(door)
			dots[played].BackgroundColor3 = DOT_PLAY
			bump(dots[played])
		end
		while fakesPlayed < #spec.fakes and t >= spec.fakes[fakesPlayed + 1] do
			fakesPlayed += 1
			Sound.play("Creak", { volume = 0.8, speed = 1.3 })
		end
		if not yourTurn and t >= spec.turnAt - 0.25 then
			yourTurn = true
			title.Text = "YOUR TURN"
			hint.Text = "Knock the same rhythm   ·   Space / Click / Tap / Ⓐ"
			for _, dot in dots do
				dot.BackgroundColor3 = DOT_IDLE
			end
		end
		if t > spec.timeout then
			finish()
		end
	end)

	local function press()
		if done or not yourTurn then
			return
		end
		local t = os.clock() - startedAt
		local previous = taps[#taps]
		if previous and t - previous < Minigames.MIN_TAP_GAP + 0.02 then
			return
		end
		table.insert(taps, t)
		local hit = #taps
		Sound.play("KnockSingle")
		bump(door)
		-- Colour the dot by how close this tap was to the rhythm.
		local err = if hit == 1 then 0 else math.abs((t - taps[1]) - spec.pattern[hit])
		local rules = Minigames.KnockRhythm
		local grade = if err <= rules.perfect
			then "PERFECT"
			elseif err <= rules.great then "GREAT"
			elseif err <= rules.good then "GOOD"
			else "MISS"
		dots[hit].BackgroundColor3 = GRADE_COLOR[grade]
		bump(dots[hit])
		callbacks.onTap(hit, grade, count)
		if hit >= count then
			finish()
		end
	end

	return {
		press = press,
		cancel = function()
			if not done then
				done = true
				connection:Disconnect()
				root:Destroy()
			end
		end,
	}
end

return KnockRhythm
