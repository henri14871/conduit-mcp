--!strict

local Tokens = require(script.Parent.Tokens)
local Util = require(script.Parent.Util)

local Header = {}
Header.__index = Header

export type Header = typeof(setmetatable({} :: {
	frame: Frame,
}, Header))

function Header.new(parent: GuiObject, order: number): Header
	local self = setmetatable({} :: any, Header)

	local header = Util.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = header

	-- Logo: sharp red square with white "C"
	local logo = Util.frame({
		Name = "Logo",
		Size = UDim2.new(0, 32, 0, 32),
		Position = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Tokens.colors.accent,
		BackgroundTransparency = 0,
		Parent = header,
	})

	Util.stroke(logo, Tokens.colors.accent)

	Util.label({
		Name = "LogoText",
		Size = UDim2.new(1, 0, 1, 0),
		Text = "C",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Font = Tokens.font.heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = logo,
	})

	-- Title
	Util.label({
		Name = "Title",
		Size = UDim2.new(1, -42, 0, 20),
		Position = UDim2.new(0, 42, 0, 0),
		Text = "Conduit MCP",
		TextColor3 = Tokens.colors.text,
		TextSize = Tokens.textSize.xl,
		Font = Tokens.font.heading,
		Parent = header,
	})

	-- Credit
	Util.label({
		Name = "Credit",
		Size = UDim2.new(1, -42, 0, 14),
		Position = UDim2.new(0, 42, 0, 22),
		Text = "Created by henriheli",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.label,
		Parent = header,
	})

	return self
end

return Header
