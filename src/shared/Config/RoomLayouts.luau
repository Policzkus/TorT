--!strict
-- How the rooms behind the windows get furnished: every house picks a layout per room (World/
-- BlenderLot.furnish), so no two houses look alike inside. Pieces are the Blender furniture
-- (art/scripts/furniture.py, ReplicatedStorage.Assets.Furniture); each faces the room's front
-- (its window wall) unless turned.
--
-- In a room's frame x runs across and y from the front (window) wall back; W and D are its width
-- and depth in studs. An item is placed by `at`:
--   back             against the back wall, facing the front; u = 0..1 across
--   left / right     against a side wall, facing into the room; u = 0..1 front to back
--   wall / wallLeft / wallRight   hung on that wall (portraits), z = height of its centre
--   free             anywhere: u, v = 0..1 across and front to back, or x, y studs from the centre;
--                    yaw in degrees (0 faces the front, 180 the back, 90 the right-hand side); z lifts it
-- minW / minD: the smallest room the layout fits. weight: how often it's picked.

export type Item = {
	piece: string,
	at: string,
	u: number?,
	v: number?,
	x: number?,
	y: number?,
	yaw: number?,
	z: number?,
}

export type Layout = { name: string, roles: { string }, minW: number, minD: number, weight: number, items: { Item } }

