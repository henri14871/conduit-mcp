--!strict

local HttpService = game:GetService("HttpService")

local Serializer = {}

-- ── Path resolution ──────────────────────────────────────────────

local function parsePathSegments(pathStr: string): { string }
	-- Parse path segments supporting both dot notation and bracket notation:
	--   game.Workspace.Part
	--   game.ServerScriptService["Lighting Server"]
	--   game["Workspace"]["My Part"]
	local segments: { string } = {}
	local pos = 1
	local len = #pathStr

	while pos <= len do
		if pathStr:sub(pos, pos) == "[" then
			-- Bracket notation: ["name"] or ['name']
			local quote = pathStr:sub(pos + 1, pos + 1)
			if quote == '"' or quote == "'" then
				local closePos = pathStr:find(quote .. "]", pos + 2, true)
				if closePos then
					table.insert(segments, pathStr:sub(pos + 2, closePos - 1))
					pos = closePos + 2
					-- Skip trailing dot if present
					if pos <= len and pathStr:sub(pos, pos) == "." then
						pos = pos + 1
					end
				else
					-- Malformed bracket, treat rest as one segment
					table.insert(segments, pathStr:sub(pos))
					break
				end
			else
				-- Bracket without quotes, treat as dot segment
				table.insert(segments, pathStr:sub(pos))
				break
			end
		else
			-- Dot notation: read until next "." or "["
			local nextDot = pathStr:find(".", pos, true)
			local nextBracket = pathStr:find("[", pos, true)
			local segEnd: number

			if nextDot and nextBracket then
				segEnd = math.min(nextDot, nextBracket) - 1
			elseif nextDot then
				segEnd = nextDot - 1
			elseif nextBracket then
				segEnd = nextBracket - 1
			else
				segEnd = len
			end

			local seg = pathStr:sub(pos, segEnd)
			if seg ~= "" then
				table.insert(segments, seg)
			end

			pos = segEnd + 1
			if pos <= len and pathStr:sub(pos, pos) == "." then
				pos = pos + 1
			end
		end
	end

	return segments
end

function Serializer.resolvePath(pathStr: string): Instance?
	local segments = parsePathSegments(pathStr)
	local current: Instance = game

	local startIdx = 1
	if segments[1] == "game" then
		startIdx = 2
	end

	for i = startIdx, #segments do
		local child = current:FindFirstChild(segments[i])
		if not child then
			return nil
		end
		current = child
	end

	return current
end

