--!strict
-- Reusable world props built from parts. Each takes a `base` CFrame on the ground whose
-- -Z (LookVector) is the prop's front.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local CandyPiece = require(ReplicatedStorage.Shared.Modules.CandyPiece)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local Assets = require(script.Parent.Assets)
local Parts = require(script.Parent.Parts)

type Rng = Rng.Rng

local M = Enum.Material

local Props = {}

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Jack-o'-lantern with a glowing face. `size` = diameter.
function Props.pumpkin(parent: Instance, base: CFrame, size: number): Model
	local m = model(parent, "Pumpkin")
	local centre = base * CFrame.new(0, size * 0.4, 0)
	Parts.decor(Parts.ball(m, "Body", Vector3.new(size, size * 0.8, size), centre, "FF7A1A", M.SmoothPlastic))
	Parts.decor(Parts.pole(m, "Stem", size * 0.25, size * 0.16, base * CFrame.new(0, size * 0.75, 0), "5A3A1A", M.Wood))
	local glow = Parts.hex("FFC24A")
	for _, x in { -0.2, 0.2 } do
		Parts.decor(
			Parts.block(
				m,
				"Eye",
				Vector3.new(size * 0.17, size * 0.15, size * 0.08),
				centre * CFrame.new(size * x, size * 0.1, -size * 0.45),
				glow,
				M.Neon
			)
		)
	end
	Parts.decor(
		Parts.block(
			m,
			"Mouth",
			Vector3.new(size * 0.42, size * 0.1, size * 0.08),
			centre * CFrame.new(0, -size * 0.13, -size * 0.45),
			glow,
			M.Neon
		)
	)
	return m
end

-- Street lamp on the ground at `base`, the arm reaching towards local -X.
function Props.lamp(parent: Instance, base: CFrame): Model
	-- The Blender cast-iron lamp (art/scripts/lobby.py) once it's imported.
	local blender = Assets.find("Lobby", "Lamp")
	if blender and blender:IsA("Model") then
		local lamp = blender:Clone()
		lamp.Name = "StreetLamp"
		lamp:PivotTo(base)
		lamp.Parent = parent
		return lamp
	end
	local m = model(parent, "StreetLamp")
	local dark = Parts.hex("26242C")
	Parts.pole(m, "Pole", 14, 0.7, base, dark, M.Metal)
	Parts.decor(Parts.block(m, "Arm", Vector3.new(3.4, 0.35, 0.35), base * CFrame.new(-1.5, 13.8, 0), dark, M.Metal))
	Parts.decor(Parts.block(m, "Hood", Vector3.new(2, 0.4, 1.6), base * CFrame.new(-3, 13.7, 0), dark, M.Metal))
	local head = Parts.decor(
		Parts.block(m, "Bulb", Vector3.new(1.4, 0.5, 1.1), base * CFrame.new(-3, 13.25, 0), "FFD59A", M.Neon)
	)
	Parts.light(head, 32, 1.4, "FFC890")
	CollectionService:AddTag(head, "StreetLamp")
	return m
end

-- The glowing chest you stand next to to stash your bucket. Returns the model and its centre.
function Props.dropoff(parent: Instance, base: CFrame, id: string): (Model, Vector3)
	local m = model(parent, "CandyBox_" .. id)
	local wood, gold = Parts.hex("6B3F22"), Parts.hex("E4AE39")
	local ring = Parts.decor(
		Parts.disc(m, "Ring", Economy.STASH_RADIUS * 2, 0.15, base * CFrame.new(0, 0.02, 0), "FF8A00", M.Neon, {
			Transparency = 0.6,
		})
	)
	Parts.decor(
		Parts.disc(m, "Pad", Economy.STASH_RADIUS * 2 - 1.2, 0.17, base * CFrame.new(0, 0.02, 0), "2A1B3D", M.Slate)
	)
	local chest = Parts.block(m, "Chest", Vector3.new(6, 3.2, 4), base * CFrame.new(0, 1.6, 0), wood, M.Wood)
	Parts.block(m, "Lid", Vector3.new(6.3, 1.2, 4.3), base * CFrame.new(0, 3.8, 0), wood, M.Wood)
	for _, x in { -2.2, 2.2 } do
		Parts.decor(Parts.block(m, "Band", Vector3.new(0.45, 4.5, 4.45), base * CFrame.new(x, 2.25, 0), gold, M.Metal))
	end
	Parts.decor(Parts.block(m, "Lock", Vector3.new(0.9, 1.1, 0.3), base * CFrame.new(0, 3.1, -2.2), gold, M.Metal))
	local candyColors = { "FF3B5C", "7CFF4F", "FFD23F", "B06CFF", "3FC8FF", "FF8A00" }
	for i, color in candyColors do
		local angle = i / #candyColors * math.pi * 2
		local at = base * CFrame.new(math.cos(angle) * 1.6, 4.7 + (i % 2) * 0.4, math.sin(angle) * 1)
		Parts.candy(m, "Candy", 1 + (i % 3) * 0.25, at * CandyPiece.tumble(i), color)
	end
	Parts.light(chest, 18, 1.6, "FF9A3C")
	Parts.billboardLines(chest, "Label", {
		{ text = "🍬 CANDY BOX", height = 0.62, color = Parts.hex("FFB347") },
		{ text = "stand in the circle to stash", height = 0.38 },
	}, Vector2.new(9, 3.4), Vector3.new(0, 6.5, 0), 140)
	m:SetAttribute("Radius", Economy.STASH_RADIUS)
	CollectionService:AddTag(ring, "DropoffRing")
	return m, base.Position
