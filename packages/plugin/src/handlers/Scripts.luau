--!strict
local Serializer = require(script.Parent.Parent.Serializer)
local ScriptEditorService = game:GetService("ScriptEditorService")

local function extractLineRange(source: string, startLine: number, endLine: number): string
	local lines = source:split("\n")
	local startIdx = math.max(1, startLine)
	local endIdx = math.min(#lines, endLine)

	local extracted: { string } = {}
	for i = startIdx, endIdx do
		table.insert(extracted, lines[i])
	end

	return table.concat(extracted, "\n")
end

local function register(router: any)
	router:register("read_script", function(params: { [string]: any })
		local path: string = params.path
		if not path then
			error("read_script requires a path")
		end

		local instance = Serializer.resolvePath(path)
		if not instance then
			error(`Could not resolve path: {path}`)
		end

		if not instance:IsA("LuaSourceContainer") then
			error(`Instance at {path} is not a script (got {instance.ClassName})`)
		end

		local source = ScriptEditorService:GetEditorSource(instance)

		local lineRange = params.lineRange
		if lineRange then
			local startLine: number = lineRange.start or 1
			local endLine: number = lineRange["end"] or math.huge
			local totalLines = #source:split("\n")
			endLine = math.min(endLine, totalLines)

			return {
				path = path,
				source = extractLineRange(source, startLine, endLine),
				lineRange = { start = startLine, ["end"] = endLine },
				totalLines = totalLines,
			}
		end

		return {
			path = path,
			source = source,
			totalLines = #source:split("\n"),
		}
	end, false)

	router:register("edit_script", function(params: { [string]: any })
		local path: string = params.path
		local mode: string = params.mode

		if not path then
			error("edit_script requires a path")
		end
		if not mode then
			error("edit_script requires a mode (full, range, or find_replace)")
		end

		local instance = Serializer.resolvePath(path)
		if not instance then
			error(`Could not resolve path: {path}`)
		end

		if not instance:IsA("LuaSourceContainer") then
			error(`Instance at {path} is not a script (got {instance.ClassName})`)
		end

		if mode == "full" then
			local source: string = params.source
			if not source then
				error("full mode requires a source parameter")
			end

			ScriptEditorService:UpdateSourceAsync(instance, function(_oldSource: string)
				return source
			end)

			return {
				path = path,
				mode = "full",
				success = true,
				totalLines = #source:split("\n"),
			}

		elseif mode == "range" then
			local edits = params.edits
			if not edits or #edits == 0 then
				error("range mode requires a non-empty edits array")
			end

			-- Try EditTextAsync for range-based editing
			-- Each edit has startLine, startColumn, endLine, endColumn, text
			local appliedEdits = 0

			-- Sort edits in reverse order so line numbers remain valid
			table.sort(edits, function(a, b)
				if a.startLine == b.startLine then
					return a.startColumn > b.startColumn
				end
				return a.startLine > b.startLine
			end)

			for _, edit in edits do
				local startLine: number = edit.startLine
				local startCol: number = edit.startColumn or 1
				local endLine: number = edit.endLine
				local endCol: number = edit.endColumn or 1
				local text: string = edit.text or ""

				local ok, err = pcall(function()
					ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
						local lines = oldSource:split("\n")

						-- Convert line/column to character offset
						local startOffset = 0
						for i = 1, startLine - 1 do
							startOffset += #lines[i] + 1 -- +1 for newline
						end
						startOffset += startCol - 1

						local endOffset = 0
						for i = 1, endLine - 1 do
							endOffset += #lines[i] + 1
						end
						endOffset += endCol - 1

						local before = oldSource:sub(1, startOffset)
						local after = oldSource:sub(endOffset + 1)

						return before .. text .. after
					end)
				end)

				if not ok then
					error(`Failed to apply range edit: {err}`)
				end

				appliedEdits += 1
			end

			local updatedSource = ScriptEditorService:GetEditorSource(instance)
			return {
				path = path,
				mode = "range",
				success = true,
				appliedEdits = appliedEdits,
				totalLines = #updatedSource:split("\n"),
			}

		elseif mode == "find_replace" then
			local findPattern: string = params.find
			local replaceWith: string = params.replace
			local useRegex: boolean = if params.regex then true else false

			if not findPattern then
				error("find_replace mode requires a find parameter")
			end
			if replaceWith == nil then
				error("find_replace mode requires a replace parameter")
			end

			local replacements = 0

			ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
				local newSource: string
				if useRegex then
					newSource = oldSource:gsub(findPattern, replaceWith)
				else
					-- Escape pattern special characters for literal matching
					local escaped = findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
					newSource = oldSource:gsub(escaped, replaceWith)
				end

				-- Count replacements by comparing
				if newSource ~= oldSource then
					-- Rough count: split on pattern and count
					local _, count = oldSource:gsub(
						if useRegex then findPattern else findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"),
						""
					)
					replacements = count
				end

				return newSource
			end)

			local updatedSource = ScriptEditorService:GetEditorSource(instance)
			return {
				path = path,
				mode = "find_replace",
				success = true,
				replacements = replacements,
				totalLines = #updatedSource:split("\n"),
			}
		else
			error(`Unknown edit mode: {mode}. Expected "full", "range", or "find_replace"`)
		end
	end, true)

	-- ── multi_replace_scripts (cross-script find/replace) ───────────
	router:register("multi_replace_scripts", function(params: { [string]: any })
		local scripts = params.scripts
		local findPattern: string = params.find
		local replaceWith: string = params.replace
		local useRegex: boolean = if params.regex then true else false

		if not scripts or #scripts == 0 then
			error("multi_replace_scripts requires a non-empty scripts array")
		end
		if not findPattern then
			error("multi_replace_scripts requires a find parameter")
		end
		if replaceWith == nil then
			error("multi_replace_scripts requires a replace parameter")
		end

		local results: { { path: string, replacements: number } } = {}
		local errors: { { path: string, error: string } } = {}
		local totalReplacements = 0
		local scriptsModified = 0

		for _, path in scripts do
			local ok, err = pcall(function()
				local instance = Serializer.resolvePath(path)
				if not instance then
					error(`Could not resolve path: {path}`)
				end
				if not instance:IsA("LuaSourceContainer") then
					error(`Instance at {path} is not a script (got {instance.ClassName})`)
				end

				local replacements = 0

				ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
					local newSource: string
					if useRegex then
						newSource = oldSource:gsub(findPattern, replaceWith)
					else
						local escaped = findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
						newSource = oldSource:gsub(escaped, replaceWith)
					end

					if newSource ~= oldSource then
						local _, count = oldSource:gsub(
							if useRegex then findPattern else findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"),
							""
						)
						replacements = count
					end

					return newSource
				end)

				table.insert(results, { path = path, replacements = replacements })
				totalReplacements += replacements
				if replacements > 0 then
					scriptsModified += 1
				end
			end)

			if not ok then
				table.insert(errors, { path = path, error = tostring(err) })
			end
		end

		return {
			results = results,
			totalReplacements = totalReplacements,
			scriptsModified = scriptsModified,
			errors = if #errors > 0 then errors else nil,
		}
	end, true)

	router:register("execute_lua", function(params: { [string]: any })
		local code: string = params.code
		if not code then
			error("execute_lua requires a code parameter")
		end

		-- Capture output during execution
		-- NOTE: LogService.MessageOut is global — it may capture unrelated messages
		-- from other threads during execution. This is a known Roblox limitation.
		-- We mitigate by disconnecting immediately after pcall returns.
		local LogService = game:GetService("LogService")
		local outputLines: { { message: string, messageType: string } } = {}
		local connection: RBXScriptConnection? = nil

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
			error("Failed to compile Luau code")
		end

		local ok, result = pcall(loadFn)

		-- Disconnect log capture
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
	end, true)
end

return { register = register }
