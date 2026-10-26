-- Studio command bar / MCP execute_luau (edit mode). Files the candy bar the user imported (their
-- inventory model "candy-bar", 96785013814575) as ReplicatedStorage.Assets.Candy.Bar: its longest
-- side 1 stud (it came in hundreds of studs long), anchored, touching nothing. Modules/CandyPiece
-- sizes copies of it for every piece of candy in the game. Save the place afterwards.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ASSET = 96785013814575

local loaded = InsertService:LoadAsset(ASSET)
local mesh = assert(loaded:FindFirstChildWhichIsA("MeshPart", true), "no mesh in the candy-bar model")
local bar = mesh:Clone()
loaded:Destroy()
bar.Name = "Bar"
local longest = math.max(bar.Size.X, bar.Size.Y, bar.Size.Z)
bar.Size = bar.Size / longest
bar.CFrame = CFrame.new()
bar.Anchored = true
bar.CanCollide = false
bar.CanQuery = false
bar.CanTouch = false
bar.CastShadow = false
bar.Massless = true
bar.CollisionFidelity = Enum.CollisionFidelity.Box

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local folder = assets:FindFirstChild("Candy") or Instance.new("Folder")
folder.Name = "Candy"
folder.Parent = assets
local old = folder:FindFirstChild("Bar")
if old then
	old:Destroy()
end
bar.Parent = folder
print(`[setup_candy] the candy bar is ready at ReplicatedStorage.Assets.Candy.Bar ({bar.Size})`)