function Serializer.resolvePathOrError(pathStr: string): (Instance?, string?)
	local segments = parsePathSegments(pathStr)
	local current: Instance = game

	local startIdx = 1
	if segments[1] == "game" then
		startIdx = 2
	end

	for i = startIdx, #segments do
		local segName = segments[i]
		local child = current:FindFirstChild(segName)
		if not child then
			-- Build the resolved-so-far path
			local resolvedPath = Serializer.getPath(current)

			-- Check for duplicate-named siblings at previous step
			local dupeHint = ""
			if i > startIdx then
				local parentName = segments[i - 1]
				local grandparent = current.Parent
				if grandparent then
					local dupeCount = 0
					for _, sibling in grandparent:GetChildren() do
						if sibling.Name == parentName then
							dupeCount += 1
						end
					end
					if dupeCount > 1 then
						dupeHint = ` (note: {dupeCount} instances named "{parentName}" exist under {Serializer.getPath(grandparent)}, resolved to the first one)`
					end
				end
			end

			-- List children of the last resolved instance
			local children = current:GetChildren()
			if #children == 0 then
				return nil, `Could not resolve path: {pathStr}. "{segName}" not found under {resolvedPath} (has no children){dupeHint}`
			end

			local childNames = {}
			local limit = math.min(#children, 10)
			for j = 1, limit do
				table.insert(childNames, children[j].Name)
			end
			local childList = table.concat(childNames, ", ")
			if #children > limit then
				childList ..= `, ... ({#children} total)`
			end

			return nil, `Could not resolve path: {pathStr}. "{segName}" not found under {resolvedPath}. Children: [{childList}]{dupeHint}`
		end
		current = child
	end

	return current, nil
end

function Serializer.getPath(instance: Instance): string
	if instance == game then
		return "game"
	end
	local parts = {}
	local current: Instance? = instance
	while current and current ~= game do
		local name = current.Name
		-- Use bracket notation for names with special characters
		if name:find("[%.%[%]\"' ]") then
			table.insert(parts, 1, '["' .. name .. '"]')
		else
			table.insert(parts, 1, name)
		end
		current = current.Parent
	end

	-- Build path, avoiding double dots before bracket segments
	local result = "game"
	for _, part in parts do
		if part:sub(1, 1) == "[" then
			result = result .. part
		else
			result = result .. "." .. part
		end
	end
	return result
end

-- ── Serialization (Roblox → JSON-safe) ──────────────────────────

function Serializer.serialize(value: any): any
	if value == nil then
		return nil
	end

	local t = typeof(value)

	if t == "string" or t == "number" or t == "boolean" then
		return value
	end

	if t == "Instance" then
		return Serializer.getPath(value)
	end

	if t == "Vector3" then
		return { Type = "Vector3", X = value.X, Y = value.Y, Z = value.Z }
	end

	if t == "Vector2" then
		return { Type = "Vector2", X = value.X, Y = value.Y }
	end

	if t == "CFrame" then
		local pos = value.Position
		local rx, ry, rz = value:ToEulerAnglesYXZ()
		return {
			Type = "CFrame",
			Position = { X = pos.X, Y = pos.Y, Z = pos.Z },
			Orientation = { X = math.deg(rx), Y = math.deg(ry), Z = math.deg(rz) },
		}
	end

	if t == "Color3" then
		return {
			Type = "Color3",
			R = math.round(value.R * 255),
			G = math.round(value.G * 255),
			B = math.round(value.B * 255),
		}
	end

	if t == "BrickColor" then
		return { Type = "BrickColor", Name = value.Name }
	end

	if t == "UDim" then
		return { Type = "UDim", Scale = value.Scale, Offset = value.Offset }
	end

	if t == "UDim2" then
		return {
			Type = "UDim2",
			X = { Scale = value.X.Scale, Offset = value.X.Offset },
			Y = { Scale = value.Y.Scale, Offset = value.Y.Offset },
		}
	end

	if t == "NumberRange" then
		return { Type = "NumberRange", Min = value.Min, Max = value.Max }
	end

	if t == "NumberSequence" then
		local keypoints = {}
		for _, kp in value.Keypoints do
			table.insert(keypoints, { Time = kp.Time, Value = kp.Value, Envelope = kp.Envelope })
		end
		return { Type = "NumberSequence", Keypoints = keypoints }
	end

	if t == "ColorSequence" then
		local keypoints = {}
		for _, kp in value.Keypoints do
			table.insert(keypoints, {
				Time = kp.Time,
				Color = Serializer.serialize(kp.Value),
			})
		end
		return { Type = "ColorSequence", Keypoints = keypoints }
	end

	if t == "Ray" then
		return {
			Type = "Ray",
			Origin = Serializer.serialize(value.Origin),
			Direction = Serializer.serialize(value.Direction),
		}
	end

	if t == "Rect" then
		return {
			Type = "Rect",
			Min = { X = value.Min.X, Y = value.Min.Y },
			Max = { X = value.Max.X, Y = value.Max.Y },
		}
	end

	if t == "EnumItem" then
		return {
			Type = "Enum",
			EnumType = tostring(value.EnumType),
			Name = value.Name,
		}
	end

	if t == "table" then
		local result = {}
		for k, v in value do
			result[k] = Serializer.serialize(v)
		end
		return result
	end

	-- Fallback: convert to string
	return tostring(value)
end

-- ── Deserialization (JSON → Roblox) ──────────────────────────────

function Serializer.deserialize(data: any): any
	if data == nil or type(data) ~= "table" then
		return data
	end

	local dataType = data.Type
	if not dataType then
		-- No Type tag — try to infer from structure
		local inferred = Serializer._inferType(data)
		if inferred then
			return inferred
		end

		-- Plain table — recurse
		local result = {}
		for k, v in data do
			result[k] = Serializer.deserialize(v)
		end
		return result
	end

	if dataType == "Vector3" then
		return Vector3.new(data.X, data.Y, data.Z)
	end

	if dataType == "Vector2" then
		return Vector2.new(data.X, data.Y)
	end

	if dataType == "CFrame" then
		local pos = Vector3.new(data.Position.X, data.Position.Y, data.Position.Z)
		if data.Orientation then
			return CFrame.new(pos)
				* CFrame.fromEulerAnglesYXZ(
					math.rad(data.Orientation.X),
					math.rad(data.Orientation.Y),
					math.rad(data.Orientation.Z)
				)
		end
		return CFrame.new(pos)
	end

	if dataType == "Color3" then
		return Color3.fromRGB(data.R, data.G, data.B)
	end

	if dataType == "BrickColor" then
		return BrickColor.new(data.Name)
	end

	if dataType == "UDim" then
		return UDim.new(data.Scale, data.Offset)
	end

	if dataType == "UDim2" then
		return UDim2.new(data.X.Scale, data.X.Offset, data.Y.Scale, data.Y.Offset)
	end

	if dataType == "NumberRange" then
		return NumberRange.new(data.Min, data.Max)
	end

	if dataType == "NumberSequence" then
		local keypoints = {}
		for _, kp in data.Keypoints do
			table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value, kp.Envelope or 0))
		end
		return NumberSequence.new(keypoints)
	end

	if dataType == "ColorSequence" then
		local keypoints = {}
		for _, kp in data.Keypoints do
			table.insert(keypoints, ColorSequenceKeypoint.new(kp.Time, Serializer.deserialize(kp.Color)))
		end
		return ColorSequence.new(keypoints)
	end

	if dataType == "Ray" then
		return Ray.new(
			Serializer.deserialize(data.Origin),
			Serializer.deserialize(data.Direction)
		)
	end

	if dataType == "Rect" then
		return Rect.new(data.Min.X, data.Min.Y, data.Max.X, data.Max.Y)
	end

	if dataType == "Enum" then
		local enumType = (Enum :: any)[data.EnumType]
		if enumType then
			return enumType[data.Name]
		end
		warn("[Conduit] Unknown enum type: " .. tostring(data.EnumType))
		return nil
	end

	return data
