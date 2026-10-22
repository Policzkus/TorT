--!strict
-- Sweet Tooth's Shop: upgrade tracks with "X% to afford" bars and glowing Buy buttons.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Images = require(Shared.Config.Images)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Modules.Format)
local Formulas = require(Shared.Modules.Formulas)
local Net = require(Shared.Modules.Net)
local NotificationController = require(script.Parent.NotificationController)
local RadialMenuController = require(script.Parent.RadialMenuController)
local Sound = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
local ProgressBar = require(script.Parent.Parent.UI.Components.ProgressBar)
local Theme = require(script.Parent.Parent.UI.Theme)
local create = require(script.Parent.Parent.UI.create)

local ShopController = {}

type Row = {
	frame: Frame,
	title: TextLabel,
	effect: TextLabel,
	bar: ProgressBar.ProgressBar,
	buy: TextButton,
	glow: UIStroke,
}

local panel: Panel.Panel
local rows: { [string]: Row } = {}
local buying = false

-- Current → next effect text for a track at `level`.
local function effectText(trackId: string, level: number): (string, string)
	local track = Formulas.track(trackId)
	if trackId == "bucketTier" then
		local now = Formulas.bucketTier(level)
		local nextTier = (track.tiers :: { Upgrades.Tier })[level + 1]
		if nextTier then
			return `{now.name} → {nextTier.name}`,
				`Holds {Format.number(now.capacity)} → {Format.number(nextTier.capacity)} 🍬`
		end
		return now.name, `Holds {Format.number(now.capacity)} 🍬`
	elseif trackId == "charm" then
		local now = math.round(Formulas.charmBonus(level) * 100)
		local after = math.round(Formulas.charmBonus(level + 1) * 100)
		return `Level {level}`, `Door candy +{now}% → +{after}%`
	elseif trackId == "sneakers" then
		return `Level {level}`, `Walk speed {Formulas.walkSpeed(level)} → {Formulas.walkSpeed(level + 1)}`
	end
	return `Level {level}`, track.description
end

-- What the cheapest affordable upgrade costs (nil if none) - the HUD uses this for its badge.
function ShopController.cheapestAffordable(): number?
	local candy = StateController.get("candy") or 0
	local upgrades = StateController.get("upgrades")
	local rebirths = StateController.get("rebirths") or 0
	if upgrades == nil then
		return nil
	end
	local best: number? = nil
	for _, trackId in Upgrades.ORDER do
		local check, cost = Formulas.canBuy(trackId, upgrades[trackId], rebirths, candy)
		if check == "ok" and cost and (best == nil or cost < best) then
			best = cost
		end
	end
	return best
end

local function refresh()
	local candy = StateController.get("candy") or 0
	local upgrades = StateController.get("upgrades")
	local rebirths = StateController.get("rebirths") or 0
	if upgrades == nil then
		return
	end
	for trackId, row in rows do
		local level = upgrades[trackId]
		local check, cost = Formulas.canBuy(trackId, level, rebirths, candy)
		local title, effect = effectText(trackId, level)
		row.title.Text = `{Formulas.track(trackId).icon} {Formulas.track(trackId).name}  •  {title}`
		row.effect.Text = effect
		if check == "maxed" then
			row.bar:set(1)
			row.bar:setText("MAXED!")
			row.bar:setColor(Theme.Colors.Slime)
			row.buy.Text = "MAX"
			row.buy.BackgroundColor3 = Theme.Colors.PanelDark
			row.glow.Enabled = false
		elseif check == "needsRebirth" then
			row.bar:set(1)
			row.bar:setText(`☠ Rebirth {Formulas.rebirthsForLevel(trackId, level)} unlocks more`)
			row.bar:setColor(Theme.Colors.Info)
			row.buy.Text = "LOCKED"
			row.buy.BackgroundColor3 = Theme.Colors.PanelDark
			row.glow.Enabled = false
		else
			local fraction = candy / (cost :: number)
			row.bar:set(fraction, true)
			row.bar:setColor(if check == "ok" then Theme.Colors.Slime else Theme.Colors.Orange)
			row.bar:setText(
				if check == "ok" then "READY!" else `{math.floor(math.min(fraction, 0.99) * 100)}% to afford`
			)
			row.buy.Text = `🍬 {Format.number(cost :: number)}`
			row.buy.BackgroundColor3 = if check == "ok" then Theme.Colors.Slime else Theme.Colors.PanelDark
			row.buy.TextColor3 = if check == "ok" then Theme.Colors.Text else Theme.Colors.TextDim
			row.glow.Enabled = check == "ok"
		end
	end
end

local function buy(trackId: string)
	if buying then
		return
	end
	buying = true
	local ok, message = Net.func("BuyUpgrade"):InvokeServer(trackId)
	buying = false
	if ok then
		Sound.play("Purchase")
		NotificationController.show(message, "success")
	else
		Sound.play("Error")
		NotificationController.show(message or "Couldn't buy that", "error")
	end
end

local function buildRow(trackId: string, order: number, parent: Instance): Row
	local glow = create("UIStroke", {
		Name = "Glow",
		Color = Theme.Colors.Slime,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
	})
	local title = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -170, 0, 28),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
	})
	local effect = create("TextLabel", {
		Name = "Effect",
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -170, 0, 20),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local frame = create("Frame", {
		Name = trackId,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 96),
		BackgroundColor3 = Theme.Colors.PanelLight,
		create("UICorner", { CornerRadius = Theme.Corner }),
		create("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 2 }),
		title,
		effect,
		Parent = parent,
	})
	local bar = ProgressBar.new({
		size = UDim2.new(1, -170, 0, 20),
		position = UDim2.fromOffset(14, 64),
		parent = frame,
	})
	local buyButton = Button.new({
		name = "Buy",
		text = "",
		size = UDim2.fromOffset(136, 56),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.PanelDark,
		textSize = 22,
		parent = frame,
		onClick = function()
			buy(trackId)
		end,
	})
	glow.Parent = buyButton
	return { frame = frame, title = title, effect = effect, bar = bar, buy = buyButton, glow = glow }
end

function ShopController.open()
	refresh()
	panel:open()
end

function ShopController.toggle()
	if panel:isOpen() then
		panel:close()
	else
		ShopController.open()
	end
end

function ShopController.Start()
	panel = Panel.new({ name = "ShopPanel", title = "🍭 Sweet Tooth's Shop", size = Vector2.new(600, 420) })
	local list = create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
		Parent = panel.content,
	})
	for order, trackId in Upgrades.ORDER do
		rows[trackId] = buildRow(trackId, order, list)
	end

	-- Affordable buttons pulse.
	task.spawn(function()
		local pulse = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		for _, row in rows do
			TweenService:Create(row.glow, pulse, { Transparency = 0.7 }):Play()
		end
	end)

	for _, key in { "candy", "upgrades", "rebirths" } do
		StateController.observe(key, function()
			if panel:isOpen() then
				refresh()
			end
		end)
	end
	RadialMenuController.register({
		id = "Shop",
		label = "UPGRADES",
		order = 1,
		icon = Images.Candy,
		onSelect = ShopController.open,
	})
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "ShopStand") then
			ShopController.open()
		end
	end)
end

return ShopController
