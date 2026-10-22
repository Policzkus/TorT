--!strict
-- Gates (unlock streets with candy), the Spooky School Bus (teleports between unlocked zones),
-- and zone tracking: sets the "Zone" attribute on each player and pushes anyone back who walks
-- into a street they haven't unlocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local MinigameService = require(script.Parent.MinigameService)
local NotifyService = require(script.Parent.NotifyService)
local WorldService = require(script.Parent.WorldService)

local ZONE_INTERVAL = 0.3
local BUS_RANGE = 22

local NeighborhoodService = {}

local teleporting: { [Player]: boolean } = {}

function NeighborhoodService.isUnlocked(player: Player, neighborhoodId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.neighborhoods[neighborhoodId] == true
end

-- Moves the character, making sure the destination has streamed in first.
function NeighborhoodService.teleport(player: Player, destination: CFrame)
	local character = player.Character
	if character == nil or teleporting[player] then
		return
	end
	teleporting[player] = true
	MinigameService.cancel(player)
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, 5)
	end)
	if player.Character == character and character.Parent then
		character:PivotTo(destination)
		Net.event("Teleported"):FireClient(player)
	end
	teleporting[player] = nil
end

function NeighborhoodService.unlock(player: Player, neighborhoodId: string)
	local neighborhood = Neighborhoods.byId[neighborhoodId]
	local data = DataService.get(player)
	if neighborhood == nil or data == nil or not neighborhood.enabled then
		return
	end
	if data.neighborhoods[neighborhoodId] then
		return
	end
	if data.rebirths < neighborhood.unlock.rebirths then
		NotifyService.send(player, `☠ {neighborhood.name} needs Rebirth {neighborhood.unlock.rebirths}`, "error")
		return
	end
	local price = neighborhood.unlock.price
	if not CandyService.spend(player, price) then
		NotifyService.send(player, `You need {Format.number(price - data.candy)} more 🍬 in your Candy Box`, "error")
		return
	end
	DataService.mutate(player, "neighborhoods", function(owned)
		owned[neighborhoodId] = true
	end)
	Net.event("Celebrate"):FireClient(player, "unlock", { id = neighborhoodId, name = neighborhood.name })
	NotifyService.others(player, `🔓 {player.DisplayName} unlocked {neighborhood.name}!`, "info")
end

local function nearBus(position: Vector3): boolean
	for _, stop in WorldService.busStops() do
		if (stop.Position - position).Magnitude <= BUS_RANGE then
			return true
		end
	end
	return false
end

local function travel(player: Player, destination: any)
	if type(destination) ~= "string" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil or not nearBus(root.Position) then
		return
	end
	if
		destination ~= "Hub"
		and not (WorldService.isBuilt(destination) and NeighborhoodService.isUnlocked(player, destination))
	then
		return
	end
	local arrival = WorldService.arrival(destination)
	if arrival then
		NeighborhoodService.teleport(player, arrival)
	end
end

local function trackZones()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local data = DataService.get(player)
		if root == nil or data == nil or teleporting[player] then
			continue
		end
		local zone = WorldService.zoneAt(root.Position)
		if zone and player:GetAttribute("Zone") ~= zone then
			player:SetAttribute("Zone", zone)
		end
		-- Walked (or glitched) through a gate they don't own.
		for _, neighborhood in Neighborhoods.list do
			if
				not data.neighborhoods[neighborhood.id] and WorldService.isDeepInside(neighborhood.id, root.Position)
			then
				local front = WorldService.gateFront(neighborhood.id)
				if front then
					NotifyService.send(player, `🔒 Unlock {neighborhood.name} at the gate first!`, "error")
					task.spawn(NeighborhoodService.teleport, player, front)
				end
				break
			end
		end
	end
end

function NeighborhoodService.Start()
	local world = WorldService.info()
	for neighborhoodId, gate in world.gates do
		if gate.state == "locked" then
			for _, descendant in gate.model:GetDescendants() do
				if descendant:IsA("ProximityPrompt") then
					descendant.Triggered:Connect(function(player)
						NeighborhoodService.unlock(player, neighborhoodId)
					end)
				end
			end
		end
	end

	Net.connect("BusTravel", travel, { rate = 0.5, burst = 2 })
	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
	end)

	while true do
		task.wait(ZONE_INTERVAL)
		trackZones()
	end
end

return NeighborhoodService
