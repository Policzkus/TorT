--!strict
-- Knock on a door → mini-game → candy into the bucket → per-player cooldown on that house.
-- Also the candy bowls (Config/Bowl): take the lot, the porch lamp bursts, and maybe the homeowner
-- comes out after you (OwnerChaseService).
-- And the seller (Config/Items): knock at his door and he comes to it like any homeowner (the same
-- figure and walk, HomeownerService), says something, and once he's out your window of his things
-- opens (SellerOpen; ItemService sells). Close it (SellerDone) or walk off and he says goodbye and
-- goes back in. No mini-game, no candy, no cooldown; a full bucket can still knock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Dialogue = require(ReplicatedStorage.Shared.Config.Dialogue)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local HouseTypes = require(ReplicatedStorage.Shared.Config.HouseTypes)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Minigames = require(ReplicatedStorage.Shared.Config.Minigames)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local HomeownerService = require(script.Parent.HomeownerService)
local HouseService = require(script.Parent.HouseService)
local MinigameService = require(script.Parent.MinigameService)
local NotifyService = require(script.Parent.NotifyService)
local OwnerChaseService = require(script.Parent.OwnerChaseService)
local WorldEventsService = require(script.Parent.WorldEventsService)
local WorldService = require(script.Parent.WorldService)

export type DoorResult = {
	houseId: string,
	grade: string,
	amount: number, -- candy the door gave
	added: number, -- what fit in the bucket
	overflow: number, -- what was lost to a full bucket
	cooldownUntil: number, -- workspace:GetServerTimeNow() when the door is ready again
	houseType: string,
	streak: number, -- Sweet Streak after this door
	brave: boolean, -- held through a trick house's Nerve Hold
	fullSize: boolean, -- got the Full-Size Bar ×10
	event: number, -- event multiplier applied (Witching Hour, Blood Moon)
	liked: boolean?, -- the homeowner's preference matched your costume's tag
	costumed: boolean?, -- false: no costume, so the homeowner barely gave anything
	bowl: boolean?, -- took candy from a bowl
	bowlLeft: number?, -- what's still in it
}

-- Goodbyes a homeowner picks from going back in, by how the visit went (HomeownerController.GOODBYES).
local GOODBYES = { pleased = { "wave", "bow", "nod" }, displeased = { "point", "shoo", "stare" } }

local DoorService = {}

local houseReadyAt: { [string]: number } = {} -- each house's: when it answers again (server time)
local darkKnocks: { [string]: number } = {} -- when someone last knocked at a dark house (os.clock)
local DARK_KNOCK_GAP = 1.2 -- seconds: knocks at a dark house closer together than this aren't heard
local streaks: { [Player]: number } = {}
local browsing: { [Player]: string } = {} -- at the seller's door, his window open: which house
local random = Random.new()
local rng = Rng.new(random:NextInteger(1, 2147483646))

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function pickMinigame(neighborhood: Neighborhoods.Neighborhood, houseType: string): string
	if houseType == "Trick" then
		return "NerveHold" -- trick houses always test your nerve
	end
	local weights = {}
	for kind, weight in neighborhood.minigames do
		if MinigameService.isAvailable(kind) then
			weights[kind] = weight
		end
	end
	return rng:weighted(weights) or "TimingBar"
end

-- A house's cooldown is everyone's (the user wants it synced): once its homeowner has answered, or
-- its bowl's been raided, nobody gets anything there until it's over. It's on the house model
-- (ReadyAt, server time), so every client draws the same ring.
local function cooldownLeft(houseId: string): number
	return math.max(0, (houseReadyAt[houseId] or 0) - now())
end

-- `after`: seconds before the cooldown starts counting (a visit's: until the door's shut again).
local function startCooldown(houseId: string, after: number?): number
	local at = math.max(houseReadyAt[houseId] or 0, now() + (after or 0) + Economy.DOOR_COOLDOWN)
	houseReadyAt[houseId] = at
	local house = WorldService.getHouse(houseId)
	if house then
		house.model:SetAttribute("ReadyAt", at)
	end
	return at
end

-- A pop-up over the player's head for everyone else (Controllers/PeersController).
local function pop(player: Player, text: string, kind: string)
	Net.event("PlayerPop"):FireAllClients(player.UserId, text, kind)
end

