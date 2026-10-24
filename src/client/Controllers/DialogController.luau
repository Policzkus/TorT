--!strict
-- How homeowners talk, in the HUD's style: a dark translucent panel with a hairline outline beside
-- the speaker's head, a thin leader line from its corner pointing at them, the words typing out
-- letter by letter, every letter shivering a little (the user's 1023.mp4 reference), with a low
-- muttering voice under them. Your replies are HUD chips stacked under it, a hairline under them
-- running out with the time. say() for lines, ask() for Costume Line's questions.
-- A line stays by the speaker's face wherever you go (smaller the farther you are; hidden while
-- they're off screen), and fades once they've gone back inside or you've walked too far off.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Homeowner = require(script.Parent.HomeownerController)
local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local DialogController = {}

local FONT = Theme.Fonts.Hud
local TEXT_SIZE = 18
local LINE_HEIGHT = 21
local MAX_WIDTH = 250 -- pixels of text per line at most
local PAD = Vector2.new(12, 8)
local TYPE_SPEED = 20 -- letters a second for spoken lines: slow, deliberate
local PAUSES = { ["."] = 0.34, [","] = 0.18, ["?"] = 0.38, ["!"] = 0.34, [";"] = 0.22, [":"] = 0.22 }
local ELLIPSIS_DOT = 0.16 -- a dot followed by another dot ("...") trails off instead of stopping
local HOLD = 1.8 -- seconds a line stays once it's all out, plus reading time per word
local HOLD_PER_WORD = 0.22
local FAR = 32 -- studs from the speaker beyond which the line is dropped
local LOST_GRACE = 0.5 -- seconds a line outlives its speaker going back inside
local SHRINK = { near = 8, far = 32, least = 0.7 } -- studs, and how small a line gets far off
local SUBTITLE_Y = 0.3 -- share of the view's height where a line with no speaker sits
local SHIVER = 1 -- pixels a letter wanders
local SHIVER_EVERY = 0.09 -- seconds between shivers (a low frame rate, like the rest)
local LEADER = 16 -- pixels the leader line runs from the panel's corner toward the face
local GAP = Vector2.new(10, 4) -- where the leader ends: this far left of and above the face
local ACTION = "DialogChoice"
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

type Letter = { label: TextLabel, home: Vector2, at: number, shown: boolean }
type Bubble = {
	frame: Frame,
	letters: { Letter },
	speaker: Model?,
	voice: number,
	started: number,
	typed: number, -- seconds until the last letter is out
	size: Vector2,
	at: Vector2?, -- where the panel's corner is on screen (eased toward where it should be)
	lost: number?, -- when its speaker was last seen gone
	leader: Frame,
	shrink: UIScale, -- smaller the farther off the speaker is
}

local gui: ScreenGui
local widths: { [string]: number } = {} -- each letter's advance, measured at start
local current: Bubble? = nil
local choiceFrame: Frame? = nil
local hideToken = 0
local shiverAt = 0
local lastUpdate = os.clock()

local function widthOf(char: string): number
	return widths[char] or TEXT_SIZE * 0.5
end

local function measure(text: string): number
	local total = 0
	for i = 1, #text do
		total += widthOf(string.sub(text, i, i))
	end
	return total
end

local function wrap(text: string): { string }
	local lines: { string } = {}
	local line = ""
	for word in string.gmatch(text, "%S+") do
		if line == "" then
			line = word
		elseif measure(line .. " " .. word) <= MAX_WIDTH then
			line ..= " " .. word
		else
			table.insert(lines, line)
			line = word
		end
	end
	if line ~= "" then
		table.insert(lines, line)
	end
	return lines
end

local function chipStroke(): UIStroke
	return create("UIStroke", {
		Color = Theme.Colors.Hairline,
		Transparency = 0.85,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function destroyBubble(bubble: Bubble, fade: boolean)
	if not fade then
		bubble.frame:Destroy()
		return
	end
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(bubble.frame, info, { BackgroundTransparency = 1 }):Play()
	for _, descendant in bubble.frame:GetDescendants() do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, info, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("Frame") then
			TweenService:Create(descendant, info, { BackgroundTransparency = 1 }):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.25, function()
		bubble.frame:Destroy()
	end)
end

-- Builds a bubble for `text`; `duration` forces how long the typing takes (questions), otherwise
-- it types at TYPE_SPEED with little pauses after punctuation.
local function newBubble(speaker: Model?, text: string, voice: number, duration: number?): Bubble
	local lines = wrap(text)
	local widest = 0
	for _, line in lines do
		widest = math.max(widest, measure(line))
	end
	local size = Vector2.new(math.ceil(widest) + PAD.X * 2, #lines * LINE_HEIGHT + PAD.Y * 2)
	local frame = create("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		create("UICorner", { CornerRadius = Theme.Corner }),
		chipStroke(),
		-- The leader: a hairline from the bottom-right corner down toward the speaker.
		create("Frame", {
			Name = "Leader",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, -2, 1, 2),
			Size = UDim2.fromOffset(LEADER, 1),
			Rotation = 40,
			BackgroundColor3 = Theme.Colors.Hairline,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
		}),
	})
	local total = 0
	for _, line in lines do
		total += #line
	end
	local step = if duration then duration / math.max(1, total) else 1 / TYPE_SPEED
	local letters: { Letter } = {}
	local t = 0
	for row, line in lines do
		local x = PAD.X + (widest - measure(line)) / 2
		for column = 1, #line do
			local char = string.sub(line, column, column)
			t += step
			local advance = widthOf(char)
			if char ~= " " then
				local home = Vector2.new(x, PAD.Y + (row - 1) * LINE_HEIGHT)
				local label = create("TextLabel", {
					Name = "L",
					Position = UDim2.fromOffset(home.X, home.Y),
					Size = UDim2.fromOffset(advance + 2, LINE_HEIGHT),
					BackgroundTransparency = 1,
					FontFace = FONT,
					Text = char,
					TextColor3 = Theme.Colors.Text,
					TextSize = TEXT_SIZE,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTransparency = 1,
					ZIndex = 2,
					Parent = frame,
				})
				table.insert(letters, { label = label, home = home, at = t, shown = false })
			end
			x += advance
			if duration == nil then
				local nextChar = string.sub(line, column + 1, column + 1)
				t += if char == "." and nextChar == "." then ELLIPSIS_DOT else PAUSES[char] or 0
			end
		end
		t += step -- the line break
	end
	frame.Parent = gui
	return {
		frame = frame,
		letters = letters,
		speaker = speaker,
		voice = voice,
		started = os.clock(),
		typed = t,
		size = size,
		at = nil,
		lost = nil,
		leader = frame:FindFirstChild("Leader") :: Frame,
		shrink = create("UIScale", { Parent = frame }),
	}
end

-- Where the panel's bottom-right corner should be and how: "face" up and left of the speaker's
-- face (its size for how far off they are), "hidden" while they're off screen, "alone" in the
-- upper middle of the view for a line with no speaker. Nil when the line should end: its speaker
-- went back inside, or you walked too far off.
local function placement(bubble: Bubble, viewport: Vector2, scale: number): (Vector2?, string, number)
	local camera = Workspace.CurrentCamera
	local speaker = bubble.speaker
	if speaker == nil or camera == nil then
		return Vector2.new(viewport.X * 0.5 + bubble.size.X * 0.5 * scale, viewport.Y * SUBTITLE_Y), "alone", 1
	end
	local face = if speaker.Parent then Homeowner.face(speaker) else nil
	if face == nil then
		bubble.lost = bubble.lost or os.clock()
		if os.clock() - (bubble.lost :: number) > LOST_GRACE then
			return nil, "gone", 1
		end
		return bubble.at, "face", 1
	end
	bubble.lost = nil
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local distance = if root then (root.Position - face).Magnitude else 0
	if distance > FAR then
		return nil, "gone", 1
	end
	local point, onScreen = camera:WorldToViewportPoint(face)
	if not onScreen or point.Z <= 0 then
		return nil, "hidden", 1
	end
	local size =
		math.clamp(1 - (distance - SHRINK.near) / (SHRINK.far - SHRINK.near) * (1 - SHRINK.least), SHRINK.least, 1)
	-- Leave room for the head itself: about a stud on screen.
	local edge = camera:WorldToViewportPoint(face + camera.CFrame.RightVector * 0.9)
	local radius = math.abs(edge.X - point.X)
	local reach = LEADER * scale * size * 0.75
	local tip = Vector2.new(point.X - radius - GAP.X * size, point.Y - GAP.Y * size)
	return Vector2.new(tip.X - reach, tip.Y - reach * 0.85), "face", size
end

local function update()
	local bubble = current
	local now = os.clock()
	local dt = math.min(now - lastUpdate, 0.1)
	lastUpdate = now
	if bubble == nil then
		return
	end
	local scale = Scale.get()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1100, 620)
	local want, how, size = placement(bubble, viewport, scale)
	if how == "gone" then
		current = nil
		destroyBubble(bubble, true)
		return
	end
	if how == "hidden" or want == nil then
		bubble.frame.Visible = false
		bubble.at = nil -- snap back to them when they're in view again
	else
		bubble.frame.Visible = true
		bubble.shrink.Scale = size
		-- Ease toward it (snap the first time), and keep the whole panel on screen.
		local at = if bubble.at then (bubble.at :: Vector2):Lerp(want, 1 - math.exp(-dt * 14)) else want
		bubble.at = at
		local w, h = bubble.size.X * scale * size, bubble.size.Y * scale * size
		local x = math.clamp(at.X, w + 8, viewport.X - 8)
		local y = math.clamp(at.Y, h + 8, viewport.Y - 8)
		bubble.frame.Position = UDim2.fromOffset(x / scale, y / scale)
		bubble.leader.Visible = how == "face"
	end

	local elapsed = os.clock() - bubble.started
	local shiver = os.clock() >= shiverAt
	if shiver then
		shiverAt = os.clock() + SHIVER_EVERY
	end
	for index, letter in bubble.letters do
		if not letter.shown and elapsed >= letter.at then
			letter.shown = true
			letter.label.TextTransparency = 0
			letter.label.TextSize = TEXT_SIZE * 1.3
			TweenService:Create(letter.label, TweenInfo.new(0.08), { TextSize = TEXT_SIZE }):Play()
			if index % 2 == 1 then
				Sound.play("Voice", { speed = bubble.voice * (0.9 + math.random() * 0.2), volume = 0.35 })
			end
		end
		if shiver and letter.shown then
			local offset = Vector2.new(math.random() * 2 - 1, math.random() * 2 - 1) * SHIVER
			letter.label.Position = UDim2.fromOffset(letter.home.X + offset.X, letter.home.Y + offset.Y)
			letter.label.Rotation = (math.random() * 2 - 1) * 4
		end
	end
