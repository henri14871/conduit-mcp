--!strict

local COLORS = {
	bg = Color3.fromRGB(30, 30, 30),
	surface = Color3.fromRGB(40, 40, 40),
	border = Color3.fromRGB(60, 60, 60),
	text = Color3.fromRGB(220, 220, 220),
	textMuted = Color3.fromRGB(140, 140, 140),
	accent = Color3.fromRGB(0, 162, 255),
	green = Color3.fromRGB(0, 200, 83),
	yellow = Color3.fromRGB(255, 193, 7),
	red = Color3.fromRGB(244, 67, 54),
	logBg = Color3.fromRGB(25, 25, 25),
	btnHover = Color3.fromRGB(55, 55, 55),
}

local MAX_LOG_ENTRIES = 50

local Dashboard = {}
Dashboard.__index = Dashboard

export type Dashboard = typeof(setmetatable({} :: {
	_widget: DockWidgetPluginGui,
	_plugin: Plugin,
	_statusDot: Frame,
	_statusLabel: TextLabel,
	_connectBtn: TextButton,
	_infoLabel: TextLabel,
	_logScroll: ScrollingFrame,
	_logLayout: UIListLayout,
	_logEntries: { Frame },
	_portBox: TextBox,
	_autoConnectBtn: TextButton,
	_onConnect: (() -> ())?,
	_onDisconnect: (() -> ())?,
	_onPortChange: ((port: number) -> ())?,
}, Dashboard))

function Dashboard.new(widget: DockWidgetPluginGui, pluginRef: Plugin): Dashboard
	local self = setmetatable({
		_widget = widget,
		_plugin = pluginRef,
		_logEntries = {},
	} :: any, Dashboard)

	self:_buildUI()
	return self
end

-- ── Public API ──────────────────────────────────────────────────

function Dashboard.updateStatus(self: Dashboard, status: string)
	if status == "connected" then
		self._statusDot.BackgroundColor3 = COLORS.green
		self._statusLabel.Text = "Connected"
		self._connectBtn.Text = "Disconnect"
	elseif status == "connecting" then
		self._statusDot.BackgroundColor3 = COLORS.yellow
		self._statusLabel.Text = "Connecting..."
		self._connectBtn.Text = "Cancel"
	else
		self._statusDot.BackgroundColor3 = COLORS.red
		self._statusLabel.Text = "Disconnected"
		self._connectBtn.Text = "Connect"
	end
end

function Dashboard.updateStudioInfo(self: Dashboard, port: number, placeName: string?)
	local parts = { "Port: " .. tostring(port) }
	if placeName and placeName ~= "" then
		parts[2] = "Studio: " .. placeName
	end
	self._infoLabel.Text = table.concat(parts, "  |  ")
end

function Dashboard.logActivity(self: Dashboard, method: string, status: string, duration: number?)
	-- Skip "running" entries — we'll show them, but update on completion
	if status == "running" then
		self:_addLogEntry(method, status, nil)
	else
		self:_updateOrAddLogEntry(method, status, duration)
	end
end

function Dashboard.setPort(self: Dashboard, port: number)
	self._portBox.Text = tostring(port)
end

function Dashboard.setAutoConnect(self: Dashboard, enabled: boolean)
	self._autoConnectBtn.Text = (enabled and "[x]" or "[  ]") .. "  Auto-connect"
end

function Dashboard.onConnect(self: Dashboard, callback: () -> ())
	self._onConnect = callback
end

function Dashboard.onDisconnect(self: Dashboard, callback: () -> ())
	self._onDisconnect = callback
end

function Dashboard.onPortChange(self: Dashboard, callback: (port: number) -> ())
	self._onPortChange = callback
end

-- ── UI Construction ─────────────────────────────────────────────

function Dashboard._buildUI(self: Dashboard)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = COLORS.bg
	container.BorderSizePixel = 0
	container.Parent = self._widget

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	-- Header
	self:_buildHeader(container)
	-- Separator
	self:_buildSeparator(container, 1)
	-- Status bar
	self:_buildStatusBar(container)
	-- Separator
	self:_buildSeparator(container, 3)
	-- Activity log
	self:_buildActivityLog(container)
	-- Separator
	self:_buildSeparator(container, 5)
	-- Settings
	self:_buildSettings(container)
end

