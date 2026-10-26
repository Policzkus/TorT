local Items = rbx.require("src/shared/Config/Items")
local Neighborhoods = rbx.require("src/shared/Config/Neighborhoods")

return {
	["every thing he sells is set out in full"] = function()
		for _, itemId in Items.ORDER do
			local item = Items[itemId]
			expect(type(item.name)).toBe("string")
			expect(type(item.blurb)).toBe("string")
			expect(item.doors > 0).toBeTruthy()
			expect(item.most >= 1).toBeTruthy()
			expect(item.key ~= nil).toBeTruthy()
		end
	end,
	["prices are the street's doors' worth, dearer on later streets"] = function()
		local first, second = Neighborhoods.list[1], Neighborhoods.list[2]
		local door = (first.candy.min + first.candy.max) / 2
		expect(Items.price("Bandage", first.id)).toBe(math.round(Items.Bandage.doors * door))
		expect(Items.price("Bandage", second.id) > Items.price("Bandage", first.id)).toBeTruthy()
		expect(Items.price("BearTrap", first.id) > Items.price("Bandage", first.id)).toBeTruthy()
		expect(Items.price("Lockpick", "nowhere") >= 1).toBeTruthy()
	end,
	["he only sells his own things"] = function()
		expect(Items.sells("Bandage")).toBe(true)
		expect(Items.sells("Lockpick")).toBe(true)
		expect(Items.sells("Pumpkin")).toBe(false)
		expect(Items.sells(5)).toBe(false)
		expect(Items.sells(nil)).toBe(false)
	end,
}
