--!strict
-- Health (Config/Health; it took the place of the three lives). Each player's "Health" attribute is
-- theirs (the HUD shows it): MAX to start with and with every new body, down when the Knifer stabs
-- you (HealthService.hurt), back a little a second a while after you were last hurt. Down to nothing
-- and you're dead (HealthService.down: no black screen, you drop as a ragdoll where you are, then
-- wake at the spawn). Caught by a homeowner (HealthService.faint, the admin's /faint): everything
-- goes black and you come to somewhere safe. Either way what's in your bucket is gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Health = require(ReplicatedStorage.Shared.Config.Health)
local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local RagdollService = require(script.Parent.RagdollService)

local HealthService = {}

local ATTRIBUTE = "Health"
local TICK = 0.25

local fainting: { [Player]: boolean } = {}
local hurtAt: { [Player]: number } = {}

local function set(player: Player, value: number)
	player:SetAttribute(ATTRIBUTE, math.clamp(value, 0, Health.MAX))
end

-- `player`'s health now (0..Health.MAX).
function HealthService.get(player: Player): number
	local value = player:GetAttribute(ATTRIBUTE)
	return if type(value) == "number" then value else Health.MAX
end

function HealthService.isFainting(player: Player): boolean
	return fainting[player] == true
end

-- What going down costs: the carried bucket. Returns how much was in it.
local function pay(player: Player, data: any): number
	local lost = data.bucket
	DataService.set(player, "bucket", 0)
	DataService.mutate(player, "stats", function(stats)
		stats.caught += 1
	end)
	return lost
end

-- A new body, with all its health, its feet at `feet` (nil: the spawn).
local function wake(player: Player, feet: CFrame?)
	fainting[player] = nil
	hurtAt[player] = nil
	if player.Parent == Players then
		set(player, Health.MAX)
		CharacterService.respawn(player, feet)
	end
end

-- Caught. Pays for it (the bucket); the character is held where it stands while the screen goes
-- black, and after Runs.FAINT_TIME they come to with their feet at `wakeAt` (nil: the spawn).
-- False if already out.
function HealthService.faint(player: Player, wakeAt: CFrame?): boolean
	local data = DataService.get(player)
	if data == nil or fainting[player] then
		return false
	end
	fainting[player] = true
	local lost = pay(player, data)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	if character then
		character:SetAttribute("Fainted", true) -- everyone sees them drop (CharacterAnimController)
	end
	Net.event("Fainted"):FireClient(player, lost, Runs.FAINT_TIME)
	task.delay(Runs.FAINT_TIME, wake, player, wakeAt)
	return true
end

-- Dead, out in the street (the Knifer's second stab). No black screen: they're thrown down as a
-- ragdoll where they stand (`push`, studs/s), see it from their own eyes, and after Runs.DOWN_TIME
-- wake up at the spawn (a quick fade, RunController). False if already down.
function HealthService.down(player: Player, push: Vector3): boolean
	local data = DataService.get(player)
	if data == nil or fainting[player] then
		return false
	end
	fainting[player] = true
	set(player, 0)
	local lost = pay(player, data)
	RagdollService.knock(player, push, Runs.DOWN_TIME + 1) -- still down when the new body comes
	Net.event("Downed"):FireClient(player, lost, Runs.DOWN_TIME)
	task.delay(Runs.DOWN_TIME, wake, player, nil)
	return true
end

-- Takes `amount` off `player`'s health. Down to nothing and they're dead (HealthService.down, thrown
-- with `push`). "hurt" or "dead", or nil if they can't be hurt now (out already).
function HealthService.hurt(player: Player, amount: number, push: Vector3): ("hurt" | "dead")?
	if fainting[player] or DataService.get(player) == nil then
		return nil
	end
	local left = HealthService.get(player) - amount
	if left <= 0 then
		return if HealthService.down(player, push) then "dead" else nil
	end
	set(player, left)
	hurtAt[player] = os.clock()
	return "hurt"
end

-- All of it back (the admin's /heal).
function HealthService.heal(player: Player)
	set(player, Health.MAX)
end

function HealthService.Start()
	Players.PlayerAdded:Connect(function(player)
		set(player, Health.MAX)
	end)
	for _, player in Players:GetPlayers() do
		set(player, HealthService.get(player))
	end
	Players.PlayerRemoving:Connect(function(player)
		fainting[player] = nil
		hurtAt[player] = nil
	end)
	-- Coming back, a while after the last hurt.
	while true do
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local health = HealthService.get(player)
			if
				health < Health.MAX
				and not fainting[player]
				and now - (hurtAt[player] or -math.huge) >= Health.REGEN.delay
			then
				set(player, health + Health.REGEN.rate * TICK)
			end
		end
		task.wait(TICK)
	end
end

return HealthService
