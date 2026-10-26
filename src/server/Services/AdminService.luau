--!strict
-- Chat commands for testing and balancing (/admin lists them; /help is taken by Roblox).
-- Admins = Config.Admins, or anyone in Studio.
-- AdminService.run(player, "/candy 5k") can also be called directly from the command bar / MCP.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local Admins = require(ReplicatedStorage.Shared.Config.Admins)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local HouseService = require(script.Parent.HouseService)
local LivesService = require(script.Parent.LivesService)
local KniferService = require(script.Parent.KniferService)
local TrafficService = require(script.Parent.TrafficService)
local WorldEventsService = require(script.Parent.WorldEventsService)
local WorldService = require(script.Parent.WorldService)

type Command = {
	usage: string,
	run: (admin: Player, args: { string }) -> string,
}

local AdminService = {}

local SUFFIX_MULTIPLIERS: { [string]: number } = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }

-- "250" -> 250, "1.5k" -> 1500, "2M" -> 2000000, "1e6" -> 1000000
local function parseAmount(text: string?): number?
	if text == nil then
		return nil
	end
	local direct = tonumber(text)
	if direct then
		return direct
	end
	local numberPart, suffix = string.match(string.lower(text), "^(%-?[%d%.]+)(%a)$")
	local base = numberPart and tonumber(numberPart)
	local multiplier = suffix and SUFFIX_MULTIPLIERS[suffix]
	if base and multiplier then
		return base * multiplier
	end
	return nil
end

