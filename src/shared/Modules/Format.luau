--!strict
-- Number and time formatting for UI. Pure module (unit-tested in tests/format.spec.luau).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
-- Guards against float error, e.g. 1.23 * 100 = 122.99999999999999.
local EPSILON = 1e-9

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- 999 -> "999", 1234 -> "1.23K", 12345 -> "12.3K", 999999 -> "999K", 1.5e6 -> "1.5M".
-- Truncates instead of rounding so a value never displays higher than it is.
function Format.number(value: number): string
	if value ~= value then
		return "0"
	end
	if value == math.huge or value == -math.huge then
		return if value > 0 then "∞" else "-∞"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		return sign .. tostring(math.floor(n + EPSILON))
	end

	local tier = math.min(math.floor(math.log10(n + EPSILON) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled < 10 then
		text = string.format("%.2f", math.floor(scaled * 100 + EPSILON) / 100)
	elseif scaled < 100 then
		text = string.format("%.1f", math.floor(scaled * 10 + EPSILON) / 10)
	else
		text = tostring(math.floor(scaled + EPSILON))
	end
	return sign .. trimZeros(text) .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.commas(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = tostring(math.floor(math.abs(value) + EPSILON))
	local result = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	result = string.gsub(result, "^,", "")
	return sign .. result
end

-- 65 -> "1:05", 3723 -> "1:02:03"
function Format.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 45 -> "45s", 125 -> "2m 5s", 7500 -> "2h 5m"
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return `{s}s`
	end
	if s < 3600 then
		local m, sec = s // 60, s % 60
		return if sec > 0 then `{m}m {sec}s` else `{m}m`
	end
	local h, m = s // 3600, (s % 3600) // 60
	return if m > 0 then `{h}h {m}m` else `{h}h`
end

return Format
