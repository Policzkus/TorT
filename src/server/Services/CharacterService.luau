--!strict
-- Player characters: first person everywhere (PROMPT §V2.3). Starter characters and costumes
-- are applied here too as they land.

local Players = game:GetService("Players")

local CharacterService = {}

local function setup(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMaxZoomDistance = 0.5
	player.CameraMinZoomDistance = 0.5
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
end

return CharacterService
