--!strict
-- A run-down Victorian house, modelled piece by piece (PROMPT §V2: houses must feel eerie, not like a
-- toy or a 3D scan). Two storeys plus attic over a stone foundation, built to the kids' scale (doors
-- 7.6 studs, storeys 11.5): an octagonal corner tower with a witch-hat roof, a projecting front bay
-- with a steep gable and a lit attic window with someone standing in it, and a wraparound porch with
-- turned posts, a sagging roof, a broken railing and a porch swing hanging from one chain.
-- Walls are cut around every door and window, so windows are recessed with dark rooms behind them.
-- Hinged doors (tag "Hinged"; HingeController swings them, HingeService handles the prompts):
-- the front door (opened by the homeowner, onto a dark hallway), a back door, storm-cellar doors and
-- the yard gate (players can open these), and loose shutters that knock in the wind.
-- `base` is the ground point at the front-centre of the lot; local -Z faces the street.
-- Custom MaterialVariants (TorT_*) are used where they exist and fall back to the base material.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local BlenderLot = require(script.Parent.Parent.BlenderLot)
local HouseData = require(script.Parent.Parent.HouseData.Types)
local VictorianRooms = require(script.Parent.Parent.HouseData.VictorianRooms)
local Parts = require(script.Parent.Parent.Parts)
local Props = require(script.Parent.Parent.Props)

local M = Enum.Material

local Victorian = {}

-- Proportions ------------------------------------------------------------------------------------
local FOUND = 2.6 -- foundation / porch deck height
local STORY = 11.5
local EAVE = FOUND + 2 * STORY -- 25.6
local T = 1 -- wall thickness
local MAIN = { x0 = -15, x1 = 15, z0 = 0, z1 = 24 }
local RIDGE_Z = 12
local RIDGE_Y = EAVE + 11
local BAY = { x0 = -15, x1 = -3, z = -4 } -- projecting front bay with its own gable
local BAY_RIDGE_Y = EAVE + 10.5
local TOWER = { x = 10.5, z = -1.2, apothem = 5.4, eave = EAVE + 8, roof = 15 }
local PORCH = { x0 = -3, x1 = 16.6, z = -10 }
local DOOR = { x = 1.5, width = 4.2, height = 7.6 }

-- Looks: { base material, MaterialVariant name, colour }
type Look = { material: Enum.Material, variant: string?, color: string }
local LOOKS: { [string]: Look } = {
	siding = { material = M.WoodPlanks, variant = "TorT_Siding", color = "A3AA9C" },
	trim = { material = M.Wood, variant = "TorT_Trim1", color = "D2CCBD" },
	roof = { material = M.RoofShingles, variant = "TorT_Shingles3", color = "8E9096" },
	scales = { material = M.Slate, variant = "TorT_FishScale1", color = "A89A98" },
	deck = { material = M.WoodPlanks, variant = "TorT_PorchBoards2", color = "A89684" },
	stone = { material = M.Cobblestone, variant = "TorT_Foundation3", color = "AEA9A0" },
	brick = { material = M.Brick, variant = "TorT_Brick3", color = "BCA49A" },
	boards = { material = M.Wood, variant = "TorT_Boards", color = "8A8274" },
	door = { material = M.Wood, variant = "TorT_DoorWood", color = "4A1E1C" },
	wallpaper = { material = M.Fabric, variant = "TorT_Wallpaper", color = "4C4436" },
	lawn = { material = M.Grass, variant = "TorT_DeadGrass", color = "6B6448" },
	iron = { material = M.Metal, variant = nil, color = "1E1E22" },
	glass = { material = M.Glass, variant = nil, color = "26302E" },
	dark = { material = M.SmoothPlastic, variant = nil, color = "060607" },
	shutter = { material = M.WoodPlanks, variant = nil, color = "2B3329" },
	fabric = { material = M.Fabric, variant = nil, color = "6A5E58" },
	brass = { material = M.Metal, variant = nil, color = "6E5E3A" },
}

-- Each house rolls its own faded paint.
local SIDING_TINTS = { "A3AA9C", "9CA3AC", "AA9F98", "A6A08E", "B0AAA0", "8F9A94" }
local SCALE_TINTS = { "A89A98", "9A9EA8", "A49A88", "8E8A86" }
local DOOR_TINTS = { "4A1E1C", "1E2A22", "2A2420", "3A2A3A", "1C2230" }
local SHUTTER_TINTS = { "2B3329", "2A2C33", "3A2A26", "26262A" }

type Builder = {
	house: Model,
	base: CFrame,
	rng: Rng.Rng,
	looks: { [string]: Look },
	part: (self: Builder, name: string, size: Vector3, cf: CFrame, look: string, parent: Instance?) -> BasePart,
	decor: (self: Builder, name: string, size: Vector3, cf: CFrame, look: string, parent: Instance?) -> BasePart,
}

local function apply(part: BasePart, look: Look)
	part.Material = look.material
	if look.variant then
		part.MaterialVariant = look.variant
	end
	part.Color = Parts.hex(look.color)
end

local function newBuilder(house: Model, base: CFrame, rng: Rng.Rng): Builder
	local looks = table.clone(LOOKS)
	local function tint(key: string, hex: string)
		local look = table.clone(looks[key])
		look.color = hex
		looks[key] = look
	end
	tint("siding", rng:pick(SIDING_TINTS))
	tint("scales", rng:pick(SCALE_TINTS))
	tint("door", rng:pick(DOOR_TINTS))
	tint("shutter", rng:pick(SHUTTER_TINTS))
	local b = { house = house, base = base, rng = rng, looks = looks } :: any
	function b.part(self: Builder, name: string, size: Vector3, cf: CFrame, look: string, parent: Instance?): BasePart
		local p = Parts.block(parent or self.house, name, size, cf, "FFFFFF", M.SmoothPlastic)
		apply(p, self.looks[look])
		return p
	end
	function b.decor(self: Builder, name: string, size: Vector3, cf: CFrame, look: string, parent: Instance?): BasePart
		return Parts.decor(self:part(name, size, cf, look, parent))
	end
	return b
end

-- Any triangle in space, as two wedges (a, b, c are world points; the slab is `thickness` thick).
local function triangle(b: Builder, name: string, a: Vector3, p1: Vector3, p2: Vector3, thickness: number, look: string)
	local pa, pb, pc = a, p1, p2
	local ab, ac, bc = pb - pa, pc - pa, pc - pb
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		pc, pa = pa, pc
	elseif acd > bcd and acd > abd then
		pa, pb = pb, pa
	end
	ab, ac, bc = pb - pa, pc - pa, pc - pb
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for i, spec in { { ab, pb, 1 }, { ac, pc, -1 } } do
		local edge, point, sign = spec[1] :: Vector3, spec[2] :: Vector3, spec[3] :: number
		local depth = math.abs(edge:Dot(back))
		if height > 0.01 and depth > 0.01 then
			local w = Parts.wedge(
				b.house,
				name .. i,
				Vector3.new(thickness, height, depth),
				CFrame.fromMatrix((pa + point) / 2, right * sign, up, back * sign),
				"FFFFFF",
				M.SmoothPlastic
			)
			apply(w, b.looks[look])
		end
	end
end

-- A slab between two edge midlines: from `lowA`..`lowB` (eave) up to `highA`..`highB` (ridge).
local function slab(
	b: Builder,
	name: string,
	low: Vector3,
	high: Vector3,
	width: number,
	thickness: number,
	look: string
)
	local mid = (low + high) / 2
	local up = (high - low)
	local along = Vector3.new(0, 1, 0):Cross(up).Unit -- horizontal, along the eave
	local normal = up.Unit:Cross(along)
	if normal.Y < 0 then
		normal = -normal
		along = -along
	end
	local cf = CFrame.fromMatrix(mid + normal * thickness / 2, along, normal)
	return b:part(name, Vector3.new(width, thickness, up.Magnitude), cf, look)
end

