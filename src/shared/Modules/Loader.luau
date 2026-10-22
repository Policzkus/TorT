--!strict
-- Boots a folder of Services/Controllers in a fixed order.
-- Each module may define Init() (runs in order, must not yield) and Start() (runs after every Init, own thread).

local Loader = {}

type Entry = { name: string, module: any }

function Loader.run(folder: Instance, order: { string }, label: string)
	local startedAt = os.clock()
	local entries: { Entry } = {}
	local listed: { [string]: boolean } = {}

	for _, name in order do
		local child = folder:FindFirstChild(name)
		if child == nil or not child:IsA("ModuleScript") then
			error(`[{label}] '{name}' is in the load order but no ModuleScript has that name`)
		end
		listed[name] = true
		table.insert(entries, { name = name, module = (require :: any)(child) })
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") and not listed[child.Name] then
			warn(`[{label}] '{child.Name}' is not in the load order and was skipped`)
		end
	end

	for _, entry in entries do
		if type(entry.module.Init) == "function" then
			local ok, err = xpcall(entry.module.Init, debug.traceback)
			if not ok then
				warn(`[{label}] {entry.name}.Init failed:\n{err}`)
			end
		end
	end
	for _, entry in entries do
		if type(entry.module.Start) == "function" then
			task.spawn(function()
				local ok, err = xpcall(entry.module.Start, debug.traceback)
				if not ok then
					warn(`[{label}] {entry.name}.Start failed:\n{err}`)
				end
			end)
		end
	end

	print(`[{label}] {#entries} modules ready in {math.round((os.clock() - startedAt) * 1000)} ms`)
end

return Loader
