--!strict
-- Buying and wearing costumes, and picking your starter kid (PROMPT §V2.3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Costumes = require(ReplicatedStorage.Shared.Config.Costumes)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CandyService = require(script.Parent.CandyService)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)

local CostumeService = {}

local random = Random.new()

function CostumeService.costume(player: Player): Costumes.Costume?
	local data = DataService.get(player)
	local id = data and data.equipped.costume
	return if id then Costumes.costumes[id] else nil
end

local function equip(player: Player, costumeId: string?)
	DataService.mutate(player, "equipped", function(equipped)
		equipped.costume = costumeId
	end)
	CharacterService.refreshLook(player)
end

function CostumeService.buy(player: Player, costumeId: any): (boolean, string)
	local costume = if type(costumeId) == "string" then Costumes.costumes[costumeId] else nil
	local data = DataService.get(player)
	if costume == nil or data == nil then
		return false, "That costume doesn't exist"
	end
	if data.costumes[costumeId] then
		return false, "You already own it"
	end
	if not CandyService.spend(player, costume.price) then
		return false, `You need {Format.number(costume.price - data.candy)} more candy`
	end
	DataService.mutate(player, "costumes", function(owned)
		owned[costumeId] = true
	end)
	equip(player, costumeId)
	return true, `{string.upper(costume.name)} unlocked`
end

function CostumeService.equip(player: Player, costumeId: any): (boolean, string)
	local data = DataService.get(player)
	if data == nil then
		return false, "Loading..."
	end
	if costumeId == "" or costumeId == nil then
		equip(player, nil)
		return true, "Costume off"
	end
	if type(costumeId) ~= "string" or not data.costumes[costumeId] then
		return false, "You don't own that costume"
	end
	equip(player, costumeId)
	return true, `Wearing {Costumes.costumes[costumeId].name}`
end

function CostumeService.chooseStarter(player: Player, starterId: any): (boolean, string)
	if type(starterId) ~= "string" or Costumes.starters[starterId] == nil then
		return false, "Nobody by that name"
	end
	DataService.set(player, "starter", starterId)
	CharacterService.refreshLook(player)
	return true, `You are {Costumes.starters[starterId].name}`
end

function CostumeService.Start()
	-- New players start as a random kid.
	DataService.Loaded:Connect(function(player: Player, data: any)
		if Costumes.starters[data.starter] == nil then
			DataService.set(player, "starter", Costumes.STARTER_ORDER[random:NextInteger(1, #Costumes.STARTER_ORDER)])
		end
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data and Costumes.starters[data.starter] == nil then
			DataService.set(player, "starter", Costumes.STARTER_ORDER[1])
		end
	end
	Net.handle("BuyCostume", CostumeService.buy, { rate = 3, burst = 6 })
	Net.handle("EquipCostume", CostumeService.equip, { rate = 3, burst = 6 })
	Net.handle("ChooseStarter", CostumeService.chooseStarter, { rate = 2, burst = 4 })
end

return CostumeService
