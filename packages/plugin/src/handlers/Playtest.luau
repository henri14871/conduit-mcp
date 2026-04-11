--!strict
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")

local function register(router: any)
	-- ── playtest (start/stop/execute) ────────────────────────────────
	router:register("playtest", function(params: { [string]: any })
		local action: string = params.action
		if not action then
			error("playtest requires an action (start, stop, or execute)")
		end

		if action == "start" then
			if RunService:IsRunning() then
				return { status = "already_running", isRunning = true }
			end

			local mode: string = params.mode or "run"

			if mode == "run" then
				local ok, err = pcall(function()
					RunService:Run()
				end)
				if not ok then
					error(`Failed to start Run mode: {err}`)
				end
				-- Run mode is synchronous — verify it started
				task.wait(0.2)
				return {
					status = "started",
					mode = "run",
					isRunning = RunService:IsRunning(),
				}
			else
				-- Play mode (F5) — this is unreliable from plugin context because
				-- ExecutePlayModeAsync transitions the DataModel and can disrupt
				-- plugin threads. We fire-and-forget and return immediately.
				local ok, StudioTestService = pcall(function()
					return game:GetService("StudioTestService")
				end)

				if ok and StudioTestService then
					task.spawn(function()
						pcall(function()
							(StudioTestService :: any):ExecutePlayModeAsync({})
						end)
					end)
					return {
						status = "started",
						mode = "play",
						isRunning = false,
						message = "Play mode initiated — the plugin connection may briefly drop during the transition. Use get_output or inspect to verify the playtest is running.",
					}
				end

				-- Fallback to Run mode if StudioTestService is unavailable
				local runOk, runErr = pcall(function()
					RunService:Run()
				end)
				if not runOk then
					error(`Failed to start playtest: {runErr}`)
				end
				task.wait(0.2)
				return {
					status = "started",
					mode = "run",
					isRunning = RunService:IsRunning(),
					message = "StudioTestService unavailable — started in Run mode instead.",
				}
			end

		elseif action == "stop" then
			if not RunService:IsRunning() then
				return { status = "already_stopped" }
			end

			-- Try StudioTestService:EndTest first, fall back to RunService:Stop
			local stopped = false
			pcall(function()
				local StudioTestService = game:GetService("StudioTestService")
				;(StudioTestService :: any):EndTest({})
				stopped = true
			end)
			if not stopped then
				local ok, err = pcall(function()
					RunService:Stop()
				end)
				if not ok then
					error(`Failed to stop playtest: {err}`)
				end
			end

			-- Brief wait for stop to take effect
			task.wait(0.2)

			return {
				status = "stopped",
				isRunning = RunService:IsRunning(),
			}

		elseif action == "execute" then
			local code: string = params.code
			if not code then
				error("execute action requires a code parameter")
			end

			local outputLines: { { message: string, messageType: string } } = {}
			local connection: RBXScriptConnection? = nil

			-- NOTE: LogService.MessageOut is global — it may capture unrelated messages
			-- from other threads during execution. This is a known Roblox limitation.
			-- We mitigate by disconnecting immediately after pcall returns.
			connection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
				table.insert(outputLines, {
					message = message,
					messageType = messageType.Name,
				})
			end)

			local loadFn = (loadstring :: any)(code)
			if not loadFn then
				if connection then
					connection:Disconnect()
				end
				error("Failed to compile code")
			end

			local ok, result = pcall(loadFn)

			if connection then
				connection:Disconnect()
			end

			if not ok then
				return {
					status = "error",
					error = tostring(result),
					output = outputLines,
				}
			end

			return {
				status = "success",
				result = if result ~= nil then tostring(result) else nil,
				output = outputLines,
			}
		else
			error(`Unknown playtest action: {action}. Expected "start", "stop", or "execute"`)
		end
	end, false)

	-- ── virtual_input (mouse + keyboard) ─────────────────────────────
	-- ── get_log_output (console/log history) ────────────────────────
	router:register("get_log_output", function(params: { [string]: any })
		local ok, history = pcall(function()
			return LogService:GetLogHistory()
		end)
		if not ok or not history then
			error("LogService:GetLogHistory() is not available in this Studio version")
		end

		local messageTypes: { string }? = params.messageTypes
		local since: number? = params.since
		local limit: number? = params.limit

		-- Build a set of allowed message types for fast lookup
		local typeFilter: { [string]: boolean }? = nil
		if messageTypes and #messageTypes > 0 then
			typeFilter = {}
			for _, mt in messageTypes do
				(typeFilter :: any)[mt] = true
			end
		end

		-- Filter logs
		local filtered: { { message: string, messageType: string, timestamp: number } } = {}
		for _, entry in history do
			local typeName = entry.messageType.Name

			if typeFilter and not (typeFilter :: any)[typeName] then
				continue
			end

			if since and entry.timestamp < since then
				continue
			end

			table.insert(filtered, {
				message = entry.message,
				messageType = typeName,
				timestamp = entry.timestamp,
			})
		end

		-- Apply limit (take from end — most recent)
		local total = #filtered
		if limit and limit > 0 and total > limit then
			local trimmed: { { message: string, messageType: string, timestamp: number } } = {}
			for i = total - limit + 1, total do
				table.insert(trimmed, filtered[i])
			end
			filtered = trimmed
		end

		return { logs = filtered, total = total }
	end, false)

	-- ── virtual_input (mouse + keyboard) ─────────────────────────────
	router:register("virtual_input", function(params: { [string]: any })
		local action: string = params.action
		if not action then
			error("virtual_input requires an action")
		end

		if not RunService:IsRunning() then
			error("Virtual input requires an active playtest. Call playtest with action 'start' first.")
		end

		local ok, VirtualInputManager = pcall(function()
			return game:GetService("VirtualInputManager")
		end)
		if not ok or not VirtualInputManager then
			error("VirtualInputManager is not available in this context.")
		end

		local VIM: any = VirtualInputManager

		if action == "mouse_click" then
			local x: number = params.x or 0
			local y: number = params.y or 0
			local button: string = params.button or "Left"

			local buttonEnum = 0
			if button == "Right" then
				buttonEnum = 1
			elseif button == "Middle" then
				buttonEnum = 2
			end

			VIM:SendMouseButtonEvent(x, y, buttonEnum, true, game, 0)
			task.wait(0.05)
			VIM:SendMouseButtonEvent(x, y, buttonEnum, false, game, 0)

			return { status = "clicked", message = `Mouse {button} click at ({x}, {y})` }

		elseif action == "mouse_move" then
			local x: number = params.x or 0
			local y: number = params.y or 0

			VIM:SendMouseMoveEvent(x, y, game)

			return { status = "moved", message = `Mouse moved to ({x}, {y})` }

		elseif action == "key_press" then
			local key: string = params.key
			if not key then
				error("key_press requires a key parameter")
			end

			local keyCode = (Enum.KeyCode :: any)[key]
			if not keyCode then
				error(`Unknown key: {key}. Must match Enum.KeyCode name (e.g. 'W', 'Space', 'Return')`)
			end

			VIM:SendKeyEvent(true, keyCode, false, game)
			task.wait(0.05)
			VIM:SendKeyEvent(false, keyCode, false, game)

			return { status = "pressed", message = `Key '{key}' pressed` }

		elseif action == "key_down" then
			local key: string = params.key
			if not key then
				error("key_down requires a key parameter")
			end

			local keyCode = (Enum.KeyCode :: any)[key]
			if not keyCode then
				error(`Unknown key: {key}`)
			end

			VIM:SendKeyEvent(true, keyCode, false, game)

			return { status = "down", message = `Key '{key}' held down` }

		elseif action == "key_up" then
			local key: string = params.key
			if not key then
				error("key_up requires a key parameter")
			end

			local keyCode = (Enum.KeyCode :: any)[key]
			if not keyCode then
				error(`Unknown key: {key}`)
			end

			VIM:SendKeyEvent(false, keyCode, false, game)

			return { status = "up", message = `Key '{key}' released` }
		else
			error(`Unknown virtual_input action: {action}`)
		end
	end, false) -- Not mutating (simulates user input, doesn't change DataModel)

	-- ── playtest_inspect (runtime expression evaluation) ─────────────
	-- NOTE: This runs in the plugin (server/edit) context, not the client.
	-- It can evaluate expressions that access game.Workspace, ServerStorage, etc.
	-- For client-specific state (LocalPlayer, PlayerGui), use the execute action instead.
	router:register("playtest_inspect", function(params: { [string]: any })
		local expression: string = params.expression
		if not expression then
			error("playtest_inspect requires an expression parameter")
		end

		-- Try evaluating as an expression first, then as a statement
		local loadFn = (loadstring :: any)("return " .. expression)
		if not loadFn then
			loadFn = (loadstring :: any)(expression)
		end
		if not loadFn then
			error(`Failed to compile expression: {expression}`)
		end

		local ok, result = pcall(loadFn)
		if not ok then
			error(`Expression error: {tostring(result)}`)
		end

		-- Serialize the result based on type
		local resultType = typeof(result)
		local serialized: any

		if result == nil then
			serialized = "nil"
		elseif resultType == "string" or resultType == "number" or resultType == "boolean" then
			serialized = result
		elseif resultType == "Instance" then
			local Serializer = require(script.Parent.Parent.Serializer)
			serialized = {
				path = Serializer.getPath(result),
				className = result.ClassName,
				name = result.Name,
			}
		elseif resultType == "Vector3" then
			serialized = { Type = "Vector3", X = result.X, Y = result.Y, Z = result.Z }
		elseif resultType == "Vector2" then
			serialized = { Type = "Vector2", X = result.X, Y = result.Y }
		elseif resultType == "CFrame" then
			local pos = result.Position
			local rx, ry, rz = result:ToEulerAnglesYXZ()
			serialized = {
				Type = "CFrame",
				Position = { X = pos.X, Y = pos.Y, Z = pos.Z },
				Orientation = { X = math.deg(rx), Y = math.deg(ry), Z = math.deg(rz) },
			}
		elseif resultType == "Color3" then
			serialized = { Type = "Color3", R = math.round(result.R * 255), G = math.round(result.G * 255), B = math.round(result.B * 255) }
		elseif resultType == "EnumItem" then
			serialized = tostring(result)
		elseif resultType == "table" then
			-- Shallow serialize tables
			local t: { [string]: any } = {}
			for k, v in result do
				t[tostring(k)] = tostring(v)
			end
			serialized = t
		else
			serialized = tostring(result)
		end

		return {
			value = serialized,
			type = resultType,
			expression = expression,
		}
	end, false)

	-- ── playtest_navigate (pathfinding navigation) ──────────────────
	-- NOTE: This runs in the plugin context. During play mode, the plugin can
	-- access Players and characters through the server-side DataModel.
	router:register("playtest_navigate", function(params: { [string]: any })
		if not RunService:IsRunning() then
			error("navigate requires an active playtest. Call playtest with action 'start' first.")
		end

		-- Find the first player's character from the server-side Players service
		local Players = game:GetService("Players")
		local player = nil
		for _, p in Players:GetPlayers() do
			player = p
			break
		end
		if not player then
			error("No players found — ensure playtest is running in Play mode (not Run mode)")
		end

		local character = player.Character
		if not character then
			-- Wait briefly for character to spawn
			local waitStart = os.clock()
			while os.clock() - waitStart < 5 do
				character = player.Character
				if character then break end
				task.wait(0.2)
			end
			if not character then
				error("Player has no character — character may not have spawned yet")
			end
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			error("Character has no Humanoid")
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			error("Character has no HumanoidRootPart")
		end

		-- Resolve target position
		local targetPos: Vector3
		if params.targetPath then
			local Serializer = require(script.Parent.Parent.Serializer)
			local targetInstance, resolveErr = Serializer.resolvePathOrError(params.targetPath)
			if not targetInstance then
				error(resolveErr)
			end
			local ok, pos = pcall(function()
				return (targetInstance :: any).Position
			end)
			if not ok then
				-- Try PrimaryPart for models
				local primary = (targetInstance :: any).PrimaryPart
				if primary then
					pos = primary.Position
				else
					error(`Target instance at {params.targetPath} has no Position property`)
				end
			end
			targetPos = pos
		elseif params.target then
			targetPos = Vector3.new(params.target.x, params.target.y, params.target.z)
		else
			error("navigate requires either target or targetPath")
		end

		local timeout: number = params.timeout or 15
		local startTime = tick()

		-- Try pathfinding first
		local PathfindingService = game:GetService("PathfindingService")
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
		})

		local pathOk, pathErr = pcall(function()
			path:ComputeAsync(rootPart.Position, targetPos)
		end)

		if pathOk and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()

			for _, waypoint in waypoints do
				if tick() - startTime > timeout then
					local finalPos = rootPart.Position
					return {
						status = "timeout",
						position = { x = finalPos.X, y = finalPos.Y, z = finalPos.Z },
						message = "Navigation timed out before reaching destination",
					}
				end

				local moveFinished = false
				local moveConn = humanoid.MoveToFinished:Connect(function(_reached: boolean)
					moveFinished = true
				end)

				humanoid:MoveTo(waypoint.Position)

				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end

				while not moveFinished and (tick() - startTime) < timeout do
					task.wait(0.1)
				end
				moveConn:Disconnect()

				if not moveFinished then
					local finalPos = rootPart.Position
					return {
						status = "timeout",
						position = { x = finalPos.X, y = finalPos.Y, z = finalPos.Z },
						message = "Navigation timed out before reaching destination",
					}
				end
			end

			local finalPos = rootPart.Position
			return {
				status = "arrived",
				position = { x = finalPos.X, y = finalPos.Y, z = finalPos.Z },
			}
		else
			-- Fallback: direct MoveTo
			humanoid:MoveTo(targetPos)

			local arrived = false
			local conn: RBXScriptConnection? = nil
			conn = humanoid.MoveToFinished:Connect(function(_reached: boolean)
				arrived = true
				if conn then
					conn:Disconnect()
				end
			end)

			while not arrived and (tick() - startTime) < timeout do
				task.wait(0.1)
			end

			if conn then
				(conn :: any):Disconnect()
			end

			local finalPos = rootPart.Position
			return {
				status = if arrived then "arrived" else "timeout",
				position = { x = finalPos.X, y = finalPos.Y, z = finalPos.Z },
				message = if not pathOk then `Pathfinding failed ({tostring(pathErr)}), used direct movement` else "Path not found, used direct movement",
			}
		end
	end, false) -- Not mutating
end

return { register = register }
