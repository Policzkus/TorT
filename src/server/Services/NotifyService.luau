--!strict
-- Toast messages for one player or the whole server. Kinds: "info" | "success" | "error" | "candy" | "rare".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Modules.Net)

local NotifyService = {}

function NotifyService.send(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

function NotifyService.all(text: string, kind: string?)
	Net.event("Notify"):FireAllClients(text, kind or "info")
end

function NotifyService.others(except: Player, text: string, kind: string?)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			NotifyService.send(player, text, kind)
		end
	end
end

return NotifyService
