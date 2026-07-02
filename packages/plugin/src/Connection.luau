--!strict

local HttpService = game:GetService("HttpService")

type ConnectionStatus = "disconnected" | "connecting" | "connected"

local HEARTBEAT_INTERVAL = 5
-- Server marks a studio stale after 20s without a heartbeat. We give up first at
-- 15s so the plugin re-establishes before the server tears the socket down — that
-- keeps reconnect ownership on the side that can act, and avoids both ends racing
-- to close the same connection.
local HEARTBEAT_ACK_TIMEOUT = 15
local MAX_RECONNECT_DELAY = 5
local HTTP_POLL_INTERVAL = 0.5
local WS_FAILURE_THRESHOLD = 3
local PORT_SCAN_RANGE = 10 -- scan basePort .. basePort+10
-- Every MCP client (Claude Code, Codex, ...) spawns its own Conduit server, and
-- when a port is taken the next server binds basePort+1, +2, ... The plugin keeps
-- an independent session per live port so all clients can drive Studio at once.
-- Scan cadence balances pickup latency for a new client against HttpService's
-- request budget (11 probes per sweep).
local SCAN_INTERVAL_DISCONNECTED = 5
local SCAN_INTERVAL_CONNECTED = 8
local CONNECT_OPEN_TIMEOUT = 10
-- While a session is stuck in HTTP fallback we periodically break out and retry
-- WebSocket. The interval doubles each failed upgrade so a Studio build without
-- WebSocket support isn't constantly interrupting a working HTTP session.
local HTTP_FALLBACK_WS_RETRY_BASE = 10
local HTTP_FALLBACK_WS_RETRY_MAX = 120
-- The server binds 127.0.0.1 only. Using "localhost" here is not equivalent: on
-- some machines it resolves to ::1 first and the connection is refused.
local HOST = "127.0.0.1"

local Connection = {}
Connection.__index = Connection

type Session = {
	port: number,
	status: ConnectionStatus,
	alive: boolean,
	-- Bumped on every (re)connect and on destroy. Socket event handlers capture
	-- the generation they were created under and ignore anything that fires late,
	-- so a lingering Closed/MessageReceived from an old socket can never clobber
	-- the state of its replacement.
	generation: number,
	ws: any?,
	wsFailureCount: number,
	useHttpFallback: boolean,
	fallbackStartTime: number,
	fallbackRetryInterval: number,
	reconnectDelay: number,
	skipBackoff: boolean,
	lastHeartbeatAck: number,
	lastHeartbeatSendTime: number,
	lastPingMs: number?,
	thread: thread?,
	heartbeatThread: thread?,
}

export type Connection = typeof(setmetatable({} :: {
	_basePort: number,
	_studioId: string,
	_status: ConnectionStatus,
	_shouldRun: boolean,
	_wsSupported: boolean,
	_sessions: { [number]: Session },
	-- request id -> session that delivered it, so responses route back to the
	-- server that asked (other servers ignore ids they don't know, but routing
	-- avoids needless cross-traffic).
	_requestOrigins: { [string]: Session },
	_scanThread: thread?,
	_messageCallbacks: { (data: any) -> () },
	_statusCallbacks: { (status: ConnectionStatus) -> () },
	_pingCallbacks: { (ms: number) -> () },
	_reconnectCountdownCallbacks: { (remaining: number, total: number) -> () },
}, Connection))

function Connection.new(port: number): Connection
	-- Older Studio builds don't have CreateWebStreamClient; those go straight to
	-- HTTP fallback instead of burning three doomed WebSocket attempts per session.
	local wsSupported = pcall(function()
		return (HttpService :: any).CreateWebStreamClient
	end)

	local self = setmetatable({
		_basePort = port,
		_studioId = HttpService:GenerateGUID(false),
		_status = "disconnected" :: ConnectionStatus,
		_shouldRun = false,
		_wsSupported = wsSupported,
		_sessions = {} :: { [number]: Session },
		_requestOrigins = {} :: { [string]: Session },
		_scanThread = nil :: thread?,
		_messageCallbacks = {},
		_statusCallbacks = {},
		_pingCallbacks = {},
		_reconnectCountdownCallbacks = {},
	}, Connection)
	return self
end

function Connection.onMessage(self: Connection, callback: (data: any) -> ())
	table.insert(self._messageCallbacks, callback)
end

function Connection.onStatusChange(self: Connection, callback: (status: ConnectionStatus) -> ())
	table.insert(self._statusCallbacks, callback)
end

