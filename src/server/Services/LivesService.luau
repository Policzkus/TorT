--!strict
-- Lives (PROMPT §V2.2/V2.3, Config/Lives). One comes back every REFILL_SECONDS of real time up to
-- MAX, counted while you're away too. You lose one caught by a homeowner (LivesService.faint:
-- everything goes black and you come to somewhere safe) or killed by the Knifer (LivesService.down:
-- no black screen, you drop as a ragdoll where you are, then wake at the spawn). Either way what's
-- in your bucket is gone. Out of lives, half your banked candy is lost and your lives refill.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lives = require(ReplicatedStorage.Shared.Config.Lives)
local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local RagdollService = require(script.Parent.RagdollService)

local LivesService = {}

local fainting: { [Player]: boolean } = {}

-- Gives back the lives that have come back since the last look (also the ones while away).
local function refill(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local lives, at = data.lives, data.livesRefillAt
	if lives < Lives.MAX then
		local now = os.time()
		if at == 0 then
			at = now + Lives.REFILL_SECONDS
		end
		while lives < Lives.MAX and now >= at do
			lives += 1
			at += Lives.REFILL_SECONDS
		end
	end
	if lives >= Lives.MAX then
		at = 0
	end
	if lives ~= data.lives then
		DataService.set(player, "lives", lives)
	end
	if at ~= data.livesRefillAt then
		DataService.set(player, "livesRefillAt", at)
	end
end

function LivesService.isFainting(player: Player): boolean
	return fainting[player] == true
end

-- What going down costs: a life and the carried bucket (out of lives: half the banked candy, then
-- they're all back). Returns the lives left and what was lost.
local function pay(player: Player, data: any): (number, number, number)
	local lostBucket = data.bucket
	DataService.set(player, "bucket", 0)
	DataService.mutate(player, "stats", function(stats)
		stats.caught += 1
	end)
	local lives = math.max(0, data.lives - 1)
	local lostBanked = 0
	if lives == 0 then
		lostBanked = math.floor(data.candy * Lives.OUT_OF_LIVES_CANDY_LOSS)
		DataService.set(player, "candy", data.candy - lostBanked)
		lives = Lives.MAX
		DataService.set(player, "livesRefillAt", 0)
	elseif data.livesRefillAt == 0 then
		DataService.set(player, "livesRefillAt", os.time() + Lives.REFILL_SECONDS)
	end
	DataService.set(player, "lives", lives)
	return lives, lostBucket, lostBanked
end

-- Caught. Pays for it (a life, the bucket); the character is held where it stands while the screen
-- goes black, and after Runs.FAINT_TIME they come to with their feet at `wakeAt` (nil: the spawn).
-- False if already out.
function LivesService.faint(player: Player, wakeAt: CFrame?): boolean
	local data = DataService.get(player)
	if data == nil or fainting[player] then
		return false
	end
	fainting[player] = true
	local lives, lostBucket, lostBanked = pay(player, data)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	if character then
		character:SetAttribute("Fainted", true) -- everyone sees them drop (CharacterAnimController)
	end
	Net.event("Fainted"):FireClient(player, lives, lostBucket, lostBanked, Runs.FAINT_TIME)
	task.delay(Runs.FAINT_TIME, function()
		fainting[player] = nil
		if player.Parent == Players then
			CharacterService.respawn(player, wakeAt)
		end
	end)
	return true
end

-- Killed out in the street (the Knifer). Pays the same as fainting, but no black screen: they're
-- thrown down as a ragdoll where they stand (`push`, studs/s), see it from their own eyes, and after
-- Runs.DOWN_TIME wake up at the spawn (a quick fade, RunController). False if already down.
function LivesService.down(player: Player, push: Vector3): boolean
	local data = DataService.get(player)
	if data == nil or fainting[player] then
		return false
	end
	fainting[player] = true
	local lives, lostBucket, lostBanked = pay(player, data)
	RagdollService.knock(player, push, Runs.DOWN_TIME + 1) -- still down when the new body comes
	Net.event("Downed"):FireClient(player, lives, lostBucket, lostBanked, Runs.DOWN_TIME)
	task.delay(Runs.DOWN_TIME, function()
		fainting[player] = nil
		if player.Parent == Players then
			CharacterService.respawn(player, nil)
		end
	end)
	return true
end

function LivesService.Start()
	Players.PlayerRemoving:Connect(function(player)
		fainting[player] = nil
	end)
	while true do
		for _, player in Players:GetPlayers() do
			refill(player)
		end
		task.wait(5)
	end
end

return LivesService
