--!strict
-- Procedural bucket models, one per tier (Config/Upgrades → bucketTier.tiers[n].model; for now every
-- tier carries the PlasticPumpkin).
-- Each model has an invisible "Handle" at the mount point and candy pieces "Candy1".."CandyN"
-- that BucketService shows as the bucket fills. Attribute "Mount" says where it attaches:
--   hand  - hangs from the right hand (handle top at the origin)
--   back  - worn on the back (origin = centre of the side touching the character)
--   tow   - dragged on the ground behind (origin = ground point under the front)
--   float - hovers behind the character (origin like tow)
-- A spec with `mesh` uses that AI-generated mesh (Config/Meshes via MeshLibrary) and falls back
-- to its part-built `parts` if the mesh didn't load.
-- Swap-in: ReplicatedStorage.Assets.Buckets.<ModelName> is used instead if it exists (it needs a
-- part named Handle; Candy1..N parts are optional).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CandyPiece = require(script.Parent.Parent.Modules.CandyPiece)
local MeshLibrary = require(script.Parent.Parent.Modules.MeshLibrary)

type PartSpec = {
	name: string,
	shape: ("block" | "ball" | "cylinder" | "wedge")?,
	size: Vector3,
	at: CFrame,
	color: string,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	light: { range: number, brightness: number, color: string }?,
}

-- A real mesh in place of `parts`, with its own candy slots (no `scale` applied).
type MeshSpec = {
	name: string, -- Config/Meshes key
	at: CFrame,
	candy: { CFrame },
	candySize: number,
}

type ModelSpec = {
	mount: "hand" | "back" | "tow" | "float",
	mesh: MeshSpec?,
	scale: number?, -- multiplies every size and offset (hand-held buckets must stay small)
	parts: { PartSpec },
	candy: { CFrame }, -- where candy pieces appear, filled in order
	candySize: number,
}

local M = Enum.Material

local CANDY_COLORS = { "FF3B5C", "FFD23F", "7CFF4F", "B06CFF", "3FC8FF", "FF8A00", "FF6FA8", "FFFFFF" }

