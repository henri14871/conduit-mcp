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
		Size = UDim2.new(1, 0, 0, 60),
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = header

	-- Banner image
	local banner = Instance.new("ImageLabel")
	banner.Name = "Banner"
	banner.Size = UDim2.new(1, 0, 0, 40)
	banner.Position = UDim2.new(0, 0, 0, 0)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Image = "rbxassetid://103653412901492"
	banner.ScaleType = Enum.ScaleType.Fit
	banner.Parent = header

	-- Credit + version
	Util.label({
		Name = "Credit",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 0, 44),
		Text = "github.com/henri14871/conduit-mcp",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.label,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = header,
	})

	return self
end

return Header
