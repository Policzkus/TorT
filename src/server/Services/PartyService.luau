--!strict
-- The lobby's party buses (PROMPT §V2.2). Get on one (its door's prompt) and you're sat in it, on a
-- party of up to Runs.PARTY_MAX: the first aboard hosts. The host can let only their friends on,
-- and sends the bus off: a countdown, then the whole party is teleported to its own reserved
-- server of this place for one Night (Modules/Mode makes that server a run). Standing up, the
-- host leaving, someone leaving the game all do what you'd expect. Clients draw it from each bus's
-- attributes: Host (UserId, 0 = empty), Members ("id,id"), FriendsOnly, DepartAt (server time; 0 =
-- parked).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local LivesService = require(script.Parent.LivesService)
local NotifyService = require(script.Parent.NotifyService)
local WorldService = require(script.Parent.WorldService)

local PartyService = {}

type Party = {
	bus: Model,
	seats: { Seat },
	members: { Player },
	host: Player?,
	friendsOnly: boolean,
	departing: boolean,
	trip: number, -- counts departures (a countdown checks it's still the same one)
}

local partyOf: { [Player]: Party } = {}
local seatedWatch: { [Player]: RBXScriptConnection } = {}

local function publish(party: Party)
	local ids = {}
	for _, member in party.members do
		table.insert(ids, tostring(member.UserId))
	end
	party.bus:SetAttribute("Host", if party.host then party.host.UserId else 0)
	party.bus:SetAttribute("Members", table.concat(ids, ","))
	party.bus:SetAttribute("FriendsOnly", party.friendsOnly)
	party.bus:SetAttribute("DepartAt", if party.departing then party.bus:GetAttribute("DepartAt") or 0 else 0)
end

local function cancelTrip(party: Party)
	party.departing = false
	party.trip += 1
	party.bus:SetAttribute("DepartAt", 0)
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Off the bus (`standUp`: out of the seat too, when they asked to get off).
local function leave(player: Player, standUp: boolean?)
	local party = partyOf[player]
	if party == nil then
		return
	end
	partyOf[player] = nil
	local watch = seatedWatch[player]
	if watch then
		watch:Disconnect()
		seatedWatch[player] = nil
	end
	local index = table.find(party.members, player)
	if index then
		table.remove(party.members, index)
	end
	local humanoid = humanoidOf(player)
	if standUp and humanoid and humanoid.SeatPart and table.find(party.seats, humanoid.SeatPart :: Seat) then
		humanoid.Sit = false
	end
	if party.host == player then
		party.host = party.members[1]
		if party.departing then
			cancelTrip(party) -- the new host decides when to go
		end
	end
	if #party.members == 0 then
		party.friendsOnly = false
		cancelTrip(party)
	end
	publish(party)
end

local function friends(player: Player, host: Player): boolean
	local ok, result = pcall(player.IsFriendsWith, player, host.UserId)
	return ok and result == true
end

local function board(player: Player, party: Party)
	if partyOf[player] == party or LivesService.isFainting(player) then
		return
	end
	if party.departing then
		NotifyService.send(player, "This bus is leaving.", "error")
		return
	end
	if #party.members >= Runs.PARTY_MAX then
		NotifyService.send(player, "This bus is full.", "error")
		return
	end
	local host = party.host
	if party.friendsOnly and host and not friends(player, host) then
		NotifyService.send(player, `Only {host.DisplayName}'s friends can get on this bus.`, "error")
		return
	end
	local humanoid = humanoidOf(player)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local free: Seat? = nil
	for _, seat in party.seats do
		if seat.Occupant == nil then
			free = seat
			break
		end
	end
	if free == nil then
		return
	end
	leave(player) -- off any other bus first
	table.insert(party.members, player)
	partyOf[player] = party
	if party.host == nil then
		party.host = player
	end
	free:Sit(humanoid)
	seatedWatch[player] = humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
		if not active or seatPart == nil or not table.find(party.seats, seatPart :: Seat) then
			leave(player)
		end
	end)
	publish(party)
end

-- The party is off: a server of its own, and everyone on it there together.
local function depart(party: Party)
	local players = table.clone(party.members)
	if #players == 0 then
		cancelTrip(party)
		return
	end
	if RunService:IsStudio() then
		for _, player in players do
			NotifyService.send(
				player,
				'Studio can\'t teleport: set Game.STUDIO_MODE to "run" to play the streets.',
				"info"
			)
		end
		cancelTrip(party)
		publish(party)
		return
	end
	local reserved, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not reserved then
		warn(`[Party] couldn't reserve a server: {code}`)
		for _, player in players do
			NotifyService.send(player, "The bus wouldn't start. Try again in a moment.", "error")
		end
		cancelTrip(party)
		publish(party)
		return
	end
	local ids = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData({ party = ids })
	for try = 1, Runs.TELEPORT_TRIES do
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, players, options)
		if ok then
			return -- they leave this server as they arrive at theirs (PlayerRemoving takes them off the bus)
		end
		warn(`[Party] teleport failed ({try}/{Runs.TELEPORT_TRIES}): {err}`)
		task.wait(2)
	end
	for _, player in players do
		NotifyService.send(player, "The bus broke down on the way. Try again.", "error")
	end
	cancelTrip(party)
	publish(party)
end

local function start(player: Player)
	local party = partyOf[player]
	if party == nil or party.host ~= player or party.departing then
		return
	end
	party.departing = true
	party.trip += 1
	local trip = party.trip
	party.bus:SetAttribute("DepartAt", Workspace:GetServerTimeNow() + Runs.COUNTDOWN)
	publish(party)
	task.delay(Runs.COUNTDOWN, function()
		if party.departing and party.trip == trip then
			depart(party)
		end
	end)
end

function PartyService.Start()
	for _, bus in WorldService.info().buses do
		local seats = {}
		local folder = bus:FindFirstChild("Seats")
		for k = 1, Runs.PARTY_MAX do
			local seat = folder and folder:FindFirstChild("Seat" .. k)
			if seat and seat:IsA("Seat") then
				table.insert(seats, seat)
			end
		end
		local party: Party = {
			bus = bus,
			seats = seats,
			members = {},
			host = nil,
			friendsOnly = false,
			departing = false,
			trip = 0,
		}
		publish(party)
		local prompt = bus:FindFirstChild("Board", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player: Player)
				board(player, party)
			end)
		end
	end

	Net.connect("PartyLeave", function(player: Player)
		leave(player, true)
	end)
	Net.connect("PartyStart", start)
	Net.connect("PartyFriendsOnly", function(player: Player, on: any)
		local party = partyOf[player]
		if party and party.host == player then
			party.friendsOnly = on == true
			publish(party)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		local party = partyOf[player]
		if party and party.departing then
			warn(`[Party] {player.Name} couldn't be teleported: {message}`)
			NotifyService.send(player, "Couldn't join your party's run. Get on a bus again.", "error")
			leave(player, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		leave(player)
	end)
end

return PartyService
