--!strict
-- Nerve Hold UI: press and hold while the house gets scary; the BRAVERY bar fills to the end.
-- Letting go early is a flinch. Scares: light flicker, the ghost peeking in, whispers, and from
-- difficulty 5 a fake "LET GO!" trap. Input sent: { pressTime, releaseTime }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Minigames = require(Shared.Config.Minigames)
local MeshLibrary = require(Shared.Modules.MeshLibrary)
local Rules = require(Shared.Modules.Minigames.NerveHold)
local Sound = require(script.Parent.Parent.SoundController)
local StateController = require(script.Parent.Parent.StateController)
local ProgressBar = require(script.Parent.Parent.Parent.UI.Components.ProgressBar)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.Parent.UI.create)

export type Callbacks = {
	onTap: (hit: number, grade: string, total: number) -> (),
	onDone: (input: { number }, spec: any) -> (),
}

local NerveHold = {}

-- A ViewportFrame with the AI ghost (or a big emoji if the mesh isn't available).
local function ghostPeek(): GuiObject
	local mesh = MeshLibrary.get("Ghost")
	if mesh == nil then
		return create("TextLabel", {
			BackgroundTransparency = 1,
			Text = "👻",
			TextScaled = true,
			FontFace = Theme.Fonts.Heading,
		})
	end
	local viewport = create("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 230),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.3, -1, -0.6),
	})
	mesh.CFrame = CFrame.new(0, 0, 0)
	mesh.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.3, -7), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

function NerveHold.run(parent: Frame, challenge: any, callbacks: Callbacks)
	local spec = Rules.generate(challenge.seed, challenge.difficulty, challenge.context)
	local settings = StateController.get("settings") or {}
	local gentle = settings.reduceFlash == true or settings.jumpscare == "Off"

	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "HOLD",
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local hint = create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		Text = "Hold Space / Tap / Ⓐ   ·   don't let go",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
	})
	local popScale = create("UIScale", { Scale = 1 }) -- grows a little as it appears
	local root = create("Frame", {
		Name = "NerveHold",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(460, 80),
		BackgroundTransparency = 1,
		popScale,
		title,
		hint,
		Parent = parent,
	})
	local bar = ProgressBar.new({
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0.5, 0, 0, 32),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.Text,
		textSize = 12,
		parent = root,
	})
	bar:setText("BRAVERY")
	TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.2 })
		:Play()

	-- Full-screen effects live in their own layer under everything else.
	local shade = create("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	})
	local lure = create("TextLabel", {
		Name = "Lure",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(600, 90),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		Text = "",
		TextColor3 = Theme.Colors.Danger,
		TextSize = 72,
		TextTransparency = 1,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1, Transparency = 0.45 }),
		Parent = parent,
	})
	local peek = ghostPeek()
	peek.Name = "Peek"
	peek.AnchorPoint = Vector2.new(1, 1)
	peek.Size = UDim2.fromOffset(220, 220)
	peek.Position = UDim2.new(1, 240, 1, 0)
	peek.Parent = parent

	local startedAt = os.clock()
	local pressAt: number? = nil
	local releaseAt: number? = nil
	local nextScare = 1
	local done = false
	local connection: RBXScriptConnection

	local function cleanup()
		Sound.stop("Heartbeat")
		shade:Destroy()
		lure:Destroy()
		peek:Destroy()
	end

	local function finish()
		if done then
			return
		end
		done = true
		connection:Disconnect()
		local input = {}
		if pressAt then
			input[1] = pressAt
			input[2] = releaseAt
		end
		callbacks.onDone(input, spec)
		cleanup()
		task.delay(0.7, function()
			root:Destroy()
		end)
	end

	local function scare(kind: string)
		if kind == "flicker" then
			task.spawn(function()
				for _ = 1, if gentle then 1 else 3 do
					shade.BackgroundTransparency = if gentle then 0.6 else 0.15
					task.wait(if gentle then 0.4 else 0.07)
					shade.BackgroundTransparency = 1
					task.wait(0.09)
				end
			end)
		elseif kind == "face" then
			Sound.play("GhostWail", { volume = 0.6, speed = 1.2 })
			peek.Position = UDim2.new(1, 240, 1, 0)
			TweenService:Create(peek, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(1, -10, 1, 20),
			}):Play()
			task.delay(0.8, function()
				if peek.Parent then
					TweenService:Create(peek, TweenInfo.new(0.2), { Position = UDim2.new(1, 240, 1, 0) }):Play()
				end
			end)
		elseif kind == "whisper" or kind == "trap" then
			local loud = kind == "trap"
			lure.Text = if loud then "LET GO!" else "...let go..."
			lure.TextSize = if loud then 84 else 40
			lure.TextTransparency = if loud then 0 else 0.35
			Sound.play(if loud then "Overflow" else "GhostWail", { volume = if loud then 1.5 else 0.4 })
			TweenService:Create(lure, TweenInfo.new(if loud then 0.9 else 1.4), { TextTransparency = 1 }):Play()
		end
	end

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt
		if pressAt then
			bar:set(Rules.heldShare(spec, { pressAt, t }))
		elseif t > Minigames.NerveHold.pressWindow then
			title.Text = "TOO SCARED TO HOLD?"
			finish()
			return
		end
		while nextScare <= #spec.scares and t >= spec.scares[nextScare].at do
			scare(spec.scares[nextScare].kind)
			nextScare += 1
		end
		if t >= spec.duration then
			title.Text = "BRAVE"
			finish()
		end
	end)

	return {
		press = function()
			if done or pressAt then
				return
			end
			local t = os.clock() - startedAt
			if t < Minigames.MIN_REACTION + 0.01 then
				return
			end
			pressAt = t
			title.Text = "KEEP HOLDING"
			Sound.play("Heartbeat")
		end,
		release = function()
			if done or pressAt == nil then
				return
			end
			releaseAt = os.clock() - startedAt
			title.Text = "FLINCHED"
			title.TextColor3 = Theme.Colors.Danger
			finish()
		end,
		cancel = function()
			if not done then
				done = true
				connection:Disconnect()
				cleanup()
				root:Destroy()
			end
		end,
	}
end

return NerveHold
