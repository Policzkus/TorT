--!strict
-- Settings menu (PROMPT §3.18): music and SFX volume, jumpscare intensity, reduce flashing.
-- Changes apply instantly and are saved to the profile (SettingsService validates them).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local ProgressBar = require(script.Parent.Parent.UI.Components.ProgressBar)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local VOLUME_STEP = 0.1
local JUMPSCARE_MODES = { "Full", "Reduced", "Off" }
local JUMPSCARE_INFO = {
	Full = "Monsters, stingers and screen flashes",
	Reduced = "Monsters only: no stinger, no flash",
	Off = 'Just a friendly "BOO!" on screen',
}

local SettingsController = {}

local panel: Panel.Panel
local current = { music = 0.5, sfx = 1, jumpscare = "Full", reduceFlash = false }
local refreshers: { () -> () } = {}
local saveQueued = false

local function save()
	Sound.setVolumes(current.music, current.sfx)
	for _, refresh in refreshers do
		refresh()
	end
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(0.6, function() -- batch quick clicks into one save
		saveQueued = false
		Net.event("SaveSettings"):FireServer(current)
	end)
end

local function row(parent: Instance, order: number, label: string): Frame
	return create("Frame", {
		Name = label,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundColor3 = Theme.Colors.PanelLight,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
		create("TextLabel", {
			Name = "Label",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0, 170, 1, 0),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = label,
			TextColor3 = Theme.Colors.Text,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
		}),
		Parent = parent,
	})
end

local function volumeRow(parent: Instance, order: number, label: string, key: "music" | "sfx")
	local frame = row(parent, order, label)
	local bar = ProgressBar.new({
		size = UDim2.new(1, -330, 0, 22),
		position = UDim2.new(0, 230, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Theme.Colors.Orange,
		parent = frame,
	})
	local function change(delta: number)
		current[key] = math.clamp(math.round((current[key] + delta) * 10) / 10, 0, 1)
		save()
		if key == "sfx" then
			Sound.play("Pop")
		end
	end
	Button.new({
		name = "Down",
		text = "-",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(0, 178, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Theme.Colors.PanelDark,
		textSize = 28,
		parent = frame,
		onClick = function()
			change(-VOLUME_STEP)
		end,
	})
	Button.new({
		name = "Up",
		text = "+",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(1, -52, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Theme.Colors.PanelDark,
		textSize = 28,
		parent = frame,
		onClick = function()
			change(VOLUME_STEP)
		end,
	})
	table.insert(refreshers, function()
		bar:set(current[key], true)
		bar:setText(`{math.round(current[key] * 100)}%`)
	end)
end

local function jumpscareRow(parent: Instance, order: number)
	local frame = row(parent, order, "Jumpscares")
	frame.Size = UDim2.new(1, -8, 0, 92)
	local info = create("TextLabel", {
		Name = "Info",
		Position = UDim2.fromOffset(14, 62),
		Size = UDim2.new(1, -28, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local label = frame:FindFirstChild("Label") :: TextLabel
	label.Size = UDim2.fromOffset(170, 60)
	local buttons: { [string]: TextButton } = {}
	for index, mode in JUMPSCARE_MODES do
		buttons[mode] = Button.new({
			name = mode,
			text = mode,
			size = UDim2.fromOffset(104, 42),
			position = UDim2.fromOffset(178 + (index - 1) * 112, 10),
			color = Theme.Colors.PanelDark,
			textSize = 19,
			parent = frame,
			onClick = function()
				current.jumpscare = mode
				save()
			end,
		})
	end
	table.insert(refreshers, function()
		for mode, button in buttons do
			button.BackgroundColor3 = if current.jumpscare == mode then Theme.Colors.Orange else Theme.Colors.PanelDark
		end
		info.Text = JUMPSCARE_INFO[current.jumpscare] or ""
	end)
end

local function flashRow(parent: Instance, order: number)
	local frame = row(parent, order, "Reduce flashing")
	local toggle = Button.new({
		name = "Toggle",
		text = "",
		size = UDim2.fromOffset(104, 42),
		position = UDim2.new(0, 178, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Theme.Colors.PanelDark,
		textSize = 19,
		parent = frame,
		onClick = function()
			current.reduceFlash = not current.reduceFlash
			save()
		end,
	})
	table.insert(refreshers, function()
		toggle.Text = if current.reduceFlash then "ON" else "OFF"
		toggle.BackgroundColor3 = if current.reduceFlash then Theme.Colors.Slime else Theme.Colors.PanelDark
	end)
end

function SettingsController.toggle()
	panel:toggle()
end

function SettingsController.Start()
	panel = Panel.new({ name = "SettingsPanel", title = "⚙ Settings", size = Vector2.new(600, 420) })
	local list = create("Frame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		Parent = panel.content,
	})
	volumeRow(list, 1, "🎵 Music", "music")
	volumeRow(list, 2, "🔊 Sounds", "sfx")
	jumpscareRow(list, 3)
	flashRow(list, 4)

	StateController.observe("settings", function(settings: any)
		if type(settings) == "table" then
			for key, value in settings do
				(current :: any)[key] = value
			end
			Sound.setVolumes(current.music, current.sfx)
			for _, refresh in refreshers do
				refresh()
			end
		end
	end)
	for _, refresh in refreshers do
		refresh()
	end
end

return SettingsController
