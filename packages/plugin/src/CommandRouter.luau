--!strict

local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)
local UndoManager = require(script.Parent.UndoManager)

type Connection = {
	onMessage: (self: any, callback: (data: any) -> ()) -> (),
	send: (self: any, message: string) -> (),
}

local CommandRouter = {}
CommandRouter.__index = CommandRouter

export type CommandRouter = typeof(setmetatable({} :: {
	_connection: Connection,
	_handlers: { [string]: Types.HandlerFn },
	_mutatingMethods: { [string]: boolean },
	_mutationQueue: { { id: string, method: string, params: any, handler: Types.HandlerFn, sessionId: string? } },
	_isMutationRunning: boolean,
	_activeTransaction: { id: string, recording: any }?,
	_transactionTimeout: thread?,
}, CommandRouter))

function CommandRouter.new(connection: Connection): CommandRouter
	local self = setmetatable({
		_connection = connection,
		_handlers = {},
		_mutatingMethods = {},
		_mutationQueue = {},
		_isMutationRunning = false,
		_activeTransaction = nil,
		_transactionTimeout = nil,
	}, CommandRouter)

	connection:onMessage(function(data: any)
		self:_handleMessage(data)
	end)

	-- Register transaction handlers
	self:register("begin_transaction", function(params: { [string]: any })
		if self._activeTransaction then
			error("A transaction is already active. Commit or rollback before starting a new one.")
		end

		local name: string = params.name or "Transaction"
		local recording = UndoManager.beginTransaction(name)
		local transactionId = name .. "_" .. tostring(tick())

		self._activeTransaction = { id = transactionId, recording = recording }

		-- Auto-rollback after 60 seconds to prevent dangling recordings
		self._transactionTimeout = task.delay(60, function()
			if self._activeTransaction and self._activeTransaction.id == transactionId then
				warn("[Conduit] Transaction timed out after 60s, auto-rolling back: " .. name)
				pcall(function()
					UndoManager.rollbackTransaction(self._activeTransaction.recording)
				end)
				self._activeTransaction = nil
				self._transactionTimeout = nil
			end
		end)

		return { transactionId = transactionId, status = "active" }
	end, true)

	self:register("commit_transaction", function(_params: { [string]: any })
		if not self._activeTransaction then
			error("No active transaction to commit")
		end

		if self._transactionTimeout then
			task.cancel(self._transactionTimeout)
			self._transactionTimeout = nil
		end

		UndoManager.commitTransaction(self._activeTransaction.recording)
		self._activeTransaction = nil

		return { status = "committed" }
	end, true)

	self:register("rollback_transaction", function(_params: { [string]: any })
		if not self._activeTransaction then
			error("No active transaction to rollback")
		end

		if self._transactionTimeout then
			task.cancel(self._transactionTimeout)
			self._transactionTimeout = nil
		end

		UndoManager.rollbackTransaction(self._activeTransaction.recording)
		self._activeTransaction = nil

		return { status = "rolled_back" }
	end, true)

	return self
end

function CommandRouter.register(self: CommandRouter, method: string, handler: Types.HandlerFn, mutating: boolean?)
	self._handlers[method] = handler
	if mutating then
		self._mutatingMethods[method] = true
	end
end

function CommandRouter._handleMessage(self: CommandRouter, data: any)
	-- Ignore heartbeats and responses (only handle requests with method)
	if not data or not data.id or not data.method then
		return
	end

	local id = data.id
	local method = data.method
	local params = data.params or {}
	local sessionId = data.sessionId

	local handler = self._handlers[method]
	if not handler then
		self:_sendError(id, "UNKNOWN_METHOD", "Unknown method: " .. tostring(method))
		return
	end

	if self._mutatingMethods[method] then
		-- Queue mutating commands for serial execution
		table.insert(self._mutationQueue, {
			id = id,
			method = method,
			params = params,
			handler = handler,
			sessionId = sessionId,
		})
		self:_processMutationQueue()
	else
		-- Read-only handlers run immediately in parallel
		task.spawn(function()
			local ok, result = pcall(handler, params)
			if ok then
				self:_sendResult(id, result)
			else
				self:_sendError(id, "HANDLER_ERROR", tostring(result))
			end
		end)
	end
end

function CommandRouter._processMutationQueue(self: CommandRouter)
	if self._isMutationRunning then
		return
	end

	local item = table.remove(self._mutationQueue, 1)
	if not item then
		return
	end

	self._isMutationRunning = true

	task.spawn(function()
		local ok, result

		local recordingName = item.method
		if item.sessionId then
			recordingName = "[" .. item.sessionId .. "] " .. item.method
		end

		local isTransactionCmd = item.method == "begin_transaction"
			or item.method == "commit_transaction"
			or item.method == "rollback_transaction"

		if isTransactionCmd or self._activeTransaction then
			-- Transaction commands manage their own recording lifecycle.
			-- Other commands inside a transaction run without individual recordings.
			ok, result = pcall(item.handler, item.params)
		else
			-- Normal: wrap in UndoManager.record for individual undo point
			ok, result = pcall(function()
				return UndoManager.record(recordingName, function()
					return item.handler(item.params)
				end)
			end)
		end

		if ok then
			self:_sendResult(item.id, result)
		else
			self:_sendError(item.id, "HANDLER_ERROR", tostring(result))
		end

		self._isMutationRunning = false
		self:_processMutationQueue()
	end)
end

function CommandRouter._sendResult(self: CommandRouter, id: string, result: any)
	local response = {
		id = id,
		result = result,
	}
	local ok, json = pcall(function()
		return HttpService:JSONEncode(response)
	end)
	if ok then
		self._connection:send(json)
	else
		warn("[Conduit] Failed to encode result for " .. id .. ": " .. tostring(json))
		self:_sendError(id, "ENCODE_ERROR", "Failed to encode response")
	end
end

function CommandRouter._sendError(self: CommandRouter, id: string, code: string, message: string)
	local response = {
		id = id,
		error = {
			code = code,
			message = message,
		},
	}
	local ok, json = pcall(function()
		return HttpService:JSONEncode(response)
	end)
	if ok then
		self._connection:send(json)
	else
		warn("[Conduit] Failed to encode error for " .. id)
	end
end

return CommandRouter
