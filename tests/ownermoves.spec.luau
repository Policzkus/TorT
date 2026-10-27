local OwnerMoves = rbx.require("src/shared/Modules/OwnerMoves")
local Dialogue = rbx.require("src/shared/Config/Dialogue")

local CHANNELS = { "fold", "twist", "sway", "nod", "tilt", "turn", "step", "lunge" }

-- Every number in a pose is finite and a sane angle (radians; lunge in studs).
local function sane(move, label)
	for _, key in CHANNELS do
		local value = move[key]
		if value ~= nil then
			expect(type(value)).toBe("number")
			if value ~= value or math.abs(value) > 3.2 then
				error(`{label}: {key} = {value}`)
			end
		end
	end
	for _, key in { "near", "far", "both" } do
		local arm = move[key]
		if arm ~= nil then
			for _, part in { "pitch", "roll", "yaw" } do
				local value = arm[part]
				if value ~= nil and (value ~= value or math.abs(value) > 3.2) then
					error(`{label}: {key}.{part} = {value}`)
				end
			end
			expect(type(arm.pitch)).toBe("number")
		end
	end
end

local function sample(pose, length, label)
	local steps = 40
	for i = 0, steps do
		sane(pose(length * i / steps), label .. " @" .. i)
	end
end

return {
	["every move is a sane pose all the way through"] = function()
		for name, def in OwnerMoves.ACTS do
			sample(def.pose, def.time, "act " .. name)
		end
		for name, def in OwnerMoves.GIVES do
			sample(def.pose, def.time, "give " .. name)
			expect(def.release > 0 and def.release < def.time).toBeTruthy()
		end
		for name, def in OwnerMoves.GOODBYES do
			sample(def.pose, def.time, "bye " .. name)
		end
		for name, def in OwnerMoves.REACTIONS do
			sample(def.pose, if def.time == math.huge then 5 else def.time, "reaction " .. name)
		end
		for name, def in OwnerMoves.TALKS do
			sample(function(t)
				return def.pose(t, 4)
			end, 4, "talk " .. name)
		end
	end,
	["every sound cue falls inside its move"] = function()
		for _, group in { OwnerMoves.ACTS, OwnerMoves.GIVES, OwnerMoves.REACTIONS } do
			for name, def in group do
				for _, cue in def.sounds or {} do
					if cue.at < 0 or cue.at >= def.time then
						error(`{name}: a sound at {cue.at} of {def.time}`)
					end
				end
			end
		end
	end,
	["every temperament names moves that exist"] = function()
		for name, temper in OwnerMoves.TEMPERAMENTS do
			expect(#temper.acts >= 4).toBeTruthy()
			for _, entry in temper.acts do
				if OwnerMoves.ACTS[entry.name] == nil then
					error(`{name}: no act {entry.name}`)
				end
				expect(entry.weight > 0).toBeTruthy()
			end
			for _, talk in { temper.hello, temper.pleased, temper.displeased } do
				if OwnerMoves.TALKS[talk] == nil then
					error(`{name}: no talk {talk}`)
				end
			end
			for _, entry in temper.gives do
				if OwnerMoves.GIVES[entry.name] == nil then
					error(`{name}: no give {entry.name}`)
				end
			end
			if OwnerMoves.REACTIONS[temper.glare] == nil then
				error(`{name}: no glare {temper.glare}`)
			end
			expect(temper.chance > 0 and temper.chance <= 1).toBeTruthy()
			-- Pleased goodbyes keep the door open; displeased ones slam it.
			for mood, list in temper.byes do
				for _, entry in list do
					local bye = OwnerMoves.GOODBYES[entry.name]
					if bye == nil then
						error(`{name}: no goodbye {entry.name}`)
					end
					if bye.slam ~= (mood == "displeased") then
						error(`{name}: {entry.name} is {mood} but slam = {bye.slam}`)
					end
				end
			end
		end
	end,
	["every personality has its own temperament, the seller his"] = function()
		for id in Dialogue.personalities do
			expect(OwnerMoves.temperament(id)).toBe(OwnerMoves.TEMPERAMENTS[id])
		end
		expect(OwnerMoves.temperament("Host", true)).toBe(OwnerMoves.TEMPERAMENTS.Seller)
		expect(OwnerMoves.temperament("Nobody")).toBe(OwnerMoves.TEMPERAMENTS.Default)
		expect(OwnerMoves.temperament(nil)).toBe(OwnerMoves.TEMPERAMENTS.Default)
	end,
	["pick goes by weight"] = function()
		local list = { { name = "a", weight = 3 }, { name = "b", weight = 1 } }
		expect(OwnerMoves.pick(list, 0)).toBe("a")
		expect(OwnerMoves.pick(list, 0.74)).toBe("a")
		expect(OwnerMoves.pick(list, 0.76)).toBe("b")
		expect(OwnerMoves.pick(list, 0.9999)).toBe("b")
		expect(OwnerMoves.pick(list, 1)).toBe("b")
	end,
	["what they do is the same on every screen, and varies"] = function()
		local temper = OwnerMoves.TEMPERAMENTS.Child
		local acts = OwnerMoves.acts(temper, 1234)
		local seen, busy, total = {}, 0, 0
		for i = 0, 6000 do
			local now = 50000 + i * 0.1
			local a, t = OwnerMoves.actAt(temper, acts, 1234, now)
			local b, u = OwnerMoves.actAt(temper, acts, 1234, now)
			expect(a).toBe(b)
			expect(t).toBe(u)
			if a then
				seen[a] = true
				busy += 1
				expect(t >= 0 and t < OwnerMoves.ACTS[a].time).toBeTruthy()
			end
			total += 1
		end
		local kinds = 0
		for _ in seen do
			kinds += 1
		end
		expect(kinds).toBe(#temper.acts) -- every one of theirs turns up over ten minutes
		-- A Child fidgets: busy with something a good share of the time.
		expect(busy / total > 0.25 and busy / total < 0.6).toBeTruthy()
	end,
	["each house has its own favourite"] = function()
		local temper = OwnerMoves.TEMPERAMENTS.OldMan
		local favourites = {}
		for seed = 1, 60 do
			for _, entry in OwnerMoves.acts(temper, seed) do
				local base
				for _, original in temper.acts do
					if original.name == entry.name then
						base = original.weight
					end
				end
				if entry.weight ~= base then
					expect(entry.weight).toBe(base * OwnerMoves.FAVOURITE)
					favourites[entry.name] = true
				end
			end
		end
		local count = 0
		for _ in favourites do
			count += 1
		end
		expect(count >= 5).toBeTruthy() -- different houses, different favourites
	end,
	["goodbyes fit the mood and who they are"] = function()
		for i = 0, 20 do
			local roll = i / 21
			local pleased = OwnerMoves.bye("Child", false, "pleased", roll)
			expect(OwnerMoves.GOODBYES[pleased].slam).toBe(false)
			local cross = OwnerMoves.bye("OldMan", false, "displeased", roll)
			expect(OwnerMoves.GOODBYES[cross].slam).toBe(true)
			local seller = OwnerMoves.bye("Host", true, "pleased", roll)
			expect(seller == "tip" or seller == "nod").toBeTruthy()
		end
	end,
	["they talk by how it's going"] = function()
		local temper = OwnerMoves.TEMPERAMENTS.Host
		expect(OwnerMoves.talk(temper, nil, false)).toBe("greet")
		expect(OwnerMoves.talk(temper, nil, true)).toBe("chest")
		expect(OwnerMoves.talk(temper, "pleased", false)).toBe("chest")
		expect(OwnerMoves.talk(temper, "displeased", true)).toBe("wag")
	end,
}
