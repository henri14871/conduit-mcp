--!strict
local InsertService = game:GetService("InsertService")
local Serializer = require(script.Parent.Parent.Serializer)

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

		local results: { { [string]: any } }

		local searchCategory = if category then category:lower() else "models"

		if searchCategory == "decals" or searchCategory == "images" then
			local ok, decals = pcall(function()
				return InsertService:GetFreeDecals(query, 0)
			end)
			if not ok then
				error(`Failed to search decals: {decals}`)
			end
			results = decals
		else
			local ok, models = pcall(function()
				return InsertService:GetFreeModels(query, 0)
			end)
			if not ok then
				error(`Failed to search models: {models}`)
			end
			results = models
		end

		-- Trim to maxResults
		local trimmed: { { [string]: any } } = {}
		for i = 1, math.min(#results, maxResults) do
			local item = results[i]
			table.insert(trimmed, {
				assetId = item.AssetId,
				name = item.Name,
				creatorName = item.CreatorName,
			})
		end

		return {
			query = query,
			category = searchCategory,
			results = trimmed,
			totalFound = #results,
		}
	end, false)
end

return { register = register }
