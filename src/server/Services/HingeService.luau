--!strict
-- Doors, gates and cellar hatches that open (models tagged "Hinged", built by World/HouseStyles).
-- Players open and close the ones marked Openable through their ProximityPrompt; the Open attribute
-- replicates and HingeController swings them smoothly on every client. They swing shut again after
-- a while, so the streets reset. Front doors aren't openable: the homeowner opens those
-- (HomeownerController).

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local AUTO_CLOSE = 30 -- seconds

local HingeService = {}

local function hingedModel(prompt: ProximityPrompt): Model?
	local holder = prompt.Parent
	local model = holder and holder.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, "Hinged") then
		return model
	end
	return nil
end

-- The model and any siblings that share its Group attribute (the two leaves of a double gate,
-- which open and shut together from one prompt).
local function leaves(model: Model): { Model }
	local list = { model }
	local group = model:GetAttribute("Group")
	if group ~= nil and model.Parent then
		for _, other in model.Parent:GetChildren() do
			if
				other ~= model
				and other:GetAttribute("Group") == group
				and CollectionService:HasTag(other, "Hinged")
			then
				table.insert(list, other :: Model)
			end
		end
	end
	return list
end

local function setOpen(model: Model, prompt: ProximityPrompt, open: boolean)
	for _, leaf in leaves(model) do
		leaf:SetAttribute("Open", open)
	end
	prompt.ActionText = if open then "Close" else "Open"
	if open then
		local stamp = os.clock()
		model:SetAttribute("OpenedAt", stamp)
		task.delay(AUTO_CLOSE, function()
			if model.Parent and model:GetAttribute("OpenedAt") == stamp and model:GetAttribute("Open") == true then
				setOpen(model, prompt, false)
			end
		end)
	end
end

function HingeService.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local model = hingedModel(prompt)
		if model == nil or model:GetAttribute("Openable") ~= true then
			return
		end
		setOpen(model, prompt, model:GetAttribute("Open") ~= true)
	end)
end

return HingeService
