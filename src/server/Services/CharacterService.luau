--!strict
-- Player characters (PROMPT §V2.3). Nobody plays as their Roblox avatar: you're one of the 4 starter
-- kids, or whatever costume you're wearing, each a whole character model built by
-- Modules/CharacterRig. First person everywhere. Spawns only once the world is built
-- (CharacterAutoLoads is off, see init.server) and respawns after a short delay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Characters = require(ReplicatedStorage.Shared.Config.Characters)
local Costumes = require(ReplicatedStorage.Shared.Config.Costumes)
local CharacterRig = require(ReplicatedStorage.Shared.Modules.CharacterRig)
local MeshLibrary = require(ReplicatedStorage.Shared.Modules.MeshLibrary)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local RESPAWN_DELAY = 3
local SPAWN_SPREAD = 4

local CharacterService = {}

local random = Random.new()

-- The Config/Characters id the player should look like right now.
function CharacterService.characterFor(player: Player): string
	local data = DataService.get(player)
	local costumeId = data and data.equipped.costume
	local costume = if costumeId then Costumes.costumes[costumeId] else nil
	local starter = Costumes.starters[data and data.starter or ""]
	local id = if costume then costume.character elseif starter then starter.character else nil
	return if id and Characters[id] then id else Costumes.FALLBACK_CHARACTER
end

local function spawnFeet(): CFrame
	local spawn = WorldService.info().spawn
	local spread = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * SPAWN_SPREAD
	return CFrame.new(spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0) + spread)
end

-- Where the current character's feet are (keeping which way it faces).
local function currentFeet(character: Model): CFrame?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		return nil
	end
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	return CFrame.new(feet) * CFrame.Angles(0, yaw, 0)
end

-- Builds the player's character with its feet at `feet` and makes it theirs.
local function place(player: Player, feet: CFrame, health: number?)
	local rig = CharacterRig.build(CharacterService.characterFor(player))
		or CharacterRig.build(Costumes.FALLBACK_CHARACTER)
	if rig == nil or player.Parent ~= Players then
		warn(`[Character] couldn't build a character for {player.Name}`)
		return
	end
	rig.Name = player.Name
	rig:PivotTo(feet * rig:GetPivot())
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	if health then
		humanoid.Health = math.max(1, health)
	end
	local old = player.Character
	rig.Parent = Workspace
	player.Character = rig
	if old and old ~= rig then
		old:Destroy()
	end
	local root = rig.PrimaryPart
	if root then
		pcall(root.SetNetworkOwner, root, player)
	end
end

-- Swaps the player's character in place (after buying/equipping a costume or picking a kid).
function CharacterService.refreshLook(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	if character:GetAttribute("CharacterId") == CharacterService.characterFor(player) then
		return
	end
	local feet = currentFeet(character)
	if feet then
		place(player, feet, humanoid.Health)
	end
end

local function spawnCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	DataService.waitFor(player, 30)
	MeshLibrary.waitReady(20, "Characters")
	if player.Parent == Players then
		place(player, spawnFeet())
	end
end

local function setup(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMaxZoomDistance = 0.5
	player.CameraMinZoomDistance = 0.5
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid == nil then
			return
		end
		humanoid.Died:Once(function()
			task.delay(RESPAWN_DELAY, function()
				if player.Character == character then
					spawnCharacter(player)
				end
			end)
		end)
	end)
	task.spawn(spawnCharacter, player)
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			character:Destroy()
		end
	end)
end

return CharacterService
