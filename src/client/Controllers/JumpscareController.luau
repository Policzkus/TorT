--!strict
-- Jumpscares (PROMPT §3.19), all client-side: camera locks onto the door, the door bursts open and
-- the ghost lunges at the camera with a stinger, shake and a red flash.
-- Settings → Jumpscares: Full | Reduced (no stinger, no flash) | Off (a "BOO!" text pop).
-- A ~45 s global cooldown keeps scares effective: anything sooner gets the gentle version.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MeshLibrary = require(Shared.Modules.MeshLibrary)
local Net = require(Shared.Modules.Net)
local DoorController = require(script.Parent.DoorController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local COOLDOWN = 45

local JumpscareController = {}

local flash: Frame
local boo: TextLabel
local lineLabel: TextLabel
local lastFullScare = -math.huge
local busy = false

-- The house's own homeowner lunges at you (the ghost if the house has none).
local function monster(door: BasePart): BasePart
	local house = door:FindFirstAncestorOfClass("Model")
	local ownerModel = house and house:GetAttribute("OwnerModel")
	local mesh = (if type(ownerModel) == "string" then MeshLibrary.get(ownerModel) else nil) or MeshLibrary.get("Ghost")
	if mesh then
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CastShadow = false
		return mesh
	end
	-- Fallback: a big white blob with dark eyes.
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4, 4, 4)
	body.Color = Color3.new(0.95, 0.95, 1)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	for _, x in { -0.8, 0.8 } do
		local eye = Instance.new("Part")
		eye.Size = Vector3.new(0.7, 1, 0.2)
		eye.Color = Color3.new(0.05, 0.05, 0.08)
		eye.Anchored = true
		eye.CanCollide = false
		eye.CFrame = CFrame.new(x, 0.5, -1.9)
		eye.Parent = body
	end
	return body
end

local function popBoo(text: string)
	boo.Text = text
	boo.Visible = true
	local scale = boo:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.2
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(1.1, function()
		boo.Visible = false
	end)
end

local function showLine(text: string?)
	if text == nil then
		return
	end
	lineLabel.Text = `"{text}"`
	lineLabel.Visible = true
	task.delay(2.2, function()
		lineLabel.Visible = false
	end)
end

local function shake(camera: Camera, seconds: number, strength: number)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > seconds then
			connection:Disconnect()
			return
		end
		local fade = 1 - t / seconds
		camera.CFrame *= CFrame.new((math.random() - 0.5) * strength * fade, (math.random() - 0.5) * strength * fade, 0)
	end)
end

local function fullScare(door: BasePart, gentle: boolean, reduceFlash: boolean, line: string?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	busy = true
	local previousType = camera.CameraType
	local previousCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local view = door.CFrame * CFrame.new(0, 1.2, -10)
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		CFrame = CFrame.lookAt(view.Position, door.Position + Vector3.new(0, 0.8, 0)),
	}):Play()
	Sound.play("Creak", { speed = 1.6 })
	task.wait(0.3)

	-- Door bursts open (local only), swinging inward around its left edge.
	local original = door.CFrame
	local hinge = door.CFrame * CFrame.new(-door.Size.X / 2, 0, 0)
	local opened = hinge * CFrame.Angles(0, math.rad(-105), 0) * hinge:Inverse() * original
	TweenService:Create(door, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { CFrame = opened }):Play()

	local ghost = monster(door)
	local start = door.CFrame * CFrame.new(0, 0.4, 1.2)
	ghost.CFrame = start
	ghost.Parent = Workspace
	local target = camera.CFrame * CFrame.new(0, -0.6, -3.6)
	TweenService:Create(ghost, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = CFrame.lookAt(target.Position, camera.CFrame.Position),
	}):Play()
	if gentle then
		Sound.play("GhostWail", { volume = 0.6, speed = 1.3 })
	else
		Sound.play("Stinger")
	end
	task.wait(0.12)
	if not reduceFlash and not gentle then
		flash.BackgroundTransparency = 0.25
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end
	shake(camera, if gentle then 0.3 else 0.55, if gentle then 0.35 else 1.1)
	showLine(line)
	task.wait(0.9)

	ghost:Destroy()
	TweenService:Create(door, TweenInfo.new(0.3), { CFrame = original }):Play()
	camera.CFrame = previousCFrame
	camera.CameraType = previousType
	busy = false
end

local function onJumpscare(houseId: string, kind: string, line: string?)
	if busy then
		return
	end
	local settings = StateController.get("settings") or {}
	local mode = settings.jumpscare or "Full"
	local door = DoorController.getDoor(houseId)
	local now = os.clock()
	if mode == "Off" or door == nil then
		popBoo(if kind == "caught" then "CAUGHT!" else "BOO!")
		showLine(line)
		Sound.play("Pop", { speed = 0.8 })
		return
	end
	-- Too soon after the last big scare: keep it gentle so scares stay special.
	local gentle = mode == "Reduced" or now - lastFullScare < COOLDOWN
	if not gentle then
		lastFullScare = now
	end
	task.spawn(fullScare, door, gentle, settings.reduceFlash == true, line)
end

function JumpscareController.Init()
	flash = create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("B0101A"),
		BackgroundTransparency = 1,
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.75),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	boo = create("TextLabel", {
		Name = "Boo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 140),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "BOO!",
		TextColor3 = Theme.Colors.Text,
		TextSize = 120,
		Visible = false,
		create("UIScale", {}),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 6 }),
	})
	lineLabel = create("TextLabel", {
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromOffset(900, 50),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Danger,
		TextSize = 36,
		Visible = false,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 4 }),
	})
	local gui = create("ScreenGui", {
		Name = "Jumpscare",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 90,
		flash,
		boo,
		lineLabel,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
	Net.event("Jumpscare").OnClientEvent:Connect(onJumpscare)
end

return JumpscareController
