-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/victorian/Victorian.fbx
-- with File > Import 3D (into Workspace). Turns the imported model into the street template at
-- ReplicatedStorage.Assets.Houses.Victorian (World/Street clones it onto every Cardboard Court lot):
-- pivot at the front-centre on the ground facing the street, hinged doors, the knock zone,
-- lights, glass, and simple invisible collision. Save the place afterwards (Assets aren't in Rojo).
--
-- Blender → Roblox: Blender (x, y, z) with the street toward -Y becomes, in the template's pivot
-- frame (street toward -Z), (-x, z, y).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOUND, STORY = 2.6, 11.5
local EAVE = FOUND + 2 * STORY
local DOOR = { x = 1.5, w = 4.2, h = 7.6 }

local imported = workspace:FindFirstChild("Victorian")
assert(imported and imported:IsA("Model"), "Import Victorian.fbx into Workspace first")
local function mesh(name: string): MeshPart?
	return imported:FindFirstChild(name, true) :: MeshPart?
end
local frontSlab = assert(mesh("FrontDoor"), "no FrontDoor mesh")

-- 1. Scale: the door slab is 7.5 studs tall in Blender.
local doorHeight = frontSlab.Size.Y
if math.abs(doorHeight - 7.5) > 0.3 then
	imported:ScaleTo(imported:GetScale() * 7.5 / doorHeight)
end

-- 2. Pivot: ground level at the front-centre, looking toward the street. The front door sits
-- at Blender (1.5, 0.55, FOUND + 3.8); the street is the side of the house the door is on.
local cf, size = imported:GetBoundingBox()
local slabCF = frontSlab.CFrame
local toDoor = (slabCF.Position - cf.Position) * Vector3.new(1, 0, 1)
-- The door's thin axis, flipped to point away from the house.
local axes = { slabCF.RightVector, slabCF.UpVector, slabCF.LookVector }
local sizes = { frontSlab.Size.X, frontSlab.Size.Y, frontSlab.Size.Z }
local thin = 1
for i = 2, 3 do
	if sizes[i] < sizes[thin] then
		thin = i
	end
end
local street = (axes[thin] * Vector3.new(1, 0, 1)).Unit
if street:Dot(toDoor) < 0 then
	street = -street
end
local right = street:Cross(Vector3.yAxis) -- the pivot's +X
local groundY = slabCF.Position.Y - 3.8 - FOUND
-- Door centre is Blender x = 1.5 → pivot x = -1.5; its surface is 0.55 inside the front wall.
local doorPos = slabCF.Position
local front = Vector3.new(doorPos.X, groundY, doorPos.Z) + right * DOOR.x - street * -0.55
local pivot = CFrame.lookAt(front, front + street)
imported.WorldPivot = pivot
local function at(x: number, y: number, z: number): CFrame
	return pivot * CFrame.new(-x, z, y) -- Blender coordinates → world
end

-- 3. Looks for the flat (untextured) pieces.
local function look(name: string, props: { [string]: any })
	local part = mesh(name)
	if part then
		for k, v in props do
			(part :: any)[k] = v
		end
	end
end
-- Glass is SmoothPlastic: Roblox's Glass material hides the window-room images behind it.
look("Glass", { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(40, 48, 50), Transparency = 0.7, Reflectance = 0.08 })
look("LanternGlow", { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 160, 80), Transparency = 0.2 })
look("PumpkinGlow", { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 130, 40), Transparency = 0.15 })
look("Interior", { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(4, 4, 5) })
look("Silhouette", { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(2, 2, 2) })
look("Curtain", { Material = Enum.Material.Fabric, Color = Color3.fromRGB(70, 60, 56) })
look("Wallpaper", { Material = Enum.Material.Fabric, Color = Color3.fromRGB(52, 46, 34) })
look("Iron", { Material = Enum.Material.Metal, Color = Color3.fromRGB(16, 16, 18) })
for _, name in { "Brass_FrontDoor", "Brass_BackDoor" } do
	look(name, { Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 56, 30) })
end
for _, d in imported:GetDescendants() do
	if d:IsA("MeshPart") then
		d.Anchored = true
		d.CanCollide = false -- invisible boxes below do the colliding
		d.CanTouch = false
		d.CastShadow = d.Name ~= "Glass" and d.Name ~= "LanternGlow" and d.Name ~= "PumpkinGlow"
	end
end