local function c(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function ring(count: number, radius: number, y: number, z: number?): { CFrame }
	local list = {}
	for i = 1, count do
		local angle = i / count * math.pi * 2
		table.insert(list, c(math.cos(angle) * radius, y + (i % 2) * 0.15, (z or 0) + math.sin(angle) * radius))
	end
	return list
end

local SPECS: { [string]: ModelSpec } = {
	PaperBag = {
		mount = "hand",
		scale = 0.8,
		candySize = 0.32,
		parts = {
			{
				name = "Bag",
				size = Vector3.new(1.2, 1.5, 0.85),
				at = c(0, -0.95, 0),
				color = "B48A58",
				material = M.Cardboard,
			},
			{
				name = "Fold",
				size = Vector3.new(1.24, 0.18, 0.89),
				at = c(0, -0.25, 0),
				color = "9A7448",
				material = M.Cardboard,
			},
		},
		candy = { c(-0.25, -0.15, 0), c(0.25, -0.12, 0.1), c(0, -0.05, -0.15), c(0.2, 0.02, -0.1) },
	},
	PlasticPumpkin = {
		mount = "hand",
		mesh = {
			name = "PlasticPumpkin",
			at = c(0, -0.62, 0), -- handle top at the origin, carved face towards -Z
			candy = ring(6, 0.24, -0.45),
			candySize = 0.26,
		},
		scale = 0.62,
		candySize = 0.36,
		parts = {
			{ name = "Body", shape = "ball", size = Vector3.new(1.9, 1.6, 1.9), at = c(0, -1.55, 0), color = "FF7A1A" },
			{ name = "EyeL", size = Vector3.new(0.35, 0.3, 0.1), at = c(-0.38, -1.4, -0.9), color = "1A1A1E" },
			{ name = "EyeR", size = Vector3.new(0.35, 0.3, 0.1), at = c(0.38, -1.4, -0.9), color = "1A1A1E" },
			{ name = "Mouth", size = Vector3.new(0.9, 0.18, 0.1), at = c(0, -1.85, -0.88), color = "1A1A1E" },
			{ name = "HandleL", size = Vector3.new(0.1, 0.9, 0.1), at = c(-0.75, -0.45, 0), color = "1A1A1E" },
			{ name = "HandleR", size = Vector3.new(0.1, 0.9, 0.1), at = c(0.75, -0.45, 0), color = "1A1A1E" },
			{ name = "HandleTop", size = Vector3.new(1.6, 0.1, 0.1), at = c(0, 0, 0), color = "1A1A1E" },
		},
		candy = ring(6, 0.45, -0.8),
	},
	Pillowcase = {
		mount = "back",
		candySize = 0.4,
		parts = {
			{
				name = "Sack",
				shape = "ball",
				size = Vector3.new(1.8, 2.6, 1.4),
				at = c(0.3, 0.1, 0.75),
				color = "DCE6F2",
				material = M.Fabric,
			},
			{
				name = "Neck",
				size = Vector3.new(0.9, 0.5, 0.8),
				at = c(0.3, 1.45, 0.75),
				color = "C8D4E4",
				material = M.Fabric,
			},
			{
				name = "Stripe",
				size = Vector3.new(1.82, 0.2, 1.42),
				at = c(0.3, 0.5, 0.75),
				color = "6E8ACB",
				material = M.Fabric,
			},
		},
		candy = ring(6, 0.32, 1.75, 0.75),
	},
	TrickSack = {
		mount = "back",
		candySize = 0.45,
		parts = {
			{
				name = "Sack",
				shape = "ball",
				size = Vector3.new(2.4, 3, 2),
				at = c(0, 0.2, 1.05),
				color = "5A2E8A",
				material = M.Fabric,
			},
			{
				name = "Rope",
				size = Vector3.new(1.2, 0.35, 1),
				at = c(0, 1.75, 1.05),
				color = "FF8A00",
				material = M.Fabric,
			},
			{
				name = "Patch",
				size = Vector3.new(0.8, 0.6, 0.1),
				at = c(0, 0.2, 2.05),
				color = "1A1A1E",
				material = M.Fabric,
			},
		},
		candy = ring(8, 0.42, 2.05, 1.05),
	},
	TrashBag = {
		mount = "back",
		candySize = 0.5,
		parts = {
			{
				name = "Bag",
				shape = "ball",
				size = Vector3.new(2.8, 3.4, 2.2),
				at = c(0, 0, 1.1),
				color = "1A1A1E",
				reflectance = 0.25,
			},
			{ name = "Tie", size = Vector3.new(0.6, 0.6, 0.6), at = c(0, 1.8, 1.1), color = "FFD23F" },
		},
		candy = ring(8, 0.6, 1.65, 1.1),
	},
	LaundryBasket = {
		mount = "back",
		candySize = 0.55,
		parts = {
			{
				name = "Basket",
				size = Vector3.new(3.2, 2.2, 2.2),
				at = c(0, -0.2, 1.1),
				color = "C8A060",
				material = M.WoodPlanks,
			},
			{
				name = "Rim",
				size = Vector3.new(3.4, 0.3, 2.4),
				at = c(0, 0.95, 1.1),
				color = "A07840",
				material = M.Wood,
			},
		},
		candy = ring(10, 0.8, 1.15, 1.1),
	},
	Wheelbarrow = {
		mount = "tow",
		candySize = 0.65,
		parts = {
			{ name = "Tray", size = Vector3.new(3, 1.4, 4), at = c(0, 2, 3), color = "3E7A3A", material = M.Metal },
			{
				name = "Wheel",
				shape = "cylinder",
				size = Vector3.new(0.5, 1.6, 1.6),
				at = c(0, 0.8, 5.2),
				color = "1A1A1E",
			},
			{
				name = "HandleL",
				size = Vector3.new(0.2, 0.2, 2.4),
				at = c(-1, 2.3, 0.6),
				color = "6A4A2E",
				material = M.Wood,
			},
			{
				name = "HandleR",
				size = Vector3.new(0.2, 0.2, 2.4),
				at = c(1, 2.3, 0.6),
				color = "6A4A2E",
				material = M.Wood,
			},
		},
		candy = ring(10, 0.9, 2.85, 3),
	},
	Wagon = {
		mount = "tow",
		candySize = 0.7,
		parts = {
			{
				name = "Bed",
				size = Vector3.new(3.2, 1.4, 5),
				at = c(0, 1.6, 3.8),
				color = "C8262E",
				material = M.Metal,
			},
			{
				name = "Wheel1",
				shape = "cylinder",
				size = Vector3.new(0.4, 1.2, 1.2),
				at = c(-1.7, 0.6, 2),
				color = "1A1A1E",
			},
			{
				name = "Wheel2",
				shape = "cylinder",
				size = Vector3.new(0.4, 1.2, 1.2),
				at = c(1.7, 0.6, 2),
				color = "1A1A1E",
			},
			{
				name = "Wheel3",
				shape = "cylinder",
				size = Vector3.new(0.4, 1.2, 1.2),
				at = c(-1.7, 0.6, 5.6),
				color = "1A1A1E",
			},
			{
				name = "Wheel4",
				shape = "cylinder",
				size = Vector3.new(0.4, 1.2, 1.2),
				at = c(1.7, 0.6, 5.6),
				color = "1A1A1E",
			},
			{
				name = "Bar",
				size = Vector3.new(0.2, 0.2, 2.4),
				at = c(0, 2, 0.4),
				color = "1A1A1E",
				material = M.Metal,
			},
		},
		candy = ring(12, 1.1, 2.5, 3.8),
	},
	Coffin = {
		mount = "back",
		candySize = 0.6,
		parts = {
			{ name = "Box", size = Vector3.new(2.4, 5, 1.1), at = c(0, 0, 0.6), color = "3A2418", material = M.Wood },
			{
				name = "Lid",
				size = Vector3.new(2.6, 0.3, 1.3),
				at = c(0, 2.65, 0.6),
				color = "2A1A10",
				material = M.Wood,
			},
			{
				name = "Bat",
				size = Vector3.new(1.4, 0.5, 0.1),
				at = c(0, 0.6, 1.2),
				color = "8A6BFF",
				material = M.Neon,
			},
		},
		candy = ring(10, 0.7, 2.95, 0.6),
	},
	Cauldron = {
		mount = "float",
		candySize = 0.7,
		parts = {
			{
				name = "Pot",
				shape = "ball",
				size = Vector3.new(3.6, 3, 3.6),
				at = c(0, 3.5, 3.5),
				color = "1E1E24",
				material = M.Metal,
			},
			{
				name = "Brew",
				shape = "cylinder",
				size = Vector3.new(0.2, 2.8, 2.8),
				at = c(0, 4.9, 3.5) * CFrame.Angles(0, 0, math.rad(90)),
				color = "7CFF4F",
				material = M.Neon,
				light = { range = 14, brightness = 1.5, color = "7CFF4F" },
			},
		},
		candy = ring(10, 0.9, 5.15, 3.5),
	},
	Wardrobe = {
		mount = "back",
		candySize = 0.7,
		parts = {
			{
				name = "Cabinet",
				size = Vector3.new(3, 5.2, 1.6),
				at = c(0, 0.4, 0.85),
				color = "3A1E4A",
				material = M.WoodPlanks,
			},
			{ name = "Gap", size = Vector3.new(0.1, 4.6, 0.1), at = c(0, 0.4, 1.68), color = "1A0A1A" },
			{
				name = "Eyes",
				size = Vector3.new(0.6, 0.15, 0.1),
				at = c(0, 1.6, 1.7),
				color = "FF2A3A",
				material = M.Neon,
			},
			{
				name = "Crown",
				size = Vector3.new(3.3, 0.4, 1.8),
				at = c(0, 3.2, 0.85),
				color = "2A1236",
				material = M.Wood,
			},
		},
		candy = ring(10, 0.9, 3.55, 0.85),
	},
	BlackHole = {
		mount = "float",
		candySize = 0.6,
		parts = {
			{ name = "Core", shape = "ball", size = Vector3.one * 3, at = c(0, 4, 3.5), color = "050508" },
			{
				name = "Disk",
				shape = "cylinder",
				size = Vector3.new(0.15, 5.4, 5.4),
				at = c(0, 4, 3.5) * CFrame.Angles(0, 0, math.rad(90)),
				color = "8A3AFF",
				material = M.Neon,
				transparency = 0.3,
				light = { range = 20, brightness = 2, color = "8A3AFF" },
			},
		},
		candy = ring(12, 2.2, 4.2, 3.5),
	},
}

local Buckets = {}

function Buckets.mount(modelName: string): string
	local spec = SPECS[modelName]
	return if spec then spec.mount else "hand"
end

local function finish(part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- Builds the bucket at the origin (unparented). Every part is welded to Handle.
function Buckets.build(modelName: string): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Buckets")
	local custom = folder and folder:FindFirstChild(modelName)
	if custom and custom:IsA("Model") and custom:FindFirstChild("Handle") then
		local clone = custom:Clone()
		clone:SetAttribute("Mount", clone:GetAttribute("Mount") or Buckets.mount(modelName))
		clone.PrimaryPart = clone:FindFirstChild("Handle") :: BasePart
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				finish(descendant) -- a swapped-in model must never collide or weigh anything
			end
		end
		return clone
	end

	local spec = SPECS[modelName] or SPECS.PaperBag
	local k = spec.scale or 1
	local function scaled(at: CFrame): CFrame
		return at.Rotation + at.Position * k
	end
	local model = Instance.new("Model")
	model.Name = "Bucket"
	model:SetAttribute("Mount", spec.mount)
	model:SetAttribute("Tier", modelName)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CFrame = CFrame.new()
	finish(handle)
	handle.Parent = model
	model.PrimaryPart = handle

	local function weld(part: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = part
		w.Parent = part
	end

	local meshSpec = spec.mesh
	local meshPart = if meshSpec then MeshLibrary.get(meshSpec.name) else nil
	local candySlots, candySize = spec.candy, spec.candySize * k
	if meshPart and meshSpec then
		meshPart.Name = "Body"
		meshPart.CFrame = meshSpec.at
		finish(meshPart)
		weld(meshPart)
		meshPart.Parent = model
		k = 1
		candySlots, candySize = meshSpec.candy, meshSpec.candySize
	end

	for _, partSpec in if meshPart then {} else spec.parts do
		local className = if partSpec.shape == "wedge" then "WedgePart" else "Part"
		local part = Instance.new(className) :: BasePart
		part.Name = partSpec.name
		part.Size = partSpec.size * k
		part.CFrame = scaled(partSpec.at)
		part.Color = Color3.fromHex(partSpec.color)
		part.Material = partSpec.material or M.SmoothPlastic
		part.Transparency = partSpec.transparency or 0
		part.Reflectance = partSpec.reflectance or 0
		if partSpec.shape == "ball" then
			(part :: Part).Shape = Enum.PartType.Ball
		elseif partSpec.shape == "cylinder" then
			(part :: Part).Shape = Enum.PartType.Cylinder
		end
		finish(part)
		if partSpec.light then
			local light = Instance.new("PointLight")
			light.Range = partSpec.light.range
			light.Brightness = partSpec.light.brightness
			light.Color = Color3.fromHex(partSpec.light.color)
			light.Parent = part
		end
		weld(part)
		part.Parent = model
	end

	for index, at in candySlots do
		local candy = CandyPiece.make(candySize, Color3.fromHex(CANDY_COLORS[(index - 1) % #CANDY_COLORS + 1]))
		candy.Name = "Candy" .. index
		candy.CFrame = scaled(at) * CandyPiece.tumble(index) -- a jumble of bars
		candy.Transparency = 1
		finish(candy)
		weld(candy)
		candy.Parent = model
	end
	model:SetAttribute("CandySlots", #candySlots)
	return model
end

-- Shows the first ceil(fill × slots) candy pieces. `fill` is 0..1.
function Buckets.setFill(model: Model, fill: number)
	local slots = (model:GetAttribute("CandySlots") :: number?) or 0
	local visible = if fill <= 0 then 0 else math.ceil(math.clamp(fill, 0, 1) * slots)
	for index = 1, slots do
		local candy = model:FindFirstChild("Candy" .. index) :: BasePart?
		if candy then
			candy.Transparency = if index <= visible then 0 else 1
		end
	end
end

return Buckets
