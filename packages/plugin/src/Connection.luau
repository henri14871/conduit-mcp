--!strict

local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)

type ConnectionStatus = "disconnected" | "connecting" | "connected"

local HEARTBEAT_INTERVAL = 5
local MAX_RECONNECT_DELAY = 10
local HTTP_POLL_INTERVAL = 0.5
local WS_FAILURE_THRESHOLD = 3
local PORT_SCAN_RANGE = 10 -- scan basePort .. basePort+10
local HTTP_FALLBACK_WS_RETRY_INTERVAL = 15 -- try WebSocket again after this many seconds in HTTP mode

local Connection = {}
Connection.__index = Connection

export type Connection = typeof(setmetatable({} :: {
	_port: number,
	_basePort: number,
	_studioId: string,
	_status: ConnectionStatus,
	_ws: any?,
	_reconnectDelay: number,
	_wsFailureCount: number,
	_useHttpFallback: boolean,
	_httpFallbackStartTime: number,
	_heartbeatThread: thread?,
	_pollThread: thread?,
	_connectThread: thread?,
	_shouldRun: boolean,
	_messageCallbacks: { (data: any) -> () },
	_statusCallbacks: { (status: ConnectionStatus) -> () },
}, Connection))

function Connection.new(port: number): Connection
	local self = setmetatable({
		_port = port,
		_basePort = port,
		_studioId = HttpService:GenerateGUID(false),
		_status = "disconnected" :: ConnectionStatus,
		_ws = nil,
		_reconnectDelay = 1,
		_wsFailureCount = 0,
		_useHttpFallback = false,
		_httpFallbackStartTime = 0,
		_heartbeatThread = nil,
		_pollThread = nil,
		_connectThread = nil,
		_shouldRun = false,
		_messageCallbacks = {},
		_statusCallbacks = {},
	}, Connection)
	return self
end

function Connection.onMessage(self: Connection, callback: (data: any) -> ())
	table.insert(self._messageCallbacks, callback)
end

function Connection.onStatusChange(self: Connection, callback: (status: ConnectionStatus) -> ())
	table.insert(self._statusCallbacks, callback)
end

function Connection.isConnected(self: Connection): boolean
	return self._status == "connected"
end

function Connection.getStatus(self: Connection): ConnectionStatus
	return self._status
end

function Connection.getStudioId(self: Connection): string
	return self._studioId
end

function Connection.getPort(self: Connection): number
	return self._port
end

function Connection.setPort(self: Connection, port: number)
	if self._basePort == port then
		return
	end
	local wasConnected = self._shouldRun
	if wasConnected then
		self:disconnect()
	end
	self._port = port
	self._basePort = port
	if wasConnected then
		self:connect()
	end
end

function Connection.connect(self: Connection)
	if self._shouldRun then
		return
	end
	self._shouldRun = true
	self._wsFailureCount = 0
	self._useHttpFallback = false

	self._connectThread = task.spawn(function()
		self:_connectLoop()
	end)
end

function Connection.disconnect(self: Connection)
	self._shouldRun = false
	self:_setStatus("disconnected")

	if self._ws then
		pcall(function()
			self._ws:Close()
		end)
		self._ws = nil
	end

	if self._heartbeatThread then
		task.cancel(self._heartbeatThread)
		self._heartbeatThread = nil
	end

	if self._pollThread then
		task.cancel(self._pollThread)
		self._pollThread = nil
	end

	-- Don't force-cancel _connectThread here — it may be the currently executing thread.
	-- Setting _shouldRun = false (above) will cause the loop to exit naturally.
	-- Defer cancellation as a safety net in case the thread is stuck yielding.
	local threadToCancel = self._connectThread
	self._connectThread = nil
	if threadToCancel then
		task.defer(function()
			task.cancel(threadToCancel)
		end)
	end
end

function Connection.send(self: Connection, message: string)
	if self._ws and self._status == "connected" and not self._useHttpFallback then
		local ok, err = pcall(function()
			self._ws:Send(message)
		end)
		if not ok then
			warn("[Conduit] WebSocket send failed:", err)
		end
	elseif self._useHttpFallback and self._status == "connected" then
		self:_httpPost("/result", message)
	end