local layouts: { Layout } = {
	-- Living rooms ----------------------------------------------------------------------------------
	{
		name = "Parlour",
		roles = { "living" },
		minW = 7,
		minD = 7,
		weight = 3,
		items = {
			{ piece = "Fireplace", at = "back", u = 0.5 },
			{ piece = "Rug", at = "free", u = 0.5, v = 0.45 },
			{ piece = "Armchair", at = "free", u = 0.26, v = 0.4, yaw = 155 },
			{ piece = "Armchair", at = "free", u = 0.74, v = 0.4, yaw = 205 },
			{ piece = "SideTable", at = "free", u = 0.1, v = 0.62 },
			{ piece = "Clock", at = "left", u = 0.25 },
		},
	},
	{
		name = "Bedroom",
		roles = { "living" },
		minW = 7,
		minD = 8.5,
		weight = 3,
		items = {
			{ piece = "Bed", at = "back", u = 0.32 },
			{ piece = "Portrait", at = "wall", u = 0.32, z = 8 },
			{ piece = "Wardrobe", at = "back", u = 0.86 },
			{ piece = "Dresser", at = "right", u = 0.3 },
			{ piece = "Chair", at = "free", u = 0.7, v = 0.55, yaw = 25 },
		},
	},
	{
		name = "Nursery",
		roles = { "living" },
		minW = 7,
		minD = 6,
		weight = 2,
		items = {
			{ piece = "Crib", at = "back", u = 0.3 },
			{ piece = "RockingChairDoll", at = "free", u = 0.68, v = 0.3, yaw = -15 },
			{ piece = "ToyBlocks", at = "free", u = 0.42, v = 0.22, yaw = 30 },
			{ piece = "Wardrobe", at = "back", u = 0.84 },
			{ piece = "Portrait", at = "wallLeft", u = 0.5, z = 6.5 },
		},
	},
	{
		name = "Study",
		roles = { "living" },
		minW = 8,
		minD = 6,
		weight = 2,
		items = {
			{ piece = "Bookshelf", at = "back", u = 0.25 },
			{ piece = "Bookshelf2", at = "back", u = 0.75 },
			{ piece = "Rug", at = "free", u = 0.5, v = 0.45 },
			{ piece = "Desk", at = "free", u = 0.5, v = 0.38 },
			{ piece = "Chair", at = "free", u = 0.5, v = 0.62 },
		},
	},
	{
		name = "Dining",
		roles = { "living" },
		minW = 9,
		minD = 8,
		weight = 2,
		items = {
			{ piece = "DiningTable", at = "free", x = 0, y = 0.5 },
			{ piece = "Candelabra", at = "free", x = 0, y = 0.5, z = 2.95 }, -- on the table
			{ piece = "Chair", at = "free", x = -2.1, y = -2.2, yaw = 180 },
			{ piece = "Chair", at = "free", x = 2.1, y = -2.2, yaw = 180 },
			{ piece = "Chair", at = "free", x = -2.1, y = 3.2 },
			{ piece = "Chair", at = "free", x = 2.1, y = 3.2 },
			{ piece = "Portrait", at = "wall", u = 0.5, z = 7 },
		},
	},
	{
		name = "Seance",
		roles = { "living", "tower" },
		minW = 7,
		minD = 7,
		weight = 2,
		items = {
			{ piece = "SeanceTable", at = "free", x = 0, y = 0.3 },
			{ piece = "Chair", at = "free", x = 0, y = -2.8, yaw = 180 },
			{ piece = "Chair", at = "free", x = 0, y = 3.3 },
			{ piece = "Chair", at = "free", x = -2.9, y = 0.3, yaw = 90 },
			{ piece = "Chair", at = "free", x = 2.9, y = 0.3, yaw = -90 },
			{ piece = "Candles", at = "free", u = 0.12, v = 0.85 },
		},
	},
	{
		name = "Coffin",
		roles = { "living" },
		minW = 8,
		minD = 6,
		weight = 2,
		items = {
			{ piece = "Coffin", at = "free", x = 0, y = 0.6, yaw = 90 },
			{ piece = "Candles", at = "free", x = -3.2, y = -1.6 },
			{ piece = "Candles", at = "free", x = 3.4, y = 2.5 },
			{ piece = "Portrait", at = "wall", u = 0.5, z = 7 },
			{ piece = "Chair", at = "free", u = 0.85, v = 0.25, yaw = 200 },
		},
	},
	{
		name = "Music",
		roles = { "living" },
		minW = 7.5,
		minD = 6,
		weight = 2,
		items = {
			{ piece = "Piano", at = "back", u = 0.38 },
			{ piece = "Armchair", at = "free", u = 0.8, v = 0.42, yaw = 200 },
			{ piece = "Portrait", at = "wall", u = 0.82, z = 7 },
			{ piece = "Candles", at = "free", u = 0.12, v = 0.2 },
		},
	},
	{
		name = "DustSheets",
		roles = { "living", "attic", "tower" },
		minW = 6,
		minD = 5,
		weight = 3,
		items = {
			{ piece = "SheetSofa", at = "free", u = 0.5, v = 0.6 },
			{ piece = "SheetChair", at = "free", u = 0.18, v = 0.3, yaw = 20 },
			{ piece = "SheetTall", at = "back", u = 0.88 },
			{ piece = "SheetLow", at = "free", u = 0.8, v = 0.28, yaw = -30 },
		},
	},
	{
		name = "Watcher",
		roles = { "living", "tower" },
		minW = 5,
		minD = 5,
		weight = 1,
		items = {
			{ piece = "Chair", at = "free", u = 0.5, v = 0.35 },
			{ piece = "Candles", at = "free", u = 0.28, v = 0.6 },
		},
	},
	{
		name = "Aviary",
		roles = { "living", "tower" },
		minW = 6,
		minD = 6,
		weight = 1,
		items = {
			{ piece = "Birdcage", at = "free", u = 0.28, v = 0.4 },
			{ piece = "Armchair", at = "free", u = 0.66, v = 0.5, yaw = 195 },
			{ piece = "Bookshelf", at = "back", u = 0.78 },
		},
	},
	{
		name = "Reading",
		roles = { "tower", "living" },
		minW = 5.5,
		minD = 5.5,
		weight = 2,
		items = {
			{ piece = "Armchair", at = "free", u = 0.55, v = 0.45 },
			{ piece = "SideTable", at = "free", u = 0.2, v = 0.55 },
			{ piece = "Rug", at = "free", u = 0.5, v = 0.5 },
		},
	},
	-- Narrow rooms ----------------------------------------------------------------------------------
	{
		name = "Sickroom",
		roles = { "living" },
		minW = 6,
		minD = 8,
		weight = 2,
		items = {
			{ piece = "Bed", at = "back", u = 0.5 },
			{ piece = "Portrait", at = "wall", u = 0.5, z = 7.5 },
			{ piece = "Chair", at = "free", u = 0.2, v = 0.45, yaw = 60 },
			{ piece = "Candles", at = "free", u = 0.85, v = 0.4 },
		},
	},
	{
		name = "Rocker",
		roles = { "living", "tower" },
		minW = 5,
		minD = 5,
		weight = 2,
		items = {
			{ piece = "Rug", at = "free", u = 0.5, v = 0.5 },
			{ piece = "RockingChair", at = "free", u = 0.5, v = 0.42, yaw = 15 },
			{ piece = "SideTable", at = "free", u = 0.16, v = 0.45 },
			{ piece = "Clock", at = "back", u = 0.82 },
		},
	},
	{
		name = "Portraits",
		roles = { "living" },
		minW = 5,
		minD = 7,
		weight = 2,
		items = {
			{ piece = "Bookshelf", at = "back", u = 0.5 },
			{ piece = "Portrait", at = "wallLeft", u = 0.3, z = 7 },
			{ piece = "Portrait", at = "wallLeft", u = 0.7, z = 7.4 },
			{ piece = "Portrait", at = "wallRight", u = 0.5, z = 7.2 },
			-- Its back to the window: is anyone sitting in it?
			{ piece = "Armchair", at = "free", u = 0.5, v = 0.42, yaw = 180 },
		},
	},
	-- Kitchens (behind the back doors) ------------------------------------------------------------
	{
		name = "Kitchen",
		roles = { "kitchen" },
		minW = 7,
		minD = 5,
		weight = 2,
		items = {
			{ piece = "Stove", at = "back", u = 0.25 },
			{ piece = "Shelves", at = "back", u = 0.72 },
			{ piece = "Table", at = "free", x = 0, y = -0.3, yaw = 5 },
			{ piece = "Chair", at = "free", x = -3.2, y = -0.2, yaw = 95 },
			{ piece = "Chair", at = "free", x = 3.2, y = -0.4, yaw = -80 },
		},
	},
	{
		name = "Scullery",
		roles = { "kitchen" },
		minW = 6,
		minD = 5,
		weight = 1,
		items = {
			{ piece = "Stove", at = "back", u = 0.7 },
			{ piece = "Table", at = "free", u = 0.35, v = 0.45, yaw = -10 },
			{ piece = "Crate", at = "free", u = 0.85, v = 0.25, yaw = 20 },
			{ piece = "Candles", at = "free", u = 0.15, v = 0.2 },
		},
	},
	-- Attics and junk rooms -------------------------------------------------------------------------
	{
		name = "Lumber",
		roles = { "attic" },
		minW = 4,
		minD = 3,
		weight = 2,
		items = {
			{ piece = "Trunk", at = "free", u = 0.35, v = 0.55, yaw = 15 },
			{ piece = "DressForm", at = "free", u = 0.78, v = 0.35, yaw = -20 },
			{ piece = "Crate", at = "free", u = 0.15, v = 0.8 },
		},
	},
	{
		name = "Forgotten",
		roles = { "attic" },
		minW = 4,
		minD = 3,
		weight = 2,
		items = {
			{ piece = "SheetTall", at = "free", u = 0.25, v = 0.6 },
			{ piece = "Crate", at = "free", u = 0.7, v = 0.45, yaw = 30 },
			{ piece = "Birdcage", at = "free", u = 0.5, v = 0.8 },
		},
	},
	{
		name = "Candlelit",
		roles = { "attic", "tower" },
		minW = 3,
		minD = 3,
		weight = 1,
		items = {
			{ piece = "Trunk", at = "free", u = 0.6, v = 0.6, yaw = -10 },
			{ piece = "Candles", at = "free", u = 0.3, v = 0.3 },
		},
	},
}

return layouts
