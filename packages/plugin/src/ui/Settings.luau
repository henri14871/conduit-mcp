--!strict

local Tokens = require(script.Parent.Tokens)
local Util = require(script.Parent.Util)

local Settings = {}
Settings.__index = Settings

export type Settings = typeof(setmetatable({} :: {
	frame: Frame,
	_portBox: TextBox,
	_portStroke: UIStroke,
	_validationLabel: TextLabel,
	_autoConnectIndicator: Frame,
	_autoConnectBtn: TextButton,
	_onPortChange: ((port: number) -> ())?,
	_pluginRef: Plugin,
	_revertThread: thread?,
}, Settings))

function Settings.new(parent: GuiObject, order: number, pluginRef: Plugin): Settings
	local self = setmetatable({
		_pluginRef = pluginRef,
	} :: any, Settings)

	local section = Util.frame({
		Name = "SettingsSection",
		Size = UDim2.new(1, 0, 0, 68),
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = section

	-- Section label
	Util.label({
		Name = "SectionLabel",
		Size = UDim2.new(1, 0, 0, 16),
		Text = "SETTINGS",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.xs,
		Font = Tokens.font.heading,
		TextTransparency = 0.3,
		Parent = section,
	})

	-- Port row
	local portRow = Util.frame({
		Name = "PortRow",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 20),
		Parent = section,
	})

	Util.label({
		Name = "PortLabel",
		Size = UDim2.new(0, 36, 0, 22),
		Text = "Port:",
		TextColor3 = Tokens.colors.text,
		TextSize = Tokens.textSize.md,
		Font = Tokens.font.label,
		Parent = portRow,
	})

	local portBox = Util.textbox({
		Name = "PortBox",
		Size = UDim2.new(0, 70, 0, 22),
		Position = UDim2.new(0, 40, 0, 0),
		Text = "3200",
		PlaceholderText = "3200",
		Parent = portRow,
	})
	self._portBox = portBox

	-- Get the stroke for validation coloring
	self._portStroke = portBox:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Validation feedback label (hidden by default)
	local validationLabel = Util.label({
		Name = "ValidationLabel",
		Size = UDim2.new(0, 140, 0, 14),
		Position = UDim2.new(0, 114, 0, 4),
		Text = "Invalid port (1-65535)",
		TextColor3 = Tokens.colors.red,
		TextSize = Tokens.textSize.xs,
		Font = Tokens.font.label,
		Parent = portRow,
	})
	validationLabel.Visible = false
	self._validationLabel = validationLabel

	portBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local num = tonumber(portBox.Text)
			if num and num >= 1 and num <= 65535 then
				num = math.floor(num)
				portBox.Text = tostring(num)
				self._portStroke.Color = Tokens.colors.border
				validationLabel.Visible = false
				pluginRef:SetSetting("ConduitPort", num)
				if self._onPortChange then
					self._onPortChange(num)
				end
			else
				-- Show validation error
				self._portStroke.Color = Tokens.colors.red
				validationLabel.Visible = true

				-- Revert after 2 seconds
				if self._revertThread then
					task.cancel(self._revertThread)
				end
				self._revertThread = task.delay(2, function()
					local saved = pluginRef:GetSetting("ConduitPort") or 3200
					portBox.Text = tostring(saved)
					self._portStroke.Color = Tokens.colors.border
					validationLabel.Visible = false
					self._revertThread = nil
				end)
			end
		end
	end)

	-- Auto-connect row
	local autoRow = Util.frame({
		Name = "AutoRow",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 46),
		Parent = section,
	})

	-- Toggle indicator (small square)
	local indicator = Util.frame({
		Name = "Indicator",
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 0, 0, 3),
		BackgroundColor3 = Tokens.colors.accent,
		BackgroundTransparency = 0,
		Parent = autoRow,
	})
	Util.stroke(indicator, Tokens.colors.accent)
	self._autoConnectIndicator = indicator

	local autoBtn = Instance.new("TextButton")
	autoBtn.Name = "AutoConnectBtn"
	autoBtn.Size = UDim2.new(1, -18, 0, 18)
	autoBtn.Position = UDim2.new(0, 18, 0, 0)
	autoBtn.BackgroundTransparency = 1
	autoBtn.BorderSizePixel = 0
	autoBtn.Text = "Auto-connect"
	autoBtn.TextColor3 = Tokens.colors.text
	autoBtn.TextSize = Tokens.textSize.md
	autoBtn.Font = Tokens.font.label
	autoBtn.TextXAlignment = Enum.TextXAlignment.Left
	autoBtn.AutoButtonColor = false
	autoBtn.Parent = autoRow
	self._autoConnectBtn = autoBtn

	-- Make the indicator clickable too by wrapping in a button
	local indicatorBtn = Instance.new("TextButton")
	indicatorBtn.Name = "IndicatorBtn"
	indicatorBtn.Size = UDim2.new(1, 0, 1, 0)
	indicatorBtn.BackgroundTransparency = 1
	indicatorBtn.BorderSizePixel = 0
	indicatorBtn.Text = ""
	indicatorBtn.AutoButtonColor = false
	indicatorBtn.Parent = indicator

	local function toggleAutoConnect()
		local current = pluginRef:GetSetting("ConduitAutoConnect")
		if current == nil then
			current = true
		end
		local newVal = not current
		pluginRef:SetSetting("ConduitAutoConnect", newVal)
		self:setAutoConnect(newVal)
	end

	autoBtn.MouseButton1Click:Connect(toggleAutoConnect)
	indicatorBtn.MouseButton1Click:Connect(toggleAutoConnect)

	return self
end

function Settings.setPort(self: Settings, port: number)
	self._portBox.Text = tostring(port)
end

function Settings.setAutoConnect(self: Settings, enabled: boolean)
	if enabled then
		self._autoConnectIndicator.BackgroundColor3 = Tokens.colors.accent
		self._autoConnectIndicator.BackgroundTransparency = 0
	else
		self._autoConnectIndicator.BackgroundColor3 = Tokens.colors.surface
		self._autoConnectIndicator.BackgroundTransparency = 0
	end
end

function Settings.onPortChange(self: Settings, callback: (port: number) -> ())
	self._onPortChange = callback
end

return Settings
