--!strict
-- Black loading screen until the world exists and your character has spawned, so nobody sees the
-- void while the server builds the neighbourhood (meshes take a few seconds on a fresh server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local LoadingController = {}

function LoadingController.Init()
	local cover = create("Frame", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		create("TextLabel", {
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(700, 60),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = "TRICK OR TREAT",
			TextColor3 = Theme.Colors.Text,
			TextSize = 44,
		}),
		create("TextLabel", {
			Name = "Status",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromOffset(700, 24),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Hud,
			Text = "the houses are waking up...",
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 16,
		}),
	})
	local gui = create("ScreenGui", {
		Name = "Loading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 200,
		cover,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	task.spawn(function()
		ReplicatedStorage:WaitForChild("WorldState", 120)
		local player = Players.LocalPlayer
		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart", 30)
		task.wait(0.6) -- let nearby houses stream in
		local fade = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
		TweenService:Create(cover, fade, { BackgroundTransparency = 1 }):Play()
		for _, label in cover:GetChildren() do
			if label:IsA("TextLabel") then
				TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
			end
		end
		task.wait(1.3)
		gui:Destroy()
	end)
end

return LoadingController