end

-- Bus stop sign + bench. The prompt (tagged BusStop) opens the destination picker on the client.
function Props.busStop(parent: Instance, base: CFrame): (Model, BasePart)
	local m = model(parent, "BusStop")
	local yellow = Parts.hex("FFC21A")
	Parts.pole(m, "Pole", 9, 0.4, base, "4A4A52", M.Metal)
	local sign =
		Parts.block(m, "Sign", Vector3.new(3.2, 2.2, 0.3), base * CFrame.new(0, 8.4, 0), yellow, M.SmoothPlastic)
	Parts.sign(sign, Enum.NormalId.Front, "🚌 BUS", { color = Color3.fromHex("1A1026"), stroke = yellow })
	Parts.sign(sign, Enum.NormalId.Back, "🚌 BUS", { color = Color3.fromHex("1A1026"), stroke = yellow })
	Parts.block(m, "Bench", Vector3.new(6, 0.5, 1.8), base * CFrame.new(3.8, 1.6, 0.6), "5A3A22", M.WoodPlanks)
	Parts.block(m, "BenchBack", Vector3.new(6, 1.6, 0.3), base * CFrame.new(3.8, 2.6, 1.4), "5A3A22", M.WoodPlanks)
	for _, x in { 1.4, 6.2 } do
		Parts.decor(
			Parts.block(m, "Leg", Vector3.new(0.3, 1.4, 1.6), base * CFrame.new(x, 0.7, 0.6), "26242C", M.Metal)
		)
	end
	local prompt = Parts.prompt(sign, "Ride the bus", "Spooky School Bus", 12)
	prompt.UIOffset = Vector2.new(0, 40)
	CollectionService:AddTag(sign, "BusStop")
	return m, sign
end

-- The Spooky School Bus in the hub. `base` faces along the bus; the door is on its +X side.
function Props.bus(parent: Instance, base: CFrame): (Model, BasePart)
	local m = model(parent, "SpookySchoolBus")
	local yellow, black = Parts.hex("F5B21A"), Parts.hex("1A1A1E")
	local glass = Parts.hex("2A3A5A")
	Parts.block(m, "Body", Vector3.new(9, 7.5, 26), base * CFrame.new(0, 5.25, 0), yellow, M.SmoothPlastic)
	Parts.block(m, "Hood", Vector3.new(8.6, 4, 5), base * CFrame.new(0, 3.5, -15.5), yellow, M.SmoothPlastic)
	Parts.block(m, "Roof", Vector3.new(8.6, 0.6, 25.6), base * CFrame.new(0, 9.3, 0), yellow, M.SmoothPlastic)
	Parts.decor(
		Parts.block(m, "Stripe", Vector3.new(9.1, 0.5, 26.1), base * CFrame.new(0, 4.2, 0), black, M.SmoothPlastic)
	)
	Parts.decor(Parts.block(m, "Bumper", Vector3.new(9.2, 0.8, 0.6), base * CFrame.new(0, 1.9, -18.2), black, M.Metal))
	for i = 0, 5 do
		local z = -9 + i * 3.6
		for _, x in { -4.55, 4.55 } do
			Parts.decor(
				Parts.block(m, "Window", Vector3.new(0.12, 2.4, 2.8), base * CFrame.new(x, 6.7, z), glass, M.Glass, {
					Transparency = 0.15,
				})
			)
		end
	end
	Parts.decor(
		Parts.block(m, "Windshield", Vector3.new(7.6, 3, 0.12), base * CFrame.new(0, 6.6, -13.05), glass, M.Glass)
	)
	for _, z in { -11, 8 } do
		for _, x in { -4.5, 4.5 } do
			Parts.cylinder(m, "Wheel", 1.4, 3.4, base * CFrame.new(x, 1.7, z), black, M.SmoothPlastic)
		end
	end
	for _, x in { -3, 3 } do
		local headlight = Parts.decor(
			Parts.block(m, "Headlight", Vector3.new(1.2, 0.9, 0.2), base * CFrame.new(x, 3.6, -18.05), "FFF4C8", M.Neon)
		)
		if x > 0 then
			Parts.light(headlight, 24, 1.2, "FFF0C0")
		end
	end
	local door = Parts.block(m, "Door", Vector3.new(0.2, 5.6, 3), base * CFrame.new(4.6, 4, -10), "2A2A30", M.Glass, {
		Transparency = 0.3,
	})
	local sign =
		Parts.block(m, "Sign", Vector3.new(0.2, 1.6, 14), base * CFrame.new(4.62, 8.4, 1), black, M.SmoothPlastic)
	Parts.sign(sign, Enum.NormalId.Right, "SPOOKY SCHOOL BUS", { color = Color3.fromHex("FFC21A") })
	local prompt = Parts.prompt(door, "Ride the bus", "Spooky School Bus", 12)
	prompt.UIOffset = Vector2.new(0, 20)
	CollectionService:AddTag(door, "BusStop")
	return m, door
