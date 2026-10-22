--!strict
-- The in-server player list stats (top-right of the Roblox UI).
local DataService = require(script.Parent.DataService)

-- data key -> stat name shown in the player list (first entry is the sort column)
local STATS: { { key: string, label: string } } = {
	{ key = "candy", label = "Candy" },
	{ key = "rebirths", label = "Rebirths" },
}

local LeaderstatsService = {}

function LeaderstatsService.Start()
	DataService.Loaded:Connect(function(player: Player, data: any)
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		for _, stat in STATS do
			local value = Instance.new("IntValue")
			value.Name = stat.label
			value.Value = data[stat.key]
			value.Parent = folder
		end
		folder.Parent = player
	end)

	DataService.Changed:Connect(function(player: Player, key: string, value: any)
		for _, stat in STATS do
			if stat.key == key then
				local folder = player:FindFirstChild("leaderstats")
				local valueObject = folder and folder:FindFirstChild(stat.label) :: IntValue?
				if valueObject then
					valueObject.Value = value
				end
			end
		end
	end)
end

return LeaderstatsService
