--!strict
local Serializer = require(script.Parent.Parent.Serializer)

local function register(router: any)
	-- ── create_instances ─────────────────────────────────────────────
	router:register("create_instances", function(params: { [string]: any })
		local operations = params.operations
		if not operations or #operations == 0 then
			error("create_instances requires a non-empty operations array")
		end

		local results: { { path: string, className: string, name: string } } = {}

		for i, op in operations do
			local className: string = op.className
			local parentPath: string = op.parent
			local name: string? = op.name
			local properties: { [string]: any }? = op.properties

			if not className then
				error(`Operation {i}: className is required`)
			end
			if not parentPath then
				error(`Operation {i}: parent is required`)
			end

			local parent = Serializer.resolvePath(parentPath)
			if not parent then
				error(`Operation {i}: could not resolve parent path: {parentPath}`)
			end

			local instance = Instance.new(className)

			if name then
				instance.Name = name
			end

			if properties then
				Serializer.applyProperties(instance, properties)
			end

			instance.Parent = parent

			table.insert(results, {
				path = Serializer.getPath(instance),
				className = instance.ClassName,
				name = instance.Name,
			})
		end

		return { created = results }
	end, true)

	-- ── modify_instances ─────────────────────────────────────────────
	router:register("modify_instances", function(params: { [string]: any })
		local operations = params.operations
		if not operations or #operations == 0 then
			error("modify_instances requires a non-empty operations array")
		end

		local results: { { path: string, modified: { string } } } = {}

		for i, op in operations do
			local path: string = op.path
			if not path then
				error(`Operation {i}: path is required`)
			end

			local instance = Serializer.resolvePath(path)
			if not instance then
				error(`Operation {i}: could not resolve path: {path}`)
			end

			local modified: { string } = {}

			if op.name then
				instance.Name = op.name
				table.insert(modified, "name")
			end

			if op.properties then
				Serializer.applyProperties(instance, op.properties)
				table.insert(modified, "properties")
			end

			if op.attributes then
				for attrName, attrValue in op.attributes do
					instance:SetAttribute(attrName, Serializer.deserialize(attrValue))
				end
				table.insert(modified, "attributes")
			end

			if op.tags then
				local tags = op.tags
				if tags.add then
					for _, tag in tags.add do
						instance:AddTag(tag)
					end
				end
				if tags.remove then
					for _, tag in tags.remove do
						instance:RemoveTag(tag)
					end
				end
				table.insert(modified, "tags")
			end

			if op.parent then
				local newParent = Serializer.resolvePath(op.parent)
				if not newParent then
					error(`Operation {i}: could not resolve new parent path: {op.parent}`)
				end
				instance.Parent = newParent
				table.insert(modified, "parent")
			end

			table.insert(results, {
				path = Serializer.getPath(instance),
				modified = modified,
			})
		end

		return { modified = results }
	end, true)

	-- ── delete_instances ─────────────────────────────────────────────
	router:register("delete_instances", function(params: { [string]: any })
		local paths = params.paths
		if not paths or #paths == 0 then
			error("delete_instances requires a non-empty paths array")
		end

		local deleted: { string } = {}

		for _, path in paths do
			local instance = Serializer.resolvePath(path)
			if not instance then
				error(`Could not resolve path: {path}`)
			end
			instance:Destroy()
			table.insert(deleted, path)
		end

		return { deleted = deleted }
	end, true)

	-- ── clone_instances ──────────────────────────────────────────────
	router:register("clone_instances", function(params: { [string]: any })
		local sources = params.sources
		local targetParentPath: string = params.targetParent

		if not sources or #sources == 0 then
			error("clone_instances requires a non-empty sources array")
		end
		if not targetParentPath then
			error("clone_instances requires a targetParent")
		end

		local targetParent = Serializer.resolvePath(targetParentPath)
		if not targetParent then
			error(`Could not resolve target parent path: {targetParentPath}`)
		end

		local cloned: { { path: string, className: string, name: string } } = {}

		for _, sourcePath in sources do
			local source = Serializer.resolvePath(sourcePath)
			if not source then
				error(`Could not resolve source path: {sourcePath}`)
			end

			local clone = source:Clone()
			if not clone then
				error(`Failed to clone instance at: {sourcePath}`)
			end
			clone.Parent = targetParent

			table.insert(cloned, {
				path = Serializer.getPath(clone),
				className = clone.ClassName,
				name = clone.Name,
			})
		end

		return { cloned = cloned }
	end, true)

	-- ── query_instances ──────────────────────────────────────────────
	router:register("query_instances", function(params: { [string]: any })
		local basePath: string = params.basePath or "game"
		local filters = params.filters or {}
		local limit: number = params.limit or 50

		local root = Serializer.resolvePath(basePath)
		if not root then
			error(`Could not resolve base path: {basePath}`)
		end

		local filterClassName: string? = filters.className
		local filterTag: string? = filters.tag
		local filterAttribute = filters.attribute
		local filterNamePattern: string? = filters.namePattern

		local results: { { path: string, className: string, name: string } } = {}
		local total = 0

		for _, descendant in root:GetDescendants() do
			local matches = true

			if filterClassName and descendant.ClassName ~= filterClassName then
				matches = false
			end

			if matches and filterTag and not descendant:HasTag(filterTag) then
				matches = false
			end

			if matches and filterAttribute then
				local attrName: string = filterAttribute.name
				local attrVal = descendant:GetAttribute(attrName)
				if attrVal == nil then
					matches = false
				elseif filterAttribute.value ~= nil and attrVal ~= filterAttribute.value then
					matches = false
				end
			end

			if matches and filterNamePattern then
				-- pcall in case the user-supplied pattern is invalid Lua pattern syntax
				local patternOk, patternMatch = pcall(string.match, descendant.Name, filterNamePattern)
				if not patternOk then
					-- Fall back to plain string.find if the pattern is invalid
					if not string.find(descendant.Name, filterNamePattern, 1, true) then
						matches = false
					end
				elseif not patternMatch then
					matches = false
				end
			end

			if matches then
				total += 1
				if #results < limit then
					table.insert(results, {
						path = Serializer.getPath(descendant),
						className = descendant.ClassName,
						name = descendant.Name,
					})
				end
			end
		end

		return { results = results, total = total }
	end, false)

	-- ── batch_modify (with strict mode) ──────────────────────────────
	router:register("batch_modify", function(params: { [string]: any })
		local paths = params.paths
		local property: string = params.property
		local rawValue = params.value
		local strict: boolean = if params.strict then true else false

		if not paths or #paths == 0 then
			error("batch_modify requires a non-empty paths array")
		end
		if not property then
			error("batch_modify requires a property name")
		end

		local value = Serializer.deserialize(rawValue)
		local modified = 0
		local failed: { { path: string, error: string } } = {}

		for _, path in paths do
			local instance = Serializer.resolvePath(path)
			if not instance then
				if strict then
					error(`Could not resolve path: {path}`)
				end
				table.insert(failed, { path = path, error = "Could not resolve path" })
				continue
			end

			local ok, err = pcall(function()
				(instance :: any)[property] = value
			end)
			if ok then
				modified += 1
			else
				if strict then
					error(`Failed to set {property} on {path}: {tostring(err)}`)
				end
				table.insert(failed, { path = path, error = tostring(err) })
			end
		end

		return { modified = modified, failed = failed }
	end, true)

	-- ── grep_scripts ─────────────────────────────────────────────────
	router:register("grep_scripts", function(params: { [string]: any })
		local ScriptEditorService = game:GetService("ScriptEditorService")
		local basePath: string = params.basePath or "game"
		local pattern: string = params.pattern
		local caseSensitive: boolean = if params.caseSensitive then true else false
		local contextLines: number = params.contextLines or 1
		local limit: number = params.limit or 50

		if not pattern then
			error("grep_scripts requires a pattern")
		end

		local root = Serializer.resolvePath(basePath)
		if not root then
			error(`Could not resolve base path: {basePath}`)
		end

		local searchPattern: string = if caseSensitive then pattern else string.lower(pattern)
		local results: { { scriptPath: string, lineNumber: number, line: string, context: { string } } } = {}
		local totalMatches = 0
		local scriptsSearched = 0

		for _, descendant in root:GetDescendants() do
			if not descendant:IsA("LuaSourceContainer") then
				continue
			end

			local ok, source = pcall(function()
				return ScriptEditorService:GetEditorSource(descendant)
			end)
			if not ok or not source or source == "" then
				continue
			end

			scriptsSearched += 1
			local lines = string.split(source, "\n")
			local scriptPath = Serializer.getPath(descendant)

			for lineNum, line in lines do
				local searchLine: string = if caseSensitive then line else string.lower(line)
				if string.find(searchLine, searchPattern, 1, true) then
					totalMatches += 1
					if #results < limit then
						-- Gather context lines
						local context: { string } = {}
						for ctx = math.max(1, lineNum - contextLines), math.min(#lines, lineNum + contextLines) do
							if ctx ~= lineNum then
								table.insert(context, `{ctx}: {lines[ctx]}`)
							end
						end

						table.insert(results, {
							scriptPath = scriptPath,
							lineNumber = lineNum,
							line = line,
							context = context,
						})
					end
				end
			end

			-- Early exit if we have enough results
			if totalMatches >= limit * 2 then
				break
			end
		end

		return {
			results = results,
			totalMatches = totalMatches,
			scriptsSearched = scriptsSearched,
		}
	end, false)
end

return { register = register }
