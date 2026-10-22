--!strict
-- The client's read-only copy of its own saved data, kept in sync by DataService.
-- UI should use StateController.observe(key, fn) instead of polling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local StateController = {}

StateController.Changed = Signal.new() -- (key: string, value: any)
StateController.Loaded = Signal.new()

local data: { [string]: any }? = nil

function StateController.isLoaded(): boolean
	return data ~= nil
end

function StateController.get(key: string): any
	return if data then data[key] else nil
end

-- Calls fn(value) now (if loaded) and every time `key` changes.
function StateController.observe(key: string, fn: (value: any) -> ()): Signal.Connection
	local connection = StateController.Changed:Connect(function(changedKey: string, value: any)
		if changedKey == key then
			fn(value)
		end
	end)
	if data then
		task.spawn(fn, data[key])
	end
	return connection
end

function StateController.Init()
	Net.event("StateSync").OnClientEvent:Connect(function(changes: { [string]: any }, isFull: boolean)
		if isFull then
			local wasLoaded = data ~= nil
			data = changes
			for key, value in changes do
				StateController.Changed:Fire(key, value)
			end
			if not wasLoaded then
				StateController.Loaded:Fire()
			end
			return
		end
		local current = data
		if current == nil then
			-- A partial update before the first full snapshot; the full snapshot will include it.
			return
		end
		for key, value in changes do
			current[key] = value
			StateController.Changed:Fire(key, value)
		end
	end)
end

function StateController.Start()
	-- Covers the case where the server's first snapshot arrived before we were listening.
	Net.event("StateRequest"):FireServer()
end

return StateController
