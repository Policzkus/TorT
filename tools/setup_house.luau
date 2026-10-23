-- Studio command bar / MCP execute_luau (edit mode), after importing art/export/<style>/<Style>.fbx
-- with File > Import 3D (into Workspace). Set STYLE below. Turns the imported model into the street
-- template at ReplicatedStorage.Assets.Houses.<Style>, from its generated data
-- (ServerScriptService.Server.World.HouseData.<Style>, written by art/scripts/housekit.py): pivot
-- at the front-centre on the ground facing the street, flat looks, lights, hinged doors and the
-- knock zone, invisible collision, decoration anchors. A template already there is kept in
-- ServerStorage as <Style>_Backup. Save the place afterwards (Assets aren't in Rojo).
-- (The Victorian predates the data files and has its own tools/setup_victorian.luau.)

local STYLE = "Farmhouse" -- or "Mansard"

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- require caches modules in edit mode: require a fresh copy so a re-exported data file is read.
local source = ServerScriptService.Server.World.HouseData:FindFirstChild(STYLE)
assert(source, "no HouseData." .. STYLE .. " (is Rojo synced?)")
local copy = source:Clone()
copy.Parent = source.Parent
local data = require(copy) :: any
copy:Destroy()

local DOOR_W, DOOR_H = 4.2, 7.6
local imported = workspace:FindFirstChild(STYLE)
assert(imported and imported:IsA("Model"), "Import " .. STYLE .. ".fbx into Workspace first")
local function mesh(name: string): MeshPart?
	return imported:FindFirstChild(name, true) :: MeshPart?
end
local frontSlab = assert(mesh("FrontDoor"), "no FrontDoor mesh")

-- Scale: the door slab is 7.5 studs tall in Blender.
if math.abs(frontSlab.Size.Y - 7.5) > 0.3 then
	imported:ScaleTo(imported:GetScale() * 7.5 / frontSlab.Size.Y)
end

-- Pivot: the street is the side the door faces (its thin axis, pointing away from the house).
local centre = imported:GetBoundingBox()
local slabCF = frontSlab.CFrame
local axes = { slabCF.RightVector, slabCF.UpVector, slabCF.LookVector }
local sizes = { frontSlab.Size.X, frontSlab.Size.Y, frontSlab.Size.Z }
local thin = 1
for i = 2, 3 do
	if sizes[i] < sizes[thin] then
		thin = i
	end
end
local street = (axes[thin] * Vector3.new(1, 0, 1)).Unit
if street:Dot((slabCF.Position - centre.Position) * Vector3.new(1, 0, 1)) < 0 then
	street = -street
end
local right = street:Cross(Vector3.yAxis) -- the pivot's +X, which is Blender's -X
local slab = slabCF.Position
local groundY = slab.Y - (data.door.sill + DOOR_H / 2)
local front = Vector3.new(slab.X, groundY, slab.Z) + right * data.door.x + street * data.door.y
local pivot = CFrame.lookAt(front, front + street)
imported.WorldPivot = pivot
local rot = pivot.Rotation
local function at(p: Vector3): CFrame
	return pivot * CFrame.new(-p.X, p.Z, p.Y) -- Blender coordinates -> world
end

-- Looks for the flat (untextured) pieces.
local LOOKS: { [string]: { [string]: any } } = {
	Glass = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(40, 48, 50), Transparency = 0.7, Reflectance = 0.08 },
	LanternGlow = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 160, 80), Transparency = 0.2 },
	PumpkinGlow = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 130, 40), Transparency = 0.15 },
	Interior = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(4, 4, 5) },
	Silhouette = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(2, 2, 2) },
	Canvas = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(10, 8, 6) },
	Pale = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(150, 138, 118) },
	Iron = { Material = Enum.Material.Metal, Color = Color3.fromRGB(16, 16, 18) },
	Brass_FrontDoor = { Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 56, 30) },
	Brass_BackDoor = { Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 56, 30) },
}
local FIGURE = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(3, 3, 4) }
for _, d in imported:GetDescendants() do
	if d:IsA("MeshPart") then
		local look = LOOKS[d.Name] or (if string.sub(d.Name, 1, 7) == "Figure_" then FIGURE else nil)
		if look then
			for k, v in look do
				(d :: any)[k] = v
			end
		end
		d.Anchored = true
		d.CanCollide = false -- invisible boxes below do the colliding
		d.CanTouch = false
		d.CastShadow = d.Name ~= "Glass" and d.Name ~= "LanternGlow" and d.Name ~= "PumpkinGlow"
	end
