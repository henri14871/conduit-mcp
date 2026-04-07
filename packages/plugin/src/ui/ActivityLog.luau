--!strict

local Tokens = require(script.Parent.Tokens)
local Util = require(script.Parent.Util)

local ActivityLog = {}
ActivityLog.__index = ActivityLog

export type ActivityLog = typeof(setmetatable({} :: {
	frame: Frame,
	_logScroll: ScrollingFrame,
	_logLayout: UIListLayout,
	_logEntries: { Frame },
	_emptyState: TextLabel,
	_filterStatus: string,
	_searchText: string,
	_filterAllBtn: TextButton,
	_filterOkBtn: TextButton,
	_filterErrBtn: TextButton,
	_filterAllStroke: UIStroke,
	_filterOkStroke: UIStroke,
	_filterErrStroke: UIStroke,
	_searchBox: TextBox,
}, ActivityLog))

function ActivityLog.new(parent: GuiObject, order: number): ActivityLog
	local self = setmetatable({
		_logEntries = {},
		_filterStatus = "all",
		_searchText = "",
	} :: any, ActivityLog)

	local section = Util.frame({
		Name = "ActivitySection",
		Size = UDim2.new(1, 0, 1, 0), -- will be resized dynamically
		LayoutOrder = order,
		Parent = parent,
	})
	self.frame = section

	-- Section header row
	local headerRow = Util.frame({
		Name = "HeaderRow",
		Size = UDim2.new(1, 0, 0, 16),
		Parent = section,
	})

	Util.label({
		Name = "SectionLabel",
		Size = UDim2.new(0, 80, 0, 16),
		Text = "ACTIVITY LOG",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.xs,
		Font = Tokens.font.heading,
		TextTransparency = 0.3,
		Parent = headerRow,
	})

	-- Filter bar
	local filterRow = Util.frame({
		Name = "FilterRow",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 20),
		Parent = section,
	})

	-- Filter buttons
	local filterAllBtn = Util.button({
		Name = "FilterAll",
		Size = UDim2.new(0, 28, 0, 18),
		Position = UDim2.new(0, 0, 0, 1),
		Text = "All",
		TextSize = Tokens.textSize.xs,
		TextColor3 = Tokens.colors.text,
		Stroke = true,
		StrokeColor = Tokens.colors.accent,
		Parent = filterRow,
	})
	self._filterAllBtn = filterAllBtn
	self._filterAllStroke = filterAllBtn:FindFirstChildOfClass("UIStroke") :: UIStroke

	local filterOkBtn = Util.button({
		Name = "FilterOk",
		Size = UDim2.new(0, 24, 0, 18),
		Position = UDim2.new(0, 32, 0, 1),
		Text = "OK",
		TextSize = Tokens.textSize.xs,
		TextColor3 = Tokens.colors.text,
		Stroke = true,
		StrokeColor = Tokens.colors.border,
		Parent = filterRow,
	})
	self._filterOkBtn = filterOkBtn
	self._filterOkStroke = filterOkBtn:FindFirstChildOfClass("UIStroke") :: UIStroke

	local filterErrBtn = Util.button({
		Name = "FilterErr",
		Size = UDim2.new(0, 26, 0, 18),
		Position = UDim2.new(0, 60, 0, 1),
		Text = "Err",
		TextSize = Tokens.textSize.xs,
		TextColor3 = Tokens.colors.text,
		Stroke = true,
		StrokeColor = Tokens.colors.border,
		Parent = filterRow,
	})
	self._filterErrBtn = filterErrBtn
	self._filterErrStroke = filterErrBtn:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Search box
	local searchBox = Util.textbox({
		Name = "SearchBox",
		Size = UDim2.new(0, 100, 0, 18),
		Position = UDim2.new(1, -142, 0, 1),
		PlaceholderText = "Search...",
		TextSize = Tokens.textSize.xs,
		Font = Tokens.font.mono,
		Parent = filterRow,
	})
	self._searchBox = searchBox

	-- Clear button
	local clearBtn = Instance.new("TextButton")
	clearBtn.Name = "ClearBtn"
	clearBtn.Size = UDim2.new(0, 34, 0, 18)
	clearBtn.Position = UDim2.new(1, -34, 0, 1)
	clearBtn.BackgroundTransparency = 1
	clearBtn.BorderSizePixel = 0
	clearBtn.Text = "Clear"
	clearBtn.TextColor3 = Tokens.colors.accent
	clearBtn.TextSize = Tokens.textSize.xs
	clearBtn.Font = Tokens.font.body
	clearBtn.TextXAlignment = Enum.TextXAlignment.Right
	clearBtn.AutoButtonColor = false
	clearBtn.Parent = filterRow

	-- Scroll frame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "LogScroll"
	scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 44)
	scroll.BackgroundColor3 = Tokens.colors.logBg
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Tokens.colors.border
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = section

	Util.stroke(scroll, Tokens.colors.border)

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

	-- Empty state
	local emptyState = Util.label({
		Name = "EmptyState",
		Size = UDim2.new(1, 0, 0, 40),
		Text = "No activity yet",
		TextColor3 = Tokens.colors.textMuted,
		TextSize = Tokens.textSize.md,
		Font = Tokens.font.label,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 0.4,
		Parent = scroll,
	})
	self._emptyState = emptyState

	-- Wire filter buttons
	filterAllBtn.MouseButton1Click:Connect(function()
		self:_setFilter("all")
	end)
	filterOkBtn.MouseButton1Click:Connect(function()
		self:_setFilter("success")
	end)
	filterErrBtn.MouseButton1Click:Connect(function()
		self:_setFilter("error")
	end)

	-- Wire search
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchText = string.lower(searchBox.Text)
		self:_applyFilters()
	end)

	-- Wire clear
	clearBtn.MouseButton1Click:Connect(function()
		self:clearLog()
	end)

	return self
