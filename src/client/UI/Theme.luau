--!strict
-- Visual identity (PROMPT §V2.3): minimal noir HUD in the spirit of the user's Watch Dogs reference.
-- Near-black translucent tiles, hairline borders, sharp corners, a typewriter face for headings.
-- Every UI file pulls colors and fonts from here.

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromHex("0C0C0F"),
	PanelLight = Color3.fromHex("1B1B20"),
	PanelDark = Color3.fromHex("050507"),
	Stroke = Color3.fromHex("000000"),
	Hairline = Color3.fromHex("E6E6E6"),
	Orange = Color3.fromHex("D89A3C"),
	OrangeLight = Color3.fromHex("E8C27A"),
	Slime = Color3.fromHex("A6E07C"),
	Text = Color3.fromHex("F0F0F0"),
	TextDim = Color3.fromHex("8E8E96"),
	Success = Color3.fromHex("A6E07C"),
	Danger = Color3.fromHex("D84A4A"),
	Info = Color3.fromHex("9A9AB4"),
}

-- CS-style rarity colors (crates).
Theme.Rarity = {
	MilSpec = Color3.fromHex("4B69FF"),
	Restricted = Color3.fromHex("8847FF"),
	Classified = Color3.fromHex("D32CE6"),
	Covert = Color3.fromHex("EB4B4B"),
	Gold = Color3.fromHex("E4AE39"),
}

Theme.Fonts = {
	Heading = Font.fromEnum(Enum.Font.SpecialElite),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	BodyHeavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Hud = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
}

Theme.Corner = UDim.new(0, 3)
Theme.StrokeThickness = 1
-- Background transparency of HUD tiles and panels.
Theme.TileTransparency = 0.35

return Theme
