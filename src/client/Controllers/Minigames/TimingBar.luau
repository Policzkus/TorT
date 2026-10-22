--!strict
-- Timing Bar UI. Draws the shared rules (Shared/Modules/Minigames/TimingBar) and records raw tap
-- times; the server re-grades them from the same seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Minigames = require(Shared.Config.Minigames)
local Rules = require(Shared.Modules.Minigames.TimingBar)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.Parent.UI.create)

export type Callbacks = {
	onTap: (hit: number, grade: string, total: number) -> (),
	onDone: (taps: { number }, spec: Rules.Spec) -> (),
}

export type Session = {
	press: () -> (),
	cancel: () -> (),
}

local ZONE_COLORS = {
	GOOD = Color3.fromHex("FF8A00"),
	GREAT = Color3.fromHex("FFD23F"),
	PERFECT = Color3.fromHex("7CFF4F"),
}

local TimingBar = {}

function TimingBar.run(parent: Frame, challenge: any, callbacks: Callbacks): Session
	local spec = Rules.generate(challenge.seed, challenge.difficulty)
	local hits = #spec.zones

	local zones: { [string]: Frame } = {}
	local track = create("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	for _, grade in { "GOOD", "GREAT", "PERFECT" } do
		zones[grade] = create("Frame", {
			Name = grade,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromScale((spec.widths :: any)[grade], 1),
			BackgroundColor3 = ZONE_COLORS[grade],
			BorderSizePixel = 0,
			Parent = track,
		})
	end
	local needle = create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 8, 1, 22),
		BackgroundColor3 = Theme.Colors.Text,
		ZIndex = 3,
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2.5 }),
	})
	local bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(1, -40, 0, 48),
		BackgroundColor3 = Theme.Colors.PanelDark,
		create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 4 }),
		track,
		needle,
	})
	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = if hits > 1 then "KNOCK KNOCK!  HIT 1 / " .. hits else "KNOCK KNOCK!",
		TextColor3 = Theme.Colors.Text,
		TextSize = 32,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
	})
	local hint = create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		Text = "Stop the needle in the GREEN  •  Space / Click / Tap / Ⓐ",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 17,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1.5 }),
	})
	local popScale = create("UIScale", { Scale = 0.6 })
	local root = create("Frame", {
		Name = "TimingBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(620, 150),
		BackgroundTransparency = 1,
		popScale,
		title,
		bar,
		hint,
		Parent = parent,
	})
	TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	local function showZone(hit: number)
		local centre = spec.zones[hit]
		for _, zone in zones do
			zone.Position = UDim2.fromScale(centre, 0)
		end
	end
	showZone(1)

	local taps: { number } = {}
	local startedAt = os.clock()
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
		needle.Position = UDim2.fromScale(Rules.needleAt(spec, t), 0.5)
		if t > spec.timeout then
			finish()
		end
	end)

	local function tap()
		if done then
			return
		end
		local t = os.clock() - startedAt
		-- Never send input the server would reject as inhuman; just ignore it.
		if t < Minigames.MIN_REACTION + 0.01 then
			return
		end
		local previous = taps[#taps]
		if previous and t - previous < Minigames.MIN_TAP_GAP + 0.02 then
			return
		end
		table.insert(taps, t)
		local hit = #taps
		local grade = Rules.gradeAt(spec, hit, t)
		callbacks.onTap(hit, grade, hits)
		needle.BackgroundColor3 = ZONE_COLORS[grade] or Theme.Colors.Danger
		task.delay(0.12, function()
			needle.BackgroundColor3 = Theme.Colors.Text
		end)
		if hit >= hits then
			finish()
		else
			title.Text = `NICE!  HIT {hit + 1} / {hits}`
			showZone(hit + 1)
		end
	end

	return {
		press = tap,
		cancel = function()
			if not done then
				done = true
				connection:Disconnect()
				root:Destroy()
			end
		end,
	}
end

return TimingBar
