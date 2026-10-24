-- Studio command bar / MCP execute_luau (play mode, Server datamodel, once the world is built):
-- finds z-fighting among the block parts the game builds (lawns, paths, the cottages, the street):
-- two faces in one plane (within GAP), facing the same way and overlapping, which flicker as the
-- camera moves. Meshes are art/scripts/zfight.py's job. Prints the worst pairs.

local GAP = 0.02
local MIN_AREA = 0.05

type Face = { part: BasePart, n: Vector3, d: number, centre: Vector3, u: Vector3, v: Vector3, hu: number, hv: number }

local faces: { Face } = {}
for _, part in workspace:GetDescendants() do
	if part:IsA("Part") and part.Shape == Enum.PartType.Block and part.Transparency < 1 then
		local cf, size = part.CFrame, part.Size
		local axes = { cf.RightVector, cf.UpVector, cf.LookVector }
		local halves = { size.X / 2, size.Y / 2, size.Z / 2 }
		for i = 1, 3 do
			for _, s in { 1, -1 } do
				local n = axes[i] * s
				local centre = cf.Position + n * halves[i]
				local j, k = i % 3 + 1, (i + 1) % 3 + 1
				table.insert(faces, {
					part = part,
					n = n,
					d = n:Dot(centre),
					centre = centre,
					u = axes[j],
					v = axes[k],
					hu = halves[j],
					hv = halves[k],
				})
			end
		end
	end
end

-- Buckets by rounded normal and plane offset, so only near-coplanar faces meet.
local buckets: { [string]: { number } } = {}
local function key(n: Vector3, d: number): string
	return string.format("%d,%d,%d,%d", math.round(n.X * 20), math.round(n.Y * 20), math.round(n.Z * 20), math.floor(d / GAP))
end
for i, f in faces do
	local k = key(f.n, f.d)
	buckets[k] = buckets[k] or {}
	table.insert(buckets[k], i)
end

local function corners(f: Face, u: Vector3, v: Vector3): { Vector2 }
	local pts = {}
	for _, c in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local p = f.centre + f.u * f.hu * c[1] + f.v * f.hv * c[2]
		table.insert(pts, Vector2.new(p:Dot(u), p:Dot(v)))
	end
	-- counter-clockwise
	local a, b, c = pts[1], pts[2], pts[3]
	if (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X) < 0 then
		pts = { pts[4], pts[3], pts[2], pts[1] }
	end
	return pts
end

local function clip(poly: { Vector2 }, a: Vector2, b: Vector2): { Vector2 }
	local out = {}
	local function side(p: Vector2): number
		return (b.X - a.X) * (p.Y - a.Y) - (b.Y - a.Y) * (p.X - a.X)
	end
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		local sp, sq = side(p), side(q)
		if sp >= 0 then
			table.insert(out, p)
		end
		if (sp >= 0) ~= (sq >= 0) then
			table.insert(out, p + (q - p) * (sp / (sp - sq)))
		end
	end
	return out
end

local function area(poly: { Vector2 }): number
	local s = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		s += p.X * q.Y - q.X * p.Y
	end
	return math.abs(s) / 2
end

local found = {}
local seen = {}
for i, f in faces do
	local nx, ny, nz = math.round(f.n.X * 20), math.round(f.n.Y * 20), math.round(f.n.Z * 20)
	local dk = math.floor(f.d / GAP)
	for _, ed in { -1, 0, 1 } do
		for _, j in buckets[string.format("%d,%d,%d,%d", nx, ny, nz, dk + ed)] or {} do
			local g = faces[j]
			if j > i and g.part ~= f.part and f.n:Dot(g.n) > 0.9995 and math.abs(f.n:Dot(g.centre) - f.d) < GAP then
				local pair = f.part:GetFullName() .. "|" .. g.part:GetFullName()
				if not seen[pair] then
					local u = f.u
					local v = f.n:Cross(u)
					local poly = corners(f, u, v)
					local other = corners(g, u, v)
					for k = 1, 4 do
						poly = clip(poly, other[k], other[k % 4 + 1])
						if #poly < 3 then
							break
						end
					end
					local a = if #poly >= 3 then area(poly) else 0
					if a >= MIN_AREA then
						seen[pair] = true
						table.insert(found, { a = a, f = f, g = g })
					end
				end
			end
		end
	end
end
table.sort(found, function(x, y)
	return x.a > y.a
end)
print(("[zfight_parts] %d block faces, %d overlapping pairs"):format(#faces, #found))
for n = 1, math.min(#found, 40) do
	local r = found[n]
	print(
		("  %.2f sq  %s (%s) | %s (%s)  at %s"):format(
			r.a,
			r.f.part.Name,
			r.f.part.Parent and r.f.part.Parent.Name or "?",
			r.g.part.Name,
			r.g.part.Parent and r.g.part.Parent.Name or "?",
			tostring(Vector3.new(math.round(r.f.centre.X), math.round(r.f.centre.Y), math.round(r.f.centre.Z)))
		)
	)
end