end

function Connection.pollHealth(self: Connection): { studioCount: number, activeStudioId: string? }?
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = "http://localhost:" .. self._port .. "/health",
			Method = "GET",
		})
	end)
	if not ok or not response or response.StatusCode ~= 200 then
		return nil
	end
	local decodeOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or not data then
		return nil
	end
	return {
		studioCount = if data.studios then #data.studios else 0,
		activeStudioId = data.activeStudioId,
	}
end

-- ── Internal ─────────────────────────────────────────────────────

function Connection._setStatus(self: Connection, status: ConnectionStatus)
	if self._status == status then
		return
	end
	self._status = status
	for _, cb in self._statusCallbacks do
		task.spawn(cb, status)
	end
end

function Connection._fireMessage(self: Connection, data: any)
	for _, cb in self._messageCallbacks do
		task.spawn(cb, data)
	end
end

--[[ Scan basePort .. basePort+PORT_SCAN_RANGE for a live Conduit /health endpoint.
     Returns the first port that responds, or nil if none found. ]]
function Connection._discoverPort(self: Connection): number?
	for offset = 0, PORT_SCAN_RANGE do
		local tryPort = self._basePort + offset
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = "http://localhost:" .. tryPort .. "/health",
				Method = "GET",
			})
		end)
		if ok and response and response.StatusCode == 200 then
			local decodeOk, data = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			-- Verify it's actually a Conduit server (has "status" field)
			if decodeOk and data and data.status == "ok" then
				if tryPort ~= self._port then
					print("[Conduit] Discovered server on port " .. tryPort .. " (configured: " .. self._basePort .. ")")
				end
				return tryPort
			end
		end
	end
	return nil
end

function Connection._connectLoop(self: Connection)
	while self._shouldRun do
		-- Discover the actual server port before each connection attempt
		local discoveredPort = self:_discoverPort()
		if discoveredPort then
			self._port = discoveredPort
		else
			self._port = self._basePort -- reset to base for next scan
		end

		-- If we've been in HTTP fallback long enough, try WebSocket again
		if self._useHttpFallback then
			local elapsed = os.clock() - self._httpFallbackStartTime
			if elapsed >= HTTP_FALLBACK_WS_RETRY_INTERVAL then
				print("[Conduit] Retrying WebSocket after HTTP fallback period")
				self._useHttpFallback = false
				self._wsFailureCount = 0
			end
		end

		if self._useHttpFallback then
			self:_connectHttp()
		else
			self:_connectWebSocket()
		end

		if not self._shouldRun then
			break
		end

		-- Wait before reconnecting (capped at MAX_RECONNECT_DELAY = 10s)
		local delay = self._reconnectDelay
		self._reconnectDelay = math.min(self._reconnectDelay * 2, MAX_RECONNECT_DELAY)
		warn("[Conduit] Reconnecting in " .. delay .. "s...")
		task.wait(delay)
	end

	self._connectThread = nil
end

