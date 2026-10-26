local Template = rbx.require("src/server/Data/Template")
local Migrations = rbx.require("src/server/Data/Migrations")

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value do
		result[k] = copy(v)
	end
	return result
end

return {
	["template version matches the migration target"] = function()
		expect(Migrations.CURRENT).toBe(Template.version)
	end,
	["fresh profile needs no migration"] = function()
		local data = copy(Template)
		expect(Migrations.apply(data)).toBe("ok")
	end,
	["data from a newer server is flagged and left untouched"] = function()
		local data = copy(Template)
		data.version = Template.version + 1
		expect(Migrations.apply(data)).toBe("future")
		expect(data.version).toBe(Template.version + 1)
	end,
	["steps run in order up to the current version"] = function()
		local seen = {}
		local restore = Migrations._withSteps({
			[2] = function(data)
				table.insert(seen, 2)
				data.renamed = data.old
				data.old = nil
			end,
			[3] = function(data)
				table.insert(seen, 3)
				data.renamed *= 10
			end,
		}, 3)
		local data = { version = 1, old = 5 }
		local result = Migrations.apply(data)
		restore()
		expect(result).toBe("migrated")
		expect(data.version).toBe(3)
		expect(data.renamed).toBe(50)
		expect(data.old).toBe(nil)
		expect(#seen).toBe(2)
		expect(seen[1]).toBe(2)
	end,
	["unversioned legacy data is treated as version 0"] = function()
		local restore = Migrations._withSteps({}, 1)
		local data = { candy = 10 }
		expect(Migrations.apply(data)).toBe("migrated")
		restore()
		expect(data.version).toBe(1)
	end,
	["v2 drops the three lives (health took their place)"] = function()
		local data = copy(Template)
		data.version = 1
		data.lives = 2
		data.livesRefillAt = 12345
		expect(Migrations.apply(data)).toBe("migrated")
		expect(data.version).toBe(Template.version)
		expect(data.lives).toBe(nil)
		expect(data.livesRefillAt).toBe(nil)
		expect(data.candy).toBe(Template.candy)
	end,
	["template has the keys the game relies on"] = function()
		for _, key in { "candy", "bucket", "souls", "rebirths", "upgrades", "stats", "settings", "purchases" } do
			expect(Template[key] ~= nil).toBe(true)
		end
		expect(Template.neighborhoods.CardboardCourt).toBe(true)
	end,
}