-- Walls with holes ---------------------------------------------------------------------------------
-- `frame` sits at the bottom centre of the wall's outer face, local -Z pointing out of the house.
-- Openings are { x (centre), y (bottom), w, h } in that frame.
type Opening = { x: number, y: number, w: number, h: number }

local function wall(b: Builder, name: string, frame: CFrame, width: number, height: number, openings: { Opening })
	local cuts = { -width / 2, width / 2 }
	for _, o in openings do
		table.insert(cuts, o.x - o.w / 2)
		table.insert(cuts, o.x + o.w / 2)
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local x0, x1 = cuts[i], cuts[i + 1]
		if x1 - x0 > 0.01 then
			local spans = { { 0, height } }
			for _, o in openings do
				if o.x - o.w / 2 < x1 - 0.01 and o.x + o.w / 2 > x0 + 0.01 then
					local nextSpans = {}
					for _, s in spans do
						local y0, y1 = s[1], s[2]
						if o.y > y0 then
							table.insert(nextSpans, { y0, math.min(y1, o.y) })
						end
						if o.y + o.h < y1 then
							table.insert(nextSpans, { math.max(y0, o.y + o.h), y1 })
						end
					end
					spans = nextSpans
				end
			end
			for _, s in spans do
				if s[2] - s[1] > 0.01 then
					b:part(
						name,
						Vector3.new(x1 - x0, s[2] - s[1], T),
						frame * CFrame.new((x0 + x1) / 2, (s[1] + s[2]) / 2, T / 2),
						"siding"
					)
				end
			end
		end
	end
end

-- Trim around an opening on the wall's outer face.
local function casing(b: Builder, frame: CFrame, o: Opening, crown: boolean)
	local tw, depth = 0.55, 0.3
	b:decor(
		"Casing",
		Vector3.new(tw, o.h + tw, depth),
		frame * CFrame.new(o.x - o.w / 2 - tw / 2, o.y + o.h / 2, -depth / 2),
		"trim"
	)
	b:decor(
		"Casing",
		Vector3.new(tw, o.h + tw, depth),
		frame * CFrame.new(o.x + o.w / 2 + tw / 2, o.y + o.h / 2, -depth / 2),
		"trim"
	)
	if crown then
		b:decor(
			"Header",
			Vector3.new(o.w + 2 * tw + 0.6, 0.7, 0.45),
			frame * CFrame.new(o.x, o.y + o.h + 0.35, -0.22),
			"trim"
		)
		b:decor(
			"Cornice",
			Vector3.new(o.w + 2 * tw + 1, 0.25, 0.7),
			frame * CFrame.new(o.x, o.y + o.h + 0.8, -0.35),
			"trim"
		)
	else
		b:decor(
			"Header",
			Vector3.new(o.w + 2 * tw, tw, depth),
			frame * CFrame.new(o.x, o.y + o.h + tw / 2, -depth / 2),
			"trim"
		)
	end
end

export type WindowOptions = {
	lit: boolean?, -- warm light inside
	figure: boolean?, -- someone standing in it (with lit)
	curtains: boolean?,
	boarded: boolean?,
	broken: boolean?,
	shutters: boolean?,
	flicker: boolean?, -- the light inside flickers (HouseVisualController looks for "Flicker")
}

