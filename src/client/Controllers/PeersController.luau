--!strict
-- What other players are up to, over their heads in the world (the user wants everyone's actions
-- visible): their grade and candy when a door gives them something, CAUGHT when a bowl does them
-- in, what they stash at a Candy Box. A HUD chip on a small panel just above the head, turned to
-- face you, rising and fading. Yours show on your HUD instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Chip = require(script.Parent.Parent.UI.Components.Chip)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local PeersController = {}

local CANVAS = Vector2.new(360, 44) -- pixels: room for the widest chip
local PIXELS = 90 -- the panel's pixels a stud
local ABOVE = 2.2 -- studs over the head it starts
local RISE = 1.3 -- studs it rises as it fades
local LIFE = 1.7 -- seconds it's up
local FAR = 80 -- studs: farther off than this and it isn't shown
local COLORS: { [string]: Color3 } = {
	PERFECT = Theme.Colors.Success,
	GREAT = Theme.Colors.Text,
	GOOD = Theme.Colors.TextDim,
	MISS = Theme.Colors.Danger,
	caught = Theme.Colors.Danger,
	stash = Theme.Colors.Slime,
}

type Pop = { part: BasePart, head: BasePart, group: CanvasGroup, started: number }

local pops: { [Player]: Pop } = {} -- one each: a new one replaces the last

local function drop(player: Player)
	local pop = pops[player]
	if pop then
		pop.part:Destroy()
		pops[player] = nil
	end
end

local function show(userId: any, text: any, kind: any)
	if type(userId) ~= "number" or type(text) ~= "string" or userId == Players.LocalPlayer.UserId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local camera = Workspace.CurrentCamera
	if player == nil or head == nil or camera == nil or (camera.CFrame.Position - head.Position).Magnitude > FAR then
		return
	end
	drop(player)
	local part = create("Part", {
		Name = "PlayerPop",
		Size = Vector3.new(CANVAS.X / PIXELS, CANVAS.Y / PIXELS, 0.05),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	})
	local surface = create("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS,
		LightInfluence = 0,
		Parent = part,
	})
	local group = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = surface,
	})
	Chip.new({
		text = text,
		textSize = 22,
		height = 34,
		color = COLORS[kind :: string] or Theme.Colors.Text,
		parent = group,
	})
	pops[player] = { part = part, head = head, group = group, started = os.clock() }
end

local function update()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	for player, pop in pops do
		local t = os.clock() - pop.started
		if t > LIFE or pop.head.Parent == nil then
			drop(player)
			continue
		end
		local rise = 1 - (1 - t / LIFE) ^ 2
		local at = pop.head.Position + Vector3.new(0, ABOVE + RISE * rise, 0)
		local look = (camera.CFrame.Position - at) * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 then
			pop.part.CFrame = CFrame.lookAt(at, at + look.Unit)
		end
		pop.group.GroupTransparency = math.clamp((t - LIFE * 0.6) / (LIFE * 0.4), 0, 1)
		if pop.part.Parent == nil then
			pop.part.Parent = camera
		end
	end
end

function PeersController.Start()
	Net.event("PlayerPop").OnClientEvent:Connect(show)
	Players.PlayerRemoving:Connect(drop)
	RunService.RenderStepped:Connect(update)
end

return PeersController
