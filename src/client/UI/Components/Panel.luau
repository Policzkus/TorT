--!strict
-- Centered modal window with a title bar and close button. Opening one panel closes the others.
-- Bouncy Back-easing open/close (PROMPT §3.18).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Modules.Signal)
local Button = require(script.Parent.Button)
local Scale = require(script.Parent.Parent.Scale)
local Theme = require(script.Parent.Parent.Theme)
local create = require(script.Parent.Parent.create)

export type Panel = {
	gui: ScreenGui,
	frame: Frame,
	content: Frame,
	Opened: Signal.Signal,
	Closed: Signal.Signal,
	open: (self: Panel) -> (),
	close: (self: Panel) -> (),
	toggle: (self: Panel) -> (),
	isOpen: (self: Panel) -> boolean,
}

export type Options = { name: string, title: string, size: Vector2 }

local Panel = {}
Panel.__index = Panel

local all: { Panel } = {}
local OPEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

function Panel.new(options: Options): Panel
	local popScale = create("UIScale", { Name = "Pop", Scale = 0 })
	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 1, -82),
		BackgroundTransparency = 1,
	})
	local frame: Frame = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(options.size.X, options.size.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
		Visible = false,
		popScale,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Hairline, Transparency = 0.7, Thickness = 1 }),
		create("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(18, 10),
			Size = UDim2.new(1, -90, 0, 46),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Heading,
			Text = string.upper(options.title),
			TextColor3 = Theme.Colors.Text,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		content,
		create("TextButton", {
			Name = "MouseUnlock",
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = "",
			Modal = true, -- frees the mouse in first person while this window is visible
		}),
	})
	local gui: ScreenGui = create("ScreenGui", {
		Name = options.name,
		ResetOnSpawn = false,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		frame,
	})
	Scale.attach(gui)

	local self = setmetatable({
		gui = gui,
		frame = frame,
		content = content,
		Opened = Signal.new(),
		Closed = Signal.new(),
		_open = false,
		_scale = popScale,
	}, Panel) :: any

	Button.new({
		name = "Close",
		text = "X",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.PanelLight,
		textSize = 22,
		parent = frame,
		onClick = function()
			self:close()
		end,
	})

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(all, self)
	return self
end

function Panel.open(self: any)
	if self._open then
		return
	end
	for _, other in all do
		if other ~= self and other:isOpen() then
			other:close()
		end
	end
	self._open = true
	self.frame.Visible = true
	self._scale.Scale = 0.6
	TweenService:Create(self._scale, OPEN, { Scale = 1 }):Play()
	self.Opened:Fire()
end

function Panel.close(self: any)
	if not self._open then
		return
	end
	self._open = false
	local tween = TweenService:Create(self._scale, CLOSE, { Scale = 0 })
	tween.Completed:Once(function()
		if not self._open then
			self.frame.Visible = false
		end
	end)
	tween:Play()
	self.Closed:Fire()
end

function Panel.toggle(self: any)
	if self._open then
		self:close()
	else
		self:open()
	end
end

function Panel.isOpen(self: any): boolean
	return self._open
end

function Panel.closeAll()
	for _, panel in all do
		panel:close()
	end
end

return Panel