end

export type GateState = "open" | "locked" | "comingSoon"

-- Arch over the road at `base` (players arrive from local +Z). Locked gates get a barrier the
-- client hides once you own the street, plus an Unlock prompt (handled by NeighborhoodService).
function Props.gate(
	parent: Instance,
	base: CFrame,
	width: number,
	fenceWidth: number,
	neighborhood: { id: string, name: string, unlock: { price: number, rebirths: number }, colors: any },
	state: GateState
): Model
	local m = model(parent, "Gate_" .. neighborhood.id)
	m:SetAttribute("Neighborhood", neighborhood.id)
	local stone, accent = Parts.hex("3A3644"), Parts.hex(neighborhood.colors.accent)
	local half = width / 2 + 1.75
	for _, x in { -half, half } do
		Parts.block(m, "Pillar", Vector3.new(3.5, 20, 3.5), base * CFrame.new(x, 10, 0), stone, M.Slate)
		Parts.decor(Parts.ball(m, "Cap", Vector3.one * 3.2, base * CFrame.new(x, 21.2, 0), accent, M.Neon))
		Parts.decor(
			Parts.block(
				m,
				"Trim",
				Vector3.new(0.4, 18, 0.4),
				base * CFrame.new(x - math.sign(x) * 1.9, 9, -1.9),
				accent,
				M.Neon
			)
		)
		Parts.decor(
			Parts.block(
				m,
				"Trim",
				Vector3.new(0.4, 18, 0.4),
				base * CFrame.new(x - math.sign(x) * 1.9, 9, 1.9),
				accent,
				M.Neon
			)
		)
	end
	local beam = Parts.block(m, "Beam", Vector3.new(width + 8, 3.6, 2.6), base * CFrame.new(0, 19, 0), stone, M.Slate)
	Parts.decor(
		Parts.block(m, "BeamTrim", Vector3.new(width + 1, 0.4, 2.7), base * CFrame.new(0, 17.1, 0), accent, M.Neon)
	)
	local title = string.upper(neighborhood.name)
	Parts.sign(beam, Enum.NormalId.Back, title, { color = accent })
	Parts.sign(beam, Enum.NormalId.Front, title, { color = accent })
	Parts.light(beam, 36, 2, accent)

	-- Hedges from the pillars to the edge of the ground, so you can't walk around the gate.
	local hedgeLength = fenceWidth / 2 - half - 1.75
	if hedgeLength > 0 then
		for _, side in { -1, 1 } do
			Parts.block(
				m,
				"Hedge",
				Vector3.new(hedgeLength, 9, 3),
				base * CFrame.new(side * (half + 1.75 + hedgeLength / 2), 4.5, 0),
				"1E3A22",
				M.LeafyGrass
			)
		end
	end

	if state ~= "open" then
		local barrier = Parts.block(
			m,
			"Barrier",
			Vector3.new(width + 0.2, 17, 0.6),
			base * CFrame.new(0, 8.5, 0),
			accent,
			M.Neon,
			{ CastShadow = false, CanQuery = false, Transparency = 0.82 }
		)
		barrier:SetAttribute("Neighborhood", neighborhood.id)
		CollectionService:AddTag(barrier, "GateBarrier")
		local lines: { Parts.Line }
		if state == "comingSoon" then
			lines = {
				{ text = title, height = 0.5, color = accent },
				{ text = "🚧 COMING SOON 🚧", height = 0.35 },
			}
		else
			lines = {
				{ text = "🔒 " .. title, height = 0.42, color = accent },
				{
					text = `{Format.number(neighborhood.unlock.price)} 🍬`,
					height = 0.36,
					color = Parts.hex("FFD23F"),
				},
			}
			if neighborhood.unlock.rebirths > 0 then
				table.insert(lines, { text = `needs Rebirth {neighborhood.unlock.rebirths}`, height = 0.22 })
			end
		end
		local board = Parts.billboardLines(beam, "GateInfo", lines, Vector2.new(22, 8), Vector3.new(0, 8, 0), 400)
		board:SetAttribute("Neighborhood", neighborhood.id)
		CollectionService:AddTag(board, "GateInfo")
		if state == "locked" then
			local prompt = Parts.prompt(
				barrier,
				"Unlock",
				`{neighborhood.name} ({Format.number(neighborhood.unlock.price)} 🍬)`,
				16,
				0.4
			)
			prompt:SetAttribute("Neighborhood", neighborhood.id)
			CollectionService:AddTag(prompt, "GatePrompt")
		end
	end
	return m