-- nil / "me" -> the admin; otherwise the first player whose name or display name starts with `query`.
local function findPlayer(admin: Player, query: string?): Player?
	if query == nil or string.lower(query) == "me" then
		return admin
	end
	local needle = string.lower(query)
	for _, player in Players:GetPlayers() do
		local name, display = string.lower(player.Name), string.lower(player.DisplayName)
		if string.sub(name, 1, #needle) == needle or string.sub(display, 1, #needle) == needle then
			return player
		end
	end
	return nil
end

local function requireTarget(admin: Player, query: string?): Player
	local target = findPlayer(admin, query)
	if target == nil then
		error(`No player matches '{query}'`, 0)
	end
	if not DataService.isLoaded(target) then
		error(`{target.Name}'s data isn't loaded yet`, 0)
	end
	return target
end

local function requireAmount(text: string?): number
	local amount = parseAmount(text)
	if amount == nil or amount ~= amount or math.abs(amount) == math.huge then
		error(`'{text}' is not a valid amount (try 500, 2.5k, 1m)`, 0)
	end
	return amount
end

local commands: { [string]: Command } = {}

local function numberCommand(key: string, mode: "add" | "set", label: string): Command
	return {
		usage = `/{if mode == "add" then key else "set" .. key} <amount> [player] - {label}`,
		run = function(admin, args)
			local amount = requireAmount(args[1])
			local target = requireTarget(admin, args[2])
			local value
			if mode == "add" then
				local current = (DataService.get(target) :: any)[key]
				value = DataService.increment(target, key, math.max(amount, -current))
			else
				DataService.set(target, key, amount)
				value = amount
			end
			return `{target.Name} {key} = {Format.number(value or 0)}`
		end,
	}
end

commands.candy = numberCommand("candy", "add", "add banked candy")
commands.setcandy = numberCommand("candy", "set", "set banked candy")
commands.bucket = numberCommand("bucket", "add", "add carried candy")
commands.souls = numberCommand("souls", "add", "add souls")
commands.setrebirths = numberCommand("rebirths", "set", "set rebirth count")

commands.unlock = {
	usage = "/unlock <neighborhoodId|all> [player] - unlock streets without paying",
	run = function(admin, args)
		local target = requireTarget(admin, args[2])
		local which = args[1]
		local unlocked = {}
		DataService.mutate(target, "neighborhoods", function(owned)
			for _, neighborhood in Neighborhoods.list do
				if which == "all" or string.lower(neighborhood.id) == string.lower(which or "") then
					owned[neighborhood.id] = true
					table.insert(unlocked, neighborhood.name)
				end
			end
		end)
		if #unlocked == 0 then
			error(`No neighborhood '{which}' (use an id like MapleLane, or 'all')`, 0)
		end
		return `{target.Name} unlocked {table.concat(unlocked, ", ")}`
	end,
}

commands.upgrade = {
	usage = "/upgrade <track> <level> [player] - set an upgrade level (bucketTier, charm, sneakers)",
	run = function(admin, args)
		local target = requireTarget(admin, args[3])
		local track, level = args[1], requireAmount(args[2])
		local data = DataService.get(target) :: any
		if type(track) ~= "string" or data.upgrades[track] == nil then
			error(`No upgrade track '{track}'`, 0)
		end
		DataService.mutate(target, "upgrades", function(upgrades)
			upgrades[track] = math.max(0, math.floor(level))
		end)
		return `{target.Name} {track} = {math.floor(level)}`
	end,
}

commands.event = {
	usage = "/event <witching|calm|fullsize|bloodmoon on|off|auto> - trigger world events",
	run = function(_admin, args)
		local which = string.lower(args[1] or "")
		if which == "calm" then
			WorldEventsService.endWitching()
			return "Witching Hour ended"
		elseif which == "witching" then
			WorldEventsService.startWitching()
			return "Witching Hour started"
		elseif which == "fullsize" then
			WorldEventsService.endFullSize()
			if not WorldEventsService.startFullSize() then
				error("Nobody is standing in a street", 0)
			end
			return "Full-Size Bar house spawned"
		elseif which == "bloodmoon" then
			local mode = string.lower(args[2] or "on")
			WorldEventsService.setBloodMoonOverride(if mode == "auto" then nil else mode == "on")
			return `Blood Moon {mode}`
		end
		error("Try /event dawn, witching, fullsize or bloodmoon on|off|auto", 0)
	end,
}

commands.housetype = {
	usage = "/housetype <Normal|Decorated|Trick|Bowl|LightsOff|Open> - change the house nearest to you",
	run = function(admin, args)
		local wanted = args[1]
		local valid = { Normal = true, Decorated = true, Trick = true, Bowl = true, LightsOff = true, Open = true }
		if not valid[wanted] then
			error("Try Normal, Decorated, Trick, Bowl, LightsOff or Open", 0)
		end
		local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			error("You need a character", 0)
		end
		local best, bestDistance = nil, math.huge
		for houseId, house in WorldService.info().houses do
			local distance = (house.door.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = houseId, distance
			end
		end
		if best == nil then
			error("No houses", 0)
		end
		HouseService.setType(best, wanted)
		return `{best} is now {wanted}`
	end,
}

commands.data = {
	usage = "/data [key] [player] - print saved data to the Output window",
	run = function(admin, args)
		local target = requireTarget(admin, args[2])
		local data = DataService.get(target) :: any
		local value = if args[1] then data[args[1]] else data
		if value == nil then
			error(`No data key '{args[1]}'`, 0)
		end
		print(`[Admin] {target.Name} data{if args[1] then "." .. args[1] else ""}:`, HttpService:JSONEncode(value))
		return "Printed to the Output window"
	end,
}

commands.reset = {
	usage = "/reset [player] - wipe data back to a fresh profile",
	run = function(admin, args)
		local target = requireTarget(admin, args[1])
		DataService.reset(target)
		return `{target.Name}'s data was reset`
	end,
}

commands.faint = {
	usage = "/faint [player] - be caught: lose a life and the bucket, black out, come to at the spawn",
	run = function(admin, args)
		local target = requireTarget(admin, args[1])
		if not LivesService.faint(target) then
			error(`{target.Name} is already out`, 0)
		end
		return `{target.Name} fainted`
	end,
}

commands.car = {
	usage = "/car [down|up] - send the car down the street you're on, now",
	run = function(admin, args)
		local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local street = root and WorldService.zoneAt(root.Position)
		if street == nil or not WorldService.isBuilt(street) then
			error("Stand on a street first", 0)
		end
		local dir = if args[1] == "down" then 1 elseif args[1] == "up" then -1 else nil
		if TrafficService.send(street, dir) == nil then
			error("No car: it isn't set up yet (tools/setup_car.luau), or one is already on this street", 0)
		end
		return `A car is coming down {street}`
	end,
}

commands.knifer = {
	usage = "/knifer [away|info] - the Knifer comes for you on your street now (away: send him off; info: what he knows of the street)",
	run = function(admin, args)
		local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local street = root and WorldService.zoneAt(root.Position)
		if street == nil or not WorldService.isBuilt(street) then
			error("Stand on a street first", 0)
		end
		if args[1] == "info" then
			return KniferService.describe(street, admin)
		end
		if args[1] == "away" then
			if not KniferService.dismiss(street) then
				error("He isn't on this street", 0)
			end
			return "The Knifer's gone"
		end
		if not KniferService.summon(street, admin) then
			error("He's already here, or there's nowhere unseen near you for him to come out of", 0)
		end
		return "The Knifer is coming"
	end,
}

commands.save = {
	usage = "/save [player] - save to the DataStore now",
	run = function(admin, args)
		local target = requireTarget(admin, args[1])
		DataService.save(target)
		return `Saving {target.Name}'s data`
	end,
}

commands.admin = {
	usage = "/admin - list admin commands",
	run = function()
		local lines = {}
		for _, command in commands do
			table.insert(lines, command.usage)
		end
		table.sort(lines)
		print("[Admin] Commands:\n  " .. table.concat(lines, "\n  "))
		return "Command list printed to the Output window (F9 in game)"
	end,
}

function AdminService.isAdmin(player: Player): boolean
	return RunService:IsStudio() or table.find(Admins.userIds, player.UserId) ~= nil
end

-- Runs a command line like "/candy 5k Filip". Returns (ok, message).
function AdminService.run(player: Player, text: string): (boolean, string)
	if not AdminService.isAdmin(player) then
		return false, "Not an admin"
	end
	local words = string.split(string.gsub(text, "^%s*/", ""), " ")
	local name = string.lower(table.remove(words, 1) or "")
	local args = {}
	for _, word in words do
		if word ~= "" then
			table.insert(args, word)
		end
	end
	local command = commands[name]
	if command == nil then
		return false, `Unknown command '/{name}' - try /admin`
	end
	local ok, result = pcall(command.run, player, args)
	local message = tostring(result)
	NotifyService.send(player, message, if ok then "success" else "error")
	if not ok then
		warn(`[Admin] /{name} failed: {message}`)
	end
	return ok, message
end

-- Studio only: the command bar and the Studio MCP get their own copy of every ModuleScript, so
-- they can't reach live profiles through require(). They call this instead:
--   game.ServerStorage.DevBridge:Invoke("/candy 5k")      -> ok, message (runs as the first player)
--   game.ServerStorage.DevBridge:Invoke("data")           -> copy of the first player's data
local function createDevBridge()
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "DevBridge"
	bridge.OnInvoke = function(text: string, playerName: string?): (any, any)
		local player = if playerName then findPlayer(Players:GetPlayers()[1], playerName) else Players:GetPlayers()[1]
		if player == nil then
			return false, "No player in the server"
		end
		if text == "data" then
			return DataService.get(player)
		end
		return AdminService.run(player, text)
	end
	bridge.Parent = ServerStorage
end

function AdminService.Start()
	if RunService:IsStudio() then
		createDevBridge()
	end

	if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
		Players.PlayerAdded:Connect(function(player)
			player.Chatted:Connect(function(message)
				if string.sub(message, 1, 1) == "/" then
					AdminService.run(player, message)
				end
			end)
		end)
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "AdminCommands"
	for name in commands do
		local command = Instance.new("TextChatCommand")
		command.Name = "Admin_" .. name
		command.PrimaryAlias = "/" .. name
		command.AutocompleteVisible = false
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				AdminService.run(player, text)
			end
		end)
		command.Parent = folder
	end
	folder.Parent = TextChatService
end

return AdminService
