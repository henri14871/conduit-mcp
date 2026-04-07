--!strict

local Tokens = require(script.Parent.Tokens)
local Util = require(script.Parent.Util)

local StatsBar = {}
StatsBar.__index = StatsBar

export type StatsBar = typeof(setmetatable({} :: {
	frame: Frame,
	_statsLabel: TextLabel,
}, StatsBar))

function StatsBar.new(parent: GuiObject, order: number): StatsBar
	local self = setmetatable({} :: any, StatsBar)

	local bar = Util.frame({
		Name = "StatsBar",
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = bar

	self._statsLabel = Util.label({
		Name = "StatsLabel",
		Size = UDim2.new(1, 0, 1, 0),
		Text = "Commands: 0  |  Errors: 0",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.mono,
		Parent = bar,
	})

	return self
end

function StatsBar.update(self: StatsBar, commandCount: number, errorCount: number)
	self._statsLabel.Text = "Commands: " .. tostring(commandCount) .. "  |  Errors: " .. tostring(errorCount)
	self._statsLabel.TextColor3 = if errorCount > 0 then Tokens.colors.red else Tokens.colors.textMuted
end

return StatsBar
