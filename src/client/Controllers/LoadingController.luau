--!strict
-- Black loading screen until the world exists and your character has spawned, so nobody sees the
-- void while the server builds the neighbourhood (meshes take a few seconds on a fresh server).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterModels = require(ReplicatedStorage.Shared.Config.CharacterModels)
local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)

local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local LoadingController = {}

local PRELOAD_TIMEOUT = 45 -- seconds; never keep anyone stuck behind the cover
local SETTLE_TIMEOUT = 15 -- seconds to wait after the warm-up for the downloads it started
-- What to download behind the cover, first to last: the Blender homeowners (tools/setup_characters),
-- the AI meshes (Modules/MeshLibrary), then the furniture seen through open doors.
local PRELOAD = {
	{ "Assets", "Characters" },
	{ "MeshTemplates" },
	{ "Assets", "Furniture" },
}

-- Everything to download under the PRELOAD folders, in order, and how many downloads that is: each
-- mesh (and its texture), and the SurfaceAppearance maps the setup scripts noted on the part as
-- "Maps" (PreloadAsync doesn't fetch them through the SurfaceAppearance itself, nor as bare ids:
-- each goes on a Decal that's never parented).
local function preloadList(): ({ Instance }, number)
	local list, count = {}, 0
	for _, path in PRELOAD do
		local folder: Instance? = ReplicatedStorage
		for _, name in path do
			folder = folder and folder:FindFirstChild(name)
		end
		if folder == nil then
			continue
		end
		for _, item in folder:GetDescendants() do
			if item:IsA("MeshPart") then
				table.insert(list, item)
				count += if item.TextureID ~= "" then 2 else 1
				local maps = item:GetAttribute("Maps")
				if type(maps) == "string" and maps ~= "" then
					for _, id in string.split(maps, ",") do
						local carrier = Instance.new("Decal")
						carrier.Texture = id
						table.insert(list, carrier)
						count += 1
					end
				end
			end
		end
	end
	return list, count
end

-- Shows every Blender homeowner once, right in front of the camera under the cover: their
-- SurfaceAppearance maps (PreloadAsync doesn't fetch those) load the first time they're seen, at the
-- detail they're seen at, so the first door that opens would wait for them.
local function warmUp()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	for id in CharacterModels do
		local rig = CharacterRig.build(id, "preview")
		if rig == nil then
			continue
		end
		local at = (camera.CFrame * CFrame.new(0, -3, -8)).Position
		local eye = camera.CFrame.Position
		rig:PivotTo(CFrame.lookAt(at, Vector3.new(eye.X, at.Y, eye.Z)))
		rig.Parent = Workspace
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		task.wait(0.1)
		rig:Destroy()
	end
end

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
		-- Download every mesh and texture now (homeowners, characters, furniture), so nothing pops in
		-- half-loaded the first time it appears at a door. What isn't done by the deadline carries on
		-- downloading in the background.
		local status = cover:FindFirstChild("Status") :: TextLabel
		local list, expected = preloadList()
		if #list > 0 then
			local done = 0
			local finished = false
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync(list, function()
						done += 1
						status.Text =
							`the homeowners are getting dressed... {math.min(100, math.floor(done / expected * 100))}%`
					end)
				end)
				finished = true
			end)
			local deadline = os.clock() + PRELOAD_TIMEOUT
			while not finished and os.clock() < deadline do
				task.wait(0.1)
			end
		end
		warmUp()
		local settle = os.clock() + SETTLE_TIMEOUT
		while ContentProvider.RequestQueueSize > 0 and os.clock() < settle do
			task.wait(0.1)
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
