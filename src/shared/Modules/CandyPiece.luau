--!strict
-- A piece of candy in the world: the wrapped candy bar the user imported
-- (ReplicatedStorage.Assets.Candy.Bar, filed by tools/setup_candy.luau with its longest side 1
-- stud). Everywhere the game shows candy uses it: the bucket filling up, the Candy Box, the shop's
-- jars, the bowls, the candy a homeowner hands over, the candy thrown when the car hits you. Until
-- it's in the place, a coloured ball.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CandyPiece = {}

local LENGTH = 1.5 -- a bar this many times the ball it stands in for (a ball `size` across is chunkier)

local function template(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Candy")
	local bar = folder and folder:FindFirstChild("Bar")
	return if bar and bar:IsA("BasePart") then bar else nil
end

-- A new piece where a ball `size` studs across would be (unparented, at the origin). `color` is the
-- ball's, if it comes to that.
function CandyPiece.make(size: number, color: Color3): BasePart
	local bar = template()
	if bar then
		local piece = bar:Clone()
		piece.Size = bar.Size * size * LENGTH
		return piece
	end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * size
	ball.Color = color
	ball.Material = Enum.Material.SmoothPlastic
	ball.TopSurface = Enum.SurfaceType.Smooth
	ball.BottomSurface = Enum.SurfaceType.Smooth
	return ball
end

-- A turn for piece number `index`, the same every time, so a heap of them lies jumbled: any way
-- round, tipped only a little (bars lying in a pile, wrapper up, not standing on end).
function CandyPiece.tumble(index: number): CFrame
	return CFrame.Angles(0, (index * 2.39) % (2 * math.pi), 0)
		* CFrame.Angles((index * 0.53) % 0.7 - 0.35, 0, (index * 0.31) % 0.6 - 0.3)
end

return CandyPiece
