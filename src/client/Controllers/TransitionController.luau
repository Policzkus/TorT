--!strict
-- Full-screen fade for teleports. fadeOut/fadeIn yield until the tween finishes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local create = require(script.Parent.Parent.UI.create)

local TransitionController = {}

local cover: Frame

local function tween(transparency: number, duration: number)
	local t = TweenService:Create(cover, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
		BackgroundTransparency = transparency,
	})
	t:Play()
	t.Completed:Wait()
end

function TransitionController.fadeOut(duration: number?)
	cover.Visible = true
	tween(0, duration or 0.25)
end

function TransitionController.fadeIn(duration: number?)
	tween(1, duration or 0.35)
	cover.Visible = false
end

function TransitionController.Init()
	cover = create("Frame", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
	})
	create("ScreenGui", {
		Name = "Transition",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		cover,
	})
end

return TransitionController