-- 4. Lights: the porch lantern (HouseVisualController flickers "PorchLight") and a candle in each
-- jack-o'-lantern. The lit rooms behind the windows come from Victorian.windowRooms per lot.
local function lightPart(name: string, cframe: CFrame, range: number, brightness: number, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.3, 0.3, 0.3)
	p.CFrame = cframe
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color, light.Shadows = range, brightness, color, true
	light.Parent = p
	p.Parent = imported
	return p
end
lightPart("PorchLight", at(DOOR.x - 3.2, -1.2, FOUND + 6.9), 16, 0.9, Color3.fromRGB(255, 170, 96))
local step1 = FOUND - FOUND / 4
for _, spot in { at(DOOR.x - 2.05, -10.58, step1 + 0.4), at(DOOR.x + 3.0, -1.0, FOUND + 0.32) } do
	local candle = lightPart("PumpkinLight", spot, 7, 0.8, Color3.fromRGB(255, 130, 50))
	candle:FindFirstChildWhichIsA("PointLight").Shadows = false
end

-- 5. Doors: each slab (+ its brass) becomes a hinged model (tag "Hinged"; HingeController swings
-- them, HomeownerController opens the front one). The knock zone is an invisible "Door" box.
local function hinged(kind: string, parts: { BasePart }, hingeCF: CFrame, angle: number, openable: boolean): Model
	local m = Instance.new("Model")
	m.Name = kind
	local hinge = Instance.new("Part")
	hinge.Name = "Hinge"
	hinge.Anchored, hinge.CanCollide, hinge.CanQuery, hinge.CanTouch = true, false, false, false
	hinge.Transparency = 1
	hinge.Size = Vector3.new(0.1, 0.1, 0.1)
	hinge.CFrame = hingeCF
	hinge.Parent = m
	m.PrimaryPart = hinge
	for _, p in parts do
		p.Parent = m
	end
	m:SetAttribute("Kind", kind)
	m:SetAttribute("OpenAngle", angle)
	m:SetAttribute("Openable", openable)
	m:SetAttribute("Open", false)
	CollectionService:AddTag(m, "Hinged")
	m.Parent = imported
	return m
end
local function prompt(parent: BasePart, text: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText, p.ObjectText = text, object
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p.Parent = parent
end
local rot = pivot.Rotation
-- Front door: hinge on Blender x = DOOR.x - w/2 (pivot x = +0.6), opening inward.
local frontParts: { BasePart } = { frontSlab }
local frontBrass = mesh("Brass_FrontDoor")
if frontBrass then
	table.insert(frontParts, frontBrass)
end
local knock = Instance.new("Part")
knock.Name = "Door"
knock.Anchored, knock.CanCollide, knock.CanTouch = true, false, false
knock.Transparency = 1
knock.Size = Vector3.new(DOOR.w - 0.1, DOOR.h - 0.1, 0.4)
knock.CFrame = rot + at(DOOR.x, 0.55, FOUND + DOOR.h / 2).Position
table.insert(frontParts, knock)
frontSlab.Name = "FrontSlab"
hinged("FrontDoor", frontParts, rot + at(DOOR.x - DOOR.w / 2, 0.55, FOUND + DOOR.h / 2).Position, 100, false)
-- Back door: on the back wall (Blender x = -8, y = 24.55), hinge on its left as seen from behind.
local backSlab = mesh("BackDoor")
if backSlab then
	local parts: { BasePart } = { backSlab }
	local brass = mesh("Brass_BackDoor")
	if brass then
		table.insert(parts, brass)
	end
	local backRot = rot * CFrame.Angles(0, math.pi, 0)
	hinged("BackDoor", parts, backRot + at(-8 + DOOR.w / 2, 24 - 0.55, FOUND + DOOR.h / 2).Position, 100, true)
	prompt(backSlab, "Open", "Back door")
end
-- Storm-cellar doors against the right wall (Blender x = 15, y = 6), hinged on their outer edges.
local run, w = 4.2, 5
local tilt = math.atan2(FOUND - 1.2, run)
local midZ = 1.2 + (FOUND - 1.2) / 2 + 0.15
for side, name in { [-1] = "CellarDoorL", [1] = "CellarDoorR" } do
	local leaf = mesh(name)
	if leaf then
		-- Edge line: Blender (15 + run/2, 6 + side * w/2, midZ), running out from the wall (along x).
		local edge = at(15 + run / 2, 6 + side * w / 2, midZ).Position
		local outward = (at(16, 0, 0).Position - at(15, 0, 0).Position).Unit
		local axis = (outward * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)).Unit
		local hingeCF = CFrame.fromMatrix(edge, axis:Cross(Vector3.yAxis).Unit, axis)
		hinged(name, { leaf }, hingeCF, -side * 110, true) -- up and outward
		prompt(leaf, "Open", "Cellar")
	end
