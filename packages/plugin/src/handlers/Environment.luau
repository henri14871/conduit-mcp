--!strict
local Workspace = game:GetService("Workspace")
local Serializer = require(script.Parent.Parent.Serializer)

local function vector3FromTable(t: { X: number, Y: number, Z: number }): Vector3
	return Vector3.new(t.X, t.Y, t.Z)
end

-- Workspace & Lighting property lists
local WORKSPACE_PROPS = {
	"Gravity", "FallenPartsDestroyHeight", "StreamingEnabled",
	"StreamingMinRadius", "StreamingTargetRadius",
}

local LIGHTING_PROPS = {
	"Brightness", "Ambient", "OutdoorAmbient", "ClockTime",
	"GeographicLatitude", "TimeOfDay",
	"FogColor", "FogEnd", "FogStart",
	"GlobalShadows", "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
	"ExposureCompensation",
}

local function register(router: any)
	-- ── terrain ──────────────────────────────────────────────────────
	router:register("terrain", function(params: { [string]: any })
		local action: string = params.action
		if not action then
			error("terrain requires an action (fill, clear, or read)")
		end

		local terrain = Workspace.Terrain

		if action == "fill" then
			local region = params.region
			local materialName: string = params.material
			local size = params.size

			if not materialName then
				error("fill action requires a material parameter")
			end

			local material = (Enum.Material :: any)[materialName]
			if not material then
				error(`Unknown material: {materialName}`)
			end

			if region then
				local min = vector3FromTable(region.min)
				local max = vector3FromTable(region.max)
				local center = (min + max) / 2
				local blockSize = max - min

				terrain:FillBlock(CFrame.new(center), blockSize, material)
			elseif size then
				local blockSize = vector3FromTable(size)
				local center = Vector3.new(0, blockSize.Y / 2, 0)

				terrain:FillBlock(CFrame.new(center), blockSize, material)
			else
				error("fill action requires either a region or size parameter")
			end

			return { status = "filled", material = materialName }

		elseif action == "clear" then
			local region = params.region
			if region then
				local min = vector3FromTable(region.min)
				local max = vector3FromTable(region.max)

				local resolution = 4
				local alignedMin = Vector3.new(
					math.floor(min.X / resolution) * resolution,
					math.floor(min.Y / resolution) * resolution,
					math.floor(min.Z / resolution) * resolution
				)
				local alignedMax = Vector3.new(
					math.ceil(max.X / resolution) * resolution,
					math.ceil(max.Y / resolution) * resolution,
					math.ceil(max.Z / resolution) * resolution
				)

				local clearRegion = Region3.new(alignedMin, alignedMax)
				terrain:FillRegion(clearRegion, resolution, Enum.Material.Air)
			else
				terrain:Clear()
			end
			return { status = "cleared" }

		elseif action == "read" then
			local region = params.region
			if not region then
				error("read action requires a region parameter")
			end

			local min = vector3FromTable(region.min)
			local max = vector3FromTable(region.max)

			local resolution = 4
			local alignedMin = Vector3.new(
				math.floor(min.X / resolution) * resolution,
				math.floor(min.Y / resolution) * resolution,
				math.floor(min.Z / resolution) * resolution
			)
			local alignedMax = Vector3.new(
				math.ceil(max.X / resolution) * resolution,
				math.ceil(max.Y / resolution) * resolution,
				math.ceil(max.Z / resolution) * resolution
			)

			local readRegion = Region3.new(alignedMin, alignedMax)
			local materials, occupancy = terrain:ReadVoxels(readRegion, resolution)

			local materialCounts: { [string]: number } = {}
			local totalVoxels = 0
			local filledVoxels = 0

			for x = 1, #materials do
				for y = 1, #materials[x] do
					for z = 1, #materials[x][y] do
						totalVoxels += 1
						local mat = materials[x][y][z]
						if mat ~= Enum.Material.Air then
							filledVoxels += 1
							local matName = mat.Name
							materialCounts[matName] = (materialCounts[matName] or 0) + 1
						end
					end
				end
			end

			return {
				region = {
					min = { X = alignedMin.X, Y = alignedMin.Y, Z = alignedMin.Z },
					max = { X = alignedMax.X, Y = alignedMax.Y, Z = alignedMax.Z },
				},
				resolution = resolution,
				totalVoxels = totalVoxels,
				filledVoxels = filledVoxels,
				materials = materialCounts,
			}
		else
			error(`Unknown terrain action: {action}. Expected "fill", "clear", or "read"`)
		end
	end, true)

	-- ── workspace_settings ───────────────────────────────────────────
	router:register("workspace_settings", function(params: { [string]: any })
		local action: string = params.action
		if not action then
			error("workspace_settings requires an action (get or set)")
		end

		local Lighting = game:GetService("Lighting")

		if action == "get" then
			local settings: { [string]: any } = {}

			for _, prop in WORKSPACE_PROPS do
				local ok, val = pcall(function()
					return (Workspace :: any)[prop]
				end)
				if ok and val ~= nil then
					settings["Workspace." .. prop] = Serializer.serialize(val)
				end
			end

			for _, prop in LIGHTING_PROPS do
				local ok, val = pcall(function()
					return (Lighting :: any)[prop]
				end)
				if ok and val ~= nil then
					settings["Lighting." .. prop] = Serializer.serialize(val)
				end
			end

			return { settings = settings }

		elseif action == "set" then
			local settingsToSet = params.settings
			if not settingsToSet then
				error("set action requires a settings parameter")
			end

			local modified: { string } = {}

			for key, rawValue in settingsToSet do
				local service, prop = string.match(key, "^(%w+)%.(.+)$")
				if not service or not prop then
					warn("[Conduit] Invalid settings key: " .. key)
					continue
				end

				local target: Instance?
				if service == "Workspace" then
					target = Workspace
				elseif service == "Lighting" then
					target = Lighting
				else
					warn("[Conduit] Unknown service in settings key: " .. key)
					continue
				end

				local value = Serializer.deserialize(rawValue)
				local ok, err = pcall(function()
					(target :: any)[prop] = value
				end)
				if ok then
					table.insert(modified, key)
				else
					warn("[Conduit] Failed to set " .. key .. ": " .. tostring(err))
				end
			end

			return { settings = {}, modified = modified }
		else
			error(`Unknown workspace_settings action: {action}. Expected "get" or "set"`)
		end
	end, true)
end

return { register = register }
