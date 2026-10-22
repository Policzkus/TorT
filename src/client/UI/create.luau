--!strict
-- Tiny instance builder:
--   create("Frame", { Size = UDim2.fromScale(1, 1), Parent = gui, create("UICorner", {}) })
-- String keys set properties (Parent is applied last); array entries become children.

local function create(className: string, props: { [any]: any }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if type(key) == "number" then
				value.Parent = instance
			elseif key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return create