end

-- 6. Invisible collision: floors and steps you can walk on, walls you can't walk through. Each is
-- { size in Blender axes (x, y, z), centre in Blender coordinates, yaw in degrees }.
local function collider(size: Vector3, centre: Vector3, yaw: number?)
	local p = Instance.new("Part")
	p.Name = "Collision"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, true, true, false
	p.Transparency = 1
	p.Size = Vector3.new(size.X, size.Z, size.Y)
	p.CFrame = rot * CFrame.Angles(0, math.rad(yaw or 0), 0) + at(centre.X, centre.Y, centre.Z).Position
	p.Parent = imported
end
collider(Vector3.new(30, 24, EAVE), Vector3.new(0, 12, EAVE / 2)) -- main block
collider(Vector3.new(12, 4, EAVE), Vector3.new(-9, -2, EAVE / 2)) -- bay
-- Tower: four strips, one per pair of opposite faces (two squares would make a star that sticks
-- out past the walls and blocks the porch).
local side = 2 * 5.4 * math.tan(math.pi / 8) + 0.1
for k = 0, 3 do
	collider(Vector3.new(side, 10.8, 33.6), Vector3.new(10.5, -1.2, 16.8), k * 45)
end
collider(Vector3.new(19.6, 10, FOUND), Vector3.new(6.8, -5, FOUND / 2)) -- porch deck
for s = 1, 3 do
	local top = FOUND - s * FOUND / 4
	collider(Vector3.new(5.4, 1.15, top), Vector3.new(DOOR.x, -10 - (s - 0.5) * 1.15, top / 2)) -- front steps
	collider(Vector3.new(5, 1, top), Vector3.new(-8, 28 + (s - 0.5), top / 2)) -- back steps
end
collider(Vector3.new(6, 4, FOUND), Vector3.new(-8, 26, FOUND / 2)) -- back stoop
-- Porch railings and the two end posts (the gap at the steps stays open).
collider(Vector3.new(11.6, 0.5, 3.4), Vector3.new(10.4, -9.5, FOUND + 1.7))
collider(Vector3.new(0.5, 5.1, 3.4), Vector3.new(-2.6, -6.95, FOUND + 1.7))
collider(Vector3.new(0.5, 5.7, 3.4), Vector3.new(16.2, -6.65, FOUND + 1.7))
for _, x in { -2.6, 4.6 } do
	collider(Vector3.new(0.9, 0.9, 10.2), Vector3.new(x, -9.5, FOUND + 5.1))
end
collider(Vector3.new(4.8, 6, 1.2), Vector3.new(17.1, 6, 0.6)) -- storm-cellar curb

-- 7. Where a Decorated house's decorations go (HouseVisualController, Assets.Decor): garlands
-- hooked under the porch beam between the posts, and a pile of pumpkins on the lawn beside the
-- steps. Attachments on one invisible part; each one's frame faces the street.
local anchors = Instance.new("Part")
anchors.Name = "DecorAnchors"
anchors.Anchored, anchors.CanCollide, anchors.CanQuery, anchors.CanTouch = true, false, false, false
anchors.Transparency = 1
anchors.Size = Vector3.new(0.2, 0.2, 0.2)
anchors.CFrame = pivot
anchors.Parent = imported
local function anchor(name: string, x: number, y: number, z: number, yaw: number?)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = anchors
	a.WorldCFrame = rot * CFrame.Angles(0, math.rad(yaw or 0), 0) + at(x, y, z).Position
end
-- Hook points just under the beam (its underside at FOUND + 8.9), in front of the spindles.
for _, x in { -0.675, 2.675, 6.6, 10.5, 14.3 } do
	anchor("Garland", x, -9.95, FOUND + 8.85)
end
anchor("PumpkinPile", -3.6, -12.6, 0, 15)

-- 8. File it as the street template.
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local houses = assets:FindFirstChild("Houses") or Instance.new("Folder")
houses.Name = "Houses"
houses.Parent = assets
local old = houses:FindFirstChild("Victorian")
if old then
	old:Destroy()
end
imported.Name = "Victorian"
imported:SetAttribute("Style", "Victorian")
imported.Parent = houses
print("[setup_victorian] template ready at ReplicatedStorage.Assets.Houses.Victorian")
