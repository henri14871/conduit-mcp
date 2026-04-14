--!strict
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Serializer = require(script.Parent.Parent.Serializer)

-- Roblox Creator Marketplace asset type IDs
local ASSET_TYPE_MAP: { [string]: string } = {
	models = "10",
	decals = "13",
	images = "13",
	meshes = "40",
	meshparts = "40",
	audio = "3",
	plugins = "38",
}

local function register(router: any)
	router:register("insert_asset", function(params: { [string]: any })
		local assetId: number = params.assetId
		local parentPath: string = params.parent

		if not assetId then
			error("insert_asset requires an assetId")
		end
		if not parentPath then
			error("insert_asset requires a parent path")
		end

		local parent, resolveErr = Serializer.resolvePathOrError(parentPath)
		if not parent then
			error(resolveErr)
		end

		local model = InsertService:LoadAsset(assetId)
		if not model then
			error(`Failed to load asset: {assetId}`)
		end

		local inserted: { { path: string, className: string, name: string } } = {}

		for _, child in model:GetChildren() do
			child.Parent = parent
			table.insert(inserted, {
				path = Serializer.getPath(child),
				className = child.ClassName,
				name = child.Name,
			})
		end

		-- Clean up the wrapper model
		model:Destroy()

		return { assetId = assetId, inserted = inserted }
	end, true)

	router:register("search_assets", function(params: { [string]: any })
		local query: string = params.query
		local category: string? = params.category
		local maxResults: number = params.maxResults or 10

		if not query then
			error("search_assets requires a query")
		end

		local searchCategory = if category then category:lower() else "models"
		local assetTypeId = ASSET_TYPE_MAP[searchCategory] or "10"

		-- Use Roblox Toolbox search API (same one Studio's Toolbox uses)
		local url = "https://apis.roblox.com/toolbox-service/v1/marketplace/"
			.. assetTypeId
			.. "?keyword=" .. HttpService:UrlEncode(query)
			.. "&limit=" .. tostring(maxResults)
			.. "&sortType=3" -- relevance

		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
			})
		end)

		if not ok then
			error(`Failed to search assets: {response}`)
		end

		if response.StatusCode ~= 200 then
			-- Fallback: try the legacy InsertService API
			local legacyResults = {}
			local legacyOk, legacyData = pcall(function()
				if searchCategory == "decals" or searchCategory == "images" then
					return InsertService:GetFreeDecals(query, 0)
				else
					return InsertService:GetFreeModels(query, 0)
				end
			end)
			if legacyOk and legacyData and #legacyData > 0 then
				for i = 1, math.min(#legacyData, maxResults) do
					local item = legacyData[i]
					table.insert(legacyResults, {
						assetId = item.AssetId,
						name = item.Name,
						creatorName = item.CreatorName or "Unknown",
					})
				end
				return {
					query = query,
					category = searchCategory,
					results = legacyResults,
					totalFound = #legacyData,
				}
			end
			error(`Asset search failed (HTTP {response.StatusCode}): {response.Body}`)
		end

		local decodeOk, data = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if not decodeOk or not data then
			error("Failed to decode asset search response")
		end

		local items = data.data or data.Data or data.results or data.Results or {}
		local trimmed: { { assetId: number, name: string, creatorName: string } } = {}

		for i = 1, math.min(#items, maxResults) do
			local item = items[i]

			-- The API response uses nested structure: item.asset.id, item.asset.name, etc.
			local asset = item.asset or item
			local creator = item.creator or asset.creator or {}

			local assetId = asset.id or asset.assetId or asset.AssetId or 0
			local name = asset.name or asset.Name or "Unknown"
			local creatorName = creator.name or creator.Name or asset.creatorName or asset.CreatorName or "Unknown"

			if type(assetId) == "number" and assetId > 0 then
				table.insert(trimmed, {
					assetId = assetId,
					name = name,
					creatorName = creatorName,
				})
			end
		end

		return {
			query = query,
			category = searchCategory,
			results = trimmed,
			totalFound = #items,
		}
	end, false)
end

return { register = register }
