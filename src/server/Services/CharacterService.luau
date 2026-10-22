--!strict
-- Player characters: first person everywhere (PROMPT §V2.3), spawned only once the world has
-- been built (CharacterAutoLoads is off, see init.server), and respawned after a short delay.
-- Starter characters and costumes are applied here too as they land.

local Players = game:GetService("Players")

local RESPAWN_DELAY = 3

local CharacterService = {}

local function spawnCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	player:LoadCharacter()
end

local function setup(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMaxZoomDistance = 0.5
	player.CameraMinZoomDistance = 0.5
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Once(function()
				task.delay(RESPAWN_DELAY, function()
					if player.Character == character then
						spawnCharacter(player)
					end
				end)
			end)
		end
	end)
	task.spawn(spawnCharacter, player)
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
end

return CharacterService