local function hinged(b: Builder, kind: string, hingeCF: CFrame, openAngle: number, openable: boolean): Model
	local m = Instance.new("Model")
	m.Name = kind
	local hinge = Parts.block(m, "Hinge", Vector3.new(0.1, 0.1, 0.1), hingeCF, "000000", M.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	m.PrimaryPart = hinge
	m:SetAttribute("Kind", kind)
	m:SetAttribute("OpenAngle", openAngle)
	m:SetAttribute("Openable", openable)
	m:SetAttribute("Open", false)
	m.Parent = b.house
	CollectionService:AddTag(m, "Hinged")
	return m
end

-- A shutter beside a window: louvred panel on a hinge at its outer edge.
local function shutter(b: Builder, frame: CFrame, x: number, y: number, h: number, side: number, loose: boolean)
	local w = 1.5
	local edge = x + side * w -- outer edge, where it hangs from
	local m = hinged(b, "Shutter", frame * CFrame.new(edge, y + h / 2, -0.35), 0, false)
	local hang = if loose then CFrame.Angles(0, 0, side * math.rad(12)) else CFrame.identity
	local centre = frame * CFrame.new(edge - side * w / 2, y + h / 2, -0.35)
	local panel = b:decor("Panel", Vector3.new(w, h, 0.2), centre, "shutter", m)
	for i = 1, math.floor(h / 1.1) do
		b:decor(
			"Louvre",
			Vector3.new(w - 0.3, 0.12, 0.3),
			centre * CFrame.new(0, -h / 2 + i * 1.1, -0.05) * CFrame.Angles(math.rad(30), 0, 0),
			"shutter",
			m
		)
	end
	if loose then
		-- Hanging from its top hinge only, swung out at an angle; it knocks in the wind.
		m:PivotTo(m:GetPivot() * hang)
		m:SetAttribute("Loose", true)
	end
	return panel
end

local function window(b: Builder, frame: CFrame, o: Opening, opts: WindowOptions)
	casing(b, frame, o, true)
	-- Sill sticking out under it.
	b:decor("Sill", Vector3.new(o.w + 1.6, 0.35, 0.9), frame * CFrame.new(o.x, o.y - 0.18, -0.35), "trim")
	local inset = 0.55
	local glassCF = frame * CFrame.new(o.x, o.y + o.h / 2, inset)
	-- The room behind it: dark, unless someone left a light on.
	local backing =
		b:decor("Room", Vector3.new(o.w + 2, o.h + 2, 0.2), frame * CFrame.new(o.x, o.y + o.h / 2, T + 2.6), "dark")
	if opts.lit then
		backing.Material = M.Neon
		backing.Color = Parts.hex("4A2A12")
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Color = Parts.hex("FF9A4A")
		light.Brightness = 1.2
		light.Range = 18
		light.Angle = 70
		light.Parent = backing
		if opts.flicker then
			backing.Name = "Flicker"
		end
	end
	if opts.figure then
		-- A dark shape against the glow: head tilted, shoulders a little too narrow.
		local fig = frame * CFrame.new(o.x + 0.2, o.y + 0.2, T + 2.2)
		b:decor("Figure", Vector3.new(1.5, 2.6, 0.3), fig * CFrame.new(0, 1.3, 0), "dark")
		b:decor("Figure", Vector3.new(0.4, 0.6, 0.3), fig * CFrame.new(0, 2.8, 0), "dark")
		local head = Parts.ball(
			b.house,
			"Figure",
			Vector3.new(1.1, 1.3, 1.1),
			fig * CFrame.new(0.25, 3.5, 0) * CFrame.Angles(0, 0, 0.35),
			"060607"
		)
		Parts.decor(head)
	end
	if opts.curtains then
		local left = b.rng:range(0.3, 0.45)
		local right = b.rng:range(0.25, 0.4)
		b:decor(
			"Curtain",
			Vector3.new(o.w * left, o.h, 0.12),
			frame * CFrame.new(o.x - o.w / 2 + o.w * left / 2, o.y + o.h / 2, T + 1.2),
			"fabric"
		)
		b:decor(
			"Curtain",
			Vector3.new(o.w * right, o.h * 0.8, 0.12),
			frame * CFrame.new(o.x + o.w / 2 - o.w * right / 2, o.y + o.h * 0.6, T + 1.2) * CFrame.Angles(0, 0, 0.04),
			"fabric"
		)
	end
	-- Glass, then the sash bars over it.
	local glass = b:decor("Glass", Vector3.new(o.w, o.h, 0.08), glassCF, "glass")
	glass.Transparency = 0.45
	glass.Reflectance = 0.12
	if opts.broken then
		-- One pane gone: a black hole with a shard left in the corner.
		local pw, ph = o.w / 2, o.h / 2
		local hole = frame * CFrame.new(o.x + pw / 2, o.y + o.h - ph / 2, inset - 0.05)
		b:decor("BrokenPane", Vector3.new(pw - 0.15, ph - 0.15, 0.06), hole, "dark")
		local shard = Parts.wedge(
			b.house,
			"Shard",
			Vector3.new(0.06, ph * 0.6, pw * 0.45),
			hole * CFrame.new(-pw * 0.2, ph * 0.12, -0.05) * CFrame.Angles(0, math.pi / 2, 0),
			"4A5654",
			M.Glass,
			{ Transparency = 0.3 }
		)
		Parts.decor(shard)
	end
	b:decor("Sash", Vector3.new(o.w, 0.22, 0.25), frame * CFrame.new(o.x, o.y + o.h / 2, inset - 0.1), "trim")
	b:decor("Sash", Vector3.new(0.18, o.h, 0.25), frame * CFrame.new(o.x, o.y + o.h / 2, inset - 0.1), "trim")
	if o.w > 4.5 then
		for _, f in { -1 / 4, 1 / 4 } do
			b:decor(
				"Sash",
				Vector3.new(0.14, o.h, 0.22),
				frame * CFrame.new(o.x + o.w * f, o.y + o.h / 2, inset - 0.1),
				"trim"
			)
		end
	end
	if opts.boarded then
		-- Boards nailed across at careless angles.
		for i = 1, 3 do
			local y = o.y + o.h * (0.2 + 0.3 * (i - 1)) + b.rng:range(-0.3, 0.3)
			b:decor(
				"Board",
				Vector3.new(o.w + 1.4, 0.75, 0.18),
				frame
					* CFrame.new(o.x + b.rng:range(-0.3, 0.3), y, -0.42)
					* CFrame.Angles(0, 0, b.rng:range(-0.25, 0.25)),
				"boards"
			)
		end
	end
	if opts.shutters then
		local loose = b.rng:chance(0.5)
		shutter(b, frame, o.x - o.w / 2 - 0.55, o.y, o.h, -1, loose)
		shutter(b, frame, o.x + o.w / 2 + 0.55, o.y, o.h, 1, not loose and b.rng:chance(0.3))
	end
end

-- A door in an opening: frame, transom glass, the hinged slab with raised panels and hardware, and a
-- dark hall (or cellar) behind it. Returns the slab and the door model.
local function door(
	b: Builder,
	frame: CFrame,
	x: number,
	y: number,
	kind: string,
	openable: boolean,
	hall: boolean
): (BasePart, Model)
	local w, h = DOOR.width, DOOR.height
	local o: Opening = { x = x, y = y, w = w, h = h + 1.5 }
	casing(b, frame, o, true)
	-- Transom over the door.
	b:decor("Transom", Vector3.new(w, 1.2, 0.1), frame * CFrame.new(x, y + h + 0.75, 0.5), "glass").Transparency = 0.4
	b:decor("TransomBar", Vector3.new(w, 0.3, 0.4), frame * CFrame.new(x, y + h + 0.1, 0.45), "trim")
	b:decor("Threshold", Vector3.new(w + 0.6, 0.2, 1.4), frame * CFrame.new(x, y + 0.1, 0.3), "trim")
	local hingeSide = if b.rng:chance(0.5) then -1 else 1
	local m = hinged(b, kind, frame * CFrame.new(x + hingeSide * w / 2, y + h / 2, 0.55), hingeSide * 100, openable)
	local slabCF = frame * CFrame.new(x, y + h / 2 + 0.05, 0.55)
	local doorSlab =
		b:part(if kind == "FrontDoor" then "Door" else "Slab", Vector3.new(w - 0.08, h - 0.1, 0.32), slabCF, "door", m)
	-- Raised panels on the outside.
	for row = 0, 2 do
		local ph = if row == 2 then h * 0.24 else h * 0.3
		local py = if row == 0 then -h * 0.27 elseif row == 1 then h * 0.06 else h * 0.32
		for _, px in { -w * 0.22, w * 0.22 } do
			b:decor("Panel", Vector3.new(w * 0.34, ph, 0.08), slabCF * CFrame.new(px, py, -0.2), "door", m)
		end
	end
	local knobX = -hingeSide * (w / 2 - 0.45)
	Parts.decor(
		Parts.ball(m, "Knob", Vector3.new(0.32, 0.32, 0.32), slabCF * CFrame.new(knobX, -0.4, -0.3), "6E5E3A", M.Metal)
	)
	Parts.decor(
		Parts.ball(m, "Knob", Vector3.new(0.32, 0.32, 0.32), slabCF * CFrame.new(knobX, -0.4, 0.3), "6E5E3A", M.Metal)
	)
	b:decor("Keyplate", Vector3.new(0.25, 0.7, 0.05), slabCF * CFrame.new(knobX, -0.55, -0.18), "brass", m)
	if kind == "FrontDoor" then
		b:decor("Knocker", Vector3.new(0.6, 0.8, 0.12), slabCF * CFrame.new(0, h * 0.18, -0.24), "brass", m)
		b:decor("MailSlot", Vector3.new(1.2, 0.25, 0.06), slabCF * CFrame.new(0, -h * 0.08, -0.2), "brass", m)
	end
	if openable then
		Parts.prompt(doorSlab, "Open", if kind == "BackDoor" then "Back door" else "Door", 8)
	end
	if hall then
		-- The dark hall behind the door: peeling wallpaper, bare boards, stairs going up into nothing.
		local depth, hw, hh = 9, w + 2.4, h + 3
		local inner = frame * CFrame.new(x, y, T)
		b:decor("HallFloor", Vector3.new(hw, 0.3, depth), inner * CFrame.new(0, -0.15, depth / 2), "deck")
		b:decor("HallCeiling", Vector3.new(hw, 0.3, depth), inner * CFrame.new(0, hh, depth / 2), "dark")
		b:decor("HallWall", Vector3.new(0.3, hh, depth), inner * CFrame.new(-hw / 2, hh / 2, depth / 2), "wallpaper")
		b:decor("HallWall", Vector3.new(0.3, hh, depth), inner * CFrame.new(hw / 2, hh / 2, depth / 2), "wallpaper")
		b:decor("HallEnd", Vector3.new(hw, hh, 0.3), inner * CFrame.new(0, hh / 2, depth), "dark")
		for i = 1, 6 do
			b:decor(
				"Stair",
				Vector3.new(hw * 0.45, 0.6 * i, 1),
				inner * CFrame.new(hw * 0.25, 0.3 * i, depth - 1 - (6 - i) * 0.9),
				"deck"
			)
		end
		local bulb = Parts.decor(
			Parts.ball(
				b.house,
				"HallBulb",
				Vector3.new(0.35, 0.35, 0.35),
				inner * CFrame.new(0, hh - 1.2, depth * 0.55),
				"8A6A3A",
				M.Neon
			)
		)
		Parts.light(bulb, 9, 0.35, "FFB070")
		b:decor("Cord", Vector3.new(0.05, 1, 0.05), inner * CFrame.new(0, hh - 0.6, depth * 0.55), "dark")
	end
	return doorSlab, m
end

-- Pieces ----------------------------------------------------------------------------------------------

local function foundation(b: Builder, at: (number, number, number) -> CFrame)
	b:part("Foundation", Vector3.new(30.4, FOUND, 24.4), at(0, FOUND / 2, 12), "stone")
	b:part("Foundation", Vector3.new(12.4, FOUND, 4.4), at((BAY.x0 + BAY.x1) / 2, FOUND / 2, -2), "stone")
	local s = TOWER.apothem * 2 + 0.4
	for _, angle in { 0, math.pi / 4 } do
		b:part(
			"Foundation",
			Vector3.new(s, FOUND, s),
			at(TOWER.x, FOUND / 2, TOWER.z) * CFrame.Angles(0, angle, 0),
			"stone"
		)
	end
	-- Cellar windows: low, barred, black.
	for _, x in { -8, 6 } do
		local cf = at(x, FOUND * 0.5, MAIN.z1 + 0.25)
		b:decor("CellarWindow", Vector3.new(2.4, 1.1, 0.2), cf, "dark")
		for i = -1, 1 do
			b:decor("Bar", Vector3.new(0.12, 1.1, 0.12), cf * CFrame.new(i * 0.6, 0, 0.15), "iron")
		end
	end
	-- Water table: a trim band where the siding meets the stone.
	b:decor("WaterTable", Vector3.new(30.8, 0.5, 24.8), at(0, FOUND + 0.25, 12), "trim")
	b:decor("WaterTable", Vector3.new(12.8, 0.5, 4.8), at((BAY.x0 + BAY.x1) / 2, FOUND + 0.25, -2), "trim")
end

local function mainWalls(b: Builder, at: (number, number, number) -> CFrame)
	local up = STORY
	-- Front: the recessed middle with the front door (the bay and tower cover the rest).
	local front = at(0, FOUND, MAIN.z0)
	local frontOpenings: { Opening } = {
		{ x = DOOR.x, y = 0, w = DOOR.width, h = DOOR.height + 1.5 },
		{ x = DOOR.x, y = up + 2.4, w = 3.2, h = 6 },
	}
	wall(b, "Wall", front, 30, EAVE - FOUND, frontOpenings)
	local frontDoor = door(b, front, DOOR.x, 0, "FrontDoor", false, true)
	window(b, front, frontOpenings[2], { boarded = b.rng:chance(0.35), curtains = true })

	-- Bay front (projects 4 studs toward the street).
	local bayX = (BAY.x0 + BAY.x1) / 2
	local bay = at(bayX, FOUND, BAY.z)
	local bayOpenings: { Opening } = {
		{ x = 0, y = 2.2, w = 7, h = 6.6 },
		{ x = -3, y = up + 2.2, w = 2.8, h = 6.2 },
		{ x = 3, y = up + 2.2, w = 2.8, h = 6.2 },
	}
	wall(b, "Wall", bay, BAY.x1 - BAY.x0, EAVE - FOUND, bayOpenings)
	window(b, bay, bayOpenings[1], { lit = true, flicker = true, curtains = true })
	window(b, bay, bayOpenings[2], { shutters = true, broken = b.rng:chance(0.6) })
	window(b, bay, bayOpenings[3], { shutters = true, boarded = b.rng:chance(0.3) })
	-- Bay's side wall facing the porch.
	wall(b, "Wall", at(BAY.x1, FOUND, BAY.z / 2) * CFrame.Angles(0, -math.pi / 2, 0), -BAY.z, EAVE - FOUND, {})

	-- Left side (incl. the bay's side).
	local leftLength = MAIN.z1 - BAY.z
	local left = at(MAIN.x0, FOUND, (MAIN.z1 + BAY.z) / 2) * CFrame.Angles(0, math.pi / 2, 0)
	local mid = (MAIN.z1 + BAY.z) / 2
	local leftOpenings: { Opening } = {}
	for _, z in { 6, 17 } do
		table.insert(leftOpenings, { x = mid - z, y = 2.4, w = 3, h = 6 })
		table.insert(leftOpenings, { x = mid - z, y = up + 2.4, w = 3, h = 6 })
	end
	wall(b, "Wall", left, leftLength, EAVE - FOUND, leftOpenings)
	for i, o in leftOpenings do
		window(b, left, o, { boarded = i == 2 or b.rng:chance(0.2), shutters = i == 3 })
	end

	-- Right side (the tower covers its front corner).
	local right = at(MAIN.x1, FOUND, 12) * CFrame.Angles(0, -math.pi / 2, 0)
	local rightOpenings: { Opening } = {}
	for _, z in { 11, 19 } do
		table.insert(rightOpenings, { x = z - 12, y = 2.4, w = 3, h = 6 })
		table.insert(rightOpenings, { x = z - 12, y = up + 2.4, w = 3, h = 6 })
	end
	wall(b, "Wall", right, 24, EAVE - FOUND, rightOpenings)
	for i, o in rightOpenings do
		window(b, right, o, { curtains = i == 1, boarded = i == 4, shutters = i == 2, broken = i == 2 })
	end

	-- Back, with the back door.
	local back = at(0, FOUND, MAIN.z1) * CFrame.Angles(0, math.pi, 0)
	local backOpenings: { Opening } = {
		{ x = -8, y = 0, w = DOOR.width, h = DOOR.height + 1.5 },
		{ x = 0, y = 2.4, w = 3, h = 6 },
		{ x = 8, y = 2.4, w = 3, h = 6 },
		{ x = -8, y = up + 2.4, w = 3, h = 6 },
		{ x = 0, y = up + 2.4, w = 3, h = 6 },
		{ x = 8, y = up + 2.4, w = 3, h = 6 },
	}
	wall(b, "Wall", back, 30, EAVE - FOUND, backOpenings)
	door(b, back, -8, 0, "BackDoor", true, true)
	for i = 2, #backOpenings do
		window(b, back, backOpenings[i], { boarded = i == 3 or i == 6, curtains = i == 4 })
	end
	-- Back stoop.
	b:part("Stoop", Vector3.new(6, FOUND, 4), back * CFrame.new(-8, -FOUND / 2, -2), "stone")
	b:part("Step", Vector3.new(5, FOUND / 2, 1.6), back * CFrame.new(-8, -FOUND * 0.75, -4.8), "stone")

	-- Corner boards and the frieze under the eaves.
	for _, c in { { MAIN.x0, BAY.z }, { MAIN.x0, MAIN.z1 }, { MAIN.x1, MAIN.z1 }, { BAY.x1, BAY.z } } do
		b:decor("CornerBoard", Vector3.new(0.8, EAVE - FOUND, 0.8), at(c[1], FOUND + (EAVE - FOUND) / 2, c[2]), "trim")
	end
	b:decor("Frieze", Vector3.new(30.6, 1.1, 0.4), at(0, EAVE - 0.55, MAIN.z1 + 0.2), "trim")
	b:decor("Frieze", Vector3.new(0.4, 1.1, 28.6), at(MAIN.x0 - 0.2, EAVE - 0.55, mid), "trim")
	b:decor("Frieze", Vector3.new(0.4, 1.1, 24.4), at(MAIN.x1 + 0.2, EAVE - 0.55, 12), "trim")
	b:decor("Frieze", Vector3.new(12.6, 1.1, 0.4), at(bayX, EAVE - 0.55, BAY.z - 0.2), "trim")
	b:decor("Frieze", Vector3.new(9, 1.1, 0.4), at(1.5, EAVE - 0.55, -0.2), "trim")
	-- A band between the floors.
	b:decor("Belt", Vector3.new(12.6, 0.45, 0.35), at(bayX, FOUND + STORY, BAY.z - 0.17), "trim")
	b:decor("Belt", Vector3.new(9, 0.45, 0.35), at(1.5, FOUND + STORY, -0.17), "trim")
	return frontDoor
end

local function mainRoof(b: Builder, at: (number, number, number) -> CFrame)
	local over = 1.3
	local slope = (RIDGE_Y - EAVE) / (RIDGE_Z - MAIN.z0)
	local lowY = EAVE - over * slope
	-- Front and back planes.
	for _, side in { -1, 1 } do
		local eaveZ = if side < 0 then MAIN.z0 - over else MAIN.z1 + over
		local low = at(0, lowY, eaveZ).Position
		local high = at(0, RIDGE_Y, RIDGE_Z).Position
		slab(b, "Roof", low, high, 32.4, 0.8, "roof")
		-- Fascia board along the eave.
		b:decor("Fascia", Vector3.new(32.4, 0.6, 0.3), at(0, lowY - 0.1, eaveZ + side * 0.1), "trim")
	end
	b:decor("RidgeCap", Vector3.new(32.6, 0.5, 1.2), at(0, RIDGE_Y + 0.55, RIDGE_Z), "roof")
	-- Gable ends: siding triangles with rake boards along the edges.
	for _, x in { MAIN.x0 + 0.5, MAIN.x1 - 0.5 } do
		local h, run = RIDGE_Y - EAVE, RIDGE_Z - MAIN.z0
		Parts.wedge(b.house, "Gable", Vector3.new(T, h, run), at(x, EAVE + h / 2, run / 2), "FFFFFF")
		Parts.wedge(
			b.house,
			"Gable",
			Vector3.new(T, h, run),
			at(x, EAVE + h / 2, run * 1.5) * CFrame.Angles(0, math.pi, 0),
			"FFFFFF"
		)
		for _, w in b.house:GetChildren() do
			if w.Name == "Gable" and w:IsA("BasePart") and w.Material == M.SmoothPlastic then
				apply(w, b.looks.scales)
			end
		end
		local outward = if x < 0 then -1 else 1
		for _, side in { -1, 1 } do
			local eaveZ = if side < 0 then MAIN.z0 - over else MAIN.z1 + over
			local low = at(x + outward * 1.05, lowY, eaveZ).Position
			local high = at(x + outward * 1.05, RIDGE_Y + 0.2, RIDGE_Z).Position
			local rake = slab(b, "Rake", low, high, 0.35, 1.1, "trim")
			Parts.decor(rake)
		end
		-- A small round attic vent window in the gable.
		local vent = at(x + outward * 0.55, EAVE + 4.2, RIDGE_Z) * CFrame.Angles(0, math.pi / 2, 0)
		local ring =
			Parts.cylinder(b.house, "Vent", 0.3, 2.6, vent * CFrame.Angles(0, math.pi / 2, 0), "B9B3A3", M.Wood)
		apply(ring, b.looks.trim)
		Parts.decor(ring)
		Parts.decor(
			Parts.cylinder(
				b.house,
				"VentHole",
				0.32,
				2,
				vent * CFrame.Angles(0, math.pi / 2, 0),
				"060607",
				M.SmoothPlastic
			)
		)
	end

	-- Chimney on the back slope, leaning very slightly.
	local chimney = at(6, (EAVE + RIDGE_Y) / 2 + 6, 17) * CFrame.Angles(math.rad(1.2), 0, math.rad(-1.5))
	b:part("Chimney", Vector3.new(3.2, 22, 3.2), chimney, "brick")
	b:decor("ChimneyCap", Vector3.new(4, 0.6, 4), chimney * CFrame.new(0, 11.2, 0), "stone")
	for _, dx in { -0.7, 0.8 } do
		Parts.decor(Parts.pole(b.house, "Pot", 1.4, 0.8, chimney * CFrame.new(dx, 11.5, 0.2), "6E5A4A", M.Brick))
	end
end

local function bay(b: Builder, at: (number, number, number) -> CFrame)
	local cx = (BAY.x0 + BAY.x1) / 2
	local half = (BAY.x1 - BAY.x0) / 2
	local rise = BAY_RIDGE_Y - EAVE
	-- Where the bay's ridge runs into the main roof.
	local slope = (RIDGE_Y - EAVE) / (RIDGE_Z - MAIN.z0)
	local backZ = (BAY_RIDGE_Y - EAVE) / slope
	local over, front = 0.9, BAY.z - 1.4
	for _, side in { -1, 1 } do
		local eaveX = cx + side * (half + over)
		local lowY = EAVE - over * rise / half
		local low = at(eaveX, lowY, (front + backZ) / 2).Position
		local high = at(cx, BAY_RIDGE_Y, (front + backZ) / 2).Position
		slab(b, "BayRoof", low, high, backZ - front, 0.8, "roof")
	end
	b:decor("RidgeCap", Vector3.new(1, 0.5, backZ - front), at(cx, BAY_RIDGE_Y + 0.5, (front + backZ) / 2), "roof")
	-- Gable wall (fish-scale shingles) facing the street.
	Parts.wedge(
		b.house,
		"BayGable",
		Vector3.new(T, rise, half),
		at(cx - half / 2, EAVE + rise / 2, BAY.z + T / 2) * CFrame.Angles(0, math.pi / 2, 0),
		"FFFFFF"
	)
	Parts.wedge(
		b.house,
		"BayGable",
		Vector3.new(T, rise, half),
		at(cx + half / 2, EAVE + rise / 2, BAY.z + T / 2) * CFrame.Angles(0, -math.pi / 2, 0),
		"FFFFFF"
	)
	for _, w in b.house:GetChildren() do
		if w.Name == "BayGable" and w:IsA("BasePart") then
			apply(w, b.looks.scales)
		end
	end
	-- Carved vergeboards along the rakes, with little drops hanging off them.
	for _, side in { -1, 1 } do
		local low = at(cx + side * (half + over), EAVE - over * rise / half - 0.1, front + 0.2).Position
		local high = at(cx, BAY_RIDGE_Y + 0.25, front + 0.2).Position
		Parts.decor(slab(b, "Verge", low, high, 0.5, 1.3, "trim"))
		for i = 1, 6 do
			local p = low:Lerp(high, i / 7)
			Parts.decor(
				Parts.pole(b.house, "Drop", 0.9, 0.22, CFrame.new(p - Vector3.new(0, 1.3, 0)), "B9B3A3", M.Wood)
			)
		end
	end
	-- King post and collar at the peak.
	b:decor("KingPost", Vector3.new(0.4, 3.5, 0.4), at(cx, BAY_RIDGE_Y - 2, front + 0.35), "trim")
	b:decor("Collar", Vector3.new(4.5, 0.35, 0.35), at(cx, BAY_RIDGE_Y - 3.4, front + 0.35), "trim")
	-- The attic window: lit, and someone is standing in it.
	local attic = at(cx, EAVE + 1.8, BAY.z - 0.05)
	local o: Opening = { x = 0, y = 0, w = 2.6, h = 4.2 }
	local fig = attic * CFrame.new(0, 0, -0.45)
	casing(b, fig, o, false)
	b:decor("Sill", Vector3.new(3.6, 0.3, 0.7), fig * CFrame.new(0, -0.15, -0.3), "trim")
	local glow = b:decor("AtticGlow", Vector3.new(o.w, o.h, 0.1), fig * CFrame.new(0, o.h / 2, 0.35), "dark")
	glow.Material = M.Neon
	glow.Color = Parts.hex("5A2814")
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Color = Parts.hex("FF7A3A")
	light.Brightness = 1.4
	light.Range = 22
	light.Angle = 60
	light.Parent = glow
	b:decor("Figure", Vector3.new(1.4, 2.1, 0.12), fig * CFrame.new(0.1, 1.05, 0.25), "dark")
	b:decor("Figure", Vector3.new(0.35, 0.4, 0.12), fig * CFrame.new(0.1, 2.25, 0.25), "dark")
	Parts.decor(
		Parts.ball(
			b.house,
			"Figure",
			Vector3.new(0.95, 1.15, 0.2),
			fig * CFrame.new(0.32, 2.85, 0.25) * CFrame.Angles(0, 0, 0.4),
			"060607"
		)
	)
	local glass = b:decor("Glass", Vector3.new(o.w, o.h, 0.06), fig * CFrame.new(0, o.h / 2, 0.12), "glass")
	glass.Transparency = 0.6
	b:decor("Sash", Vector3.new(0.16, o.h, 0.2), fig * CFrame.new(0, o.h / 2, 0.05), "trim")
	b:decor("Sash", Vector3.new(o.w, 0.16, 0.2), fig * CFrame.new(0, o.h * 0.55, 0.05), "trim")
end

local function tower(b: Builder, at: (number, number, number) -> CFrame)
	local a = TOWER.apothem
	local pw = 2 * a * math.tan(math.pi / 8)
	local height = TOWER.eave - FOUND
	local centre = at(TOWER.x, 0, TOWER.z)
	-- The tower leans away from the house, just enough to feel wrong.
	local lean = CFrame.Angles(math.rad(-0.8), 0, math.rad(-1.1))
	local base = centre * lean
	for k = 0, 7 do
		if k == 4 or k == 5 then
			continue -- inside the house
		end
		local theta = k * math.pi / 4
		local frame = base * CFrame.Angles(0, -theta, 0) * CFrame.new(0, FOUND, -a)
		local openings: { Opening } = {}
		if k == 0 or k == 1 or k == 7 or k == 2 then
			table.insert(openings, { x = 0, y = 2.6, w = 2.4, h = 5.6 })
			table.insert(openings, { x = 0, y = STORY + 2.6, w = 2.4, h = 5.6 })
			table.insert(openings, { x = 0, y = 2 * STORY + 1.4, w = 2, h = 4.2 })
		end
		wall(b, "TowerWall", frame, pw + 0.06, height, openings)
		for i, o in openings do
			window(b, frame, o, {
				boarded = (k == 1 and i == 1) or (k == 2 and i == 2),
				broken = k == 7 and i == 3,
				curtains = k == 0 and i == 2,
			})
		end
		-- Corner posts where the panels meet, plus frieze and belt pieces.
		local corner = base
			* CFrame.Angles(0, -theta - math.pi / 8, 0)
			* CFrame.new(0, FOUND + height / 2, -a / math.cos(math.pi / 8))
		b:decor("TowerCorner", Vector3.new(0.7, height, 0.7), corner * CFrame.Angles(0, math.pi / 8, 0), "trim")
		b:decor("TowerFrieze", Vector3.new(pw + 0.4, 1.2, 0.4), frame * CFrame.new(0, height - 0.6, -0.2), "trim")
		b:decor("TowerBelt", Vector3.new(pw + 0.3, 0.45, 0.35), frame * CFrame.new(0, STORY, -0.17), "trim")
		b:decor("TowerBelt", Vector3.new(pw + 0.3, 0.45, 0.35), frame * CFrame.new(0, 2 * STORY, -0.17), "trim")
	end
	-- Witch-hat roof: eight steep facets up to a spike, with a bent weathervane.
	local top = TOWER.eave
	local ring = (a + 1.1) / math.cos(math.pi / 8)
	local apex = (base * CFrame.new(0, top + TOWER.roof, 0)).Position
	for k = 0, 7 do
		local t0 = k * math.pi / 4 + math.pi / 8
		local t1 = t0 + math.pi / 4
		local v0 = (base * CFrame.new(math.sin(t0) * ring, top - 0.6, -math.cos(t0) * ring)).Position
		local v1 = (base * CFrame.new(math.sin(t1) * ring, top - 0.6, -math.cos(t1) * ring)).Position
		triangle(b, "TowerRoof", v0, v1, apex, 0.6, "roof")
		b:decor(
			"TowerFascia",
			Vector3.new((v1 - v0).Magnitude, 0.5, 0.3),
			CFrame.lookAt((v0 + v1) / 2, (v0 + v1) / 2 + (v1 - v0):Cross(Vector3.yAxis)) * CFrame.new(0, -0.2, 0),
			"trim"
		)
	end
	local spike = base * CFrame.new(0, top + TOWER.roof, 0)
	Parts.decor(Parts.pole(b.house, "Finial", 3.2, 0.3, spike, "1E1E22", M.Metal))
	Parts.decor(
		Parts.ball(b.house, "FinialBall", Vector3.new(0.7, 0.7, 0.7), spike * CFrame.new(0, 1.2, 0), "1E1E22", M.Metal)
	)
	local vane = spike * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0.7, math.rad(14))
	b:decor("Vane", Vector3.new(3, 0.12, 0.08), vane, "iron")
	Parts.decor(
		Parts.wedge(
			b.house,
			"VaneTail",
			Vector3.new(0.08, 0.9, 0.9),
			vane * CFrame.new(-1.4, 0.2, 0) * CFrame.Angles(0, math.pi / 2, 0),
			"1E1E22",
			M.Metal
		)
	)
	-- Dead ivy crawling up the street side of the tower (kept within the front panel).
	local panel = base * CFrame.new(0, FOUND, -a - 0.12)
	local function vine(x: number, y: number, maxY: number)
		while y < maxY do
			local nx = math.clamp(x + b.rng:range(-0.7, 0.7), -1.9, 1.9)
			local ny = y + b.rng:range(0.6, 1.4)
			local p0 = (panel * CFrame.new(x, y, 0)).Position
			local p1 = (panel * CFrame.new(nx, ny, 0)).Position
			local stem = b:decor(
				"Ivy",
				Vector3.new(0.13, (p1 - p0).Magnitude, 0.13),
				CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(math.pi / 2, 0, 0),
				"dark"
			)
			stem.Color = Parts.hex("2E261C")
			if b.rng:chance(0.3) then
				local tx, ty = math.clamp(nx + b.rng:range(-0.9, 0.9), -2.1, 2.1), ny + b.rng:range(0.2, 0.7)
				local t1 = (panel * CFrame.new(tx, ty, 0)).Position
				local twig = b:decor(
					"Ivy",
					Vector3.new(0.07, (t1 - p1).Magnitude, 0.07),
					CFrame.lookAt((p1 + t1) / 2, t1) * CFrame.Angles(math.pi / 2, 0, 0),
					"dark"
				)
				twig.Color = Parts.hex("2E261C")
			end
			x, y = nx, ny
		end
	end
	vine(-1.4, 0, STORY * 1.6)
	vine(1.2, 0, STORY * 0.9)
end

local function porch(b: Builder, at: (number, number, number) -> CFrame): BasePart
	local x0, x1, z0 = PORCH.x0, PORCH.x1, PORCH.z
	local w, d = x1 - x0, -z0
	local cx = (x0 + x1) / 2
	-- Deck on a lattice skirt.
	b:part("Deck", Vector3.new(w, 0.4, d), at(cx, FOUND - 0.2, z0 / 2), "deck")
	b:decor("Skirt", Vector3.new(w, FOUND - 0.4, 0.3), at(cx, (FOUND - 0.4) / 2, z0 + 0.3), "dark")
	for i = 0, math.floor(w / 1.8) do
		local x = x0 + i * 1.8
		for _, a in { 0.8, -0.8 } do
			b:decor(
				"Lattice",
				Vector3.new(0.18, 3.2, 0.12),
				at(x, (FOUND - 0.4) / 2, z0 + 0.1) * CFrame.Angles(0, 0, a),
				"trim"
			)
		end
	end
	b:decor("DeckEdge", Vector3.new(w + 0.4, 0.5, 0.5), at(cx, FOUND - 0.15, z0 + 0.1), "trim")
	-- Steps down to the path, a little uneven.
	for i = 1, 3 do
		local top = FOUND - i * FOUND / 4
		b:part(
			"Step",
			Vector3.new(5.4, top, 1.15),
			at(DOOR.x, top / 2, z0 - (i - 0.5) * 1.15) * CFrame.Angles(0, 0, math.rad((i - 2) * 0.8)),
			"deck"
		)
	end
	for _, side in { -1, 1 } do
		local stringer = Parts.wedge(
			b.house,
			"Stringer",
			Vector3.new(0.4, FOUND, 3.6),
			at(DOOR.x + side * 2.9, FOUND / 2, z0 - 1.8),
			"FFFFFF"
		)
		apply(stringer, b.looks.trim)
	end

	-- Turned posts, brackets, railings (one section broken).
	local postZ = z0 + 0.5
	local posts = { x0 + 0.4, DOOR.x + 3.1, 8.6, 12.4, x1 - 0.4 }
	local roofLow, roofHigh = FOUND + 10.2, FOUND + 11.4
	for i, x in posts do
		local sag = if i == 3 or i == 4 then -0.35 else 0 -- the porch roof sags in the middle
		local h = roofLow - FOUND + sag
		local p = at(x, FOUND, postZ)
		b:part("PostBase", Vector3.new(0.9, 1.4, 0.9), p * CFrame.new(0, 0.7, 0), "trim")
		local shaft = Parts.pole(b.house, "Post", h - 2.4, 0.55, p * CFrame.new(0, 1.4, 0), "B9B3A3", M.Wood)
		apply(shaft, b.looks.trim)
		for _, y in { 2.2, h * 0.5, h - 1.6 } do
			Parts.decor(Parts.pole(b.house, "Turn", 0.35, 0.8, p * CFrame.new(0, y, 0), "B9B3A3", M.Wood))
		end
		b:decor("PostCap", Vector3.new(0.9, 1, 0.9), p * CFrame.new(0, h - 0.5, 0), "trim")
		for _, side in { -1, 1 } do
			Parts.decor(
				Parts.wedge(
					b.house,
					"Bracket",
					Vector3.new(0.25, 1.2, 1.2),
					p * CFrame.new(side * 0.95, h - 1.6, 0) * CFrame.Angles(0, side * math.pi / 2, math.pi),
					"B9B3A3",
					M.Wood
				)
			)
		end
	end
	local function railing(a: Vector3, c: Vector3, broken: boolean)
		local len = (c - a).Magnitude
		local frame = CFrame.lookAt((a + c) / 2, c)
		b:decor("Rail", Vector3.new(0.3, 0.3, len), frame * CFrame.new(0, 3.1, 0), "trim")
		b:decor("Rail", Vector3.new(0.25, 0.25, len), frame * CFrame.new(0, 0.5, 0), "trim")
		local count = math.floor(len / 1)
		for i = 1, count - 1 do
			local z = -len / 2 + i * len / count
			if broken and i >= count * 0.4 and i <= count * 0.55 then
				continue -- snapped balusters
			end
			b:decor("Baluster", Vector3.new(0.18, 2.6, 0.18), frame * CFrame.new(0, 1.8, z), "trim")
		end
		if broken then
			-- A loose length of top rail hanging down.
			b:decor(
				"Rail",
				Vector3.new(0.3, 0.3, len * 0.4),
				frame * CFrame.new(0, 2.2, len * 0.05) * CFrame.Angles(math.rad(25), 0, 0),
				"trim"
			)
		end
	end
	for i = 1, #posts - 1 do
		if i ~= 1 then -- the gap for the steps
			local a = at(posts[i], FOUND, postZ).Position
			local c = at(posts[i + 1], FOUND, postZ).Position
			railing(a, c, i == 3)
		end
	end
	railing(at(x0 + 0.4, FOUND, postZ).Position, at(x0 + 0.4, FOUND, BAY.z - 0.4).Position, false)
	railing(at(x1 - 0.4, FOUND, postZ).Position, at(x1 - 0.4, FOUND, -3.8).Position, false)

	-- Porch roof: a shed roof from the house out to the posts, sagging between them.
	local roofFront = z0 - 0.6
	local low = at(cx, roofLow, roofFront).Position
	local high = at(cx, roofHigh, 0).Position
	local roof = slab(b, "PorchRoof", low, high, w + 0.8, 0.6, "roof")
	roof.CFrame *= CFrame.Angles(0, 0, math.rad(0.5))
	b:decor(
		"PorchBeam",
		Vector3.new(w, 1.2, 0.5),
		at(cx, roofLow - 0.6, postZ) * CFrame.Angles(0, 0, math.rad(0.6)),
		"trim"
	)
	b:decor("PorchCeiling", Vector3.new(w, 0.2, d - 0.4), at(cx, roofLow - 0.15, z0 / 2 + 0.2), "boards")
	-- Spindle frieze under the beam (gingerbread).
	for i = 0, math.floor(w / 0.9) do
		b:decor("Spindle", Vector3.new(0.12, 0.8, 0.12), at(x0 + 0.3 + i * 0.9, roofLow - 1.7, postZ), "trim")
	end
	b:decor("SpindleRail", Vector3.new(w, 0.2, 0.25), at(cx, roofLow - 2.15, postZ), "trim")

	-- Porch lantern by the door (HouseVisualController flickers it).
	local lantern = at(DOOR.x - 3.2, FOUND + 6.9, -0.55)
	b:decor("LanternBracket", Vector3.new(0.15, 0.15, 0.8), lantern * CFrame.new(0, 0.9, 0.3), "iron")
	b:decor("LanternTop", Vector3.new(0.9, 0.3, 0.9), lantern * CFrame.new(0, 0.75, 0), "iron")
	local bulb = b:decor("PorchLight", Vector3.new(0.6, 1.1, 0.6), lantern, "dark")
	bulb.Material = M.Neon
	bulb.Color = Parts.hex("C98A48")
	bulb.Transparency = 0.15
	Parts.light(bulb, 16, 0.9, "FFAA60")

	-- Furniture: a rocking chair angled toward the door, a swing hanging from one chain.
	local chair = at(-0.8, FOUND, -3) * CFrame.Angles(0, math.rad(-35), 0)
	b:decor("ChairSeat", Vector3.new(1.8, 0.25, 1.8), chair * CFrame.new(0, 1.6, 0), "boards")
	b:decor(
		"ChairBack",
		Vector3.new(1.8, 2.4, 0.25),
		chair * CFrame.new(0, 2.9, 0.85) * CFrame.Angles(math.rad(-10), 0, 0),
		"boards"
	)
	for _, sx in { -0.8, 0.8 } do
		b:decor(
			"Rocker",
			Vector3.new(0.18, 0.3, 2.6),
			chair * CFrame.new(sx, 0.2, 0.1) * CFrame.Angles(math.rad(6), 0, 0),
			"boards"
		)
		b:decor("ChairLeg", Vector3.new(0.18, 1.5, 0.18), chair * CFrame.new(sx, 0.9, -0.7), "boards")
		b:decor("ChairLeg", Vector3.new(0.18, 1.5, 0.18), chair * CFrame.new(sx, 0.9, 0.8), "boards")
	end
	local swingTop = at(11.6, roofLow - 0.2, -3.2)
	b:decor("Chain", Vector3.new(0.08, 5.5, 0.08), swingTop * CFrame.new(-2, -2.75, 0), "iron")
	local swing = swingTop * CFrame.new(0.2, -6.4, 0) * CFrame.Angles(0, 0, math.rad(-24))
	b:decor("SwingSeat", Vector3.new(4.6, 0.3, 1.6), swing, "boards")
	b:decor("SwingBack", Vector3.new(4.6, 1.6, 0.25), swing * CFrame.new(0, 0.9, 0.7), "boards")
	b:decor(
		"Chain",
		Vector3.new(0.08, 1.6, 0.08),
		swing * CFrame.new(2.2, 0.8, 0) * CFrame.Angles(0, 0, math.rad(40)),
		"iron"
	)
	return bulb
end

local function cellar(b: Builder, at: (number, number, number) -> CFrame)
	-- Slanted storm-cellar doors against the right wall; both leaves can be opened onto a black pit.
	local frame = at(MAIN.x1, 0, 6) * CFrame.Angles(0, -math.pi / 2, 0)
	local w, run = 5, 4.2
	b:part("CellarCurb", Vector3.new(w + 1, 1.2, run + 0.6), frame * CFrame.new(0, 0.6, -run / 2), "stone")
	b:decor("CellarPit", Vector3.new(w, 0.1, run), frame * CFrame.new(0, 1.25, -run / 2), "dark")
	local tilt = math.atan2(FOUND - 1.2, run)
	local midY = 1.2 + (FOUND - 1.2) / 2 + 0.15
	for _, side in { -1, 1 } do
		local slope = frame * CFrame.new(side * w / 2, midY, -run / 2) * CFrame.Angles(-tilt, 0, 0)
		local m = hinged(b, "CellarDoor", slope * CFrame.Angles(math.pi / 2, 0, 0), side * 110, true)
		local leaf = frame * CFrame.new(side * w / 4, midY, -run / 2) * CFrame.Angles(-tilt, 0, 0)
		local leafPart = b:part("Slab", Vector3.new(w / 2 - 0.05, 0.3, run / math.cos(tilt)), leaf, "boards", m)
		for _, dz in { -1.2, 0, 1.2 } do
			b:decor("Strap", Vector3.new(w / 2 - 0.4, 0.08, 0.25), leaf * CFrame.new(0, 0.18, dz), "iron", m)
		end
		Parts.prompt(leafPart, "Open", "Cellar", 8)
	end
end

local function yard(
	b: Builder,
	at: (number, number, number) -> CFrame,
	yardDepth: number,
	lotWidth: number,
	mirror: number?
)
	local m = mirror or 1
	-- Dead lawn inside the fence and a cracked flagstone path to the steps.
	local fenceZ = -(yardDepth - 0.6)
	local half = lotWidth / 2 - 1
	b:decor("Lawn", Vector3.new(half * 2, 0.1, yardDepth - 1), at(0, 0.06, fenceZ / 2), "lawn")
	local z = PORCH.z - 3.6
	while z > fenceZ + 0.8 do
		local s = b.rng:range(1.6, 2.3)
		b:decor(
			"Flagstone",
			Vector3.new(s * 1.3, 0.16, s),
			at(DOOR.x + b.rng:range(-0.4, 0.4), 0.13, z) * CFrame.Angles(0, b.rng:range(-0.3, 0.3), 0),
			"stone"
		)
		z -= s + b.rng:range(0.25, 0.6)
	end
	-- Wrought-iron fence with spear tops, stone pillars at a gate left hanging open.
	local gateW = 4.4
	-- An invisible wall so nobody walks through the bars (the bars themselves are decoration).
	local function blocker(parent: Instance, size: Vector3, cframe: CFrame): BasePart
		local collider = b:part("Collision", size, cframe, "dark", parent)
		collider.Transparency = 1
		collider.CanQuery = false
		collider.CanTouch = false
		collider.CastShadow = false
		return collider
	end
	local function fence(xa: number, xb: number)
		local len = math.abs(xb - xa)
		local cx = (xa + xb) / 2
		blocker(b.house, Vector3.new(len, 4.6, 0.4), at(cx, 2.3, fenceZ))
		b:decor("FenceRail", Vector3.new(len, 0.15, 0.15), at(cx, 3.6, fenceZ), "iron")
		b:decor("FenceRail", Vector3.new(len, 0.15, 0.15), at(cx, 0.6, fenceZ), "iron")
		for i = 0, math.floor(len / 0.8) do
			local x = math.min(xa, xb) + i * 0.8
			local lean = b.rng:range(-0.04, 0.04)
			b:decor("Picket", Vector3.new(0.12, 4.2, 0.12), at(x, 2.1, fenceZ) * CFrame.Angles(lean, 0, lean), "iron")
			Parts.decor(
				Parts.wedge(
					b.house,
					"Spear",
					Vector3.new(0.12, 0.45, 0.25),
					at(x, 4.42, fenceZ) * CFrame.Angles(0, math.pi / 2, 0),
					"1E1E22",
					M.Metal
				)
			)
		end
	end
	fence(-half, DOOR.x - gateW / 2 - 0.7)
	fence(DOOR.x + gateW / 2 + 0.7, half)
	for _, side in { -1, 1 } do
		local x = DOOR.x + side * (gateW / 2 + 0.35)
		b:part("Pillar", Vector3.new(1.3, 5.2, 1.3), at(x, 2.6, fenceZ), "stone")
		b:decor("PillarCap", Vector3.new(1.7, 0.4, 1.7), at(x, 5.4, fenceZ), "stone")
	end
	local gate = hinged(b, "Gate", at(DOOR.x - gateW / 2, 2.3, fenceZ), -70 * m, true)
	for i = 0, 6 do
		b:decor(
			"GateBar",
			Vector3.new(0.14, 4.2, 0.14),
			at(DOOR.x - gateW / 2 + 0.3 + i * (gateW - 0.6) / 6, 2.3, fenceZ),
			"iron",
			gate
		)
	end
	b:decor("GateRail", Vector3.new(gateW, 0.18, 0.18), at(DOOR.x, 3.9, fenceZ), "iron", gate)
	local gateRail = b:part("Slab", Vector3.new(gateW, 0.18, 0.18), at(DOOR.x, 0.7, fenceZ), "iron", gate)
	Parts.prompt(gateRail, "Close", "Gate", 8)
	blocker(gate, Vector3.new(gateW - 0.2, 4.2, 0.3), at(DOOR.x, 2.3, fenceZ)) -- swings with the gate
	-- Left standing open (so the path is free); anyone can swing it shut.
	gate:SetAttribute("Open", true)

	-- A dead tree, a leaning mailbox and two small graves under the bay window.
	Props.tree(b.house, at(-(half - 2), 0, fenceZ + 2.2), b.rng, "dead")
	Props.mailbox(b.house, at(DOOR.x + gateW / 2 + 2.2, 0, fenceZ + 1.2) * CFrame.Angles(0, 0, math.rad(9)), "2A2A2E")
	for i = 1, 2 do
		Props.gravestone(
			b.house,
			at(-9 + i * 2.6, 0, PORCH.z - 2) * CFrame.Angles(0, b.rng:range(-0.25, 0.25), b.rng:range(-0.08, 0.08)),
			b.rng
		)
	end
end

-- The yard set modelled in Blender (art/scripts/yard.py, filed by tools/setup_yard.luau): an iron
-- fence whose panels stretch to fit the lot, stone pillars and an arched double gate left open, a
-- stepping stone, a dead tree, a mailbox, and two graves under the bay window. Works in the lot's
-- own frame (x across, -z toward the street), where the imported house's door is at x = -DOOR.x.
-- The Blender model's lot, in the same shape as the generated house data (HouseData/Types).
local BLENDER_LOT: HouseData.Data = {
	style = "Victorian",
	door = { x = DOOR.x, y = 0.55, sill = FOUND },
	hinged = {},
	colliders = {},
	lights = {},
	anchors = {},
	rooms = VictorianRooms,
	yard = {
		fence = "Iron",
		pathFrom = PORCH.z - 4.3,
		tree = Vector3.new(-16.5, -13.9, 0),
		graves = { Vector3.new(-7.5, -10.2, 0), Vector3.new(-10.8, -10.8, 0) },
	},
}

-- Dresses the lot around the imported Blender model (ReplicatedStorage.Assets.Houses.Victorian,
-- art/scripts/victorian.py): the Blender yard set and room lights (BlenderLot), or the built yard
-- when the yard set isn't there. The model's x runs the other way (its front door is at x = -1.5), so
-- the built yard mirrors x.
function Victorian.dressLot(house: Model, base: CFrame, rng: Rng.Rng, yardDepth: number, lotWidth: number)
	if not BlenderLot.dress(house, base, rng, yardDepth, lotWidth, BLENDER_LOT) then
		yard(newBuilder(house, base, rng), function(x: number, y: number, z: number): CFrame
			return base * CFrame.new(-x, y, z)
		end, yardDepth, lotWidth, -1)
	end
end

function Victorian.build(
	parent: Instance,
	base: CFrame,
	rng: Rng.Rng,
	yardDepth: number,
	lotWidth: number
): (Model, BasePart)
	local house = Instance.new("Model")
	house.Name = "Victorian"
	local b = newBuilder(house, base, rng)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	foundation(b, at)
	local front = mainWalls(b, at)
	mainRoof(b, at)
	bay(b, at)
	tower(b, at)
	porch(b, at)
	cellar(b, at)
	yard(b, at, yardDepth, lotWidth)
	house:SetAttribute("Style", "Victorian")
	house.Parent = parent
	return house, front
end

return Victorian
