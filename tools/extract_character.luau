-- Studio command-bar / MCP execute_luau snippet (edit mode): turns a segmented AI character into a
-- Config/Characters entry. Generate with segmentation = "explicit" and
-- partNames = head, torso, left arm, right arm, left leg, right leg. Then select the generated
-- model, set KEY and HEIGHT below and run this; paste the output into Config/Characters.
-- Generated characters face +Z (their parts come rotated 180°), so everything is rotated to face
-- -Z. Left/right labels from the generator are unreliable, so arms and legs are sided by position.

local KEY = "Costume_Something"
local HEIGHT = 4.6 -- studs, feet to top (kids are ~4.4–4.8; hats and ears count)

local model = game:GetService("Selection"):Get()[1]
assert(model and model:IsA("Model"), "Select the generated model first")

local function r(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function id(content: string): string
	return string.match(content, "%d+") or "0"
end

local cf, size = model:GetBoundingBox()
local minY = cf.Position.Y - size.Y / 2
local scale = HEIGHT / size.Y
local lines = {}
for _, part in model:GetDescendants() do
	if part:IsA("MeshPart") then
		local raw = string.lower(part.Name)
		local x = -(part.Position.X - cf.Position.X) * scale
		local y = (part.Position.Y - minY) * scale
		local z = -(part.Position.Z - cf.Position.Z) * scale
		local segment = if string.find(raw, "head")
			then "Head"
			elseif string.find(raw, "torso") then "Torso"
			elseif string.find(raw, "arm") then (if x < 0 then "LeftArm" else "RightArm")
			else (if x < 0 then "LeftLeg" else "RightLeg")
		table.insert(
			lines,
			string.format(
				"\t\t\t%s = { mesh = %s, texture = %s, size = { %s, %s, %s }, offset = { %s, %s, %s } },",
				segment,
				id(part.MeshId),
				id(part.TextureID),
				r(part.Size.X * scale),
				r(part.Size.Y * scale),
				r(part.Size.Z * scale),
				r(x),
				r(y),
				r(z)
			)
		)
	end
end
table.sort(lines)
print(
	`\t{KEY} = \{\n\t\teye = ?, -- eye height; check the face in the preview\n\t\tsegments = \{\n{table.concat(
		lines,
		"\n"
	)}\n\t\t\},\n\t\},`
)