function Connection.onPingUpdate(self: Connection, callback: (ms: number) -> ())
	table.insert(self._pingCallbacks, callback)
end

function Connection.onReconnectCountdown(self: Connection, callback: (remaining: number, total: number) -> ())
	table.insert(self._reconnectCountdownCallbacks, callback)
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
	local primary = self:_primarySession()
	return if primary then primary.port else self._basePort
end

function Connection.getLastPing(self: Connection): number?
	local primary = self:_primarySession()
	return if primary then primary.lastPingMs else nil
end

function Connection.getServerCount(self: Connection): number
	local count = 0
	for _, session in self._sessions do
		if session.status == "connected" then
			count += 1
		end
	end
	return count
end

function Connection.setPort(self: Connection, port: number)
	if self._basePort == port then
		return
	end
	local wasRunning = self._shouldRun
	if wasRunning then
		self:disconnect()
	end
	self._basePort = port
	if wasRunning then
		self:connect()
	end
end

function Connection.connect(self: Connection)
	if self._shouldRun then
		return
	end
	self._shouldRun = true
	self._scanThread = task.spawn(function()
		self:_scanLoop()
	end)
end

function Connection.disconnect(self: Connection)
	self._shouldRun = false

	if self._scanThread then
		local thread = self._scanThread
		self._scanThread = nil
		if coroutine.running() ~= thread then
			pcall(task.cancel, thread)
		end
	end

	local sessions: { Session } = {}
	for _, session in self._sessions do
		table.insert(sessions, session)
	end
	for _, session in sessions do
		self:_destroySession(session)
	end
	table.clear(self._requestOrigins)

	self:_recomputeStatus()
end

--[[ Send a plugin->server message. When `requestId` is given, the message is a
     response to a request and is routed to the server session that issued it.
     Falls back to broadcasting to every connected session — servers silently
     ignore response ids they don't recognize. ]]
function Connection.send(self: Connection, message: string, requestId: string?)
	local origin: Session? = nil
	if requestId ~= nil then
		local key = tostring(requestId)
		origin = self._requestOrigins[key]
		self._requestOrigins[key] = nil
	end

	if origin and self:_trySend(origin, message) then
		return
	end

	for _, session in self._sessions do
		if session ~= origin then
			self:_trySend(session, message)
		end
	end
end

function Connection.pollHealth(self: Connection): { studioCount: number, activeStudioId: string?, isRegistered: boolean }?
	local data = self:_probeHealth(self:getPort())
	if not data then
		return nil
	end
	local isRegistered = false
	if data.studios then
		for _, studio in data.studios do
			if studio.studioId == self._studioId then
				isRegistered = true
				break
			end
		end
	end
	return {
		studioCount = if data.studios then #data.studios else 0,
		activeStudioId = data.activeStudioId,
		isRegistered = isRegistered,
	}
end

-- ── Internal: callbacks ──────────────────────────────────────────

function Connection._recomputeStatus(self: Connection)
	local newStatus: ConnectionStatus = "disconnected"
	if self._shouldRun then
		local anyConnecting = false
		for _, session in self._sessions do
			if session.status == "connected" then
				newStatus = "connected"
				break
			elseif session.status == "connecting" then
				anyConnecting = true
			end
		end
		if newStatus ~= "connected" and anyConnecting then
			newStatus = "connecting"
		end
	end

	if self._status == newStatus then
		return
	end
	self._status = newStatus
	for _, cb in self._statusCallbacks do
		task.spawn(cb, newStatus)
	end
end

function Connection._fireMessage(self: Connection, data: any)
	for _, cb in self._messageCallbacks do
		task.spawn(cb, data)
	end
end

function Connection._firePingUpdate(self: Connection, ms: number)
	for _, cb in self._pingCallbacks do
		task.spawn(cb, ms)
	end
end

function Connection._fireReconnectCountdown(self: Connection, remaining: number, total: number)
	for _, cb in self._reconnectCountdownCallbacks do
		task.spawn(cb, remaining, total)
	end
end

-- ── Internal: sessions ───────────────────────────────────────────

function Connection._anyConnected(self: Connection): boolean
	for _, session in self._sessions do
		if session.status == "connected" then
			return true
		end
	end
	return false
end

function Connection._primarySession(self: Connection): Session?
	local best: Session? = nil
	for _, session in self._sessions do
		if session.status == "connected" and (best == nil or session.port < best.port) then
			best = session
		end
	end
	if best then
		return best
	end
	for _, session in self._sessions do
		if best == nil or session.port < best.port then
			best = session
		end
	end
	return best
end

--[[ GET /health on a port; returns the decoded body only when a real Conduit
     server answered (it has status = "ok"). ]]
function Connection._probeHealth(self: Connection, port: number): any?
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = string.format("http://%s:%d/health", HOST, port),
			Method = "GET",
		})
	end)
	if not ok or not response or response.StatusCode ~= 200 then
		return nil
	end
	local decodeOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or type(data) ~= "table" or data.status ~= "ok" then
		return nil
	end
	return data
