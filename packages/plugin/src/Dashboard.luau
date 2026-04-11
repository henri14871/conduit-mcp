--!strict

local Tokens = require(script.Parent.ui.Tokens)
local Util = require(script.Parent.ui.Util)
local Header = require(script.Parent.ui.Header)
local StatusBar = require(script.Parent.ui.StatusBar)
local StatsBar = require(script.Parent.ui.StatsBar)
local ActivityLog = require(script.Parent.ui.ActivityLog)
local Settings = require(script.Parent.ui.Settings)

local Dashboard = {}
Dashboard.__index = Dashboard

export type Dashboard = typeof(setmetatable({} :: {
	_widget: DockWidgetPluginGui,
	_plugin: Plugin,
	_container: Frame,
	_header: Header.Header,
	_statusBar: StatusBar.StatusBar,
	_statsBar: StatsBar.StatsBar,
	_activityLog: ActivityLog.ActivityLog,
	_settings: Settings.Settings,
	_commandCount: number,
	_errorCount: number,
	_fixedSections: { GuiObject },
}, Dashboard))

function Dashboard.new(widget: DockWidgetPluginGui, pluginRef: Plugin): Dashboard
	local self = setmetatable({
		_widget = widget,
		_plugin = pluginRef,
		_commandCount = 0,
		_errorCount = 0,
		_fixedSections = {},
	} :: any, Dashboard)

	self:_buildUI()
	return self
end

-- ── Public API ──────────────────────────────────────────────────

function Dashboard.updateStatus(self: Dashboard, status: string)
	self._statusBar:updateStatus(status)
end

function Dashboard.updateStudioInfo(self: Dashboard, port: number, placeName: string?)
	self._statusBar:updateStudioInfo(port, placeName)
end

function Dashboard.startUptime(self: Dashboard)
	self._statusBar:startUptime()
end

function Dashboard.stopUptime(self: Dashboard)
	self._statusBar:stopUptime()
end

function Dashboard.updateStudiosInfo(self: Dashboard, studioCount: number, isActiveStudio: boolean)
	self._statusBar:updateStudiosInfo(studioCount, isActiveStudio)
end

function Dashboard.updatePing(self: Dashboard, latencyMs: number?)
	self._statusBar:updatePing(latencyMs)
end

function Dashboard.showReconnectCountdown(self: Dashboard, seconds: number)
	self._statusBar:showReconnectCountdown(seconds)
end

function Dashboard.hideReconnectCountdown(self: Dashboard)
	self._statusBar:hideReconnectCountdown()
end

function Dashboard.logActivity(self: Dashboard, method: string, status: string, duration: number?, errorMessage: string?)
	if status == "success" or status == "error" then
		self._commandCount += 1
		if status == "error" then
			self._errorCount += 1
		end
		self._statsBar:update(self._commandCount, self._errorCount)
	end

	if status == "running" then
		self._activityLog:addEntry(method, status, nil, nil)
	else
		local updated = self._activityLog:updateEntry(method, status, duration, errorMessage)
		if not updated then
			self._activityLog:addEntry(method, status, duration, errorMessage)
		end
	end
end

function Dashboard.setPort(self: Dashboard, port: number)
	self._settings:setPort(port)
end

function Dashboard.setAutoConnect(self: Dashboard, enabled: boolean)
	self._settings:setAutoConnect(enabled)
end

function Dashboard.onConnect(self: Dashboard, callback: () -> ())
	self._statusBar:onConnect(callback)
end

function Dashboard.onDisconnect(self: Dashboard, callback: () -> ())
	self._statusBar:onDisconnect(callback)
end

function Dashboard.onPortChange(self: Dashboard, callback: (port: number) -> ())
	self._settings:onPortChange(callback)
end

function Dashboard.onAutoConnectChange(self: Dashboard, callback: (enabled: boolean) -> ())
	self._settings:onAutoConnectChange(callback)
end

-- ── UI Construction ─────────────────────────────────────────────

function Dashboard._buildUI(self: Dashboard)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = Tokens.colors.bg
	container.BorderSizePixel = 0
	container.Parent = self._widget
	self._container = container

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

	-- Build sections
	self._header = Header.new(container, 0)
	table.insert(self._fixedSections, self._header.frame)

	Util.separator(container, 1)

	self._statusBar = StatusBar.new(container, 2)
	table.insert(self._fixedSections, self._statusBar.frame)

	Util.separator(container, 3)

	self._statsBar = StatsBar.new(container, 4)
	table.insert(self._fixedSections, self._statsBar.frame)

	Util.separator(container, 5)

	self._activityLog = ActivityLog.new(container, 6)

	Util.separator(container, 7)

	self._settings = Settings.new(container, 8, self._plugin)
	table.insert(self._fixedSections, self._settings.frame)

	-- Responsive sizing: recalculate activity log height when container resizes
	self:_recalcActivityHeight()
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_recalcActivityHeight()
	end)
end

function Dashboard._recalcActivityHeight(self: Dashboard)
	task.defer(function()
		local containerHeight = self._container.AbsoluteSize.Y
		-- Subtract padding (8 top + 8 bottom = 16)
		local available = containerHeight - 16

		-- Sum fixed section heights
		local fixedTotal = 0
		for _, section in self._fixedSections do
			fixedTotal += section.AbsoluteSize.Y
		end

		-- 4 separators at 1px each = 4px
		-- 8 sections/separators with 6px spacing = ~48px spacing
		-- (header, sep, status, sep, stats, sep, activityLog, sep, settings = 9 items, 8 gaps)
		local separatorsHeight = 4
		local spacingHeight = 8 * 6

		local activityHeight = available - fixedTotal - separatorsHeight - spacingHeight
		activityHeight = math.max(activityHeight, 60) -- minimum 60px

		self._activityLog.frame.Size = UDim2.new(1, 0, 0, activityHeight)
	end)
end

return Dashboard
