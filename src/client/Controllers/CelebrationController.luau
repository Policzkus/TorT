--!strict
-- Big centre-screen moments ("MAPLE LANE UNLOCKED!"). The server fires Celebrate(kind, payload);
-- other controllers can also subscribe with CelebrationController.on(kind, fn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Modules.Signal)
local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local CelebrationController = {}

local fired = Signal.new() -- (kind, payload)
local banner: TextLabel
local subtitle: TextLabel
local popScale: UIScale
local showing = 0

function CelebrationController.on(kind: string, fn: (payload: any) -> ())
	return fired:Connect(function(firedKind: string, payload: any)
		if firedKind == kind then
			fn(payload)
		end
	end)
end

function CelebrationController.show(title: string, sub: string?, color: Color3?, sound: string?)
	showing += 1
	local token = showing
	banner.Text = title
	banner.TextColor3 = color or Theme.Colors.OrangeLight
	subtitle.Text = sub or ""
	banner.Visible = true
	subtitle.Visible = sub ~= nil
	popScale.Scale = 0.3
	TweenService:Create(popScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	Sound.play(sound or "Unlock")
	task.delay(2.8, function()
		if showing == token then
			local out = TweenService:Create(
				popScale,
				TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			)
			out:Play()
			out.Completed:Wait()
			if showing == token then
				banner.Visible = false
				subtitle.Visible = false
			end
		end
	end)
end

local function handle(kind: string, payload: any)
	if kind == "unlock" then
		CelebrationController.show(
			`🔓 {string.upper(payload.name)} UNLOCKED!`,
			"Walk through the gate or take the bus 🚌",
			Theme.Colors.Slime
		)
	end
	fired:Fire(kind, payload)
end

function CelebrationController.Init()
	popScale = create("UIScale", { Scale = 0 })
	banner = create("TextLabel", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextSize = 58,
		TextColor3 = Theme.Colors.OrangeLight,
		Visible = false,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 5 }),
	})
	subtitle = create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextSize = 26,
		TextColor3 = Theme.Colors.Text,
		Visible = false,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 3 }),
	})
	local gui = create("ScreenGui", {
		Name = "Celebration",
		ResetOnSpawn = false,
		DisplayOrder = 60,
		create("Frame", {
			Name = "Holder",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.fromOffset(900, 110),
			BackgroundTransparency = 1,
			popScale,
			banner,
			subtitle,
		}),
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
	Net.event("Celebrate").OnClientEvent:Connect(handle)
end

return CelebrationController