local function nearHouse(player: Player, houseId: string, range: number?): boolean
	local house = WorldService.getHouse(houseId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return house ~= nil
		and root ~= nil
		and (root.Position - house.door.Position).Magnitude <= (range or Economy.DOOR_RANGE)
end

-- Shared checks for knocking and bowls. Returns the house and its street config if allowed.
local function canVisit(player: Player, houseId: string): (any, Neighborhoods.Neighborhood?)
	local house = WorldService.getHouse(houseId)
	local data = DataService.get(player)
	if house == nil or data == nil or not data.neighborhoods[house.neighborhood] then
		return nil, nil
	end
	if MinigameService.isBusy(player) or not nearHouse(player, houseId) then
		return nil, nil
	end
	-- A full bucket takes no more: empty it at your Candy Box first. (You were told when it filled
	-- up, CandyService, and the doors say so: DoorController.)
	if data.bucket >= CandyService.bucketCapacity(player) then
		return nil, nil
	end
	local wait = cooldownLeft(houseId)
	if wait > 0 then
		NotifyService.send(player, `💤 Nobody's answering yet. Come back in {math.ceil(wait)}s`, "info")
		return nil, nil
	end
	return house, Neighborhoods.byId[house.neighborhood]
end

-- The homeowner at `houseId` says `text` in `after` seconds, for everyone near the door to see
-- (DoorController); `except` sees it some other way (the Costume Line question, with its answers).
local function say(houseId: string, text: string, after: number, except: Player?)
	Net.event("HomeownerSay"):FireAllClients(houseId, text, now() + after, if except then except.UserId else nil)
end

-- One of the house's personality's lines of a kind ("hello", "pleased", "displeased").
local function line(houseId: string, kind: string): string?
	local personality = Dialogue.personalities[HouseService.owner(houseId) :: string]
	local lines = personality and (personality :: any)[kind]
	return if type(lines) == "table" and #lines > 0 then lines[random:NextInteger(1, #lines)] else nil
end

local function updateStreak(player: Player, grade: string): number
	local streak = streaks[player] or 0
	if Formulas.isGoodGrade(grade) then
		streak += 1
	elseif grade == "MISS" then
		streak = 0
	end
	streaks[player] = streak
	return streak
end

-- The visit's over with `grade`: candy, the cooldown, what they say. Returns how long until the
-- homeowner may go back in (they wait out what they say), or nil for the usual LEAVE_DELAY.
local function finish(player: Player, houseId: string, houseType: string, grade: string?): number?
	if grade == nil or player.Parent ~= Players then
		return nil -- abandoned: no reward, no cooldown, they can knock again
	end
	local house = WorldService.getHouse(houseId)
	local neighborhood = house and Neighborhoods.byId[house.neighborhood]
	if house == nil or neighborhood == nil or DataService.get(player) == nil then
		return nil
	end
	-- What they'll make of it (a trick house's Nerve Hold ends in the jumpscare instead), and so how
	-- long they stay out: until it's been said and gone, never less than LEAVE_DELAY.
	local slapped = grade == "MISS" and houseType ~= "Trick"
	local reaction = if houseType ~= "Trick"
		then line(houseId, if grade == "MISS" then "displeased" else "pleased")
		else nil
	local sayIn = if slapped then Homeowners.SLAP_LANDS + 0.25 else 0.35
	local leaveIn = if reaction
		then math.max(Homeowners.LEAVE_DELAY, sayIn + Dialogue.lineTime(reaction) + Homeowners.AFTER_LINE)
		else Homeowners.LEAVE_DELAY

	local brave = houseType == "Trick" and grade ~= "MISS"
	local typeMultiplier = if houseType == "Trick"
		then (if brave then HouseTypes.CANDY.Trick else 1)
		else HouseTypes.CANDY[houseType] or 1
	local fullSize = WorldEventsService.claimFullSize(player, houseId)
	local streak = updateStreak(player, grade)
	local event = CandyService.eventMultiplier(player)
	local base = random:NextNumber(neighborhood.candy.min, neighborhood.candy.max) * typeMultiplier * fullSize
	local bonuses = CandyService.bonuses(player)
	local costume = CandyService.costume(player)
	local liked = costume ~= nil and costume.tag == HouseService.preference(houseId)
	if liked then
		bonuses.preference = HouseTypes.PREFERENCE_BONUS
	end
	local amount = Formulas.doorCandy(base, grade, Formulas.streakBonus(streak), bonuses, event)
	local added, overflow = CandyService.addToBucket(player, amount)
	-- The door's cooldown (the ring on it) counts from when it shuts on them, not from now.
	local readyAt = startCooldown(houseId, leaveIn + Homeowners.SHUT_AFTER)

	DataService.mutate(player, "stats", function(stats)
		stats.doors += 1
		if grade == "PERFECT" then
			stats.perfects += 1
		end
		stats.bestStreak = math.max(stats.bestStreak, streak)
	end)

	local result: DoorResult = {
		houseId = houseId,
		grade = grade,
		amount = amount,
		added = added,
		overflow = overflow,
		cooldownUntil = readyAt,
		houseType = houseType,
		streak = streak,
		brave = brave,
		fullSize = fullSize > 1,
		event = event,
		liked = liked,
		costumed = costume ~= nil,
	}
	Net.event("DoorResult"):FireClient(player, result)
	pop(player, `{grade}  +{Format.number(added)}`, grade)
	-- What they make of it, for everyone near: get it wrong and they slap you first, then tell you off;
	-- get it right and they hand you your candy. Their goodbye going back in follows from it (OwnerMood).
	if houseType ~= "Trick" then
		local mood = if grade == "MISS" then "displeased" else "pleased"
		local byes = GOODBYES[mood]
		house.model:SetAttribute("OwnerMood", mood)
		house.model:SetAttribute("OwnerBye", byes[random:NextInteger(1, #byes)])
	end
	if slapped then
		Net.event("HomeownerStrike"):FireAllClients(houseId, player.UserId)
	elseif houseType ~= "Trick" then
		Net.event("HomeownerGive"):FireAllClients(houseId, player.UserId, grade) -- (a PERFECT gets a slow clap first)
	end
	if reaction then
		say(houseId, reaction, sayIn)
	end
	if fullSize > 1 then
		NotifyService.others(player, `🍫 {player.DisplayName} grabbed a FULL-SIZE BAR!`, "rare")
	end
	return leaveIn
end

-- Done at the seller's: he says goodbye and goes back in once it's said (and nobody else is there).
local function sellerDone(player: Player, houseId: any)
	if browsing[player] ~= houseId then
		return
	end
	browsing[player] = nil
	local house = WorldService.getHouse(houseId)
	local bye = Items.SELLER.BYE[random:NextInteger(1, #Items.SELLER.BYE)]
	if house then
		house.model:SetAttribute("OwnerMood", "pleased")
		house.model:SetAttribute("OwnerBye", GOODBYES.pleased[random:NextInteger(1, #GOODBYES.pleased)])
	end
	say(houseId, bye, 0.2)
	HomeownerService.leave(
		houseId,
		math.max(Homeowners.LEAVE_DELAY, 0.2 + Dialogue.lineTime(bye) + Homeowners.AFTER_LINE)
	)
end

-- Knocked at the seller's: he comes to the door, says something, and your window opens once he's
-- out. Walk off and he goes back in.
local function sellerVisit(player: Player, houseId: string)
	if browsing[player] == houseId or MinigameService.isBusy(player) or not nearHouse(player, houseId) then
		return
	end
	local previous = browsing[player]
	if previous then
		sellerDone(player, previous)
	end
	Net.event("DoorKnocked"):FireAllClients(houseId, player.UserId) -- everyone near hears it
	local outIn = HomeownerService.appear(houseId, player, Items.SELLER.STYLE)
	browsing[player] = houseId
	local lines = Items.SELLER.LINES
	say(houseId, lines[random:NextInteger(1, #lines)], outIn + 0.3)
	task.delay(outIn, function()
		if browsing[player] == houseId then
			Net.event("SellerOpen"):FireClient(player, houseId)
		end
	end)
	task.spawn(function()
		while browsing[player] == houseId do
			if
				player.Parent ~= Players
				or not nearHouse(player, houseId, Economy.DOOR_LEAVE)
				or HouseService.houseType(houseId) ~= "Seller" -- a new night: he's moved on
			then
				sellerDone(player, houseId)
				break
			end
			task.wait(0.25)
		end
	end)
end

local function knock(player: Player, houseId: string)
	local houseType = HouseService.houseType(houseId)
	if houseType == "Seller" then
		sellerVisit(player, houseId)
		return
	end
	if houseType == "LightsOff" then
		-- A dark house: you can knock (everyone near hears it), but nobody comes.
		local last = darkKnocks[houseId]
		if nearHouse(player, houseId) and (last == nil or os.clock() - last >= DARK_KNOCK_GAP) then
			darkKnocks[houseId] = os.clock()
			Net.event("DoorKnocked"):FireAllClients(houseId, player.UserId)
		end
		return
	end
	if houseType == "Bowl" or houseType == "Open" or OwnerChaseService.away(houseId) then
		return -- nobody answers (or they're out after someone)
	end
	local house, neighborhood = canVisit(player, houseId)
	if house == nil or neighborhood == nil then
		return
	end
	Net.event("DoorKnocked"):FireAllClients(houseId, player.UserId) -- everyone near hears it
	local difficulty = neighborhood.tier
		+ (HouseTypes.DIFFICULTY[houseType] or 0)
		+ WorldEventsService.difficultyBonus()
	difficulty = math.clamp(difficulty, Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local kind = pickMinigame(neighborhood, houseType)
	-- They come out and say hello before the mini-game starts (Costume Line's question is its
	-- hello): the challenge's intro, which the client plays out and the clock leaves out.
	local outIn = HomeownerService.appear(houseId, player)
	local intro = outIn + (if kind == "CostumeLine" then 0 else Homeowners.HELLO_TIME)
	local context = {
		houseId = houseId,
		personality = HouseService.owner(houseId),
		houseType = houseType,
		outIn = outIn,
		door = house.door.Position, -- the client calls the visit off if you walk away from it
	}
	local issued = MinigameService.issue(player, kind, difficulty, function(grade)
		local leaveIn = finish(player, houseId, houseType, grade)
		HomeownerService.leave(houseId, leaveIn) -- once what they've said has gone
		-- Every Nerve Hold ends with the jumpscare (the client tones it down per Settings).
		if grade and kind == "NerveHold" then
			Net.event("Jumpscare"):FireClient(player, houseId, "monster")
			Net.event("ScareSeen"):FireAllClients(houseId, player.UserId, "monster")
		end
	end, context, intro)
	if issued == nil then
		HomeownerService.leave(houseId)
		return
	end
	-- Their hello once they're out, for everyone near. In Costume Line the question is the hello: the
	-- visitor gets it with its answers, everyone else hears it asked.
	if kind == "CostumeLine" then
		local spec = MinigameService.specOf(player)
		if spec and type(spec.greeting) == "string" then
			say(houseId, spec.greeting, outIn, player)
		end
	else
		local hello = line(houseId, "hello")
		if hello then
			say(houseId, hello, outIn + 0.3)
		end
	end
	-- Walk away while they're coming out, or mid-game, and it's off (the client usually says so first).
	task.spawn(function()
		while MinigameService.isOpen(player, issued.id) do
			if not nearHouse(player, houseId, Economy.DOOR_LEAVE) then
				MinigameService.cancel(player)
				Net.event("MinigameCancelled"):FireClient(player, issued.id)
				break
			end
			task.wait(0.25)
		end
	end)
end

-- Someone held the bowl's prompt through: they get as much of what's in it as their bucket holds
-- (the rest stays for whoever comes next, or for them once they've emptied their bucket). The first
-- time, the porch lamp bursts for everyone to see (LampBroken, the server time it went; LampBrokenBy,
-- who did it: HouseVisualController). Every time, maybe the homeowner comes out after them
-- (OwnerChaseService).
local function takeFromBowl(player: Player, houseId: string)
	if HouseService.houseType(houseId) ~= "Bowl" then
		return
	end
	local left = HouseService.bowlCandy(houseId)
	if left <= 0 then
		NotifyService.send(player, "The bowl's empty. Somebody beat you to it", "info")
		return
	end
	local house, neighborhood = canVisit(player, houseId)
	local data = DataService.get(player)
	if house == nil or neighborhood == nil or data == nil then
		return
	end
	local room = math.max(0, CandyService.bucketCapacity(player) - data.bucket)
	local added = CandyService.addToBucket(player, math.min(left, room))
	if added <= 0 then
		return
	end
	HouseService.takeFromBowl(houseId, added)
	local result: DoorResult = {
		houseId = houseId,
		grade = "PERFECT",
		amount = added,
		added = added,
		overflow = 0,
		cooldownUntil = 0,
		houseType = "Bowl",
		streak = streaks[player] or 0,
		brave = false,
		fullSize = false,
		event = 1,
		bowl = true,
		bowlLeft = left - added,
	}
	Net.event("DoorResult"):FireClient(player, result)
	pop(player, `+{Format.number(added)}`, result.grade)
	if house.model:GetAttribute("LampBroken") == nil then
		house.model:SetAttribute("LampBrokenBy", player.UserId)
		house.model:SetAttribute("LampBroken", now())
	end
	OwnerChaseService.raid(player, houseId)
end

function DoorService.resetCooldowns()
	for houseId in houseReadyAt do
		local house = WorldService.getHouse(houseId)
		if house then
			house.model:SetAttribute("ReadyAt", 0)
		end
	end
	table.clear(houseReadyAt)
end

function DoorService.streak(player: Player): number
	return streaks[player] or 0
end

function DoorService.Start()
	for houseId, house in WorldService.info().houses do
		house.prompt.Triggered:Connect(function(player)
			knock(player, houseId)
		end)
	end
	HouseService.BowlTriggered:Connect(takeFromBowl)
	Net.connect("SellerDone", sellerDone, { rate = 2, burst = 4 })

	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
	end)
end

return DoorService