end

local function closeChoices()
	ContextActionService:UnbindAction(ACTION)
	GuiService.SelectedObject = nil
	local frame = choiceFrame
	choiceFrame = nil
	if frame then
		task.delay(0.6, function()
			frame:Destroy()
		end)
	end
end

-- Says a line over the speaker's (a house's homeowner's) head; it stays a moment after the last
-- letter, then fades. A new line replaces the old one.
function DialogController.say(speaker: Model?, text: string, voice: number?)
	if current then
		destroyBubble(current, false)
	end
	local bubble = newBubble(speaker, text, voice or 1)
	current = bubble
	hideToken += 1
	local token = hideToken
	local _, words = string.gsub(text, "%S+", "")
	task.delay(bubble.typed + HOLD + words * HOLD_PER_WORD, function()
		if hideToken == token and current == bubble then
			current = nil
			destroyBubble(bubble, true)
		end
	end)
end

export type Asked = {
	mark: (chosen: number, right: number) -> (),
	setTime: (left: number) -> (), -- 0..1 of the answer time left
	close: () -> (),
}

-- Asks a question: the text types out over `readTime` seconds, then the replies appear under it.
-- `onChoose(index)` fires once, on a click, a tap, keys 1-4 or the gamepad.
function DialogController.ask(
	speaker: Model?,
	text: string,
	choices: { string },
	voice: number?,
	readTime: number,
	onChoose: (index: number) -> ()
): Asked
	if current then
		destroyBubble(current, false)
	end
	closeChoices()
	hideToken += 1
	local bubble = newBubble(speaker, text, voice or 1, readTime)
	current = bubble

	local timeLine = create("Frame", {
		Name = "Time",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Colors.Hairline,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	})
	local list = create("Frame", {
		Name = "Choices",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("Frame", { -- holds the time line, under the last reply
			Name = "TimeRow",
			Size = UDim2.new(0.5, 0, 0, 1),
			BackgroundTransparency = 1,
			LayoutOrder = 99,
			timeLine,
		}),
		-- First person locks the mouse; a visible modal button frees it while you choose.
		create("TextButton", {
			Name = "MouseUnlock",
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = "",
			Modal = true,
			LayoutOrder = 100,
		}),
		Parent = gui,
	})
	choiceFrame = list

	local chosen = false
	local buttons: { TextButton } = {}
	local function choose(index: number)
		if chosen or not list.Visible or buttons[index] == nil then
			return
		end
		chosen = true
		Sound.play("Click")
		onChoose(index)
	end
	for index, choice in choices do
		local stroke = chipStroke()
		local button = create("TextButton", {
			Name = "Choice" .. index,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = Theme.TileTransparency,
			AutoButtonColor = false,
			FontFace = FONT,
			Text = choice,
			TextColor3 = Theme.Colors.Text,
			TextSize = 17,
			TextWrapped = true,
			LayoutOrder = index,
			create("UICorner", { CornerRadius = Theme.Corner }),
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 7),
			}),
			create("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge) }),
			stroke,
			Parent = list,
		})
		button.MouseEnter:Connect(function()
			if not chosen then
				button.BackgroundTransparency = 0.12
				stroke.Transparency = 0.4
				Sound.play("Hover")
			end
		end)
		button.MouseLeave:Connect(function()
			if not chosen then
				button.BackgroundTransparency = Theme.TileTransparency
				stroke.Transparency = 0.85
			end
		end)
		button.Activated:Connect(function()
			choose(index)
		end)
		buttons[index] = button
	end

	-- The replies come once the question is out.
	task.delay(readTime, function()
		if choiceFrame ~= list then
			return
		end
		list.Visible = true
		for i, button in buttons do
			local scale = create("UIScale", { Scale = 0.9, Parent = button })
			button.BackgroundTransparency = 1
			button.TextTransparency = 1
			task.delay((i - 1) * 0.05, function()
				local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(scale, info, { Scale = 1 }):Play()
				TweenService
					:Create(button, info, { BackgroundTransparency = Theme.TileTransparency, TextTransparency = 0 })
					:Play()
			end)
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = buttons[1]
		end
	end)
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local index = table.find(KEYS, input.KeyCode)
			if index then
				choose(index)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(KEYS))

	local function close()
		if choiceFrame == list then
			closeChoices()
		end
		if current == bubble then
			current = nil
			destroyBubble(bubble, true)
		end
	end
	return {
		mark = function(picked: number, right: number)
			chosen = true
			for index, button in buttons do
				local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
				if index == right then
					stroke.Color = Theme.Colors.Success
					stroke.Transparency = 0
				elseif index == picked then
					stroke.Color = Theme.Colors.Danger
					stroke.Transparency = 0
				else
					button.TextTransparency = 0.6
				end
			end
			task.delay(0.9, close)
		end,
		setTime = function(left: number)
			local share = math.clamp(left, 0, 1)
			timeLine.Size = UDim2.new(share, 0, 0, 1)
			timeLine.Position = UDim2.fromScale((1 - share) / 2, 0)
			timeLine.BackgroundColor3 = if share < 0.25 then Theme.Colors.Danger else Theme.Colors.Hairline
		end,
		close = close,
	}
end

-- Ends whatever is being said right now.
function DialogController.clear()
	closeChoices()
	if current then
		destroyBubble(current, true)
		current = nil
	end
end

function DialogController.Init()
	gui = create("ScreenGui", {
		Name = "Dialog",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 25, -- over the mini-game panel
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
end

function DialogController.Start()
	RunService.RenderStepped:Connect(update)
	-- Each printable letter's width in the HUD font, measured once (until then, a guess).
	local params = Instance.new("GetTextBoundsParams")
	params.Font = FONT
	params.Size = TEXT_SIZE
	params.Width = 10000
	-- Measured between two bars so spaces and side bearings count.
	params.Text = "||"
	local okBars, bars = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if not okBars then
		return
	end
	for code = 32, 126 do
		local char = string.char(code)
		-- Ten in a row: the bounds come back in whole pixels, a tenth of the error per letter.
		params.Text = "|" .. string.rep(char, 10) .. "|"
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		if ok then
			widths[char] = ((bounds :: Vector2).X - (bars :: Vector2).X) / 10
		end
	end
end

return DialogController
