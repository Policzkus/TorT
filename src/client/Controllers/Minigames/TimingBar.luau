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

-- HUD style: the zones are brightness, not colour (green only where it's perfect).
local ZONES = {
	GOOD = { color = Theme.Colors.Hairline, transparency = 0.78 },
	GREAT = { color = Theme.Colors.Hairline, transparency = 0.5 },
	PERFECT = { color = Theme.Colors.Success, transparency = 0.1 },
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
			BackgroundColor3 = ZONES[grade].color,
			BackgroundTransparency = ZONES[grade].transparency,
			BorderSizePixel = 0,
			Parent = track,
		})
	end
	local needle = create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 3, 1, 10),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 3,
	})
	local bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = Theme.HairlineTransparency, Thickness = 1 }),
		track,
		needle,
	})
	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = if hits > 1 then "KNOCK   1 / " .. hits else "KNOCK",
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local hint = create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		Text = "Stop it in the green   ·   Space / Tap / Ⓐ",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local popScale = create("UIScale", { Scale = 1 }) -- grows a little as it appears
	local root = create("Frame", {
		Name = "TimingBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(460, 80),
		BackgroundTransparency = 1,
		popScale,
		title,
		bar,
		hint,
		Parent = parent,
	})
	TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.2 })
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
		needle.BackgroundColor3 = if ZONES[grade] then ZONES[grade].color else Theme.Colors.Danger
		task.delay(0.12, function()
			needle.BackgroundColor3 = Theme.Colors.Text
		end)
		if hit >= hits then
			finish()
		else
			title.Text = `KNOCK   {hit + 1} / {hits}`
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
