--!strict

local Tokens = require(script.Parent.Tokens)

local Util = {}

function Util.frame(props: {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	Parent: GuiObject?,
	LayoutOrder: number?,
	BackgroundColor3: Color3?,
	BackgroundTransparency: number?,
}): Frame
	local f = Instance.new("Frame")
	f.Name = props.Name or "Frame"
	f.Size = props.Size or UDim2.new(1, 0, 0, 0)
	if props.Position then
		f.Position = props.Position
	end
	f.BackgroundColor3 = props.BackgroundColor3 or Tokens.colors.bg
	f.BackgroundTransparency = if props.BackgroundTransparency ~= nil then props.BackgroundTransparency else 1
	f.BorderSizePixel = 0
	if props.LayoutOrder then
		f.LayoutOrder = props.LayoutOrder
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

function Util.label(props: {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	Parent: GuiObject?,
	Text: string?,
	TextColor3: Color3?,
	TextSize: number?,
	Font: Enum.Font?,
	TextXAlignment: Enum.TextXAlignment?,
	TextTransparency: number?,
	TextTruncate: Enum.TextTruncate?,
	LayoutOrder: number?,
	BackgroundTransparency: number?,
	TextWrapped: boolean?,
	AutomaticSize: Enum.AutomaticSize?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.new(1, 0, 0, 18)
	if props.Position then
		l.Position = props.Position
	end
	l.BackgroundTransparency = if props.BackgroundTransparency ~= nil then props.BackgroundTransparency else 1
	l.BorderSizePixel = 0
	l.Text = props.Text or ""
	l.TextColor3 = props.TextColor3 or Tokens.colors.text
	l.TextSize = props.TextSize or Tokens.textSize.md
	l.Font = props.Font or Tokens.font.label
	l.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	if props.TextTransparency then
		l.TextTransparency = props.TextTransparency
	end
	if props.TextTruncate then
		l.TextTruncate = props.TextTruncate
	end
	if props.LayoutOrder then
		l.LayoutOrder = props.LayoutOrder
	end
	if props.TextWrapped then
		l.TextWrapped = true
	end
	if props.AutomaticSize then
		l.AutomaticSize = props.AutomaticSize
	end
	if props.Parent then
		l.Parent = props.Parent
	end
	return l
end

function Util.button(props: {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	Parent: GuiObject?,
	Text: string?,
	TextColor3: Color3?,
	TextSize: number?,
	Font: Enum.Font?,
	TextXAlignment: Enum.TextXAlignment?,
	LayoutOrder: number?,
	BackgroundColor3: Color3?,
	Stroke: boolean?,
	StrokeColor: Color3?,
}): TextButton
	local b = Instance.new("TextButton")
	b.Name = props.Name or "Button"
	b.Size = props.Size or UDim2.new(0, 90, 0, 24)
	if props.Position then
		b.Position = props.Position
	end
	b.BackgroundColor3 = props.BackgroundColor3 or Tokens.colors.surface
	b.BorderSizePixel = 0
	b.Text = props.Text or ""
	b.TextColor3 = props.TextColor3 or Tokens.colors.accent
	b.TextSize = props.TextSize or Tokens.textSize.md
	b.Font = props.Font or Tokens.font.body
	b.AutoButtonColor = false
	if props.TextXAlignment then
		b.TextXAlignment = props.TextXAlignment
	end
	if props.LayoutOrder then
		b.LayoutOrder = props.LayoutOrder
	end

	if props.Stroke ~= false then
		Util.stroke(b, props.StrokeColor)
	end

	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = Tokens.colors.btnHover
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = props.BackgroundColor3 or Tokens.colors.surface
	end)

	if props.Parent then
		b.Parent = props.Parent
	end
	return b
end

function Util.textbox(props: {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	Parent: GuiObject?,
	Text: string?,
	PlaceholderText: string?,
	TextSize: number?,
	Font: Enum.Font?,
}): TextBox
	local t = Instance.new("TextBox")
	t.Name = props.Name or "TextBox"
	t.Size = props.Size or UDim2.new(0, 70, 0, 22)
	if props.Position then
		t.Position = props.Position
	end
	t.BackgroundColor3 = Tokens.colors.surface
	t.BorderSizePixel = 0
	t.Text = props.Text or ""
	t.TextColor3 = Tokens.colors.text
	t.PlaceholderText = props.PlaceholderText or ""
	t.PlaceholderColor3 = Tokens.colors.textMuted
	t.TextSize = props.TextSize or Tokens.textSize.md
	t.Font = props.Font or Tokens.font.body
	t.ClearTextOnFocus = false

	Util.stroke(t, Tokens.colors.border)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = t

	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

function Util.separator(parent: GuiObject, order: number): Frame
	local sep = Instance.new("Frame")
	sep.Name = "Separator"
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = Tokens.colors.border
	sep.BorderSizePixel = 0
	sep.LayoutOrder = order
	sep.Parent = parent
	return sep
end

function Util.stroke(parent: GuiObject, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Tokens.colors.accent
	s.Thickness = Tokens.stroke.thin
	s.Parent = parent
	return s
end

function Util.formatDuration(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then
		return string.format("%dh %dm %ds", h, m, s)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	else
		return string.format("%ds", s)
	end
end

return Util