end

export type TreeKind = "autumn" | "dead" | "pine"

function Props.tree(parent: Instance, base: CFrame, rng: Rng, kind: TreeKind): Model
	-- The Blender dead trees from the yard set (art/scripts/yard.py) when they've been imported:
	-- either shape, turned and sized at random, with an invisible trunk to bump into.
	local blender = if kind ~= "pine" then Assets.find("Yard", if rng:chance(0.5) then "Tree" else "Tree2") else nil
	if blender and blender:IsA("PVInstance") then
		local m = model(parent, "Tree")
		local tree = blender:Clone()
		tree.Parent = m
		m.WorldPivot = tree:GetPivot()
		m:PivotTo(base * CFrame.Angles(0, rng:range(0, math.pi * 2), 0))
		m:ScaleTo(rng:range(0.85, 1.3))
		Parts.block(m, "Trunk", Vector3.new(2, 8, 2), base * CFrame.new(0, 4, 0), "3A3036", M.Wood, {
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		return m
	end
	local m = model(parent, "Tree")
	local height = rng:range(9, 14)
	local trunkColor = if kind == "dead" then "3A3036" else "4A3020"
	Parts.pole(m, "Trunk", height, rng:range(1.1, 1.6), base, trunkColor, M.Wood)
	if kind == "dead" then
		for i = 1, 3 do
			local angle = rng:range(0, math.pi * 2)
			local branch = base
				* CFrame.new(0, height * rng:range(0.55, 0.9), 0)
				* CFrame.Angles(0, angle, math.rad(rng:range(35, 60)))
				* CFrame.new(0, 2, 0)
			Parts.decor(Parts.block(m, "Branch" .. i, Vector3.new(0.5, 4.5, 0.5), branch, trunkColor, M.Wood))
		end
	elseif kind == "pine" then
		for i = 0, 2 do
			Parts.decor(
				Parts.wedge(
					m,
					"Needles",
					Vector3.new(7 - i * 1.8, 5, 3.5 - i * 0.9),
					base * CFrame.new(0, height * 0.45 + i * 3, 0),
					"1E3A26",
					M.Grass
				)
			)
		end
	else
		local leafColors = { "D2691E", "B5341E", "E8A33A", "A0522D" }
		for _ = 1, 3 do
			Parts.decor(
				Parts.ball(
					m,
					"Leaves",
					Vector3.one * rng:range(5.5, 8),
					base * CFrame.new(rng:range(-1.8, 1.8), height + rng:range(-1, 1.5), rng:range(-1.8, 1.8)),
					rng:pick(leafColors),
					M.Grass
				)
			)
		end
	end
	return m
end

function Props.mailbox(parent: Instance, base: CFrame, color: string)
	local m = model(parent, "Mailbox")
	Parts.decor(Parts.block(m, "Post", Vector3.new(0.4, 3.6, 0.4), base * CFrame.new(0, 1.8, 0), "5A4632", M.Wood))
	Parts.decor(Parts.block(m, "Box", Vector3.new(1, 1, 1.8), base * CFrame.new(0, 3.9, 0), color, M.Metal))
	Parts.decor(
		Parts.block(m, "Flag", Vector3.new(0.1, 0.8, 0.3), base * CFrame.new(0.55, 4.3, 0.4), "E23A3A", M.SmoothPlastic)
	)
end

function Props.gravestone(parent: Instance, base: CFrame, rng: Rng)
	local m = model(parent, "Gravestone")
	local stone = rng:pick({ "6A6A72", "5A5A62", "7A7680" })
	Parts.decor(Parts.block(m, "Stone", Vector3.new(2.4, 2.6, 0.6), base * CFrame.new(0, 1.3, 0), stone, M.Slate))
	Parts.decor(
		Parts.cylinder(
			m,
			"Top",
			0.6,
			2.4,
			base * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.rad(90), 0),
			stone,
			M.Slate
		)
	)
	Parts.decor(Parts.block(m, "Dirt", Vector3.new(2.6, 0.3, 4), base * CFrame.new(0, 0.15, -2.2), "3A2A1E", M.Ground))
end

function Props.flamingo(parent: Instance, base: CFrame)
	local m = model(parent, "Flamingo")
	local pink = Parts.hex("FF6FA8")
	Parts.decor(Parts.block(m, "Leg", Vector3.new(0.15, 2, 0.15), base * CFrame.new(0, 1, 0), "3A3A3A", M.Metal))
	Parts.decor(Parts.ball(m, "Body", Vector3.new(0.9, 0.8, 1.6), base * CFrame.new(0, 2.3, 0), pink, M.SmoothPlastic))
	Parts.decor(
		Parts.block(m, "Neck", Vector3.new(0.2, 1.3, 0.2), base * CFrame.new(0, 3.1, -0.6), pink, M.SmoothPlastic)
	)
	Parts.decor(Parts.ball(m, "Head", Vector3.one * 0.5, base * CFrame.new(0, 3.8, -0.7), pink, M.SmoothPlastic))
end

function Props.trashCan(parent: Instance, base: CFrame)
	local m = model(parent, "TrashCan")
	Parts.pole(m, "Can", 3, 2.2, base, "5E6268", M.Metal)
	Parts.decor(Parts.disc(m, "Lid", 2.5, 0.25, base * CFrame.new(0, 3, 0), "4E5258", M.Metal))
end

function Props.hayBale(parent: Instance, base: CFrame)
	Parts.block(parent, "HayBale", Vector3.new(4, 2.2, 2.4), base * CFrame.new(0, 1.1, 0), "C9A24A", M.Fabric)
end

export type FenceStyle = "chain" | "picket"

-- A fence along the ground from `a` to `b` (world positions at ground height).
function Props.fence(parent: Instance, a: Vector3, b: Vector3, style: FenceStyle)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	if length < 1 then
		return
	end
	local frame = CFrame.lookAt(a, a + flat) -- local -Z runs from a to b
	local m = model(parent, "Fence")
	if style == "chain" then
		local height = 3.6
		Parts.block(
			m,
			"Mesh",
			Vector3.new(0.12, height, length),
			frame * CFrame.new(0, height / 2, -length / 2),
			"8A8E94",
			M.DiamondPlate,
			{
				Transparency = 0.55,
				CastShadow = false,
			}
		)
		Parts.decor(
			Parts.block(
				m,
				"Rail",
				Vector3.new(0.2, 0.2, length),
				frame * CFrame.new(0, height, -length / 2),
				"6E7278",
				M.Metal
			)
		)
		local posts = math.max(1, math.floor(length / 8))
		for i = 0, posts do
			Parts.decor(
				Parts.block(
					m,
					"Post",
					Vector3.new(0.3, height + 0.3, 0.3),
					frame * CFrame.new(0, (height + 0.3) / 2, -length * i / posts),
					"6E7278",
					M.Metal
				)
			)
		end
	else
		local height = 3
		local white = Parts.hex("F2EEE6")
		for _, y in { 1, 2.2 } do
			Parts.block(
				m,
				"Rail",
				Vector3.new(0.2, 0.35, length),
				frame * CFrame.new(0, y, -length / 2),
				white,
				M.WoodPlanks
			)
		end
		local pickets = math.max(1, math.floor(length / 1.6))
		for i = 0, pickets do
			Parts.decor(
				Parts.block(
					m,
					"Picket",
					Vector3.new(0.25, height, 0.7),
					frame * CFrame.new(0, height / 2, -length * i / pickets),
					white,
					M.WoodPlanks
				)
			)
		end
	end
end

return Props