end

-- Infer Roblox types from untagged data shapes (no "Type" field).
-- Handles the formats AI clients naturally produce.
function Serializer._inferType(data: any): any
	-- Array formats: [R,G,B], [X,Y], [X,Y,Z], [XScale,XOffset,YScale,YOffset]
	if data[1] ~= nil then
		-- Don't infer arrays — they're ambiguous without property context.
		-- Type-aware coercion in applyProperties handles these.
		return nil
	end

	-- UDim2: {X: {Scale, Offset}, Y: {Scale, Offset}}
	if type(data.X) == "table" and type(data.Y) == "table"
		and data.X.Scale ~= nil and data.X.Offset ~= nil
		and data.Y.Scale ~= nil and data.Y.Offset ~= nil then
		return UDim2.new(data.X.Scale, data.X.Offset, data.Y.Scale, data.Y.Offset)
	end

	-- UDim: {Scale, Offset} (no X/Y)
	if data.Scale ~= nil and data.Offset ~= nil and data.X == nil then
		return UDim.new(data.Scale, data.Offset)
	end

	-- Vector3: {X, Y, Z} (all numbers, no Scale/Offset)
	if type(data.X) == "number" and type(data.Y) == "number" and type(data.Z) == "number"
		and data.Scale == nil and data.Offset == nil then
		return Vector3.new(data.X, data.Y, data.Z)
	end

	-- Vector2: {X, Y} (both numbers, no Z, no Scale/Offset)
	if type(data.X) == "number" and type(data.Y) == "number"
		and data.Z == nil and data.Scale == nil and data.Offset == nil then
		return Vector2.new(data.X, data.Y)
	end

	-- Color3: {R, G, B}
	if type(data.R) == "number" and type(data.G) == "number" and type(data.B) == "number" then
		-- Detect 0-255 vs 0-1 range
		if data.R > 1 or data.G > 1 or data.B > 1 then
			return Color3.fromRGB(data.R, data.G, data.B)
		end
		return Color3.new(data.R, data.G, data.B)
	end

	-- NumberRange: {Min, Max}
	if type(data.Min) == "number" and type(data.Max) == "number" then
		return NumberRange.new(data.Min, data.Max)
	end

	-- Rect: {Min: {X,Y}, Max: {X,Y}}
	if type(data.Min) == "table" and type(data.Max) == "table"
		and type(data.Min.X) == "number" and type(data.Min.Y) == "number"
		and type(data.Max.X) == "number" and type(data.Max.Y) == "number" then
		return Rect.new(data.Min.X, data.Min.Y, data.Max.X, data.Max.Y)
	end

	-- CFrame: {Position: {X,Y,Z}, ...}
	if type(data.Position) == "table" and type(data.Position.X) == "number" then
		local pos = Vector3.new(data.Position.X, data.Position.Y, data.Position.Z)
		if data.Orientation then
			return CFrame.new(pos)
				* CFrame.fromEulerAnglesYXZ(
					math.rad(data.Orientation.X),
					math.rad(data.Orientation.Y),
					math.rad(data.Orientation.Z)
				)
		end
		return CFrame.new(pos)
	end

	-- Enum: {EnumType, Name} or {EnumType, Value}
	if type(data.EnumType) == "string" then
		local enumType = (Enum :: any)[data.EnumType]
		if enumType then
			if data.Name then
				return enumType[data.Name]
			elseif data.Value ~= nil then
				return enumType[data.Value]
			end
		end
	end

	return nil
end

-- ── Property helpers ──────────────────────────────────────────────

function Serializer.serializeProperties(instance: Instance, propertyNames: { string }?): { [string]: any }
	local result: { [string]: any } = {}

	if propertyNames then
		for _, propName in propertyNames do
			local ok, val = pcall(function()
				return (instance :: any)[propName]
			end)
			if ok then
				result[propName] = Serializer.serialize(val)
			end
		end
	else
		-- Serialize common properties
		local commonProps = { "Name", "ClassName", "Parent" }
		for _, propName in commonProps do
			local ok, val = pcall(function()
				return (instance :: any)[propName]
			end)
			if ok then
				result[propName] = Serializer.serialize(val)
			end
		end
	end

	return result
