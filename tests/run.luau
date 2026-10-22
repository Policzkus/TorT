--!strict
-- Runs every tests/*.spec.luau. Usage (from the project root):  lune run tests/run
-- A spec returns { ["test name"] = function() ... end }. The globals `rbx` and `expect` are provided.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local rbx = require("./lib/rbx")
local expect = require("./lib/expect")

local passed, failed = 0, 0
local specFiles = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specFiles, name)
	end
end
table.sort(specFiles)

for _, file in specFiles do
	rbx.reset()
	local chunk = luau.load(fs.readFile("tests/" .. file), {
		debugName = file,
		environment = { rbx = rbx, expect = expect },
	})
	local okLoad, spec = pcall(chunk)
	if not okLoad then
		failed += 1
		print(`✗ {file}: failed to load: {spec}`)
		continue
	end
	local names = {}
	for name in spec do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(spec[name])
		if ok then
			passed += 1
		else
			failed += 1
			print(`✗ {file} > {name}\n    {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed ({#specFiles} spec files)`)
process.exit(if failed > 0 then 1 else 0)
