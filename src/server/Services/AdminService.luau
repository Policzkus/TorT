--!strict
-- Chat commands for testing and balancing (/admin lists them; /help is taken by Roblox).
-- Admins = Config.Admins, or anyone in Studio.
-- AdminService.run(player, "/candy 5k") can also be called directly from the command bar / MCP.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Admins = require(ReplicatedStorage.Shared.Config.Admins)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

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
				value = DataService.increment(target, key, amount)
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

function AdminService.Start()
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