end

function Serializer.applyProperties(instance: Instance, properties: { [string]: any })
	for propName, rawValue in properties do
		local value = Serializer.deserialize(rawValue)

		-- Type-aware coercion: read the existing property to know the expected type,
		-- then convert arrays, plain tables, and strings that deserialize didn't catch.
		local existingOk, existing = pcall(function()
			return (instance :: any)[propName]
		end)
		if existingOk and existing ~= nil then
			if type(value) == "table" then
				local coerced = Serializer._coerceToType(value, existing)
				if coerced ~= nil then
					value = coerced
				end
			elseif type(value) == "string" and typeof(existing) == "EnumItem" then
				-- Coerce string to enum: "Gotham" → Enum.Font.Gotham
				local enumType = (Enum :: any)[tostring(existing.EnumType)]
				if enumType then
					local enumOk, enumVal = pcall(function()
						return enumType[value]
					end)
					if enumOk and enumVal then
						value = enumVal
					end
				end
			end
		end

		local ok, err = pcall(function()
			(instance :: any)[propName] = value
		end)
		if not ok then
			warn("[Conduit] Failed to set " .. propName .. ": " .. tostring(err))
		end
	end
end

-- Coerce a raw table/array to match the type of an existing property value.
-- Handles array formats like [0.5, 0.5] for Vector2, [R,G,B] for Color3, etc.
function Serializer._coerceToType(data: any, existing: any): any
	local existingType = typeof(existing)

	if existingType == "Vector2" then
		-- [X, Y] or {X, Y}
		if data[1] ~= nil then
			return Vector2.new(data[1], data[2] or 0)
		elseif data.X ~= nil then
			return Vector2.new(data.X, data.Y or 0)
		end
	end

	if existingType == "Vector3" then
		-- [X, Y, Z] or {X, Y, Z}
		if data[1] ~= nil then
			return Vector3.new(data[1], data[2] or 0, data[3] or 0)
		elseif data.X ~= nil then
			return Vector3.new(data.X, data.Y or 0, data.Z or 0)
		end
	end

	if existingType == "UDim2" then
		-- [XScale, XOffset, YScale, YOffset]
		if data[1] ~= nil then
			return UDim2.new(data[1], data[2] or 0, data[3] or 0, data[4] or 0)
		end
		-- {X: {Scale, Offset}, Y: {Scale, Offset}}
		if type(data.X) == "table" and type(data.Y) == "table" then
			return UDim2.new(
				data.X.Scale or 0, data.X.Offset or 0,
				data.Y.Scale or 0, data.Y.Offset or 0
			)
		end
	end

	if existingType == "UDim" then
		-- [Scale, Offset]
		if data[1] ~= nil then
			return UDim.new(data[1], data[2] or 0)
		end
		if data.Scale ~= nil then
			return UDim.new(data.Scale, data.Offset or 0)
		end
	end

	if existingType == "Color3" then
		-- [R, G, B]
		if data[1] ~= nil then
			if data[1] > 1 or data[2] > 1 or data[3] > 1 then
				return Color3.fromRGB(data[1], data[2], data[3])
			end
			return Color3.new(data[1], data[2], data[3])
		end
		if data.R ~= nil then
			if data.R > 1 or data.G > 1 or data.B > 1 then
				return Color3.fromRGB(data.R, data.G, data.B)
			end
			return Color3.new(data.R, data.G, data.B)
		end
	end

	if existingType == "CFrame" then
		-- [X, Y, Z] as position-only
		if data[1] ~= nil then
			return CFrame.new(data[1], data[2] or 0, data[3] or 0)
		end
		if type(data.Position) == "table" then
			local pos = Vector3.new(data.Position.X or 0, data.Position.Y or 0, data.Position.Z or 0)
			if data.Orientation then
				return CFrame.new(pos)
					* CFrame.fromEulerAnglesYXZ(
						math.rad(data.Orientation.X or 0),
						math.rad(data.Orientation.Y or 0),
						math.rad(data.Orientation.Z or 0)
					)
			end
			return CFrame.new(pos)
		end
		if data.X ~= nil then
			return CFrame.new(data.X, data.Y or 0, data.Z or 0)
		end
	end

	if existingType == "Rect" then
		-- [MinX, MinY, MaxX, MaxY]
		if data[1] ~= nil then
			return Rect.new(data[1], data[2] or 0, data[3] or 0, data[4] or 0)
		end
	end

	if existingType == "NumberRange" then
		-- [Min, Max]
		if data[1] ~= nil then
			return NumberRange.new(data[1], data[2] or data[1])
		end
	end

	return nil
end

return Serializer