function Connection._connectWebSocket(self: Connection)
	self:_setStatus("connecting")

	local ok, ws = pcall(function()
		return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
			Url = "ws://localhost:" .. self._port,
		})
	end)

	if not ok or not ws then
		warn("[Conduit] WebSocket creation failed:", ws)
		self._wsFailureCount += 1
		if self._wsFailureCount >= WS_FAILURE_THRESHOLD then
			warn("[Conduit] Switching to HTTP fallback after " .. WS_FAILURE_THRESHOLD .. " WebSocket failures")
			self._useHttpFallback = true
			self._httpFallbackStartTime = os.clock()
		end
		return
	end

	self._ws = ws
	local connected = false
	local closed = false

	ws.Opened:Connect(function()
		connected = true
		self._wsFailureCount = 0
		self._reconnectDelay = 1

		-- Send studio registration before anything else
		local regOk = pcall(function()
			ws:Send(HttpService:JSONEncode({
				type = "register",
				studioId = self._studioId,
				placeId = game.PlaceId,
				placeName = game.Name or "Unknown",
			}))
		end)
		if not regOk then
			warn("[Conduit] Failed to send registration")
		end

		self:_setStatus("connected")
		print("[Conduit] Connected via WebSocket to port " .. self._port .. " (studio: " .. self._studioId .. ")")

		-- Start heartbeat
		self._heartbeatThread = task.spawn(function()
			while self._shouldRun and self._status == "connected" do
				local hbOk = pcall(function()
					ws:Send(HttpService:JSONEncode({ type = "heartbeat" }))
				end)
				if not hbOk then
					warn("[Conduit] Heartbeat send failed — connection lost")
					pcall(function()
						ws:Close()
					end)
					self._ws = nil
					closed = true
					if self._shouldRun then
						self:_setStatus("disconnected")
					end
					break
				end
				task.wait(HEARTBEAT_INTERVAL)
			end
		end)
	end)

	ws.MessageReceived:Connect(function(message: string)
		local decodeOk, data = pcall(function()
			return HttpService:JSONDecode(message)
		end)
		if decodeOk and data then
			self:_fireMessage(data)
		else
			warn("[Conduit] Failed to decode message:", message)
		end
	end)

	ws.Closed:Connect(function()
		closed = true
		self._ws = nil
		if self._heartbeatThread then
			task.cancel(self._heartbeatThread)
			self._heartbeatThread = nil
		end
		if self._shouldRun then
			self:_setStatus("disconnected")
		end
	end)

	ws.Error:Connect(function(err: string)
		warn("[Conduit] WebSocket error:", err)
	end)

	-- Wait until connection opens, with a 10-second timeout
	local waitStart = os.clock()
	while self._shouldRun and not closed and not connected do
		if os.clock() - waitStart > 10 then
			warn("[Conduit] WebSocket connection timed out after 10s")
			pcall(function()
				ws:Close()
			end)
			self._ws = nil
			self._wsFailureCount += 1
			if self._wsFailureCount >= WS_FAILURE_THRESHOLD then
				warn("[Conduit] Switching to HTTP fallback after " .. WS_FAILURE_THRESHOLD .. " WebSocket failures")
				self._useHttpFallback = true
				self._httpFallbackStartTime = os.clock()
			end
			return
		end
		task.wait(0.5)
	end

	-- Wait until connection closes or we disconnect
	while self._shouldRun and not closed do
		task.wait(1)
	end
end

function Connection._connectHttp(self: Connection)
	self:_setStatus("connecting")

	-- Check if server is available
	local healthOk, healthResult = pcall(function()
		local response = HttpService:RequestAsync({
			Url = "http://localhost:" .. self._port .. "/health",
			Method = "GET",
		})
		return response.StatusCode == 200
	end)

	if not healthOk or not healthResult then
		return
	end

	self._reconnectDelay = 1
	self:_setStatus("connected")
	print("[Conduit] Connected via HTTP fallback to port " .. self._port .. " (studio: " .. self._studioId .. ")")

	-- Start polling loop
	while self._shouldRun and self._status == "connected" do
		local pollOk, response = pcall(function()
			return HttpService:RequestAsync({
				Url = "http://localhost:" .. self._port .. "/poll?studioId=" .. self._studioId
				.. "&placeId=" .. tostring(game.PlaceId)
				.. "&placeName=" .. HttpService:UrlEncode(game.Name or "Unknown"),
				Method = "GET",
			})
		end)

		if not pollOk then
			warn("[Conduit] HTTP poll failed")
			self:_setStatus("disconnected")
			break
		end

		if response.StatusCode == 200 and response.Body and #response.Body > 0 then
			local decodeOk, data = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			if decodeOk and data then
				self:_fireMessage(data)
			end
		elseif response.StatusCode ~= 204 then
			warn("[Conduit] Unexpected poll status:", response.StatusCode)
			self:_setStatus("disconnected")
			break
		end

		task.wait(HTTP_POLL_INTERVAL)
	end
end

function Connection._httpPost(self: Connection, path: string, body: string): boolean
	local ok = pcall(function()
		HttpService:RequestAsync({
			Url = "http://localhost:" .. self._port .. path,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	return ok
end

return Connection