function Dashboard._buildHeader(self: Dashboard, parent: Frame)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 0
	header.Parent = parent

	-- Placeholder logo
	local logo = Instance.new("Frame")
	logo.Name = "Logo"
	logo.Size = UDim2.new(0, 36, 0, 36)
	logo.Position = UDim2.new(0, 0, 0, 2)
	logo.BackgroundColor3 = COLORS.accent
	logo.BorderSizePixel = 0
	logo.Parent = header

	local logoCorner = Instance.new("UICorner")
	logoCorner.CornerRadius = UDim.new(0, 8)
	logoCorner.Parent = logo

	local logoText = Instance.new("TextLabel")
	logoText.Name = "LogoText"
	logoText.Size = UDim2.new(1, 0, 1, 0)
	logoText.BackgroundTransparency = 1
	logoText.Text = "C"
	logoText.TextColor3 = Color3.fromRGB(255, 255, 255)
	logoText.TextSize = 20
	logoText.Font = Enum.Font.GothamBold
	logoText.Parent = logo

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -46, 0, 22)
	title.Position = UDim2.new(0, 46, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Conduit MCP"
	title.TextColor3 = COLORS.text
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	-- Credit
	local credit = Instance.new("TextLabel")
	credit.Name = "Credit"
	credit.Size = UDim2.new(1, -46, 0, 16)
	credit.Position = UDim2.new(0, 46, 0, 24)
	credit.BackgroundTransparency = 1
	credit.Text = "Created by henriheli"
	credit.TextColor3 = COLORS.textMuted
	credit.TextSize = 12
	credit.Font = Enum.Font.Gotham
	credit.TextXAlignment = Enum.TextXAlignment.Left
	credit.Parent = header
end

function Dashboard._buildSeparator(_self: Dashboard, parent: Frame, order: number)
	local sep = Instance.new("Frame")
	sep.Name = "Separator"
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = COLORS.border
	sep.BorderSizePixel = 0
	sep.LayoutOrder = order
	sep.Parent = parent
end

function Dashboard._buildStatusBar(self: Dashboard, parent: Frame)
	local bar = Instance.new("Frame")
	bar.Name = "StatusBar"
	bar.Size = UDim2.new(1, 0, 0, 50)
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = 2
	bar.Parent = parent

	-- Top row: dot + status text + button
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0, 24)
	topRow.BackgroundTransparency = 1
	topRow.Parent = bar

	-- Status dot
	local dot = Instance.new("Frame")
	dot.Name = "StatusDot"
	dot.Size = UDim2.new(0, 10, 0, 10)
	dot.Position = UDim2.new(0, 0, 0, 7)
	dot.BackgroundColor3 = COLORS.red
	dot.BorderSizePixel = 0
	dot.Parent = topRow

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	self._statusDot = dot

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0, 120, 0, 24)
	statusLabel.Position = UDim2.new(0, 18, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Disconnected"
	statusLabel.TextColor3 = COLORS.text
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = topRow

	self._statusLabel = statusLabel

	-- Connect/Disconnect button
	local btn = Instance.new("TextButton")
	btn.Name = "ConnectBtn"
	btn.Size = UDim2.new(0, 90, 0, 24)
	btn.Position = UDim2.new(1, -90, 0, 0)
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundColor3 = COLORS.surface
	btn.BorderSizePixel = 0
	btn.Text = "Connect"
	btn.TextColor3 = COLORS.accent
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamMedium
	btn.AutoButtonColor = false
	btn.Parent = topRow

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = btn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = COLORS.accent
	btnStroke.Thickness = 1
	btnStroke.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLORS.btnHover
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = COLORS.surface
	end)

	btn.MouseButton1Click:Connect(function()
		local text = btn.Text
		if text == "Connect" then
			if self._onConnect then
				self._onConnect()
			end
		else
			if self._onDisconnect then
				self._onDisconnect()
			end
		end
	end)

	self._connectBtn = btn

	-- Info line
	local info = Instance.new("TextLabel")
	info.Name = "InfoLabel"
	info.Size = UDim2.new(1, 0, 0, 18)
	info.Position = UDim2.new(0, 0, 0, 28)
	info.BackgroundTransparency = 1
	info.Text = "Port: 3200"
	info.TextColor3 = COLORS.textMuted
	info.TextSize = 11
	info.Font = Enum.Font.Gotham
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.Parent = bar

	self._infoLabel = info
end

