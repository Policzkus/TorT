--!strict
-- Builds the world at boot and answers questions about it: houses, drop-offs, bus stops, gates,
-- which zone a position is in, and where to teleport people. A lobby server builds the lobby
-- instead (World/Lobby): no houses to visit, the party buses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local MeshLibrary = require(ReplicatedStorage.Shared.Modules.MeshLibrary)
local Mode = require(ReplicatedStorage.Shared.Modules.Mode)
local Builder = require(script.Parent.Parent.World.Builder)
local Lighting = require(script.Parent.Parent.World.Lighting)
local Lobby = require(script.Parent.Parent.World.Lobby)
local Street = require(script.Parent.Parent.World.Street)

local WorldService = {}

-- How far past a gate you must be before counting as "inside" a locked street (gate pushback).
local INSIDE_MARGIN = 8

local info: Builder.WorldInfo

local function localPoint(zone: Builder.Zone, position: Vector3): Vector3
	return zone.cframe:PointToObjectSpace(position)
end

local function inside(zone: Builder.Zone, position: Vector3): boolean
	local p = localPoint(zone, position)
	local half = zone.size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

function WorldService.Init()
	Lighting.apply()
	-- Clear leftovers of the default place template; the builder makes its own ground and spawn.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = Workspace:FindFirstChild(name)
		if leftover and leftover:IsA("BasePart") then
			leftover:Destroy()
		end
	end
	-- The AI house meshes must exist before the streets are built (a few seconds at boot).
	MeshLibrary.preload()
	MeshLibrary.waitReady(15, "World")
	if Mode.isLobby() then
		local lobby = Lobby.build(Workspace)
		info = {
			folder = lobby.folder,
			spawn = lobby.spawn,
			houses = {},
			dropoffs = {},
			busStops = {},
			zones = { { id = "Hub", cframe = lobby.zone.cframe, size = lobby.zone.size } },
			streets = {},
			gates = {},
			arrivals = { Hub = lobby.spawn.CFrame },
			buses = lobby.buses,
		}
	else
		info = Builder.build(Workspace)
	end
end

function WorldService.info(): Builder.WorldInfo
	return info
end

function WorldService.getHouse(houseId: string): Street.HouseInfo?
	return info.houses[houseId]
end

function WorldService.dropoffs(): { Street.DropoffInfo }
	return info.dropoffs
end

function WorldService.busStops(): { BasePart }
	return info.busStops
end

-- "Hub", a neighborhood id, or nil when between zones (e.g. inside a road bend).
function WorldService.zoneAt(position: Vector3): string?
	for _, zone in info.zones do
		if inside(zone, position) then
			return zone.id
		end
	end
	return nil
end

-- True when `position` is clearly past the gate of `neighborhoodId` (not just touching it).
function WorldService.isDeepInside(neighborhoodId: string, position: Vector3): boolean
	local street = info.streets[neighborhoodId]
	if street == nil then
		return false
	end
	local p = street.start:PointToObjectSpace(position)
	return -p.Z > INSIDE_MARGIN and -p.Z <= street.length and math.abs(p.X) <= 90
end

-- Where to put someone who walked through a gate they don't own: just in front of it.
function WorldService.gateFront(neighborhoodId: string): CFrame?
	local gate = info.gates[neighborhoodId]
	if gate == nil then
		return nil
	end
	return gate.frame * CFrame.new(0, 3, 12) -- still facing the gate
end

function WorldService.arrival(zoneId: string): CFrame?
	return info.arrivals[zoneId]
end

function WorldService.isBuilt(neighborhoodId: string): boolean
	return info.streets[neighborhoodId] ~= nil
end

function WorldService.neighborhood(neighborhoodId: string): Neighborhoods.Neighborhood?
	return Neighborhoods.byId[neighborhoodId]
end

return WorldService
