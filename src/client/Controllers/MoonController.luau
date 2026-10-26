--!strict
-- The moon in the Witching Hour (and under the Blood Moon): it turns red, slowly, as the hour starts
-- (the user's ask), swelling a little, a red glow round it, then holds still until it's over and
-- fades back. No other animation: a heartbeat throb read as blinking. The sky's own moon stays the
-- moon (its texture); over it sits a red disc that's see-through at first and less so as it reddens,
-- with fainter, wider discs for the glow. They're a billboard out along the moon's direction, sized
-- to the sky's moon (Sky.MoonAngularSize), so they stay on it wherever you look from. The red sky
-- itself is ZoneLightingController's. Its thick red haze all but hid the moon (the user wanted it to
-- stand out): red, it's bigger, near solid and lit past white (the billboard's Brightness), so it
-- glows through the haze and the bloom catches it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local create = require(script.Parent.Parent.UI.create)

local MoonController = {}

local DISTANCE = 2000 -- studs out along the moon's direction (past everything in the town)
local DISC = 1.06 -- of the sky moon's angular size: a touch over, so no white rim peeks out round it
local RED_IN = 25 -- seconds for the moon to go all the way red once the Witching Hour starts
local FADE_OUT = 8 -- seconds back to white once it's over
local SWELL = 1.7 -- how much bigger the moon gets, all red
local PALE = Color3.fromHex("E8C9B0")
local RED = Color3.fromHex("E8281E") -- blood red, bright enough to read through the red fog
local GLOW = Color3.fromHex("FF4A3C") -- the glow round it, brighter than the red sky
local OPAQUE = 0.95 -- how much of the moon the red covers, all red (its craters only just show through)
local LIT = 2.6 -- the billboard's Brightness, all red: past white, so it glows through the haze
-- Glow round it: size (times the disc) and how see-through, all red.
local HALOS =
	{ { size = 1.35, transparency = 0.55 }, { size = 2.1, transparency = 0.76 }, { size = 3.4, transparency = 0.88 } }

local worldState: Instance? = nil
local anchor: Attachment
local billboard: BillboardGui
local disc: Frame
local halos: { Frame } = {}
local sky: Sky? = nil
local redness = 0 -- 0..1 now
local endedAt = -math.huge -- when it last stopped being red (os.clock)
local endedFrom = 0 -- how red it was then

local function circle(name: string, size: number, z: number): Frame
	return create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = RED,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Parent = billboard,
	})
end

-- How red the moon should be right now (0..1).
local function wanted(): number
	local state = worldState
	if state == nil then
		return 0
	end
	if state:GetAttribute("BloodMoon") == true then
		return 1
	end
	if state:GetAttribute("Witching") == true then
		local startedAt = (state:GetAttribute("WitchingAt") :: number?) or Workspace:GetServerTimeNow()
		return math.clamp((Workspace:GetServerTimeNow() - startedAt) / RED_IN, 0, 1)
	end
	return 0
end

local function update()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local target = wanted()
	if target > 0 then
		redness = target
		endedAt, endedFrom = os.clock(), target
	else
		redness = endedFrom * (1 - math.clamp((os.clock() - endedAt) / FADE_OUT, 0, 1))
	end
	billboard.Enabled = redness > 0.01
	if not billboard.Enabled then
		if sky then
			(sky :: Sky).MoonAngularSize = World.LIGHTING.moonSize
		end
		return
	end
	-- Eased in and out; once it's red it stays still (a throb read as blinking to the user).
	local red = redness * redness * (3 - 2 * redness)
	local angular = World.LIGHTING.moonSize * (1 + (SWELL - 1) * red)
	if sky then
		(sky :: Sky).MoonAngularSize = angular
	end
	local direction = Lighting:GetMoonDirection()
	local diameter = 2 * DISTANCE * math.tan(math.rad(angular) / 2) * DISC
	-- The sky's moon sits a hair above its direction: lift the disc to match.
	anchor.WorldPosition = camera.CFrame.Position + direction * DISTANCE + Vector3.new(0, diameter * 0.025, 0)
	local widest = HALOS[#HALOS].size
	billboard.Size = UDim2.fromScale(diameter * widest, diameter * widest)
	disc.Size = UDim2.fromScale(1 / widest, 1 / widest)
	disc.BackgroundColor3 = PALE:Lerp(RED, red)
	disc.BackgroundTransparency = 1 - red * OPAQUE
	billboard.Brightness = 1 + (LIT - 1) * red
	for index, halo in halos do
		local spec = HALOS[index]
		local grow = 0.85 + 0.15 * red
		halo.Size = UDim2.fromScale(spec.size / widest * grow, spec.size / widest * grow)
		halo.BackgroundTransparency = 1 - (1 - spec.transparency) * red
	end
end

function MoonController.Init()
	anchor = create("Attachment", { Name = "RedMoon", Parent = Workspace.Terrain })
	billboard = create("BillboardGui", {
		Name = "RedMoon",
		Adornee = anchor,
		Size = UDim2.fromScale(100, 100),
		LightInfluence = 0,
		AlwaysOnTop = false,
		Enabled = false,
		Parent = anchor,
	})
	for index = #HALOS, 1, -1 do
		halos[index] = circle("Halo" .. index, HALOS[index].size, #HALOS - index + 1)
	end
	for _, halo in halos do
		halo.BackgroundColor3 = GLOW
	end
	disc = circle("Disc", 1, #HALOS + 2)
end

function MoonController.Start()
	sky = Lighting:FindFirstChildOfClass("Sky")
	Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Sky") then
			sky = child
		end
	end)
	worldState = ReplicatedStorage:WaitForChild("WorldState", 15)
	RunService.RenderStepped:Connect(update)
end

return MoonController
