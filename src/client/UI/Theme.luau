--!strict
-- Visual identity: chunky cartoon Halloween. Every UI file pulls colors and fonts from here.

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromHex("2A1B3D"),
	PanelLight = Color3.fromHex("3D2A56"),
	PanelDark = Color3.fromHex("1A1026"),
	Stroke = Color3.fromHex("120A1C"),
	Orange = Color3.fromHex("FF8A00"),
	OrangeLight = Color3.fromHex("FFB347"),
	Slime = Color3.fromHex("7CFF4F"),
	Text = Color3.fromHex("FFFFFF"),
	TextDim = Color3.fromHex("C9B8E0"),
	Success = Color3.fromHex("4CD964"),
	Danger = Color3.fromHex("FF4D5E"),
	Info = Color3.fromHex("8E6BFF"),
}

-- CS-style rarity colors.
Theme.Rarity = {
	MilSpec = Color3.fromHex("4B69FF"),
	Restricted = Color3.fromHex("8847FF"),
	Classified = Color3.fromHex("D32CE6"),
	Covert = Color3.fromHex("EB4B4B"),
	Gold = Color3.fromHex("E4AE39"),
}

Theme.Fonts = {
	Heading = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	BodyHeavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
}

Theme.Corner = UDim.new(0, 12)
Theme.StrokeThickness = 2.5

return Theme