function Dashboard._buildActivityLog(self: Dashboard, parent: Frame)
	local section = Instance.new("Frame")
	section.Name = "ActivitySection"
	section.Size = UDim2.new(1, 0, 1, -213)
	section.BackgroundTransparency = 1
	section.LayoutOrder = 4
	section.Parent = parent

	local sectionLabel = Instance.new("TextLabel")
	sectionLabel.Name = "SectionLabel"
	sectionLabel.Size = UDim2.new(1, 0, 0, 18)
	sectionLabel.BackgroundTransparency = 1
	sectionLabel.Text = "Activity Log"
	sectionLabel.TextColor3 = COLORS.textMuted
	sectionLabel.TextSize = 11
	sectionLabel.Font = Enum.Font.GothamBold
	sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
	sectionLabel.TextTransparency = 0.3
	sectionLabel.Parent = section

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "LogScroll"
	scroll.Size = UDim2.new(1, 0, 1, -22)
	scroll.Position = UDim2.new(0, 0, 0, 22)
	scroll.BackgroundColor3 = COLORS.logBg
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLORS.border
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = section

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 4)
	scrollCorner.Parent = scroll

	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingBottom = UDim.new(0, 4)
	scrollPadding.PaddingLeft = UDim.new(0, 6)
	scrollPadding.PaddingRight = UDim.new(0, 6)
	scrollPadding.Parent = scroll

	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Padding = UDim.new(0, 2)
	logLayout.Parent = scroll

	self._logScroll = scroll
	self._logLayout = logLayout
end

function Dashboard._buildSettings(self: Dashboard, parent: Frame)
	local section = Instance.new("Frame")
	section.Name = "SettingsSection"
	section.Size = UDim2.new(1, 0, 0, 60)
	section.BackgroundTransparency = 1
	section.LayoutOrder = 6
	section.Parent = parent

	local sectionLabel = Instance.new("TextLabel")
	sectionLabel.Name = "SectionLabel"
	sectionLabel.Size = UDim2.new(1, 0, 0, 18)
	sectionLabel.BackgroundTransparency = 1
	sectionLabel.Text = "Settings"
	sectionLabel.TextColor3 = COLORS.textMuted
	sectionLabel.TextSize = 11
	sectionLabel.Font = Enum.Font.GothamBold
	sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
	sectionLabel.TextTransparency = 0.3
	sectionLabel.Parent = section

	-- Port row
	local portRow = Instance.new("Frame")
	portRow.Name = "PortRow"
	portRow.Size = UDim2.new(1, 0, 0, 22)
	portRow.Position = UDim2.new(0, 0, 0, 20)
	portRow.BackgroundTransparency = 1
	portRow.Parent = section

	local portLabel = Instance.new("TextLabel")
	portLabel.Name = "PortLabel"
	portLabel.Size = UDim2.new(0, 36, 0, 22)
	portLabel.BackgroundTransparency = 1
	portLabel.Text = "Port:"
	portLabel.TextColor3 = COLORS.text
	portLabel.TextSize = 12
	portLabel.Font = Enum.Font.Gotham
	portLabel.TextXAlignment = Enum.TextXAlignment.Left
	portLabel.Parent = portRow

	local portBox = Instance.new("TextBox")
	portBox.Name = "PortBox"
	portBox.Size = UDim2.new(0, 70, 0, 22)
	portBox.Position = UDim2.new(0, 40, 0, 0)
	portBox.BackgroundColor3 = COLORS.surface
	portBox.BorderSizePixel = 0
	portBox.Text = "3200"
	portBox.TextColor3 = COLORS.text
	portBox.PlaceholderText = "3200"
	portBox.PlaceholderColor3 = COLORS.textMuted
	portBox.TextSize = 12
	portBox.Font = Enum.Font.GothamMedium
	portBox.ClearTextOnFocus = false
	portBox.Parent = portRow

	local portBoxCorner = Instance.new("UICorner")
	portBoxCorner.CornerRadius = UDim.new(0, 4)
	portBoxCorner.Parent = portBox

	local portBoxPad = Instance.new("UIPadding")
	portBoxPad.PaddingLeft = UDim.new(0, 6)
	portBoxPad.PaddingRight = UDim.new(0, 6)
	portBoxPad.Parent = portBox

	portBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local num = tonumber(portBox.Text)
			if num and num >= 1 and num <= 65535 then
				num = math.floor(num)
				portBox.Text = tostring(num)
				self._plugin:SetSetting("ConduitPort", num)
				if self._onPortChange then
					self._onPortChange(num)
				end
			else
				-- Revert to saved
				local saved = self._plugin:GetSetting("ConduitPort") or 3200
				portBox.Text = tostring(saved)
			end
		end
	end)

	self._portBox = portBox

	-- Auto-connect toggle
	local autoBtn = Instance.new("TextButton")
	autoBtn.Name = "AutoConnectBtn"
	autoBtn.Size = UDim2.new(1, 0, 0, 18)
	autoBtn.Position = UDim2.new(0, 0, 0, 44)
	autoBtn.BackgroundTransparency = 1
	autoBtn.Text = "[x]  Auto-connect"
	autoBtn.TextColor3 = COLORS.text
	autoBtn.TextSize = 12
	autoBtn.Font = Enum.Font.Gotham
	autoBtn.TextXAlignment = Enum.TextXAlignment.Left
	autoBtn.Parent = section

	autoBtn.MouseButton1Click:Connect(function()
		local current = self._plugin:GetSetting("ConduitAutoConnect")
		if current == nil then
			current = true
		end
		local newVal = not current
		self._plugin:SetSetting("ConduitAutoConnect", newVal)
		self:setAutoConnect(newVal)
	end)

	self._autoConnectBtn = autoBtn
