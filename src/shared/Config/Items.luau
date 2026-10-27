--!strict
-- What the seller sells (the user: "Seller spawns in one of the houses (random), he sells lockpicks,
-- traps, (items that helps against mobs), bandage that gives u hp"). One stands at a random house on
-- every street, a different one each night (HouseService: house type "Seller"). Bought with banked
-- candy (Services/ItemService), kept between runs (PlayerData.consumables), used from the bar at the
-- bottom of the view (Controllers/ItemsController: keys 1-4).
-- Prices are a number of the street's doors (`doors`: its average door's candy), so they're worth
-- the same on every street. You carry at most `most` of each.

local Neighborhoods = require(script.Parent.Neighborhoods)

export type Item = {
	name: string,
	icon: string,
	blurb: string, -- what it does, in the seller's window
	doors: number, -- price, in the street's average doors
	most: number, -- most you can carry
	key: string, -- the Enum.KeyCode that uses it
	pad: string?, -- on a gamepad
}

local Items = {
	ORDER = { "Bandage", "BearTrap", "Firecracker", "Lockpick" },

	Bandage = {
		name = "Bandage",
		icon = "🩹",
		blurb = "Wrap a wound: +50 health. (Health doesn't come back by itself.)",
		doors = 8,
		most = 5,
		key = "One",
		pad = "DPadLeft",
	} :: Item,
	BearTrap = {
		name = "Bear Trap",
		icon = "🪤",
		blurb = "Set it at your feet. The Knifer or a homeowner who walks into it is stuck there.",
		doors = 14,
		most = 3,
		key = "Two",
		pad = "DPadDown",
	} :: Item,
	Firecracker = {
		name = "Firecracker",
		icon = "🧨",
		blurb = "Throw it. Its bangs draw them to it, and they see no one till it's done.",
		doors = 10,
		most = 5,
		key = "Three",
		pad = "DPadRight",
	} :: Item,
	-- (The user: "leave it without usage for now".)
	Lockpick = {
		name = "Lockpick",
		icon = "🗝️",
		blurb = "No use yet. Hold on to it.",
		doors = 12,
		most = 3,
		key = "Four",
	} :: Item,

	BANDAGE = { heal = 50 },
	-- The bear trap: a hunter whose feet come within `reach` studs of it is held `hold` seconds. You
	-- can have `set` of them out at once; one nobody steps in is gone after `lasts` seconds.
	TRAP = { reach = 2.4, hold = 5, set = 3, lasts = 300 },
	-- The firecracker: thrown `throw` studs ahead (short of a wall), it fizzes `fuse` seconds, then
	-- bangs for `bangs` seconds. Every hunter within `reach` studs of it goes to it and sees no one
	-- (nor hears anyone) till `blind` seconds after the first bang.
	FIRECRACKER = { throw = 26, fuse = 1.3, bangs = 5, reach = 120, blind = 7 },
	COOLDOWN = 0.8, -- seconds between using anything
	-- The seller: who he is (Config/Characters; out of the homeowners' cast), how he comes to the door
	-- (Homeowners.STYLES: already standing there in the dark hall), how near his door you have to be
	-- to buy, and what he says: opening the door (LINES; HURT if you're hurt), when you buy (THANKS, no
	-- more than one every THANKS_GAP seconds) and going back in (BYE if you bought something, SNUB if
	-- you didn't).
	SELLER = {
		CHARACTER = "Owner_BagMan",
		STYLE = "Waiting",
		RANGE = 16,
		THANKS_GAP = 4,
		BYE = { "Come back alive.", "Don't waste them.", "Mind the dark out there." },
		SNUB = { "Nothing? Your loss.", "Window shopping. Tonight of all nights.", "Don't come crying back." },
		THANKS = { "Pleasure.", "Use it well.", "Good choice.", "Mm. Careful with that.", "Sold." },
		HURT = {
			"You're bleeding on my step. Bandage?",
			"He got you, didn't he. I have just the thing.",
			"That looks bad. I can help, for a price.",
		},
		LINES = {
			"Candy for these. Everything has a price.",
			"Out late? You'll want something.",
			"Bandages, traps... a little noise. Take your pick.",
			"He's out there tonight. I'd buy something.",
			"Don't ask where I got them.",
		},
	},
}

-- What `itemId` costs on `neighborhoodId` (banked candy): its `doors` of the street's average door.
function Items.price(itemId: string, neighborhoodId: string): number
	local item = (Items :: any)[itemId] :: Item
	local street = Neighborhoods.byId[neighborhoodId]
	local door = if street then (street.candy.min + street.candy.max) / 2 else 5
	return math.max(1, math.round(item.doors * door))
end

-- Whether `itemId` is one of his.
function Items.sells(itemId: any): boolean
	return type(itemId) == "string" and table.find(Items.ORDER, itemId) ~= nil
end

return Items
