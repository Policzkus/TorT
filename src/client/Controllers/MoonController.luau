--!strict
-- The moon in the Witching Hour (and under the Blood Moon): as the hour starts it turns, slowly, into
-- a blood moon, swelling, a warm glow round it, then holds still until it's over and fades back. No
-- other animation: a heartbeat throb read as blinking. The sky's own moon stays the moon (its
-- texture); over it sits a disc that's see-through at first and solid once it's turned, with a dark
-- rim and fainter, wider discs for the glow. They're a billboard along the moon's direction, sized
-- to the sky's moon (Sky.MoonAngularSize), so they stay on it wherever you look from. The red sky
-- itself is ZoneLightingController's.
-- A red moon on that red sky didn't show at all (the user, twice): it's no longer red on red but lit,
-- bone pale on one side going to blood orange on the other (a sphere lit from the side), outlined
-- dark, its glow orange rather than the sky's crimson, and lit past white (the billboard's
-- Brightness) so the bloom catches it. And it's drawn near you, not far off in the fog (the haze
-- would wash anything out there to the sky's colour): only as far out as puts it above the roofs.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local create = require(script.Parent.Parent.UI.create)

local MoonController = {}

-- Studs out along the moon's direction: far enough to be up over every roof (ABOVE studs over
-- your eyes), no further (the fog).
local DISTANCE = { least = 80, above = 60 }
local DISC = 1.06 -- of the sky moon's angular size: a touch over, so no white rim peeks out round it
local RED_IN = 25 -- seconds for the moon to turn all the way once the Witching Hour starts
local FADE_OUT = 8 -- seconds back once it's over
local SWELL = 1.5 -- how much bigger the moon gets, turned
local PALE = Color3.fromHex("E8C9B0") -- the sky's moon, before it turns
local LIGHT = Color3.fromHex("FFEBDA") -- turned: its lit side, bone pale
local DEEP = Color3.fromHex("E2401F") -- its shadowed side, blood orange
local SHADE = 35 -- the shading turned this many degrees: lit from the upper right
local RIM = { size = 1.07, color = Color3.fromHex("1E0305"), transparency = 0.35 } -- the dark outline
local GLOW = Color3.fromHex("FF9450") -- the glow round it: orange, not the sky's crimson
local OPAQUE = 0.97 -- how much of the moon it covers, turned (its craters only just show through)
local LIT = 3 -- the billboard's Brightness, turned: past white, so the bloom catches it
-- Glow round it: size (times the disc) and how see-through, turned.
local HALOS =
	{ { size = 1.35, transparency = 0.62 }, { size = 2.1, transparency = 0.8 }, { size = 3.4, transparency = 0.9 } }

local worldState: Instance? = nil
local anchor: Attachment
local billboard: BillboardGui
local disc: Frame
local shading: UIGradient
local rim: Frame
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
		BackgroundColor3 = GLOW,
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
	local distance = math.max(DISTANCE.least, DISTANCE.above / math.max(direction.Y, 0.2))
	local diameter = 2 * distance * math.tan(math.rad(angular) / 2) * DISC
	-- The sky's moon sits a hair above its direction: lift the disc to match.
	anchor.WorldPosition = camera.CFrame.Position + direction * distance + Vector3.new(0, diameter * 0.025, 0)
	local widest = HALOS[#HALOS].size
	billboard.Size = UDim2.fromScale(diameter * widest, diameter * widest)
	disc.Size = UDim2.fromScale(1 / widest, 1 / widest)
	disc.BackgroundTransparency = 1 - red * OPAQUE
	shading.Color = ColorSequence.new(PALE:Lerp(LIGHT, red), PALE:Lerp(DEEP, red))
	rim.Size = UDim2.fromScale(RIM.size / widest, RIM.size / widest)
	rim.BackgroundTransparency = 1 - (1 - RIM.transparency) * red
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
	rim = circle("Rim", RIM.size, #HALOS + 1)
	rim.BackgroundColor3 = RIM.color
	disc = circle("Disc", 1, #HALOS + 2)
	disc.BackgroundColor3 = Color3.new(1, 1, 1) -- (the gradient colours it)
	shading = create("UIGradient", { Rotation = SHADE + 90, Parent = disc })
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
