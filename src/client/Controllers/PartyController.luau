--!strict
-- The lobby's party buses, on screen (Services/PartyService has the say). Over each bus door a big
-- sign: whose party it is, how many are on, whether it's friends only, and what pressing E does.
-- In the lobby a line tells you how to host. On a bus yourself, a large band at the bottom says what
-- to do next (the host: PRESS E TO START THE RUN; everyone else: waiting for the host; then the
-- countdown), with the party listed on the right. The host starts (E / ButtonX) and lets only
-- friends on or anyone (G / ButtonY); anyone gets off by jumping. On a touch screen the keys are
-- big buttons. Sat in a bus your eyes are raised SEAT_RISE (the user wanted to see more out of it).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Runs = require(ReplicatedStorage.Shared.Config.Runs)
local Mode = require(ReplicatedStorage.Shared.Modules.Mode)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Scale = require(script.Parent.Parent.UI.Scale)
local create = require(script.Parent.Parent.UI.create)
local Sound = require(script.Parent.SoundController)

local PartyController = {}

local SEAT_RISE = 1.4 -- studs your view is raised while you're sat on a party bus

local player = Players.LocalPlayer

local band: Frame -- the big instruction at the bottom
local bandMain: TextLabel
local bandSub: TextLabel
local touchRow: Frame
local friendsButton: TextButton
local list: Frame -- the party, on the right
local listTitle: TextLabel
local listNames: TextLabel
local hint: Frame -- how to host, in the lobby while you're not on a bus
local current: Model? = nil -- the bus you're on
local lastCount = -1

local function members(bus: Model): { number }
	local ids = {}
	local text = bus:GetAttribute("Members")
	for id in string.gmatch(if type(text) == "string" then text else "", "%d+") do
		table.insert(ids, tonumber(id) :: number)
	end
	return ids
end

local function nameOf(userId: number): string
	local member = Players:GetPlayerByUserId(userId)
	return if member then member.DisplayName else "..."
end

local function busOf(userId: number): Model?
	for _, bus in CollectionService:GetTagged("PartyBus") do
		if bus:IsA("Model") and table.find(members(bus), userId) then
			return bus
		end
	end
	return nil
end

local function departAt(bus: Model): number?
	local at = bus:GetAttribute("DepartAt")
	return if type(at) == "number" and at > 0 then at else nil
end

local function isHost(bus: Model): boolean
	return bus:GetAttribute("Host") == player.UserId
end

local function label(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Hud,
		TextColor3 = Theme.Colors.Text,
		RichText = true,
		TextStrokeTransparency = 0.55,
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextLabel", base)
end

-- The sign over a bus door, for everyone in the lobby (once the door has streamed in).
local function sign(bus: Model)
	local door = bus:WaitForChild("Door", 30)
	if door == nil or not door:IsA("BasePart") then
		return
	end
	local top = label({ Size = UDim2.fromScale(1, 0.55), FontFace = Theme.Fonts.Heading, TextScaled = true })
	local bottom = label({
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.42),
		TextColor3 = Theme.Colors.TextDim,
		TextScaled = true,
	})
	create("BillboardGui", {
		Name = "PartySign",
		Size = UDim2.fromScale(9, 2.4), -- in studs: readable from across the island
		StudsOffsetWorldSpace = Vector3.new(0, 9, 0), -- clear of the bus roof
		MaxDistance = 90,
		LightInfluence = 0,
		Adornee = door,
		top,
		bottom,
		Parent = door,
	})
	local function refresh()
		local ids = members(bus)
		local host = bus:GetAttribute("Host")
		if departAt(bus) then
			top.Text = "LEAVING"
			bottom.Text = "too late to get on"
		elseif #ids == 0 then
			top.Text = "PARTY BUS"
			bottom.Text = "press E at the door to host a run"
		elseif #ids >= Runs.PARTY_MAX then
			top.Text = `{string.upper(nameOf(if type(host) == "number" then host else 0))}'S PARTY`
			bottom.Text = `full  {#ids}/{Runs.PARTY_MAX}`
		else
			top.Text = `{string.upper(nameOf(if type(host) == "number" then host else 0))}'S PARTY`
			local who = if bus:GetAttribute("FriendsOnly") == true then "friends only" else "press E to join"
			bottom.Text = `{#ids}/{Runs.PARTY_MAX}  ·  {who}`
		end
	end
	for _, attribute in { "Members", "Host", "FriendsOnly", "DepartAt" } do
		bus:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end

local function refresh()
	local bus = current
	hint.Visible = bus == nil
	band.Visible = bus ~= nil
	list.Visible = bus ~= nil
	if bus == nil then
		return
	end
	local ids = members(bus)
	local host = bus:GetAttribute("Host")
	local hostName = nameOf(if type(host) == "number" then host else 0)
	local lines = {}
	for _, id in ids do
		table.insert(lines, if id == host then `{nameOf(id)}  <font color="#8E8E96">host</font>` else nameOf(id))
	end
	for _ = #ids + 1, Runs.PARTY_MAX do
		table.insert(lines, `<font color="#4A4A52">empty seat</font>`)
	end
	listNames.Text = table.concat(lines, "\n")
	listTitle.Text = `PARTY  <font color="#8E8E96">{#ids}/{Runs.PARTY_MAX}</font>`
	local friendsOnly = bus:GetAttribute("FriendsOnly") == true
	local leaving = departAt(bus)
	local hosting = isHost(bus)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if leaving then
		local left = math.max(0, math.ceil(leaving - Workspace:GetServerTimeNow()))
		bandMain.Text = `LEAVING IN {left}`
		bandMain.TextColor3 = Theme.Colors.Success
		bandSub.Text = if touch then "jump to get off" else "[SPACE] get off"
	elseif hosting then
		bandMain.Text = if touch then "TAP START TO BEGIN THE RUN" else "PRESS  [E]  TO START THE RUN"
		bandMain.TextColor3 = Theme.Colors.Text
		local who = if friendsOnly then "only your friends can get on" else "anyone can get on"
		bandSub.Text = if touch
			then `{who}   ·   jump to get off`
			else `[G] {if friendsOnly then "let anyone on" else "friends only"}  ({who})     [SPACE] get off`
	else
		bandMain.Text = `WAITING FOR {string.upper(hostName)} TO START`
		bandMain.TextColor3 = Theme.Colors.Text
		bandSub.Text = if touch then "jump to get off" else "[SPACE] get off"
	end
	touchRow.Visible = touch and hosting and not leaving
	friendsButton.Text = if friendsOnly then "LET ANYONE ON" else "FRIENDS ONLY"
	if #ids ~= lastCount then
		if lastCount >= 0 and #ids > lastCount then
			Sound.play("Click")
		end
		lastCount = #ids
	end
