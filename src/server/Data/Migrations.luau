--!strict
-- Ordered data migrations. STEPS[n] upgrades a profile from version n - 1 to version n.
-- Rules: never edit or delete a step that has shipped; bump Template.version when adding one.
--
-- Example for a future v2:
--   [2] = function(data)
--       data.upgrades.speed = data.upgrades.sneakers
--       data.upgrades.sneakers = nil
--   end,

local Template = require(script.Parent.Template)

local STEPS: { [number]: (data: any) -> () } = {
	-- v2: health took the place of the three lives (HealthService); nothing of them is kept.
	[2] = function(data)
		data.lives = nil
		data.livesRefillAt = nil
	end,
}

local Migrations = {}

Migrations.CURRENT = Template.version

export type Result = "ok" | "migrated" | "future"

-- Mutates `data` in place. "future" means the data was saved by a newer server than this one:
-- the caller must not touch or save it.
function Migrations.apply(data: any): Result
	local version = if type(data.version) == "number" then data.version else 0
	if version > Migrations.CURRENT then
		return "future"
	end
	if version == Migrations.CURRENT then
		return "ok"
	end
	for step = version + 1, Migrations.CURRENT do
		local migrate = STEPS[step]
		if migrate then
			migrate(data)
		end
		data.version = step
	end
	return "migrated"
end

-- For tests: lets a spec register throwaway steps without editing the shipped table.
function Migrations._withSteps(steps: { [number]: (data: any) -> () }, current: number)
	local previousSteps, previousCurrent = STEPS, Migrations.CURRENT
	STEPS, Migrations.CURRENT = steps, current
	return function()
		STEPS, Migrations.CURRENT = previousSteps, previousCurrent
	end
end

return Migrations
