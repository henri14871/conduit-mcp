--!strict

local Tokens = require(script.Parent.Tokens)
local Util = require(script.Parent.Util)

local StatusBar = {}
StatusBar.__index = StatusBar

export type StatusBar = typeof(setmetatable({} :: {
	frame: Frame,
	_statusDot: Frame,
	_statusLabel: TextLabel,
	_pingLabel: TextLabel,
	_connectBtn: TextButton,
	_infoLabel: TextLabel,
	_countdownLabel: TextLabel,
	_onConnect: (() -> ())?,
	_onDisconnect: (() -> ())?,
	-- Info state
	_currentPort: number,
	_currentPlaceName: string?,
	_connectedAt: number?,
	_uptimeThread: thread?,
	_studioCount: number?,
	_isActiveStudio: boolean?,
	_countdownThread: thread?,
	_showingCountdown: boolean,
}, StatusBar))

function StatusBar.new(parent: GuiObject, order: number): StatusBar
	local self = setmetatable({
		_currentPort = 3200,
		_showingCountdown = false,
	} :: any, StatusBar)

	local bar = Util.frame({
		Name = "StatusBar",
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = bar

	-- Top row: dot + status + ping + connect button
	local topRow = Util.frame({
		Name = "TopRow",
		Size = UDim2.new(1, 0, 0, 24),
		Parent = bar,
	})

	-- Status dot (circular — only rounded element)
	local dot = Instance.new("Frame")
	dot.Name = "StatusDot"
	dot.Size = UDim2.new(0, 10, 0, 10)
	dot.Position = UDim2.new(0, 0, 0, 7)
	dot.BackgroundColor3 = Tokens.colors.red
	dot.BorderSizePixel = 0
	dot.Parent = topRow

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	self._statusDot = dot

	-- Status label
	self._statusLabel = Util.label({
		Name = "StatusLabel",
		Size = UDim2.new(0, 100, 0, 24),
		Position = UDim2.new(0, 16, 0, 0),
		Text = "Disconnected",
		TextColor3 = Tokens.colors.text,
		TextSize = Tokens.textSize.lg,
		Font = Tokens.font.body,
		Parent = topRow,
	})

	-- Ping badge
	self._pingLabel = Util.label({
		Name = "PingLabel",
		Size = UDim2.new(0, 50, 0, 24),
		Position = UDim2.new(0, 118, 0, 0),
		Text = "",
		TextColor3 = Tokens.colors.green,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.mono,
		Parent = topRow,
	})

	-- Connect/Disconnect button
	local btn = Util.button({
		Name = "ConnectBtn",
		Size = UDim2.new(0, 90, 0, 24),
		Position = UDim2.new(1, -90, 0, 0),
		Text = "Connect",
		Parent = topRow,
	})

	btn.MouseButton1Click:Connect(function()
		if btn.Text == "Connect" then
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
	self._infoLabel = Util.label({
		Name = "InfoLabel",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 28),
		Text = "Port: 3200",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.mono,
		Parent = bar,
	})

	-- Countdown label (hidden, replaces info line when reconnecting)
	self._countdownLabel = Util.label({
		Name = "CountdownLabel",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 28),
		Text = "",
		TextColor3 = Tokens.colors.yellow,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.mono,
		Parent = bar,
	})
	self._countdownLabel.Visible = false

	return self
end

function StatusBar.updateStatus(self: StatusBar, status: string)
	if status == "connected" then
		self._statusDot.BackgroundColor3 = Tokens.colors.green
		self._statusLabel.Text = "Connected"
		self._connectBtn.Text = "Disconnect"
		self:hideReconnectCountdown()
	elseif status == "connecting" then
		self._statusDot.BackgroundColor3 = Tokens.colors.yellow
		self._statusLabel.Text = "Connecting..."
		self._connectBtn.Text = "Cancel"
	else
		self._statusDot.BackgroundColor3 = Tokens.colors.red
		self._statusLabel.Text = "Disconnected"
		self._connectBtn.Text = "Connect"
	end
end

function StatusBar.updatePing(self: StatusBar, latencyMs: number?)
	if latencyMs then
		self._pingLabel.Text = tostring(latencyMs) .. "ms"
		if latencyMs < 50 then
			self._pingLabel.TextColor3 = Tokens.colors.green
		elseif latencyMs < 150 then
			self._pingLabel.TextColor3 = Tokens.colors.yellow
		else
			self._pingLabel.TextColor3 = Tokens.colors.red
		end
	else
		self._pingLabel.Text = ""
	end
end

function StatusBar.showReconnectCountdown(self: StatusBar, seconds: number)
	self._showingCountdown = true
	self._countdownLabel.Text = "Reconnecting in " .. tostring(seconds) .. "s..."
	self._countdownLabel.Visible = true
	self._infoLabel.Visible = false
end

function StatusBar.hideReconnectCountdown(self: StatusBar)
	self._showingCountdown = false
	self._countdownLabel.Visible = false
	self._infoLabel.Visible = true
end

function StatusBar.updateStudioInfo(self: StatusBar, port: number, placeName: string?)
	self._currentPort = port
	self._currentPlaceName = placeName
	self:_refreshInfoLine()
end

function StatusBar.updateStudiosInfo(self: StatusBar, studioCount: number, isActiveStudio: boolean)
	self._studioCount = studioCount
	self._isActiveStudio = isActiveStudio
	self:_refreshInfoLine()
end

function StatusBar.startUptime(self: StatusBar)
	self._connectedAt = os.clock()
	if self._uptimeThread then
		task.cancel(self._uptimeThread)
	end
	self._uptimeThread = task.spawn(function()
		while self._connectedAt do
			self:_refreshInfoLine()
			task.wait(1)
		end
	end)
end

function StatusBar.stopUptime(self: StatusBar)
	self._connectedAt = nil
	if self._uptimeThread then
		task.cancel(self._uptimeThread)
		self._uptimeThread = nil
	end
	self:_refreshInfoLine()
end

function StatusBar.onConnect(self: StatusBar, callback: () -> ())
	self._onConnect = callback
end

function StatusBar.onDisconnect(self: StatusBar, callback: () -> ())
	self._onDisconnect = callback
end

function StatusBar._refreshInfoLine(self: StatusBar)
	local parts = { "Port: " .. tostring(self._currentPort) }
	local nameStr = self._currentPlaceName or ""
	if nameStr ~= "" then
		if self._studioCount and self._studioCount > 1 then
			nameStr ..= " (" .. tostring(self._studioCount) .. ")"
			if self._isActiveStudio then
				nameStr ..= " active"
			end
		end
		table.insert(parts, nameStr)
	end
	if self._connectedAt then
		local elapsed = os.clock() - self._connectedAt
		table.insert(parts, "Up: " .. Util.formatDuration(elapsed))
	end
	self._infoLabel.Text = table.concat(parts, "  |  ")
end

return StatusBar