end

--[[ Discovery loop: probe every port in range and open a session for each live
     Conduit server that doesn't have one. Sessions handle their own reconnects;
     this loop only creates them (and re-creates them after a server comes back). ]]
function Connection._scanLoop(self: Connection)
	while self._shouldRun do
		for offset = 0, PORT_SCAN_RANGE do
			if not self._shouldRun then
				return
			end
			local port = self._basePort + offset
			if not self._sessions[port] and self:_probeHealth(port) ~= nil then
				self:_createSession(port)
			end
		end

		if not self._shouldRun then
			return
		end

		local interval = if self:_anyConnected() then SCAN_INTERVAL_CONNECTED else SCAN_INTERVAL_DISCONNECTED
		if next(self._sessions) == nil then
			-- Nothing to talk to — surface the rescan wait as a countdown so the
			-- dashboard shows when the next attempt happens.
			for remaining = interval, 1, -1 do
				self:_fireReconnectCountdown(remaining, interval)
				task.wait(1)
				if not self._shouldRun then
					return
				end
			end
			self:_fireReconnectCountdown(0, interval)
		else
			task.wait(interval)
		end
	end
end

function Connection._createSession(self: Connection, port: number)
	local session: Session = {
		port = port,
		status = "connecting" :: ConnectionStatus,
		alive = true,
		generation = 0,
		ws = nil,
		wsFailureCount = 0,
		useHttpFallback = not self._wsSupported,
		fallbackStartTime = 0,
		fallbackRetryInterval = HTTP_FALLBACK_WS_RETRY_BASE,
		reconnectDelay = 1,
		skipBackoff = false,
		lastHeartbeatAck = 0,
		lastHeartbeatSendTime = 0,
		lastPingMs = nil,
		thread = nil,
		heartbeatThread = nil,
	}
	self._sessions[port] = session
	print("[Conduit] Discovered MCP server on port " .. port)
	self:_recomputeStatus()

	session.thread = task.spawn(function()
		self:_sessionLoop(session)
	end)
end

function Connection._destroySession(self: Connection, session: Session)
	session.alive = false
	session.generation += 1 -- invalidate any handlers still wired to old sockets
	session.status = "disconnected"

	if session.ws then
		local ws = session.ws
		session.ws = nil
		pcall(function()
			ws:Close()
		end)
	end

	if session.heartbeatThread then
		local thread = session.heartbeatThread
		session.heartbeatThread = nil
		if coroutine.running() ~= thread then
			pcall(task.cancel, thread)
		end
	end

	for id, origin in self._requestOrigins do
		if origin == session then
			self._requestOrigins[id] = nil
		end
	end

	if self._sessions[session.port] == session then
		self._sessions[session.port] = nil
	end

	if session.thread then
		local thread = session.thread
		session.thread = nil
		if coroutine.running() ~= thread then
			pcall(task.cancel, thread)
		end
	end

	self:_recomputeStatus()
end

function Connection._sessionLoop(self: Connection, session: Session)
	while self._shouldRun and session.alive do
		if session.useHttpFallback then
			self:_runHttpFallback(session)
		else
			self:_runWebSocket(session)
		end

		if not self._shouldRun or not session.alive then
			break
		end

		-- If the server itself is gone, drop the session; the scanner re-creates
		-- it as soon as something is listening on the port again.
		if self:_probeHealth(session.port) == nil then
			print("[Conduit] MCP server on port " .. session.port .. " is gone")
			break
		end

		if session.skipBackoff then
			-- Internal transport switch (WS -> HTTP fallback or upgrade attempt);
			-- the server is fine, so don't sit out a backoff delay.
			session.skipBackoff = false
		else
			local delay = session.reconnectDelay
			session.reconnectDelay = math.min(session.reconnectDelay * 2, MAX_RECONNECT_DELAY)
			for remaining = delay, 1, -1 do
				if not self:_anyConnected() then
					self:_fireReconnectCountdown(remaining, delay)
				end
				task.wait(1)
				if not self._shouldRun or not session.alive then
					break
				end
			end
			if not self:_anyConnected() then
				self:_fireReconnectCountdown(0, delay)
			end
		end
	end

	self:_destroySession(session)
