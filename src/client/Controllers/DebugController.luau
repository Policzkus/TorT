--!strict
-- TEMPORARY (Phase 0): bottom-left readout proving data loads, saves and syncs.
-- Replaced by the real HUD in Phase 1.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local Format = require(Shared.Modules.Format)
local StateController = require(script.Parent.StateController)
local create = require(script.Parent.Parent.UI.create)
local Theme = require(script.Parent.Parent.UI.Theme)

local DebugController = {}

function DebugController.Start()
	local label = create("TextLabel", {
		Name = "DebugReadout",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Loading data...",
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
	})
	create("ScreenGui", {
		Name = "Debug",
		ResetOnSpawn = false,
		DisplayOrder = 40,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		label,
	})

	local function refresh()
		if not StateController.isLoaded() then
			return
		end
		label.Text = string.format(
			"DEV v%s   🍬 %s   🪣 %s   👻 %s souls   ☠ %d rebirths",
			GameConfig.VERSION,
			Format.number(StateController.get("candy")),
			Format.number(StateController.get("bucket")),
			Format.number(StateController.get("souls")),
			StateController.get("rebirths")
		)
	end
	for _, key in { "candy", "bucket", "souls", "rebirths" } do
		StateController.observe(key, refresh)
	end
	StateController.Loaded:Connect(refresh)
	refresh()
end

return DebugController
