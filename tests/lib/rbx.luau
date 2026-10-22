--!strict
-- Lets Lune load our Roblox modules: emulates `script`, instance-style `require`, and
-- game:GetService for the folders Rojo maps (see default.project.json).
-- Only for pure modules - anything touching real Roblox APIs must be tested in Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SERVICE_ROOTS: { [string]: { [string]: string } } = {
	ReplicatedStorage = { Shared = "src/shared" },
	ServerScriptService = { Server = "src/server" },
}

type Node = {
	__path: string, -- path without extension (folder, or module file stem)
	__virtual: { [string]: string }?, -- for service roots: child name -> real path
}

-- Lune's fs calls yield, and metamethods can't yield, so index the source tree up front.
local files: { [string]: boolean } = {}
local dirs: { [string]: boolean } = {}

local function scan(dir: string)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		else
			files[path] = true
		end
	end
end
scan("src")

local rbx = {}

local moduleCache: { [string]: any } = {}
local nodeMeta = {}

local function makeNode(path: string, virtual: { [string]: string }?): any
	return setmetatable({ __path = path, __virtual = virtual }, nodeMeta)
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function basename(path: string): string
	return string.match(path, "([^/]*)$") or path
end

-- Where the code for `path` lives, if it is a module.
local function moduleFile(path: string): string?
	for _, candidate in { path .. ".luau", path .. ".lua", path .. "/init.luau", path .. "/init.lua" } do
		if files[candidate] then
			return candidate
		end
	end
	return nil
end

local function childPath(node: Node, name: string): string?
	-- rawget: plain indexing would recurse into nodeMeta.__index for missing fields.
	local virtual = rawget(node :: any, "__virtual")
	if virtual then
		return virtual[name]
	end
	local path = rawget(node :: any, "__path") .. "/" .. name
	if moduleFile(path) or dirs[path] then
		return path
	end
	return nil
end

function nodeMeta.__index(self: Node, key: string): any
	local path: string = rawget(self :: any, "__path")
	if key == "Parent" then
		return makeNode(dirname(path))
	elseif key == "Name" then
		return basename(path)
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(node: Node, name: string)
			local child = childPath(node, name)
			if child == nil and key == "WaitForChild" then
				error(`[rbx] {rawget(node :: any, "__path")} has no child '{name}'`, 2)
			end
			return if child then makeNode(child) else nil
		end
	end
	local child = childPath(self, key)
	if child == nil then
		error(`[rbx] {path} has no child '{key}'`, 2)
	end
	return makeNode(child)
end

local fakeGame = {
	GetService = function(_self: any, serviceName: string): any
		local roots = SERVICE_ROOTS[serviceName]
		if roots == nil then
			error(`[rbx] game:GetService('{serviceName}') is not available in Lune tests`, 2)
		end
		return makeNode(serviceName, roots)
	end,
}

local loadModule: (node: Node) -> any

local function shimRequire(target: any): any
	if type(target) == "table" and getmetatable(target) == nodeMeta then
		return loadModule(target)
	end
	error("[rbx] require() expects a module node (string requires are not supported here)", 2)
end

function loadModule(node: Node): any
	local file = moduleFile(rawget(node :: any, "__path"))
	if file == nil then
		error(`[rbx] {rawget(node :: any, "__path")} is not a ModuleScript`, 2)
	end
	local cached = moduleCache[file]
	if cached ~= nil then
		return cached
	end
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = { script = node, require = shimRequire, game = fakeGame },
	})
	local result = chunk()
	moduleCache[file] = result
	return result
end

-- rbx.require("src/shared/Modules/Format")
function rbx.require(path: string): any
	return loadModule(makeNode(path))
end

-- Drop cached modules (e.g. between specs that mutate module state).
function rbx.reset()
	table.clear(moduleCache)
end

return rbx
