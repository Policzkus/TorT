--!strict
-- Black loading screen until the world exists and your character has spawned, so nobody sees the
-- void while the server builds the neighbourhood (meshes take a few seconds on a fresh server).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local LoadingController = {}

local PRELOAD_TIMEOUT = 25 -- seconds; never keep anyone stuck behind the cover

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
			TextSize = 30,
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
		-- Download every mesh and texture now (houses, homeowners, characters), so nothing pops in
		-- half-loaded the first time it appears at a door.
		local status = cover:FindFirstChild("Status") :: TextLabel
		local templates = ReplicatedStorage:FindFirstChild("MeshTemplates")
		if templates then
			local list = templates:GetChildren()
			local done = 0
			local finished = false
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync(list, function()
						done += 1
						status.Text = `the homeowners are getting dressed... {math.min(
							100,
							math.floor(done / (#list * 2) * 100)
						)}%`
					end)
				end)
				finished = true
			end)
			local deadline = os.clock() + PRELOAD_TIMEOUT
			while not finished and os.clock() < deadline do
				task.wait(0.1)
			end
		end
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