end

function ActivityLog.addEntry(self: ActivityLog, method: string, status: string, duration: number?, errorMessage: string?)
	-- Hide empty state
	if self._emptyState.Visible then
		self._emptyState.Visible = false
	end

	local scroll = self._logScroll
	local isAtBottom = (scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y - scroll.CanvasPosition.Y) < 20

	local entry = Util.frame({
		Name = "Log_" .. method .. "_" .. tostring(#self._logEntries + 1),
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = #self._logEntries + 1,
		Parent = scroll,
	})

	-- Store metadata as attributes for filtering
	entry:SetAttribute("status", status)
	entry:SetAttribute("method", method)

	local timeStr = os.date("%H:%M:%S") :: string

	local statusIcon, color = self:_getStatusDisplay(status)

	local durationStr = self:_formatDuration(duration)

	local methodDisplay = string.sub(method, 1, 22)
	local line = string.format("%-8s %-22s %-4s %s", timeStr, methodDisplay, statusIcon, durationStr)

	local label = Util.label({
		Name = "Text",
		Size = UDim2.new(1, -16, 0, 16),
		Text = line,
		TextColor3 = color,
		TextSize = Tokens.textSize.sm,
		Font = Tokens.font.mono,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = entry,
	})

	-- Error expand indicator and detail
	if status == "error" and errorMessage then
		entry:SetAttribute("errorMessage", errorMessage)
		entry:SetAttribute("expanded", false)

		-- Expand indicator ">"
		local expandLabel = Util.label({
			Name = "ExpandIndicator",
			Size = UDim2.new(0, 14, 0, 16),
			Position = UDim2.new(1, -14, 0, 0),
			Text = ">",
			TextColor3 = Tokens.colors.accent,
			TextSize = Tokens.textSize.xs,
			Font = Tokens.font.mono,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = entry,
		})

		-- Error detail (hidden initially)
		local errDetail = Util.label({
			Name = "ErrorDetail",
			Size = UDim2.new(1, -12, 0, 0),
			Position = UDim2.new(0, 12, 0, 16),
			Text = errorMessage,
			TextColor3 = Tokens.colors.red,
			TextSize = Tokens.textSize.xs,
			Font = Tokens.font.mono,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = entry,
		})
		errDetail.Visible = false

		-- Click to expand/collapse
		local clickBtn = Instance.new("TextButton")
		clickBtn.Name = "ClickArea"
		clickBtn.Size = UDim2.new(1, 0, 0, 16)
		clickBtn.BackgroundTransparency = 1
		clickBtn.BorderSizePixel = 0
		clickBtn.Text = ""
		clickBtn.AutoButtonColor = false
		clickBtn.Parent = entry

		clickBtn.MouseButton1Click:Connect(function()
			local expanded = entry:GetAttribute("expanded")
			if expanded then
				-- Collapse
				entry:SetAttribute("expanded", false)
				expandLabel.Text = ">"
				errDetail.Visible = false
				entry.Size = UDim2.new(1, 0, 0, 16)
			else
				-- Expand
				entry:SetAttribute("expanded", true)
				expandLabel.Text = "v"
				errDetail.Visible = true
				-- Wait a frame for AutomaticSize to compute
				task.defer(function()
					local detailHeight = errDetail.AbsoluteSize.Y
					entry.Size = UDim2.new(1, 0, 0, 16 + detailHeight + 4)
				end)
			end
		end)
	end

	table.insert(self._logEntries, entry)

	-- Prune old entries
	while #self._logEntries > Tokens.MAX_LOG_ENTRIES do
		local old = table.remove(self._logEntries, 1)
		if old then
			old:Destroy()
		end
	end

	-- Re-number layout orders
	for i, e in self._logEntries do
		e.LayoutOrder = i
	end

	-- Apply current filters to new entry
	self:_applyFilterToEntry(entry)

	-- Auto-scroll
	if isAtBottom then
		task.defer(function()
			scroll.CanvasPosition = Vector2.new(0, math.huge)
		end)
	end
end

function ActivityLog.updateEntry(self: ActivityLog, method: string, status: string, duration: number?, errorMessage: string?)
	-- Find last "running" entry for this method
	for i = #self._logEntries, 1, -1 do
		local entry = self._logEntries[i]
		if entry:GetAttribute("status") == "running" and entry:GetAttribute("method") == method then
			-- Update attributes
			entry:SetAttribute("status", status)

			local textLabel = entry:FindFirstChild("Text") :: TextLabel?
			if textLabel then
				local timeStr = os.date("%H:%M:%S") :: string
				local statusIcon, color = self:_getStatusDisplay(status)
				local durationStr = self:_formatDuration(duration)
				local methodDisplay = string.sub(method, 1, 22)
				textLabel.Text = string.format("%-8s %-22s %-4s %s", timeStr, methodDisplay, statusIcon, durationStr)
				textLabel.TextColor3 = color
			end

			-- Add error details if needed
			if status == "error" and errorMessage then
				entry:SetAttribute("errorMessage", errorMessage)
				entry:SetAttribute("expanded", false)

				local existing = entry:FindFirstChild("ErrorDetail")
				if not existing then
					-- Expand indicator
					local expandLabel = Util.label({
						Name = "ExpandIndicator",
						Size = UDim2.new(0, 14, 0, 16),
						Position = UDim2.new(1, -14, 0, 0),
						Text = ">",
						TextColor3 = Tokens.colors.accent,
						TextSize = Tokens.textSize.xs,
						Font = Tokens.font.mono,
						TextXAlignment = Enum.TextXAlignment.Center,
						Parent = entry,
					})

					local errDetail = Util.label({
						Name = "ErrorDetail",
						Size = UDim2.new(1, -12, 0, 0),
						Position = UDim2.new(0, 12, 0, 16),
						Text = errorMessage,
						TextColor3 = Tokens.colors.red,
						TextSize = Tokens.textSize.xs,
						Font = Tokens.font.mono,
						TextWrapped = true,
						AutomaticSize = Enum.AutomaticSize.Y,
						Parent = entry,
					})
					errDetail.Visible = false

					-- Resize text label to make room for indicator
					if textLabel then
						textLabel.Size = UDim2.new(1, -16, 0, 16)
					end

					local clickBtn = Instance.new("TextButton")
					clickBtn.Name = "ClickArea"
					clickBtn.Size = UDim2.new(1, 0, 0, 16)
					clickBtn.BackgroundTransparency = 1
					clickBtn.BorderSizePixel = 0
					clickBtn.Text = ""
					clickBtn.AutoButtonColor = false
					clickBtn.Parent = entry

					clickBtn.MouseButton1Click:Connect(function()
						local expanded = entry:GetAttribute("expanded")
						if expanded then
							entry:SetAttribute("expanded", false)
							expandLabel.Text = ">"
							errDetail.Visible = false
							entry.Size = UDim2.new(1, 0, 0, 16)
						else
							entry:SetAttribute("expanded", true)
							expandLabel.Text = "v"
							errDetail.Visible = true
							task.defer(function()
								local detailHeight = errDetail.AbsoluteSize.Y
								entry.Size = UDim2.new(1, 0, 0, 16 + detailHeight + 4)
							end)
						end
					end)
				end
			end

			-- Re-apply filters
			self:_applyFilterToEntry(entry)
			return true
		end
	end

	return false
end

function ActivityLog.clearLog(self: ActivityLog)
	for _, entry in self._logEntries do
		entry:Destroy()
	end
	self._logEntries = {}
	self._emptyState.Visible = true
end

function ActivityLog._getStatusDisplay(_self: ActivityLog, status: string): (string, Color3)
	if status == "running" then
		return "...", Tokens.colors.yellow
	elseif status == "success" then
		return "ok", Tokens.colors.green
	elseif status == "error" then
		return "err", Tokens.colors.red
	end
	return "", Tokens.colors.textMuted
end

function ActivityLog._formatDuration(_self: ActivityLog, duration: number?): string
	if not duration then
		return ""
	end
	if duration < 1 then
		return string.format("%.0fms", duration * 1000)
	end
	return string.format("%.1fs", duration)
end

function ActivityLog._setFilter(self: ActivityLog, filter: string)
	self._filterStatus = filter

	-- Update button strokes
	self._filterAllStroke.Color = if filter == "all" then Tokens.colors.accent else Tokens.colors.border
	self._filterOkStroke.Color = if filter == "success" then Tokens.colors.accent else Tokens.colors.border
	self._filterErrStroke.Color = if filter == "error" then Tokens.colors.accent else Tokens.colors.border

	self:_applyFilters()
end

function ActivityLog._applyFilters(self: ActivityLog)
	for _, entry in self._logEntries do
		self:_applyFilterToEntry(entry)
	end
end

function ActivityLog._applyFilterToEntry(self: ActivityLog, entry: Frame)
	local status = entry:GetAttribute("status") :: string?
	local method = entry:GetAttribute("method") :: string?

	local visible = true

	-- Status filter
	if self._filterStatus ~= "all" and status then
		if self._filterStatus == "success" then
			visible = status == "success"
		elseif self._filterStatus == "error" then
			visible = status == "error"
		end
	end

	-- Search filter
	if visible and self._searchText ~= "" and method then
		visible = string.find(string.lower(method), self._searchText, 1, true) ~= nil
	end

	entry.Visible = visible
end

return ActivityLog
