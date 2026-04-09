--!strict
local Serializer = require(script.Parent.Parent.Serializer)
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local SKIP_SERVICES: { [string]: boolean } = {
	CoreGui = true,
	CorePackages = true,
	RobloxPluginGuiService = true,
}

local function buildTree(
	instance: Instance,
	depth: number,
	maxDepth: number,
	filter: string?,
	includeProperties: boolean
): { [string]: any }?
	if depth > maxDepth then
		return nil
	end

	local className = instance.ClassName
	if SKIP_SERVICES[instance.Name] then
		return nil
	end

	if filter and className ~= filter then
		local matchingChildren: { { [string]: any } } = {}
		for _, child in instance:GetChildren() do
			local childNode = buildTree(child, depth + 1, maxDepth, filter, includeProperties)
			if childNode then
				table.insert(matchingChildren, childNode)
			end
		end
		if #matchingChildren > 0 then
			return {
				name = instance.Name,
				className = className,
				path = Serializer.getPath(instance),
				children = matchingChildren,
			}
		end
		return nil
	end

	local node: { [string]: any } = {
		name = instance.Name,
		className = className,
		path = Serializer.getPath(instance),
	}

	if includeProperties then
		node.properties = Serializer.serializeProperties(instance)
	end

	if depth < maxDepth then
		local children: { { [string]: any } } = {}
		for _, child in instance:GetChildren() do
			local childNode = buildTree(child, depth + 1, maxDepth, filter, includeProperties)
			if childNode then
				table.insert(children, childNode)
			end
		end
		if #children > 0 then
			node.children = children
		end
	else
		local childCount = #instance:GetChildren()
		if childCount > 0 then
			node.childCount = childCount
		end
	end

	return node
end

-- Common properties to try reading (no reflection API in Roblox)
local COMMON_PROPERTIES = {
	-- Base
	"Name", "ClassName", "Parent", "Archivable",
	-- BasePart
	"Position", "Size", "CFrame", "Orientation", "Anchored", "CanCollide",
	"CanTouch", "CanQuery", "Transparency", "Color", "BrickColor", "Material",
	"Reflectance", "CastShadow", "Massless", "RootPriority",
	"TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface",
	"Shape", "AssemblyLinearVelocity", "AssemblyAngularVelocity",
	-- Lighting
	"Brightness", "Ambient", "OutdoorAmbient", "ClockTime", "GeographicLatitude",
	"FogColor", "FogEnd", "FogStart", "GlobalShadows", "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
	-- GuiObject
	"BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel",
	"AnchorPoint", "AutomaticSize", "LayoutOrder", "Visible", "ZIndex",
	"TextColor3", "TextSize", "Font", "Text", "TextWrapped", "TextScaled",
	"RichText", "TextXAlignment", "TextYAlignment",
	"Image", "ImageColor3", "ImageTransparency", "ScaleType",
	-- Layout
	"SortOrder", "FillDirection", "HorizontalAlignment", "VerticalAlignment",
	"Padding",
	-- UIConstraint
	"MaxSize", "MinSize", "MaxTextSize", "MinTextSize",
	-- Workspace
	"Gravity", "FallenPartsDestroyHeight", "StreamingEnabled",
	-- Script
	"Enabled", "RunContext",
	-- Sound
	"SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing",
	-- Model
	"PrimaryPart", "WorldPivot",
	-- Camera
	"CameraType", "FieldOfView", "CameraSubject",
	-- ParticleEmitter
	"Rate", "Speed", "Lifetime", "Texture",
	-- Value objects
	"Value",
}

