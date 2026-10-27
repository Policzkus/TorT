--!strict
-- How homeowners talk, in the HUD's style: a dark translucent panel with a hairline outline beside
-- the speaker's head, a thin leader line from its corner pointing at them, the words typing out
-- letter by letter, every letter shivering a little (the user's 1023.mp4 reference), with a low
-- muttering voice under them. Your replies are HUD chips stacked under it, a hairline under them
-- running out with the time, gone the moment you answer (or the time's up). say() for lines, ask()
-- for Costume Line's questions.
-- The panel is in the world, not on the screen (the user wants dialogue 3D): a surface beside the
-- speaker's head at about mouth height, on your left of it, its leader running straight in to the
-- edge of the head as you see it, the panel square to your view (no tilt however you look up at
-- them; drawn a little bigger the farther off you are, to stay readable). So nothing on the porch
-- hides it, it's drawn nearer you along your line of sight, scaled down to match: it looks just the
-- same, beside their head (SurfaceGui.AlwaysOnTop didn't draw at all). It stays by them wherever you
-- go, and fades once they've gone back inside or you've walked too far off. Your replies are your
-- own, so they stay on the HUD.
-- Lines are quick, and yours to skip (the user wanted a faster game): a left click (a tap, Ⓨ) shows
-- the rest of the line at once, again puts it away; once it's all out, moving the mouse puts it away.
-- (Not Space: that's the mini-games'.) A click counts wherever it lands except on a button on the
-- screen: something else having had it first (a door's prompt in the middle of the view, a panel)
-- used to swallow it, and the line stayed. A question (Costume Line) isn't skipped: it's timed.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Dialogue = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Dialogue)
local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Modules.Signal)
local Homeowner = require(script.Parent.HomeownerController)
local Sound = require(script.Parent.SoundController)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local DialogController = {}

DialogController.skipped = Signal.new() -- (speaker: Model?) you put a line away with a click or a key

local FONT = Theme.Fonts.Hud
local TEXT_SIZE = 18
local LINE_HEIGHT = 21
local MAX_WIDTH = 250 -- pixels of text per line at most
local PAD = Vector2.new(12, 8)
-- Typing speed, pauses and how long a line stays: shared with the server (Config/Dialogue.TIMING),
-- which waits a homeowner's last line out before they go back in.
local TYPE_SPEED = Dialogue.TIMING.TYPE_SPEED
local PAUSES = Dialogue.TIMING.PAUSES
local ELLIPSIS_DOT = Dialogue.TIMING.ELLIPSIS_DOT
local HOLD = Dialogue.TIMING.HOLD
local HOLD_PER_WORD = Dialogue.TIMING.HOLD_PER_WORD
local SKIP = "DialogSkip"
-- Put a line away: a left click (or a tap: below), Ⓨ on a gamepad. Not Space: that's the mini-games'
-- (the user wanted the two apart).
local SKIP_KEYS = { Enum.KeyCode.ButtonY }
local LOOK_AWAY = 60 -- pixels of mouse movement, once a line is all out, that put it away
local FAR = 32 -- studs from the speaker beyond which the line is dropped
local LOST_GRACE = 0.5 -- seconds a line outlives its speaker going back inside
local PIXELS = 68 -- the panel's pixels a stud, close up (fewer: bigger)
local GROW = { near = 10, far = 26, most = 1.7 } -- studs off, and how much bigger it's drawn far off
local MOUTH = 0.4 -- studs under the face (its eyes) the panel's middle sits: about the mouth
local ROUND = 0.88 -- heads are round: their edge is this share of their box's
local NEAR = 3.5 -- studs from your eye it's drawn at, at most (scaled to look the same)
local SUBTITLE = 6 -- studs in front of you a line with no speaker floats
local SHIVER = 1 -- pixels a letter wanders
local SHIVER_EVERY = 0.09 -- seconds between shivers (a low frame rate, like the rest)
local LEADER = 14 -- pixels the leader line runs from the panel's side in to the head
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
	canvas: Vector2, -- pixels: the panel and room for its leader
	part: BasePart, -- what it's drawn on, in the world
	surface: SurfaceGui,
	at: Vector3?, -- where its middle is, beside the head (eased toward where it should be)
	lost: number?, -- when its speaker was last seen gone
	leader: Frame,
	rushed: boolean, -- skipped to the end (the rest of the letters show silently)
	said: boolean, -- a line (yours to skip), not a question
}

local gui: ScreenGui
local widths: { [string]: number } = {} -- each letter's advance, measured at start
local current: Bubble? = nil
local choiceFrame: Frame? = nil
local hideToken = 0
local lookedAway = 0 -- pixels the mouse has moved since the current line was all out
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
		bubble.part:Destroy()
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
		bubble.part:Destroy()
	end)
