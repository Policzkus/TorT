--!strict
-- What the seller sells (the user: "Seller spawns in one of the houses (random), he sells lockpicks,
-- traps, (items that helps against mobs), bandage that gives u hp"). One stands at a random house on
-- every street, a different one each night (HouseService: house type "Seller"). Bought with banked
-- candy (Services/ItemService), kept between runs (PlayerData.consumables), used from the bar at the
-- bottom of the view (Controllers/ItemsController: keys 1-4, F for the flashlight).
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
	ORDER = { "Bandage", "BearTrap", "Firecracker", "Flashlight", "Lockpick" },

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
	-- The user: "it has to be realistic with battery that decreases. When battery runs out item is
	-- removed from your inventory." (FLASHLIGHT below; ItemService, Controllers/FlashlightController.)
	Flashlight = {
		name = "Flashlight",
		icon = "🔦",
		blurb = "F to switch it on and off. Its battery only runs down while it's on; dead, it's gone.",
		doors = 15,
		most = 2,
		key = "F",
		pad = "ButtonR3",
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
	-- The flashlight: `battery` seconds of light in a new one (it runs down only while it's on, and
	-- what's left is kept between runs: PlayerData.battery). Like a torch on real cells it dims as it
	-- goes: from full, slowly, going a little warmer, to `fade` of full when `low` is left; then fast
	-- (to `dimmest`, just before it dies) and yellow; under `flicker` it stutters, more and more. Left
	-- off a while, a tired battery picks up a little (`rest`: after `full` s off it's as if it had
	-- `gain` more charge, fading over `lasts` s once it's on again).
	-- Its light (the user: "it needs to be better more realistic"), from the lens: a bright `hotspot`
	-- (degrees across, brightness, studs; with shadows from yours) inside a dim, wide `corona`; the
	-- light that comes back off whatever it's pointed at (`bounce`: as bright as this at the lens,
	-- lighting `near`..`far` studs round the spot, nearer to further); the beam seen in the fog
	-- (`shaft`: how strong yours and anyone else's look, as far as `length` studs). Held in a hand it
	-- shakes a little (`tremor`, degrees: standing, walking, running) and trails your turns (`lag`).
	-- Pointed at your eyes (within `glare.cone` degrees, `glare.range` studs) it dazzles you.
	-- With it on, hunters see you from `seen` times as far, and a hiding place doesn't hide you: a
	-- light in the dark gives you away. `toggle`: seconds between switches.
	FLASHLIGHT = {
		battery = 240,
		low = 0.3,
		fade = 0.82,
		dimmest = 0.3,
		flicker = 0.15,
		rest = { full = 30, lasts = 8, gain = 0.06 },
		hotspot = { angle = 22, brightness = 3.4, range = 62 },
		corona = { angle = 70, brightness = 0.5, range = 30 },
		bounce = { brightness = 0.9, near = 7, far = 15 },
		shaft = { yours = 0.05, theirs = 0.14, length = 34 },
		tremor = { still = 0.22, moving = 0.6, running = 1.5 },
		lag = 13,
		glare = { range = 45, cone = 10 },
		seen = 1.35,
		toggle = 0.25,
	},
	COOLDOWN = 0.8, -- seconds between using anything (the flashlight aside)
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
			"Batteries don't last. Nothing does.",
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
