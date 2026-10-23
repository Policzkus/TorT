--!strict
-- Finding a door's house. The knock door can sit inside other models (a hinged door is its own
-- model), so walk up to the model World/Street marked with a HouseId.

local Houses = {}

function Houses.of(door: Instance): Model?
	local node = door.Parent
	while node and node ~= game do
		if node:IsA("Model") and node:GetAttribute("HouseId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

return Houses
