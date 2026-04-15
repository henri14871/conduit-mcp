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

		local instance, resolveErr = Serializer.resolvePathOrError(path)
		if not instance then
			error(resolveErr)
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

	-- ── outline_script (function signatures + structure) ────────────
	router:register("outline_script", function(params: { [string]: any })
		local path: string = params.path
		if not path then
			error("outline_script requires a path")
		end

		local instance, resolveErr = Serializer.resolvePathOrError(path)
		if not instance then
			error(resolveErr)
		end

		if not instance:IsA("LuaSourceContainer") then
			error(`Instance at {path} is not a script (got {instance.ClassName})`)
		end

		local source = ScriptEditorService:GetEditorSource(instance)
		local lines = source:split("\n")
		local entries: { { line: number, text: string, kind: string, indent: number } } = {}

		for lineNum, lineText in lines do
			local stripped = lineText:match("^%s*(.-)%s*$") or ""
			local indentStr = lineText:match("^(%s*)") or ""
			local indent = #indentStr

			-- function Name(...) or function Module.Name(...) or function Module:Name(...)
			if stripped:match("^function%s+[%w_%.%:]+%s*%(") then
				local sig = stripped:match("^(function%s+[%w_%.%:]+%s*%([^%)]*%))")
				table.insert(entries, {
					line = lineNum,
					text = sig or stripped,
					kind = "function",
					indent = indent,
				})
			-- local function Name(...)
			elseif stripped:match("^local%s+function%s+[%w_]+%s*%(") then
				local sig = stripped:match("^(local%s+function%s+[%w_]+%s*%([^%)]*%))")
				table.insert(entries, {
					line = lineNum,
					text = sig or stripped,
					kind = "local_function",
					indent = indent,
				})
			-- Module.Name = function(...) or self.Name = function(...)
			elseif stripped:match("^[%w_%.%:]+%s*=%s*function%s*%(") then
				local sig = stripped:match("^([%w_%.%:]+%s*=%s*function%s*%([^%)]*%))")
				table.insert(entries, {
					line = lineNum,
					text = sig or stripped,
					kind = "assigned_function",
					indent = indent,
				})
			-- Top-level local declarations (indent 0 only, skip function-level locals)
			elseif indent == 0 and stripped:match("^local%s+[%w_]+") and not stripped:match("^local%s+function") then
				local decl = stripped:match("^(local%s+[%w_]+)")
				table.insert(entries, {
					line = lineNum,
					text = decl or stripped,
					kind = "local",
					indent = indent,
				})
			-- return statement at indent 0 (module return)
			elseif indent == 0 and stripped:match("^return%s") then
				table.insert(entries, {
					line = lineNum,
					text = stripped,
					kind = "return",
					indent = indent,
				})
			-- Type definitions
			elseif stripped:match("^export%s+type%s+") or stripped:match("^type%s+[%w_]+") then
				local decl = stripped:match("^(export%s+type%s+[%w_]+)") or stripped:match("^(type%s+[%w_]+)")
				table.insert(entries, {
					line = lineNum,
					text = decl or stripped,
					kind = "type",
					indent = indent,
				})
			end
		end

		return {
			path = path,
			totalLines = #lines,
			outline = entries,
		}
	end, false)

	-- ── batch_read_scripts (multiple scripts in one call) ────────
	router:register("batch_read_scripts", function(params: { [string]: any })
		local scripts = params.scripts
		if not scripts or #scripts == 0 then
			error("batch_read_scripts requires a non-empty scripts array")
		end

		local results: { { [string]: any } } = {}
		local errors: { { path: string, error: string } } = {}

		for _, entry in scripts do
			local path: string = entry.path
			local ok, res = pcall(function()
				if not path then
					error("Each entry requires a path")
				end

				local instance, resolveErr = Serializer.resolvePathOrError(path)
				if not instance then
					error(resolveErr)
				end
				if not instance:IsA("LuaSourceContainer") then
					error(`Instance at {path} is not a script (got {instance.ClassName})`)
				end

				local source = ScriptEditorService:GetEditorSource(instance)
				local lines = source:split("\n")

				-- Outline mode
				if entry.outline then
					local entries: { { line: number, text: string, kind: string, indent: number } } = {}
					for lineNum, lineText in lines do
						local stripped = lineText:match("^%s*(.-)%s*$") or ""
						local indentStr = lineText:match("^(%s*)") or ""
						local indent = #indentStr

						if stripped:match("^function%s+[%w_%.%:]+%s*%(") then
							local sig = stripped:match("^(function%s+[%w_%.%:]+%s*%([^%)]*%))")
							table.insert(entries, { line = lineNum, text = sig or stripped, kind = "function", indent = indent })
						elseif stripped:match("^local%s+function%s+[%w_]+%s*%(") then
							local sig = stripped:match("^(local%s+function%s+[%w_]+%s*%([^%)]*%))")
							table.insert(entries, { line = lineNum, text = sig or stripped, kind = "local_function", indent = indent })
						elseif stripped:match("^[%w_%.%:]+%s*=%s*function%s*%(") then
							local sig = stripped:match("^([%w_%.%:]+%s*=%s*function%s*%([^%)]*%))")
							table.insert(entries, { line = lineNum, text = sig or stripped, kind = "assigned_function", indent = indent })
						elseif indent == 0 and stripped:match("^local%s+[%w_]+") and not stripped:match("^local%s+function") then
							local decl = stripped:match("^(local%s+[%w_]+)")
							table.insert(entries, { line = lineNum, text = decl or stripped, kind = "local", indent = indent })
						elseif indent == 0 and stripped:match("^return%s") then
							table.insert(entries, { line = lineNum, text = stripped, kind = "return", indent = indent })
						elseif stripped:match("^export%s+type%s+") or stripped:match("^type%s+[%w_]+") then
							local decl = stripped:match("^(export%s+type%s+[%w_]+)") or stripped:match("^(type%s+[%w_]+)")
							table.insert(entries, { line = lineNum, text = decl or stripped, kind = "type", indent = indent })
						end
					end
					return { path = path, totalLines = #lines, outline = entries }
				end

				-- Line range mode
				local lineRange = entry.lineRange
				if lineRange then
					local startLine: number = lineRange.start or 1
					local endLine: number = lineRange["end"] or #lines
					endLine = math.min(endLine, #lines)
					return {
						path = path,
						source = extractLineRange(source, startLine, endLine),
						lineRange = { start = startLine, ["end"] = endLine },
						totalLines = #lines,
					}
				end

				-- Full source
				return { path = path, source = source, totalLines = #lines }
			end)

			if ok then
				table.insert(results, res)
			else
				table.insert(errors, { path = path or "unknown", error = tostring(res) })
			end
		end

		return {
			results = results,
			errors = if #errors > 0 then errors else nil,
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

		local instance, resolveErr = Serializer.resolvePathOrError(path)
		if not instance then
			error(resolveErr)
		end

		if not instance:IsA("LuaSourceContainer") then
			error(`Instance at {path} is not a script (got {instance.ClassName})`)
		end

		-- Snapshot pre-edit source so transaction rollback can restore it.
		-- ScriptEditorService edits aren't captured by ChangeHistoryService recordings.
		router:captureScriptBackup(path, instance)

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
				local text: string = edit.text or ""

				local ok, err = pcall(function()
					ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
						local lines = oldSource:split("\n")

						-- Default endColumn to end of the endLine (replace full lines)
						local endCol: number = edit.endColumn or (#lines[endLine] + 1)

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
			-- Escape % in replacement string for literal mode (gsub treats % as special in replacements)
			local safeReplace = replaceWith:gsub("%%", "%%%%")

			ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
				local newSource: string
				if useRegex then
					newSource = oldSource:gsub(findPattern, replaceWith)
				else
					-- Escape pattern special characters for literal matching
					local escaped = findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
					newSource = oldSource:gsub(escaped, safeReplace)

					-- If no match found, retry with flexible whitespace matching:
					-- Normalize both the find pattern and source to handle tab/space mismatches.
					-- AI models often convert tabs to spaces when crafting find text.
					if newSource == oldSource then
						-- Build a pattern that treats runs of whitespace as interchangeable
						local flexEscaped = findPattern
							:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") -- escape specials first
							:gsub("%s+", "%%s+") -- any whitespace run matches any whitespace

						local flexSource = oldSource:gsub(flexEscaped, safeReplace)
						if flexSource ~= oldSource then
							newSource = flexSource
						end
					end
				end

				-- Count replacements by comparing
				if newSource ~= oldSource then
					-- Rough count: split on pattern and count
					local _, count = oldSource:gsub(
						if useRegex then findPattern else findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"),
						""
					)
					replacements = count
					-- If exact match didn't work but flex did, recount with flex pattern
					if replacements == 0 then
						local flexEscaped = findPattern
							:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
							:gsub("%s+", "%%s+")
						local _, flexCount = oldSource:gsub(flexEscaped, "")
						replacements = flexCount
					end
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
				local instance, resolveErr = Serializer.resolvePathOrError(path)
				if not instance then
					error(resolveErr)
				end
				if not instance:IsA("LuaSourceContainer") then
					error(`Instance at {path} is not a script (got {instance.ClassName})`)
				end

				router:captureScriptBackup(path, instance)

				local replacements = 0
				-- Escape % in replacement string for literal mode (gsub treats % as special in replacements)
				local safeReplace = replaceWith:gsub("%%", "%%%%")

				ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
					local newSource: string
					if useRegex then
						newSource = oldSource:gsub(findPattern, replaceWith)
					else
						local escaped = findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
						newSource = oldSource:gsub(escaped, safeReplace)
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

	-- ── batch_edit_scripts (different edits per script) ─────────────
	-- Each edit can be either:
	--   { path, source }           → full source replacement
	--   { path, find, replace }    → find/replace
	router:register("batch_edit_scripts", function(params: { [string]: any })
		local edits = params.edits
		if not edits or #edits == 0 then
			error("batch_edit_scripts requires a non-empty edits array")
		end

		local results: { { path: string, success: boolean, mode: string, replacements: number? } } = {}
		local errors: { { path: string, error: string } } = {}
		local scriptsModified = 0

		for _, edit in edits do
			local path: string = edit.path

			local ok, err = pcall(function()
				if not path then
					error("Each edit requires a path")
				end

				local instance, resolveErr = Serializer.resolvePathOrError(path)
				if not instance then
					error(resolveErr)
				end
				if not instance:IsA("LuaSourceContainer") then
					error(`Instance at {path} is not a script (got {instance.ClassName})`)
				end

				router:captureScriptBackup(path, instance)

				-- Full source replacement mode
				if edit.source ~= nil then
					local newSource: string = edit.source
					ScriptEditorService:UpdateSourceAsync(instance, function(_oldSource: string)
						return newSource
					end)
					table.insert(results, {
						path = path,
						success = true,
						mode = "full",
					})
					scriptsModified += 1
					return
				end

				-- Find/replace mode
				local findPattern: string = edit.find
				if not findPattern then
					error("Each edit requires either a 'source' or 'find' parameter")
				end

				local replaceWith: string = edit.replace or ""
				local useRegex: boolean = if edit.regex then true else false
				local replacements = 0
				local safeReplace = replaceWith:gsub("%%", "%%%%")

				ScriptEditorService:UpdateSourceAsync(instance, function(oldSource: string)
					local newSource: string
					if useRegex then
						newSource = oldSource:gsub(findPattern, replaceWith)
					else
						local escaped = findPattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
						newSource = oldSource:gsub(escaped, safeReplace)
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

				table.insert(results, { path = path, success = true, mode = "find_replace", replacements = replacements })
				if replacements > 0 then
					scriptsModified += 1
				end
			end)

			if not ok then
				table.insert(results, { path = path, success = false, mode = "error" })
				table.insert(errors, { path = path, error = tostring(err) })
			end
		end

		return {
			results = results,
			scriptsModified = scriptsModified,
			errors = if #errors > 0 then errors else nil,
		}
	end, true)

	router:register("execute_lua", function(params: { [string]: any })
		local code: string = params.code
		if not code then
			error("execute_lua requires a code parameter")
		end

		-- Watchdog timeout (default 10s, capped at 30s). Anything longer risks freezing
		-- Studio because Luau is cooperative — code that never yields can't be preempted.
		local timeout: number = math.clamp(tonumber(params.timeout) or 10, 1, 30)

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

		local done = false
		local userOk: boolean = false
		local userResult: any = nil
		local workerThread: thread? = nil

		workerThread = task.spawn(function()
			userOk, userResult = pcall(loadFn)
			done = true
		end)

		local deadline = os.clock() + timeout
		while not done and os.clock() < deadline do
			task.wait(0.05)
		end

		if not done then
			-- Only cancels at the next yield point — a true CPU-bound loop will still
			-- hold the scheduler, but at least the router won't wait on it forever.
			if workerThread then
				pcall(task.cancel, workerThread)
			end
			if connection then
				connection:Disconnect()
			end
			return {
				status = "timeout",
				error = `execute_lua exceeded {timeout}s timeout; worker thread cancelled`,
				output = outputLines,
				timeoutSeconds = timeout,
			}
		end

		if connection then
			connection:Disconnect()
		end

		if not userOk then
			return {
				status = "error",
				error = tostring(userResult),
				output = outputLines,
			}
		end

		return {
			status = "success",
			result = if userResult ~= nil then tostring(userResult) else nil,
			output = outputLines,
		}
	end, true)
end

return { register = register }