local function register(router: any)
	-- ── explore (tree browsing) ─────────────────────────────────────
	router:register("explore", function(params: { [string]: any }?)
		local p = params or {}
		local path: string = p.path or "game"
		local depth: number = p.depth or 2
		local filter: string? = p.filter
		local includeProperties: boolean = if p.includeProperties then true else false

		local root = Serializer.resolvePath(path)
		if not root then
			error(`Could not resolve path: {path}`)
		end

		local tree = buildTree(root, 0, depth, filter, includeProperties)
		if not tree then
			error(`No results found at path: {path}`)
		end

		return tree
	end, false)

	-- ── get_selection ────────────────────────────────────────────────
	router:register("get_selection", function(_params: { [string]: any }?)
		local Selection = game:GetService("Selection")
		local selected = Selection:Get()
		local results: { { path: string, className: string, name: string } } = {}

		for _, instance in selected do
			table.insert(results, {
				path = Serializer.getPath(instance),
				className = instance.ClassName,
				name = instance.Name,
			})
		end

		return { selection = results }
	end, false)

	-- ── set_selection ────────────────────────────────────────────────
	router:register("set_selection", function(params: { [string]: any })
		local paths = params.paths
		if not paths or #paths == 0 then
			error("set_selection requires a non-empty paths array")
		end

		local Selection = game:GetService("Selection")
		local instances: { Instance } = {}

		for _, path in paths do
			local instance = Serializer.resolvePath(path)
			if instance then
				table.insert(instances, instance)
			end
		end

		Selection:Set(instances)
		return { selected = #instances }
	end, false)

	-- ── get_services ─────────────────────────────────────────────────
	router:register("get_services", function(_params: { [string]: any }?)
		local services: { { name: string, className: string } } = {}

		for _, child in game:GetChildren() do
			if not SKIP_SERVICES[child.Name] then
				table.insert(services, {
					name = child.Name,
					className = child.ClassName,
				})
			end
		end

		return { services = services }
	end, false)

	-- ── get_info (merged get_instance_info + list_properties) ────────
	router:register("get_info", function(params: { [string]: any })
		local path: string = params.path
		if not path then
			error("get_info requires a path")
		end

		local instance = Serializer.resolvePath(path)
		if not instance then
			error(`Could not resolve path: {path}`)
		end

		local result: { [string]: any } = {
			name = instance.Name,
			className = instance.ClassName,
			path = Serializer.getPath(instance),
			parent = if instance.Parent then Serializer.getPath(instance.Parent) else nil,
			childCount = #instance:GetChildren(),
		}

		if params.includeProperties then
			local props: { [string]: any } = {}
			-- If specific property names are requested, read only those
			local propsToRead: { string } = if params.propertyNames and #params.propertyNames > 0
				then params.propertyNames
				else COMMON_PROPERTIES
			for _, propName in propsToRead do
				if propName == "Name" or propName == "ClassName" or propName == "Parent" then
					continue
				end
				local ok, val = pcall(function()
					return (instance :: any)[propName]
				end)
				if ok and val ~= nil then
					props[propName] = Serializer.serialize(val)
				end
			end
			result.properties = props
		end

		if params.includeAttributes then
			local attrs = instance:GetAttributes()
			local serialized: { [string]: any } = {}
			for k, v in attrs do
				serialized[k] = Serializer.serialize(v)
			end
			result.attributes = serialized
		end

		if params.includeTags then
			result.tags = instance:GetTags()
		end

		if params.includePropertyList then
			local filter: string? = params.propertyFilter
			local properties: { { name: string, type: string, value: any } } = {}
			local filterLower: string? = if filter then string.lower(filter) else nil

			for _, propName in COMMON_PROPERTIES do
				if filterLower and not string.find(string.lower(propName), filterLower, 1, true) then
					continue
				end

				local ok, val = pcall(function()
					return (instance :: any)[propName]
				end)
				if ok and val ~= nil then
					table.insert(properties, {
						name = propName,
						type = typeof(val),
						value = Serializer.serialize(val),
					})
				end
			end

			result.propertyList = properties
		end

		return result
	end, false)

	-- ── get_studio_state ─────────────────────────────────────────────
	router:register("get_studio_state", function(_params: { [string]: any }?)
		local isRunning = RunService:IsRunning()

		local isClient = false
		pcall(function()
			isClient = RunService:IsClient()
		end)

		local isServer = false
		pcall(function()
			isServer = RunService:IsServer()
		end)

		local placeId = game.PlaceId
		local gameId = game.GameId

		local placeName: string? = nil
		if placeId ~= 0 then
			pcall(function()
				local info = game:GetService("MarketplaceService"):GetProductInfo(placeId)
				placeName = info.Name
			end)
		end

		local canUndo: boolean? = nil
		pcall(function()
			canUndo = ChangeHistoryService:GetCanUndo()
		end)

		local canRedo: boolean? = nil
		pcall(function()
			canRedo = ChangeHistoryService:GetCanRedo()
		end)

		return {
			isRunning = isRunning,
			isClient = isClient,
			isServer = isServer,
			placeId = placeId,
			gameId = gameId,
			placeName = placeName,
			canUndo = canUndo,
			canRedo = canRedo,
		}
	end, false)
end

return { register = register }