end

-- ── Log Helpers ─────────────────────────────────────────────────

function Dashboard._addLogEntry(self: Dashboard, method: string, status: string, duration: number?)
	local entry = Instance.new("Frame")
	entry.Name = "Log_" .. method .. "_" .. tostring(#self._logEntries + 1)
	entry.Size = UDim2.new(1, 0, 0, 16)
	entry.BackgroundTransparency = 1
	entry.LayoutOrder = #self._logEntries + 1
	entry.Parent = self._logScroll

	local timeStr = os.date("%H:%M:%S")

	local statusIcon = ""
	local color = COLORS.textMuted
	if status == "running" then
		statusIcon = "..."
		color = COLORS.yellow
	elseif status == "success" then
		statusIcon = "ok"
		color = COLORS.green
	elseif status == "error" then
		statusIcon = "err"
		color = COLORS.red
	end

	local durationStr = ""
	if duration then
		if duration < 1 then
			durationStr = string.format(" (%.0fms)", duration * 1000)
		else
			durationStr = string.format(" (%.1fs)", duration)
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = timeStr .. "  " .. method .. "  " .. statusIcon .. durationStr
	label.TextColor3 = color
	label.TextSize = 11
	label.Font = Enum.Font.Code
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = entry

	table.insert(self._logEntries, entry)

	-- Prune old entries
	while #self._logEntries > MAX_LOG_ENTRIES do
		local old = table.remove(self._logEntries, 1)
		if old then
			old:Destroy()
		end
	end

	-- Re-number layout orders after pruning
	for i, e in self._logEntries do
		e.LayoutOrder = i
	end

	-- Auto-scroll to bottom
	task.defer(function()
		self._logScroll.CanvasPosition = Vector2.new(0, math.huge)
	end)
end

function Dashboard._updateOrAddLogEntry(self: Dashboard, method: string, status: string, duration: number?)
	-- Try to find the last "running" entry for this method and update it
	for i = #self._logEntries, 1, -1 do
		local entry = self._logEntries[i]
		local textLabel = entry:FindFirstChild("Text") :: TextLabel?
		if textLabel and string.find(textLabel.Text, method, 1, true) and string.find(textLabel.Text, "%.%.%.") then
			-- Update this entry
			local timeStr = os.date("%H:%M:%S")
			local statusIcon = ""
			local color = COLORS.textMuted
			if status == "success" then
				statusIcon = "ok"
				color = COLORS.green
			elseif status == "error" then
				statusIcon = "err"
				color = COLORS.red
			end

			local durationStr = ""
			if duration then
				if duration < 1 then
					durationStr = string.format(" (%.0fms)", duration * 1000)
				else
					durationStr = string.format(" (%.1fs)", duration)
				end
			end

			textLabel.Text = timeStr .. "  " .. method .. "  " .. statusIcon .. durationStr
			textLabel.TextColor3 = color
			return
		end
	end

	-- No running entry found, add a new one
	self:_addLogEntry(method, status, duration)
end

return Dashboard
