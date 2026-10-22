--!strict
-- Swap-in support (PROMPT §3.2): drop a model at ReplicatedStorage.Assets.<Category>.<Name> and the
-- world uses it instead of the procedural version, with no code changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

function Assets.find(category: string, name: string): Instance?
	local root = ReplicatedStorage:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(category)
	return folder and folder:FindFirstChild(name)
end

-- A clone of the asset if it exists and is a Model, else nil.
function Assets.clone(category: string, name: string): Model?
	local asset = Assets.find(category, name)
	if asset and asset:IsA("Model") then
		return asset:Clone()
	end
	return nil
end

return Assets