end

function Connection._registerWsFailure(self: Connection, session: Session)
	session.wsFailureCount += 1
	if session.wsFailureCount >= WS_FAILURE_THRESHOLD then
		warn(
			"[Conduit] Switching to HTTP fallback on port "
				.. session.port
				.. " after "
				.. WS_FAILURE_THRESHOLD
				.. " WebSocket failures"
		)
		session.useHttpFallback = true
		session.fallbackStartTime = os.clock()
		session.reconnectDelay = 1
		session.skipBackoff = true
	end
end

function Connection._runWebSocket(self: Connection, session: Session)
	session.status = "connecting"
	self:_recomputeStatus()

	local ok, ws = pcall(function()
		return (HttpService :: any):CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
			Url = string.format("ws://%s:%d", HOST, session.port),
		})
	end)

	if not ok or not ws then
		warn("[Conduit] WebSocket creation failed on port " .. session.port .. ":", ws)
		self:_registerWsFailure(session)
		return
	end

	session.generation += 1
	local generation = session.generation
	session.ws = ws
	session.lastHeartbeatAck = 0
	session.lastHeartbeatSendTime = 0
	session.lastPingMs = nil

	local opened = false
	local closed = false

	local function isStale(): boolean
		return session.generation ~= generation or not session.alive or not self._shouldRun
	end

	ws.Opened:Connect(function()
		if isStale() then
			return
		end
		opened = true
		session.wsFailureCount = 0
		session.reconnectDelay = 1
		session.fallbackRetryInterval = HTTP_FALLBACK_WS_RETRY_BASE
		session.lastHeartbeatAck = os.clock()

		-- Registration is the first send on a fresh socket; if it fails the link
		-- is unusable. Close now and let the session loop retry instead of waiting
		-- for the server's registration timeout to kick us.
		local regOk = pcall(function()
			ws:Send(HttpService:JSONEncode({
				type = "register",
				studioId = self._studioId,
				placeId = game.PlaceId,
				placeName = game.Name or "Unknown",
			}))
		end)
		if not regOk then
			warn("[Conduit] Failed to send registration on port " .. session.port .. " — reconnecting")
			closed = true
			pcall(function()
				ws:Close()
			end)
			return
		end

		session.status = "connected"
		self:_recomputeStatus()
		print(string.format("[Conduit] Connected via WebSocket to port %d (studio: %s)", session.port, self._studioId))

		session.heartbeatThread = task.spawn(function()
			while not isStale() and session.status == "connected" do
				session.lastHeartbeatSendTime = os.clock()
				local hbOk = pcall(function()
					ws:Send(HttpService:JSONEncode({ type = "heartbeat" }))
				end)
				if not hbOk then
					warn("[Conduit] Heartbeat send failed on port " .. session.port .. " — reconnecting")
					closed = true
					pcall(function()
						ws:Close()
					end)
					break
				end

				if session.lastHeartbeatAck > 0 and (os.clock() - session.lastHeartbeatAck) > HEARTBEAT_ACK_TIMEOUT then
					warn(
						"[Conduit] No heartbeat_ack from port "
							.. session.port
							.. " for "
							.. HEARTBEAT_ACK_TIMEOUT
							.. "s — connection stale"
					)
					closed = true
					pcall(function()
						ws:Close()
					end)
					break
				end

				task.wait(HEARTBEAT_INTERVAL)
			end
		end)
	end)

	ws.MessageReceived:Connect(function(message: string)
		if isStale() then
			return
		end
		local decodeOk, data = pcall(function()
			return HttpService:JSONDecode(message)
		end)
		if not decodeOk or not data then
			warn("[Conduit] Failed to decode message:", message)
			return
		end

		if data.type == "heartbeat_ack" then
			session.lastHeartbeatAck = os.clock()
			if session.lastHeartbeatSendTime > 0 then
				local rtt = os.clock() - session.lastHeartbeatSendTime
				session.lastPingMs = math.floor(rtt * 1000)
				if self:_primarySession() == session then
					self:_firePingUpdate(session.lastPingMs :: number)
				end
			end
			return
		end

		if type(data) == "table" and data.id ~= nil and data.method ~= nil then
			self._requestOrigins[tostring(data.id)] = session
		end
		self:_fireMessage(data)
	end)

	ws.Closed:Connect(function()
		if session.generation ~= generation then
			return
		end
		closed = true
		session.ws = nil
		if session.heartbeatThread then
			local thread = session.heartbeatThread
			session.heartbeatThread = nil
			if coroutine.running() ~= thread then
				pcall(task.cancel, thread)
			end
		end
		if session.status ~= "disconnected" then
			session.status = "disconnected"
			self:_recomputeStatus()
		end
	end)

	ws.Error:Connect(function(err: string)
		if isStale() then
			return
		end
		warn("[Conduit] WebSocket error on port " .. session.port .. ":", err)
	end)

	-- Wait until the connection opens, with a timeout
	local waitStart = os.clock()
	while not opened and not closed and not isStale() do
		if os.clock() - waitStart > CONNECT_OPEN_TIMEOUT then
			warn("[Conduit] WebSocket connection timed out after " .. CONNECT_OPEN_TIMEOUT .. "s on port " .. session.port)
			session.ws = nil
			pcall(function()
				ws:Close()
			end)
			self:_registerWsFailure(session)
			return
		end
		task.wait(0.25)
	end

	-- Wait until the connection closes or the session is torn down
	while not closed and not isStale() do
		task.wait(0.5)
	end

	if not opened then
		-- Closed before ever opening: handshake refused/failed
		self:_registerWsFailure(session)
	end
