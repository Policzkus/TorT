--!strict
-- Leaving a run (PROMPT §V2.2): the run on a party's own server goes on as long as they like (there
-- are no Nights to end it); anyone can go back to the public lobby whenever they want, from LOBBY in
-- the TAB menu (RunController asks first). Their bucket stays with them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local NotifyService = require(script.Parent.NotifyService)

local RunExitService = {}

local leaving: { [Player]: boolean } = {}

-- Sends one player to a public server of the place: the lobby.
local function sendHome(player: Player)
	if leaving[player] then
		return
	end
	if RunService:IsStudio() then
		NotifyService.send(player, "(Studio can't teleport: a live run sends you back to the lobby here.)", "info")
		return
	end
	leaving[player] = true
	for try = 1, Runs.TELEPORT_TRIES do
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
		if ok then
			return
		end
		warn(`[Run] teleport to the lobby failed ({try}/{Runs.TELEPORT_TRIES}): {err}`)
		task.wait(2)
	end
	leaving[player] = nil
	NotifyService.send(player, "Couldn't get back to the lobby. Try again, or rejoin the game.", "error")
end

function RunExitService.Start()
	Net.connect("RunLeave", function(player: Player)
		task.spawn(sendHome, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = nil
	end)
end

return RunExitService
