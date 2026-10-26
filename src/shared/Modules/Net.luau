--!strict
-- The single registry of every remote in the game.
-- Server: call Net.setup() first, then Net.connect / Net.handle to listen (rate-limited and error-isolated).
-- Client: Net.event(name) / Net.func(name) wait for the remote to exist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require(script.Parent.RateLimiter)

local FOLDER_NAME = "Remotes"
local IS_SERVER = RunService:IsServer()

-- name -> purpose. Direction: S→C server fires client, C→S client fires server.
local EVENTS: { [string]: string } = {
	StateSync = "S→C partial player-data snapshot: (changes: {[key]: value}, isFull: boolean)",
	StateRequest = "C→S ask for a full snapshot (sent once the client is listening)",
	Notify = "S→C toast: (text: string, kind: string?)",
	Celebrate = "S→C big moment banner: (kind: string, payload: table) e.g. 'unlock'",
	-- Doors and mini-games
	MinigameStart = "S→C play a mini-game: (challenge: {id, kind, difficulty, seed, context})",
	MinigameSubmit = "C→S raw input for a challenge: (id: number, taps: {number})",
	MinigameCancel = "C→S you walked away from the door: drop the challenge (id: number)",
	MinigameSkip = "C→S you skipped their hello: the game starts now (id: number)",
	HomeownerSay = "S→C a homeowner says a line, everyone near sees it: (houseId, text, showAt: server time, except: userId?)",
	HomeownerStrike = "S→C a homeowner slaps whoever got it wrong, everyone near sees it: (houseId, userId)",
	HomeownerGive = "S→C a homeowner hands someone their candy, everyone near sees it (a PERFECT: a clap first): (houseId, userId, grade)",
	LookPitch = "C→S how far up or down you're looking, so others see your head turn: (pitch: radians)",
	Crouch = "C→S you crouched or stood up, so others see it and the Knifer hears less: (on: boolean)",
	DoorKnocked = "S→C someone knocked on a door, everyone near hears it: (houseId, userId)",
	ScareSeen = "S→C someone got a scare at a door, everyone near sees it go for them: (houseId, userId, kind)",
	PlayerPop = "S→C a pop-up over a player's head for everyone else (a grade, a stash): (userId, text, kind)",
	-- The Knifer (KniferService)
	Downed = "S→C you're killed and down as a ragdoll, no black screen: (lostBucket, wakeIn)",
	KniferCame = "S→C the Knifer has come onto a street, everyone on it hears the sting: (streetId)",
	KniferStruck = "S→C the Knifer stabbed someone, everyone near hears it: (userId, dead: boolean)",
	-- A homeowner after a bowl thief (OwnerChaseService)
	OwnerGrab = "S→C a homeowner caught the kid who took their bowl and took their candy back, everyone sees it fly: (houseId, userId, lost, seed)",
	-- The car (TrafficService)
	CarTrip = "S→C a car drives down a street, everyone draws it on the same path: (trip: Traffic.Trip)",
	CarHit = "S→C the car hit someone, everyone sees the same candy fly: (userId, lost: number, seed: number)",
	CarHonk = "S→C the car honks at someone in front of it, everyone hears it: (tripId)",
	MinigameCancelled = "S→C your challenge was dropped, you left the door: (id: number)",
	DoorResult = "S→C candy from a door: (result: DoorService.DoorResult)",
	Jumpscare = "S→C play a scare: (houseId: string, kind: 'monster' | 'caught', line: string?)",
	SaveSettings = "C→S store the player's settings: (settings: {music, sfx, jumpscare, reduceFlash, psx, headBob})",
	-- Bucket and bank
	Stashed = "S→C bucket poured into the Candy Box: (moved: number, boxFull: boolean, dropoffId: string)",
	-- Travel
	BusTravel = "C→S ride the bus: (destination: 'Hub' | neighborhoodId)",
	Teleported = "S→C the character was just moved (fade back in)",
	-- Lobby parties and runs
	PartyLeave = "C→S get off the party bus you're on",
	PartyFriendsOnly = "C→S the host lets only their friends on board, or anyone: (on: boolean)",
	PartyStart = "C→S the host sends the bus off (a countdown, then the teleport)",
	RunLeave = "C→S leave the run and go back to the lobby",
	Fainted = "S→C you were caught: (lostBucket: number, wakeIn: number)",
}

local FUNCTIONS: { [string]: string } = {
	BuyUpgrade = "C→S buy the next level of a shop track: (trackId) -> (ok: boolean, message: string)",
	BuyCostume = "C→S buy a costume with candy and put it on: (costumeId) -> (ok: boolean, message: string)",
	EquipCostume = "C→S wear an owned costume ('' = take it off): (costumeId) -> (ok: boolean, message: string)",
	ChooseStarter = "C→S pick which starter kid you are: (starterId) -> (ok: boolean, message: string)",
}

type Options = {
	-- Sustained requests per second per player, and the burst allowed on top.
	rate: number?,
	burst: number?,
}

local DEFAULT_RATE = 10
local DEFAULT_BURST = 20

local Net = {}

local folder: Folder? = nil
local limiters: { RateLimiter.RateLimiter } = {}

local function getFolder(): Folder
	if folder then
		return folder
	end
	if IS_SERVER then
		error("Net.setup() must run before any remote is used on the server", 3)
	end
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	return folder :: Folder
end

local function getRemote(name: string, registry: { [string]: string }, className: string): Instance
	if registry[name] == nil then
		error(`Unknown remote '{name}' - add it to Net.luau first`, 3)
	end
	local remote = getFolder():WaitForChild(name, 15)
	if remote == nil or not remote:IsA(className) then
		error(`Remote '{name}' is missing or not a {className}`, 3)
	end
	return remote
end

-- Server only. Creates every remote; safe to call once at boot.
function Net.setup()
	assert(IS_SERVER, "Net.setup is server-only")
	if folder then
		return
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	for name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = newFolder
	end
	for name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = newFolder
	end
	newFolder.Parent = ReplicatedStorage
	folder = newFolder

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:clear(player)
		end
	end)
end

function Net.event(name: string): RemoteEvent
	return getRemote(name, EVENTS, "RemoteEvent") :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return getRemote(name, FUNCTIONS, "RemoteFunction") :: RemoteFunction
end

-- Server only. Rate-limited, pcall-wrapped OnServerEvent. Handlers must still validate every argument.
function Net.connect(name: string, handler: (player: Player, ...any) -> (), options: Options?): RBXScriptConnection
	assert(IS_SERVER, "Net.connect is server-only")
	local opts: Options = options or {}
	local limiter = RateLimiter.new(opts.rate or DEFAULT_RATE, opts.burst or DEFAULT_BURST)
	table.insert(limiters, limiter)
	return Net.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:allow(player) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] {name} handler error for {player.Name}: {err}`)
		end
	end)
end

-- Server only. Rate-limited, pcall-wrapped OnServerInvoke. Returns nil when limited or on error.
function Net.handle(name: string, handler: (player: Player, ...any) -> ...any, options: Options?)
	assert(IS_SERVER, "Net.handle is server-only")
	local opts: Options = options or {}
	local limiter = RateLimiter.new(opts.rate or DEFAULT_RATE, opts.burst or DEFAULT_BURST)
	table.insert(limiters, limiter)
	Net.func(name).OnServerInvoke = function(player: Player, ...)
		if not limiter:allow(player) then
			return nil
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(`[Net] {name} invoke error for {player.Name}: {results[2]}`)
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

return Net
