--!strict
-- Server side of the door mini-games (PROMPT §5.5). The server issues a challenge
-- {id, kind, difficulty, seed}; the client plays it and returns raw tap times; the server
-- re-simulates from the seed to grade it. Bad input never errors: it just grades as MISS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minigames = require(ReplicatedStorage.Shared.Config.Minigames)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Games = ReplicatedStorage.Shared.Modules.Minigames

-- Every mini-game rules module has the same shape (generate / grade / validInput).
type Rules = {
	generate: (seed: number, difficulty: number, context: any?) -> any,
	grade: (spec: any, input: { number }) -> (string, { string }),
	validInput: (spec: any, input: any, elapsed: number) -> boolean,
}

-- Mini-games that exist. Others in a neighborhood's weights are skipped until built.
local KINDS: { [string]: Rules } = {
	TimingBar = require(Games.TimingBar) :: any,
	KnockRhythm = require(Games.KnockRhythm) :: any,
	NerveHold = require(Games.NerveHold) :: any,
	CostumeLine = require(Games.CostumeLine) :: any,
}

export type Challenge = {
	id: number,
	kind: string,
	difficulty: number,
	seed: number,
	context: { [string]: any }?,
	intro: number, -- seconds before the game starts (the homeowner coming out, their hello)
}

type Pending = {
	challenge: Challenge,
	spec: any,
	issuedAt: number,
	onResult: (grade: string?) -> (),
}

-- Statistical outlier logging only (no bans at launch, PROMPT §5.5).
local SUSPICIOUS_SAMPLE = 50
local SUSPICIOUS_PERFECT_RATE = 0.9

local MinigameService = {}

local pending: { [Player]: Pending } = {}
local history: { [Player]: { total: number, perfect: number, flagged: boolean } } = {}
local random = Random.new()
local nextId = 0

function MinigameService.isAvailable(kind: string): boolean
	return KINDS[kind] ~= nil
end

function MinigameService.isBusy(player: Player): boolean
	return pending[player] ~= nil
end

-- Drops the player's open challenge without a result (e.g. they left or teleported).
function MinigameService.cancel(player: Player)
	local open = pending[player]
	pending[player] = nil
	if open then
		task.spawn(open.onResult, nil)
	end
end

local function record(player: Player, grade: string)
	local stats = history[player]
	if stats == nil then
		stats = { total = 0, perfect = 0, flagged = false }
		history[player] = stats
	end
	stats.total += 1
	if grade == "PERFECT" then
		stats.perfect += 1
	end
	if not stats.flagged and stats.total >= SUSPICIOUS_SAMPLE then
		if stats.perfect / stats.total > SUSPICIOUS_PERFECT_RATE then
			stats.flagged = true
			warn(`[AntiCheat] {player.Name} ({player.UserId}) PERFECT rate {stats.perfect}/{stats.total}`)
		end
	end
end

-- Starts a mini-game for the player. `onResult(grade)` gets "MISS".."PERFECT", or nil if the
-- challenge was abandoned or cancelled. `intro` seconds go first (the homeowner coming out and
-- saying hello): the client starts the game after them, and so does the clock.
function MinigameService.issue(
	player: Player,
	kind: string,
	difficulty: number,
	onResult: (grade: string?) -> (),
	context: { [string]: any }?,
	intro: number?
): Challenge?
	local rules = KINDS[kind]
	if rules == nil then
		warn(`[Minigame] '{kind}' is not implemented`)
		return nil
	end
	MinigameService.cancel(player)
	nextId += 1
	local challenge: Challenge = {
		id = nextId,
		kind = kind,
		difficulty = difficulty,
		seed = random:NextInteger(1, 2147483646),
		context = context,
		intro = intro or 0,
	}
	local spec = rules.generate(challenge.seed, difficulty, context)
	local lead = intro or 0
	pending[player] = { challenge = challenge, spec = spec, issuedAt = os.clock() + lead, onResult = onResult }
	Net.event("MinigameStart"):FireClient(player, challenge)

	task.delay(lead + spec.timeout + Minigames.EXPIRE_GRACE, function()
		local open = pending[player]
		if open and open.challenge.id == challenge.id then
			pending[player] = nil
			onResult(nil)
		end
	end)
	return challenge
end

function MinigameService.Start()
	Net.connect("MinigameSubmit", function(player: Player, id: any, taps: any)
		local open = pending[player]
		if open == nil or open.challenge.id ~= id then
			return
		end
		pending[player] = nil
		local rules = KINDS[open.challenge.kind]
		local elapsed = os.clock() - open.issuedAt
		local grade = "MISS"
		if rules.validInput(open.spec, taps, elapsed) then
			grade = rules.grade(open.spec, taps)
		else
			warn(`[AntiCheat] {player.Name} sent invalid {open.challenge.kind} input`)
		end
		record(player, grade)
		open.onResult(grade)
	end, { rate = 4, burst = 6 })

	Players.PlayerRemoving:Connect(function(player)
		MinigameService.cancel(player)
		history[player] = nil
	end)
end

return MinigameService
