--!strict
-- Collision groups. Whatever hunts you on the streets (AI/Hunter: the Knifer, a homeowner out after
-- you) walks through what stands on the porches (a candy bowl, the seller's crate): a bowl right in
-- front of the door used to wedge a homeowner coming out after whoever emptied it. Everyone else
-- still bumps into them.

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	HUNTERS = "Hunters",
	PORCH = "Porch",
}

local registered = false

local function register()
	if registered then
		return
	end
	registered = true
	for _, name in { CollisionGroups.HUNTERS, CollisionGroups.PORCH } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.HUNTERS, CollisionGroups.PORCH, false)
end

-- Puts every part of `model` in `group`.
function CollisionGroups.put(model: Instance, group: string)
	register()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

return CollisionGroups