end

-- Builds a bubble for `text`; `duration` forces how long the typing takes (questions), otherwise
-- it types at TYPE_SPEED with little pauses after punctuation. It goes into the world on its first
-- update, where it belongs.
local function newBubble(speaker: Model?, text: string, voice: number, duration: number?): Bubble
	local lines = wrap(text)
	local widest = 0
	for _, line in lines do
		widest = math.max(widest, measure(line))
	end
	local size = Vector2.new(math.ceil(widest) + PAD.X * 2, #lines * LINE_HEIGHT + PAD.Y * 2)
	-- The panel on the left of its surface; the leader runs on from its right side to the edge.
	local canvas = size + Vector2.new(LEADER, 0)
	local part = create("Part", {
		Name = "Line",
		Size = Vector3.new(canvas.X / PIXELS, canvas.Y / PIXELS, 0.05),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	})
	local surface = create("SurfaceGui", {
		Name = "Line",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS,
		LightInfluence = 0,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = part,
	})
	local frame = create("Frame", {
		Name = "Bubble",
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.18, -- more solid than a HUD tile: porch lamps behind don't wash the words out
		create("UICorner", { CornerRadius = Theme.Corner }),
		chipStroke(),
		-- The leader: a hairline from the middle of the right side straight in to the speaker's head.
		create("Frame", {
			Name = "Leader",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(LEADER, 1),
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
	frame.Parent = surface
	return {
		frame = frame,
		letters = letters,
		speaker = speaker,
		voice = voice,
		started = os.clock(),
		typed = t,
		size = size,
		canvas = canvas,
		part = part,
		surface = surface,
		at = nil,
		lost = nil,
		leader = frame:FindFirstChild("Leader") :: Frame,
		rushed = false,
		said = false,
	}
end

-- How far a part reaches from its middle along `axis` (its box, turned however it's turned).
local function reach(part: BasePart, axis: Vector3): number
	local cf, size = part.CFrame, part.Size
	return math.abs(cf.RightVector:Dot(axis)) * size.X / 2
		+ math.abs(cf.UpVector:Dot(axis)) * size.Y / 2
		+ math.abs(cf.LookVector:Dot(axis)) * size.Z / 2
end

-- Where the panel's middle should be in the world, how, and how much bigger it's drawn: "face",
-- beside the speaker's head on your left at about mouth height, the end of its leader on the edge
-- of the head as you see it; "alone", floating in front of you for a line with no speaker. Nil
-- when the line should end: its speaker went back inside, or you walked too far off.
local function placement(bubble: Bubble): (Vector3?, string, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return bubble.at, "alone", 1
	end
	local speaker = bubble.speaker
	if speaker == nil then
		return (camera.CFrame * CFrame.new(0, 0.9, -SUBTITLE)).Position, "alone", 1
	end
	-- They've started back in: the line goes now (the server waits it out first, so this is only
	-- when a visit ends early).
	if speaker:GetAttribute("OwnerOut") == false then
		return nil, "gone", 1
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
	local grow = math.clamp(1 + (distance - GROW.near) / (GROW.far - GROW.near) * (GROW.most - 1), 1, GROW.most)
	local width = bubble.canvas.X / PIXELS * grow
	-- The head as you see it: its left edge (your left), at mouth height.
	local figure = Homeowner.current(speaker)
	local head = figure and figure.Parent and figure.Parent:FindFirstChild("Head") :: BasePart?
	local centre = if head then head.Position else face
	local left = -camera.CFrame.RightVector
	local side = if head then reach(head, left) * ROUND else 0.6
	local tip = Vector3.new(centre.X, face.Y - MOUTH, centre.Z) + left * side
	return tip + left * (width / 2), "face", grow
end

local function update()
	local bubble = current
	local now = os.clock()
	local dt = math.min(now - lastUpdate, 0.1)
	lastUpdate = now
	if bubble == nil then
		return
	end
	local want, how, grow = placement(bubble)
	if how == "gone" then
		current = nil
		destroyBubble(bubble, true)
		return
	end
	local camera = Workspace.CurrentCamera
	if want and camera then
		-- Ease toward it (snap the first time).
		local at = if bubble.at then (bubble.at :: Vector3):Lerp(want, 1 - math.exp(-dt * 14)) else want
		bubble.at = at
		-- Square to your view, and drawn nearer you on the same line of sight, scaled to match.
		local eye = camera.CFrame.Position
		local pull = math.clamp(NEAR / math.max((at - eye).Magnitude, 0.01), 0.15, 1)
		local drawn = eye + (at - eye) * pull
		local scale = grow * pull
		bubble.part.Size = Vector3.new(bubble.canvas.X / PIXELS * scale, bubble.canvas.Y / PIXELS * scale, 0.05)
		bubble.surface.PixelsPerStud = PIXELS / scale
		bubble.part.CFrame = CFrame.lookAt(drawn, drawn - camera.CFrame.LookVector, camera.CFrame.UpVector)
		if bubble.part.Parent == nil then
			bubble.part.Parent = camera
		end
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
			if index % 2 == 1 and not bubble.rushed then
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

-- The replies go at once (the user: gone the moment you answer); the mouse locks again with them.
local function closeChoices()
	ContextActionService:UnbindAction(ACTION)
	GuiService.SelectedObject = nil
	local frame = choiceFrame
	choiceFrame = nil
	if frame then
		frame:Destroy()
	end
end

-- Says a line over the speaker's (a house's homeowner's) head; it stays a moment after the last
-- letter, then fades. A new line replaces the old one.
function DialogController.say(speaker: Model?, text: string, voice: number?)
	if current then
		destroyBubble(current, false)
	end
	local bubble = newBubble(speaker, text, voice or 1)
	bubble.said = true
	current = bubble
	lookedAway = 0
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

local function allOut(bubble: Bubble): boolean
	return os.clock() - bubble.started >= bubble.typed
end

-- Whether a click at `position` lands on a button on the screen (a reply, a menu's) or anywhere in an
-- open window (the seller's: a near miss of his Buy): it's theirs, not a skip.
local function onButton(position: Vector3): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, object in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		local holder = object:FindFirstAncestorWhichIsA("LayerCollector")
		if holder == nil or not holder:IsA("ScreenGui") then
			continue
		end
		if object:IsA("GuiButton") and object.Active and object.Name ~= "MouseUnlock" then
			return true
		end
		if object.Name == "Window" or object:FindFirstAncestor("Window") then -- (UI/Components/Panel)
			return true
		end
	end
	return false
end

-- You skip the line being said: the rest of it at once, or (all out already) it goes away. `clicked`
-- is false when you only looked away. False if there was nothing of yours to skip.
local function skip(clicked: boolean): boolean
	local bubble = current
	if bubble == nil or not bubble.said then
		return false
	end
	if not allOut(bubble) then
		bubble.rushed = true
		bubble.started = os.clock() - bubble.typed
		lookedAway = 0
		hideToken += 1
		local token = hideToken
		task.delay(HOLD + 0.6, function()
			if hideToken == token and current == bubble then
				current = nil
				destroyBubble(bubble, true)
			end
		end)
		return true
	end
	current = nil
	destroyBubble(bubble, true)
	if clicked then
		DialogController.skipped:Fire(bubble.speaker)
	end
	return true
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
		if choiceFrame == list then
			closeChoices()
		end
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
		-- Answered (`picked`; 0: the time ran out): the replies are already gone or go now, the
		-- question a moment later. How it went shows in the grade (and their slap).
		mark = function(_picked: number, _right: number)
			chosen = true
			if choiceFrame == list then
				closeChoices()
			end
			task.delay(0.4, close)
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

-- Ends what `speaker` is saying, if anything (you walked away from them).
function DialogController.hush(speaker: Model)
	if current and current.speaker == speaker then
		closeChoices()
		destroyBubble(current, true)
		current = nil
	end
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
	-- Under a question's own keys (Ⓨ only skips while there's a line to skip).
	ContextActionService:BindActionAtPriority(SKIP, function(_, state)
		if state == Enum.UserInputState.Begin and skip(true) then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 5, table.unpack(SKIP_KEYS))
	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			if current and current.said and not onButton(input.Position) then
				skip(true)
			end
		elseif kind == Enum.UserInputType.Touch and not processed then -- (not the thumbstick, the jump button)
			skip(true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local bubble = current
		if input.UserInputType ~= Enum.UserInputType.MouseMovement or bubble == nil or not bubble.said then
			return
		end
		-- A moment to see the last word first.
		if os.clock() - bubble.started > bubble.typed + 0.3 then
			lookedAway += input.Delta.Magnitude
			if lookedAway >= LOOK_AWAY then
				skip(false)
			end
		end
	end)
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
