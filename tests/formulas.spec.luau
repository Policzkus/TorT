local Formulas = rbx.require("src/shared/Modules/Formulas")
local Economy = rbx.require("src/shared/Config/Economy")
local Upgrades = rbx.require("src/shared/Config/Upgrades")

return {
	["door candy multiplies grade, streak and categories"] = function()
		-- 10 base × GREAT 1.6 × streak 1.2 × charm 1.3 × rebirth 1.4 = 34.944 -> 35
		local candy = Formulas.doorCandy(10, "GREAT", 0.2, { charm = 0.3, rebirth = 0.4 })
		expect(candy).toBe(35)
	end,
	["bonuses add within a category"] = function()
		-- charm +10% upgrade +40% preference = ×1.5 (not 1.1 × 1.4)
		expect(Formulas.doorCandy(10, "GOOD", 0, { charm = 0.1 + 0.4 })).toBe(15)
	end,
	["a door always gives at least the minimum"] = function()
		expect(Formulas.doorCandy(1, "MISS", 0, {})).toBe(Economy.MIN_DOOR_CANDY)
	end,
	["event multiplier is capped"] = function()
		expect(Formulas.doorCandy(10, "GOOD", 0, {}, 2 * 2 * 2)).toBe(10 * Economy.EVENT_MULTIPLIER_CAP)
	end,
	["unknown grades are rejected"] = function()
		expect(pcall(Formulas.doorCandy, 10, "AMAZING", 0, {})).toBe(false)
	end,
	["streak bonus caps at the max"] = function()
		expect(Formulas.streakBonus(3)).toBeNear(0.3, 1e-9)
		expect(Formulas.streakBonus(50)).toBe(Economy.STREAK_MAX)
	end,
	["bucket overflow is lost"] = function()
		local bucket, added, overflow = Formulas.addToBucket(10, 12, 15)
		expect(bucket).toBe(15)
		expect(added).toBe(5)
		expect(overflow).toBe(7)
	end,
	["bucket with space takes everything"] = function()
		local bucket, added, overflow = Formulas.addToBucket(0, 12, 15)
		expect(bucket).toBe(12)
		expect(added).toBe(12)
		expect(overflow).toBe(0)
	end,
	["stash stops at box capacity"] = function()
		local moved, bucket, banked = Formulas.stash(100, 24950, 25000)
		expect(moved).toBe(50)
		expect(bucket).toBe(50)
		expect(banked).toBe(25000)
	end,
	["box capacity follows the list then grows ×4"] = function()
		expect(Formulas.boxCapacity(0)).toBe(25e3)
		expect(Formulas.boxCapacity(5)).toBe(40e6)
		expect(Formulas.boxCapacity(6)).toBe(160e6)
		expect(Formulas.boxCapacity(7)).toBe(640e6)
	end,
	["bucket tiers respect rebirth gates"] = function()
		expect(Formulas.maxLevel("bucketTier", 0)).toBe(7)
		expect(Formulas.maxLevel("bucketTier", 1)).toBe(9)
		expect(Formulas.canBuy("bucketTier", 7, 0, 1e9)).toBe("needsRebirth")
		expect(Formulas.canBuy("bucketTier", 7, 1, 1e9)).toBe("ok")
		expect(Formulas.canBuy("bucketTier", 12, 9, 1e12)).toBe("maxed")
	end,
	["level tracks gain 5 levels per rebirth"] = function()
		expect(Formulas.maxLevel("charm", 0)).toBe(10)
		expect(Formulas.maxLevel("charm", 2)).toBe(20)
		expect(Formulas.rebirthsForLevel("charm", 9)).toBe(0)
		expect(Formulas.rebirthsForLevel("charm", 10)).toBe(1)
		expect(Formulas.rebirthsForLevel("charm", 15)).toBe(2)
		expect(Formulas.canBuy("charm", 10, 0, 1e12)).toBe("needsRebirth")
	end,
	["fixed-max tracks are maxed, not rebirth-gated"] = function()
		expect(Formulas.canBuy("sneakers", 10, 0, 1e12)).toBe("maxed")
		expect(Formulas.walkSpeed(10)).toBe(26)
	end,
	["level costs grow geometrically"] = function()
		local track = Upgrades.tracks.charm
		expect(Formulas.upgradeCost("charm", 0)).toBe(track.baseCost)
		expect(Formulas.upgradeCost("charm", 3)).toBe(math.round(track.baseCost * track.growth ^ 3))
	end,
	["every price fits in half of its life's Candy Box"] = function()
		for trackId in Upgrades.tracks do
			for rebirths = 0, 6 do
				local half = Formulas.boxCapacity(rebirths) / 2
				local maxLevel = Formulas.maxLevel(trackId, rebirths)
				local absolute = Formulas.absoluteMaxLevel(trackId)
				local top = if absolute then math.min(maxLevel, absolute) else maxLevel
				for level = 0, top - 1 do
					if Formulas.rebirthsForLevel(trackId, level) == rebirths then
						local cost = Formulas.upgradeCost(trackId, level)
						if cost and cost > half then
							error(`{trackId} level {level + 1} costs {cost} > half of the R{rebirths} box ({half})`)
						end
					end
				end
			end
		end
	end,
}