end

local function start()
	local bus = current
	if bus and isHost(bus) and departAt(bus) == nil then
		Net.event("PartyStart"):FireServer()
	end
end

local function toggleFriends()
	local bus = current
	if bus and isHost(bus) then
		Net.event("PartyFriendsOnly"):FireServer(bus:GetAttribute("FriendsOnly") ~= true)
	end
end

-- Which bus you're on changed: the UI, your own bus's prompt (hidden while aboard), the keys.
local function setCurrent(bus: Model?)
	if bus == current then
		return
	end
	if current then
		local prompt = current:FindFirstChild("Board", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = true
		end
	end
	current = bus
	lastCount = -1
	if bus then
		local prompt = bus:FindFirstChild("Board", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
		ContextActionService:BindAction("PartyStart", function(_, state)
			if state == Enum.UserInputState.Begin then
				start()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		ContextActionService:BindAction("PartyFriends", function(_, state)
			if state == Enum.UserInputState.Begin then
				toggleFriends()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	else
		ContextActionService:UnbindAction("PartyStart")
		ContextActionService:UnbindAction("PartyFriends")
	end
	refresh()
end

local function touchButton(text: string, onTap: () -> ()): TextButton
	local button: TextButton = create("TextButton", {
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Heading,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = 24,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	button.Activated:Connect(onTap)
	return button
end

local function tile(props: { [string]: any }, children: { Instance }): Frame
	local frame = create("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.TileTransparency,
		Visible = false,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", {
			Color = Theme.Colors.Hairline,
			Transparency = Theme.HairlineTransparency,
			Thickness = Theme.StrokeThickness,
		}),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
	for key, value in props do
		(frame :: any)[key] = value
	end
	for _, child in children do
		child.Parent = frame
	end
	return frame
end

local function build()
	bandMain = label({
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.Fonts.Heading,
		TextSize = 38,
		LayoutOrder = 1,
	})
	bandSub = label({
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 22,
		LayoutOrder = 2,
	})
	friendsButton = touchButton("FRIENDS ONLY", toggleFriends)
	touchRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 3,
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }),
		touchButton("START", start),
		friendsButton,
	})
	band = tile({
		Name = "PartyBand",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.fromOffset(820, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { bandMain, bandSub, touchRow })

	listTitle = label({
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = Theme.Fonts.Heading,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	listNames = label({
		Size = UDim2.new(1, 0, 0, 27 * Runs.PARTY_MAX),
		TextSize = 21,
		LineHeight = 1.15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
	})
	list = tile({
		Name = "PartyList",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { listTitle, listNames })

	hint = tile({
		Name = "HostHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.fromOffset(760, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		label({
			Size = UDim2.new(1, 0, 0, 36),
			FontFace = Theme.Fonts.Heading,
			TextSize = 30,
			Text = "WALK UP TO A BUS DOOR AND PRESS  [E]  TO HOST A RUN",
			LayoutOrder = 1,
		}),
		label({
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 20,
			Text = `up to {Runs.PARTY_MAX} players  ·  get on a friend's bus to join their party`,
			LayoutOrder = 2,
		}),
	})

	local gui = create("ScreenGui", {
		Name = "Party",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12,
		band,
		list,
		hint,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Scale.attach(gui)
end

function PartyController.Start()
	if not Mode.isLobby() then
		return
	end
	build()
	local function watch(bus: Instance)
		if not bus:IsA("Model") then
			return
		end
		task.spawn(sign, bus)
		for _, attribute in { "Members", "Host", "FriendsOnly", "DepartAt" } do
			bus:GetAttributeChangedSignal(attribute):Connect(function()
				setCurrent(busOf(player.UserId))
				refresh()
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal("PartyBus"):Connect(watch)
	for _, bus in CollectionService:GetTagged("PartyBus") do
		watch(bus)
	end
	setCurrent(busOf(player.UserId))
	refresh()
	-- Sat down on a bus: your eyes go up; up again, back to where they were.
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid == nil then
			return
		end
		local raised = false
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seat = humanoid.SeatPart
			local onBus = seat ~= nil
				and seat.Parent ~= nil
				and seat.Parent.Name == "Seats"
				and CollectionService:HasTag(seat.Parent.Parent :: Instance, "PartyBus")
			if onBus ~= raised then
				raised = onBus
				humanoid.CameraOffset += Vector3.new(0, if onBus then SEAT_RISE else -SEAT_RISE, 0)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.25 and current then -- the countdown ticking
			elapsed = 0
			refresh()
		end
	end)
end

return PartyController