end

-- Lights (HouseVisualController flickers "PorchLight" on Trick houses and every "PumpkinLight").
for _, l in data.lights do
	local p = Instance.new("Part")
	p.Name = l.name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.3
	p.CFrame = at(l.at)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color, light.Shadows = l.range, l.brightness, l.color, l.shadows
	light.Parent = p
	p.Parent = imported
end

-- Doors: each slab (+ its brass) becomes a hinged model (tag "Hinged"; HingeController swings
-- them, HomeownerController opens the front one). The knock zone is an invisible "Door" box.
for _, h in data.hinged do
	local slabPart = mesh(h.name)
	if slabPart then
		local m = Instance.new("Model")
		m.Name = h.kind
		local hinge = Instance.new("Part")
		hinge.Name = "Hinge"
		hinge.Anchored, hinge.CanCollide, hinge.CanQuery, hinge.CanTouch = true, false, false, false
		hinge.Transparency = 1
		hinge.Size = Vector3.one * 0.1
		hinge.CFrame = rot * CFrame.Angles(0, math.rad(h.yaw), 0) + at(h.hinge).Position
		hinge.Parent = m
		m.PrimaryPart = hinge
		slabPart.Parent = m
		local brass = mesh("Brass_" .. h.name)
		if brass then
			brass.Parent = m
		end
		if h.kind == "FrontDoor" then
			slabPart.Name = "FrontSlab"
			local knock = Instance.new("Part")
			knock.Name = "Door"
			knock.Anchored, knock.CanCollide, knock.CanTouch = true, false, false
			knock.Transparency = 1
			knock.Size = Vector3.new(DOOR_W - 0.1, DOOR_H - 0.1, 0.4)
			knock.CFrame = rot + at(Vector3.new(data.door.x, data.door.y, data.door.sill + DOOR_H / 2)).Position
			knock.Parent = m
		end
		if h.prompt then
			local p = Instance.new("ProximityPrompt")
			p.ActionText, p.ObjectText = "Open", h.prompt
			p.MaxActivationDistance = 8
			p.RequiresLineOfSight = false
			p.Parent = slabPart
		end
		m:SetAttribute("Kind", h.kind)
		m:SetAttribute("OpenAngle", h.angle)
		m:SetAttribute("Openable", h.openable)
		m:SetAttribute("Open", false)
		CollectionService:AddTag(m, "Hinged")
		m.Parent = imported
	end
end

-- Invisible collision.
for _, c in data.colliders do
	local p = Instance.new("Part")
	p.Name = "Collision"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, true, true, false
	p.Transparency = 1
	p.Size = Vector3.new(c.size.X, c.size.Z, c.size.Y)
	p.CFrame = rot * CFrame.Angles(0, math.rad(c.yaw), 0) + at(c.centre).Position
	p.Parent = imported
end

-- Where a Decorated house's decorations go (HouseVisualController, Assets.Decor).
local anchors = Instance.new("Part")
anchors.Name = "DecorAnchors"
anchors.Anchored, anchors.CanCollide, anchors.CanQuery, anchors.CanTouch = true, false, false, false
anchors.Transparency = 1
anchors.Size = Vector3.one * 0.2
anchors.CFrame = pivot
anchors.Parent = imported
for _, a in data.anchors do
	local att = Instance.new("Attachment")
	att.Name = a.name
	att.Parent = anchors
	att.WorldCFrame = rot * CFrame.Angles(0, math.rad(a.yaw), 0) + at(a.at).Position
end

-- File it as the street template, keeping any previous one.
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local houses = assets:FindFirstChild("Houses") or Instance.new("Folder")
houses.Name = "Houses"
houses.Parent = assets
local old = houses:FindFirstChild(STYLE)
if old then
	local backup = ServerStorage:FindFirstChild(STYLE .. "_Backup")
	if backup then
		backup:Destroy()
	end
	old.Name = STYLE .. "_Backup"
	old.Parent = ServerStorage
end
imported.Name = STYLE
imported:SetAttribute("Style", STYLE)
imported.Parent = houses
print(`[setup_house] {STYLE} ready at ReplicatedStorage.Assets.Houses.{STYLE}`)
