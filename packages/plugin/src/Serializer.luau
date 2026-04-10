--!strict

local HttpService = game:GetService("HttpService")

local Serializer = {}

-- ── Path resolution ──────────────────────────────────────────────

function Serializer.resolvePath(pathStr: string): Instance?
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
		local ok, err = pcall(function()
			(instance :: any)[propName] = value
		end)
		if not ok then
			warn("[Conduit] Failed to set " .. propName .. ": " .. tostring(err))
		end
	end
end

return Serializer
