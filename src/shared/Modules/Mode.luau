--!strict
-- Which kind of server this is (PROMPT §V2.2): the public lobby (shop, costumes, the party buses)
-- or a party's private run (a reserved server of the same place: one Night on the streets). The
-- server decides once at boot and tells clients through ReplicatedStorage's "Mode" attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = require(script.Parent.Parent.Config.Game)

export type Mode = "lobby" | "run"

local Mode = {}

-- Server, at boot: a reserved server (no owner) is a run; any other live server is a lobby (a
-- player's own private server too: their friends gather there). Studio plays Game.STUDIO_MODE.
function Mode.decide(): Mode
	local mode: Mode = if RunService:IsStudio()
		then (if Game.STUDIO_MODE == "lobby" then "lobby" else "run")
		elseif game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then "run"
		else "lobby"
	ReplicatedStorage:SetAttribute("Mode", mode)
	return mode
end

-- (On a client this waits for the server's answer, which arrives with the place.)
function Mode.get(): Mode
	local mode = ReplicatedStorage:GetAttribute("Mode")
	while mode ~= "lobby" and mode ~= "run" do
		ReplicatedStorage:GetAttributeChangedSignal("Mode"):Wait()
		mode = ReplicatedStorage:GetAttribute("Mode")
	end
	return mode :: Mode
end

function Mode.isLobby(): boolean
	return Mode.get() == "lobby"
end

return Mode