end

function Connection._runHttpFallback(self: Connection, session: Session)
	session.status = "connecting"
	self:_recomputeStatus()
	session.fallbackStartTime = os.clock()

	if self:_probeHealth(session.port) == nil then
		return
	end

	session.reconnectDelay = 1
	session.status = "connected"
	self:_recomputeStatus()
	print(string.format("[Conduit] Connected via HTTP fallback to port %d (studio: %s)", session.port, self._studioId))

	while self._shouldRun and session.alive and session.status == "connected" do
		-- Periodically break out and retry WebSocket — a fallback session should
		-- heal back to the fast transport once the server is reachable over WS.
		if self._wsSupported and (os.clock() - session.fallbackStartTime) >= session.fallbackRetryInterval then
			print("[Conduit] Attempting WebSocket upgrade on port " .. session.port)
			session.useHttpFallback = false
			session.wsFailureCount = 0
			session.fallbackRetryInterval =
				math.min(session.fallbackRetryInterval * 2, HTTP_FALLBACK_WS_RETRY_MAX)
			session.skipBackoff = true
			session.status = "connecting"
			self:_recomputeStatus()
			return
		end

		local pollOk, response = pcall(function()
			return HttpService:RequestAsync({
				Url = string.format(
					"http://%s:%d/poll?studioId=%s&placeId=%s&placeName=%s",
					HOST,
					session.port,
					self._studioId,
					tostring(game.PlaceId),
					HttpService:UrlEncode(game.Name or "Unknown")
				),
				Method = "GET",
			})
		end)

		if not self._shouldRun or not session.alive or session.status ~= "connected" then
			break
		end

		if not pollOk then
			warn("[Conduit] HTTP poll failed on port " .. session.port)
			session.status = "disconnected"
			self:_recomputeStatus()
			break
		end

		if response.StatusCode == 200 and response.Body and #response.Body > 0 then
			local decodeOk, data = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			if decodeOk and data then
				if type(data) == "table" and data.id ~= nil and data.method ~= nil then
					self._requestOrigins[tostring(data.id)] = session
				end
				self:_fireMessage(data)
			end
		elseif response.StatusCode ~= 204 then
			warn("[Conduit] Unexpected poll status on port " .. session.port .. ":", response.StatusCode)
			session.status = "disconnected"
			self:_recomputeStatus()
			break
		end

		task.wait(HTTP_POLL_INTERVAL)
	end
end

function Connection._trySend(self: Connection, session: Session, message: string): boolean
	if not session.alive or session.status ~= "connected" then
		return false
	end

	if session.useHttpFallback then
		local ok = self:_httpPost(session.port, "/result", message)
		if not ok then
			warn("[Conduit] Failed to POST result to port " .. session.port)
		end
		return ok
	end

	local ws = session.ws
	if not ws then
		return false
	end
	local ok, err = pcall(function()
		ws:Send(message)
	end)
	if not ok then
		-- The socket is broken. Close it so the session reconnects immediately
		-- instead of silently dropping every subsequent response.
		warn("[Conduit] WebSocket send failed on port " .. session.port .. ":", err)
		pcall(function()
			ws:Close()
		end)
		return false
	end
	return true
end

function Connection._httpPost(self: Connection, port: number, path: string, body: string): boolean
	local ok = pcall(function()
		HttpService:RequestAsync({
			Url = string.format("http://%s:%d%s", HOST, port, path),
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	return ok
end

return Connection
