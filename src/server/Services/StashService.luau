--!strict
-- Stand in a Candy Box circle and your bucket pours into the bank (PROMPT §3.8).
-- Position checks are server-side; the client only plays the animation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local WorldService = require(script.Parent.WorldService)

local CHECK_INTERVAL = 0.2
local HEIGHT_TOLERANCE = 8

local StashService = {}

local fullWarned: { [Player]: boolean } = {}

local function dropoffNear(position: Vector3): string?
	for _, dropoff in WorldService.dropoffs() do
		local offset = position - dropoff.position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat <= Economy.STASH_RADIUS + 0.5 and math.abs(offset.Y) <= HEIGHT_TOLERANCE then
			return dropoff.id
		end
	end
	return nil
end

local function check(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if data == nil or root == nil or data.bucket <= 0 then
		return
	end
	local dropoffId = dropoffNear(root.Position)
	if dropoffId == nil then
		return
	end
	local moved, boxFull = CandyService.stash(player)
	if moved > 0 then
		Net.event("Stashed"):FireClient(player, moved, boxFull, dropoffId)
		if not boxFull then
			fullWarned[player] = nil
		end
	end
	if boxFull and not fullWarned[player] then
		fullWarned[player] = true
		NotifyService.send(
			player,
			"📦 Your Candy Box is FULL! Spend some candy to make room (Rebirth is coming soon)",
			"error"
		)
	end
end

function StashService.Start()
	Players.PlayerRemoving:Connect(function(player)
		fullWarned[player] = nil
	end)
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return StashService
