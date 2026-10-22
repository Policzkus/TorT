--!strict
-- Toast messages at the top of the screen. Server sends them through the Notify remote;
-- client code can call NotificationController.show directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Scale = require(script.Parent.Parent.UI.Scale)
local create = require(script.Parent.Parent.UI.create)
local Theme = require(script.Parent.Parent.UI.Theme)

local MAX_VISIBLE = 4
local LIFETIME = 3.5

local KIND_COLORS: { [string]: Color3 } = {
	info = Theme.Colors.Info,
	success = Theme.Colors.Success,
	error = Theme.Colors.Danger,
	candy = Theme.Colors.Orange,
	rare = Theme.Rarity.Gold,
}

local NotificationController = {}

local container: Frame
local toasts: { Frame } = {}
local order = 0

local function dismiss(toast: Frame)
	local index = table.find(toasts, toast)
	if index == nil then
		return
	end
	table.remove(toasts, index)
	local scale = toast:FindFirstChildOfClass("UIScale")
	if scale then
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
			:Play()
	end
	task.delay(0.2, function()
		toast:Destroy()
	end)
end

function NotificationController.show(text: string, kind: string?)
	order += 1
	local accent = KIND_COLORS[kind or "info"] or Theme.Colors.Info
	local scale = create("UIScale", { Scale = 0.5 })
	local toast: Frame = create("Frame", {
		Name = "Toast",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		Parent = container,
		scale,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = accent, Thickness = Theme.StrokeThickness }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		create("TextLabel", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = text,
			TextColor3 = Theme.Colors.Text,
			TextSize = 20,
			TextWrapped = true,
			create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1.5 }),
		}),
	})
	table.insert(toasts, toast)
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	while #toasts > MAX_VISIBLE do
		dismiss(toasts[1])
	end
	task.delay(LIFETIME, dismiss, toast)
end

function NotificationController.Init()
	local gui = create("ScreenGui", {
		Name = "Notifications",
		ResetOnSpawn = false,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
	container = create("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128), -- below the HUD's top bar and goal
		Size = UDim2.fromScale(0.9, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
		create("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge) }),
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		NotificationController.show(text, kind)
	end)
end

return NotificationController
