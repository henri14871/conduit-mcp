--!strict
local Serializer = require(script.Parent.Parent.Serializer)

local function deepSerialize(instance: Instance): { [string]: any }
	local ScriptEditorService = game:GetService("ScriptEditorService")

	local node: { [string]: any } = {
		className = instance.ClassName,
		name = instance.Name,
		properties = {},
		attributes = {},
		tags = {},
		children = {},
	}

	-- Serialize common writable properties
	local WRITABLE_PROPS = {
		-- BasePart
		"Anchored", "CanCollide", "CanTouch", "CanQuery",
		"CastShadow", "Massless", "Transparency", "Reflectance",
		"Color", "BrickColor", "Material", "Size", "CFrame",
		"TopSurface", "BottomSurface", "Shape",
		-- GuiObject
		"BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel",
		"AnchorPoint", "Visible", "ZIndex", "LayoutOrder", "AutomaticSize",
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextScaled",
		"RichText", "TextXAlignment", "TextYAlignment",
		"Image", "ImageColor3", "ImageTransparency", "ScaleType",
		-- Layout
		"SortOrder", "FillDirection", "HorizontalAlignment", "VerticalAlignment",
		"Padding",
		-- Sound
		"SoundId", "Volume", "PlaybackSpeed", "Looped",
		-- Model
		"PrimaryPart",
		-- Script
		"Enabled", "RunContext",
		-- Light
		"Brightness", "Range",
		-- Value objects
		"Value",
	}

	for _, propName in WRITABLE_PROPS do
		local ok, val = pcall(function()
			return (instance :: any)[propName]
		end)
		if ok and val ~= nil then
			node.properties[propName] = Serializer.serialize(val)
		end
	end

	-- Serialize source for scripts
	if instance:IsA("LuaSourceContainer") then
		local ok, source = pcall(function()
			return ScriptEditorService:GetEditorSource(instance)
		end)
		if ok and source then
			node.source = source
		end
	end

	-- Attributes
	for k, v in instance:GetAttributes() do
		node.attributes[k] = Serializer.serialize(v)
	end

	-- Tags
	node.tags = instance:GetTags()

	-- Children (recursive)
	for _, child in instance:GetChildren() do
		table.insert(node.children, deepSerialize(child))
	end

	return node
end

local function deepImport(node: { [string]: any }, parent: Instance): Instance
	local ScriptEditorService = game:GetService("ScriptEditorService")

	local instance = Instance.new(node.className)
	instance.Name = node.name or node.className

	-- Apply properties
	if node.properties then
		Serializer.applyProperties(instance, node.properties)
	end

	-- Apply source for scripts
	if node.source and instance:IsA("LuaSourceContainer") then
		pcall(function()
			ScriptEditorService:UpdateSourceAsync(instance, function(_old: string)
				return node.source
			end)
		end)
	end

	-- Apply attributes
	if node.attributes then
		for k, v in node.attributes do
			local ok, val = pcall(function()
				return Serializer.deserialize(v)
			end)
			if ok then
				instance:SetAttribute(k, val)
			end
		end
	end

	-- Apply tags
	if node.tags then
		for _, tag in node.tags do
			instance:AddTag(tag)
		end
	end

	-- Set parent before children for parenting
	instance.Parent = parent

	-- Import children recursively
	if node.children then
		for _, childNode in node.children do
			deepImport(childNode, instance)
		end
	end

	return instance
end

local function register(router: any)
	-- ── export_build ─────────────────────────────────────────────────
	router:register("export_build", function(params: { [string]: any })
		local path: string = params.path
		if not path then
			error("export_build requires a path")
		end

		local instance = Serializer.resolvePath(path)
		if not instance then
			error(`Could not resolve path: {path}`)
		end

		return deepSerialize(instance)
	end, false)

	-- ── import_build ─────────────────────────────────────────────────
	router:register("import_build", function(params: { [string]: any })
		local tree = params.tree
		local targetParentPath: string = params.targetParent

		if not tree then
			error("import_build requires a tree")
		end
		if not targetParentPath then
			error("import_build requires a targetParent")
		end

		local targetParent = Serializer.resolvePath(targetParentPath)
		if not targetParent then
			error(`Could not resolve target parent path: {targetParentPath}`)
		end

		local root = deepImport(tree, targetParent)

		return {
			path = Serializer.getPath(root),
			className = root.ClassName,
			childCount = #root:GetChildren(),
		}
	end, true)
end

return { register = register }
