--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local function register(router: any)
	-- ── undo_redo (with count support) ───────────────────────────────
	router:register("undo_redo", function(params: { [string]: any })
		local action: string = params.action
		local count: number = params.count or 1

		if not action then
			error("undo_redo requires an action (undo or redo)")
		end

		if action == "undo" then
			for _ = 1, count do
				local ok, err = pcall(function()
					ChangeHistoryService:Undo()
				end)
				if not ok then
					error(`Failed to undo: {err}`)
				end
			end
			return { status = "undone", count = count }

		elseif action == "redo" then
			for _ = 1, count do
				local ok, err = pcall(function()
					ChangeHistoryService:Redo()
				end)
				if not ok then
					error(`Failed to redo: {err}`)
				end
			end
			return { status = "redone", count = count }
		else
			error(`Unknown undo_redo action: {action}. Expected "undo" or "redo"`)
		end
	end, true)

	-- ── screenshot ───────────────────────────────────────────────────
	router:register("screenshot", function(_params: { [string]: any }?)
		-- Try StudioService:CaptureScreenshot first (newer API)
		local capturedViaStudioService = false
		pcall(function()
			local StudioService = game:GetService("StudioService")
			if typeof((StudioService :: any).CaptureScreenshot) == "function" then
				(StudioService :: any):CaptureScreenshot()
				capturedViaStudioService = true
			end
		end)

		if capturedViaStudioService then
			return {
				status = "captured",
				message = "Screenshot saved to Roblox screenshots folder via StudioService:CaptureScreenshot().",
			}
		end

		-- Try plugin:CaptureScreenshot (older API)
		local capturePlugin: any = plugin
		if capturePlugin and typeof(capturePlugin.CaptureScreenshot) == "function" then
			local ok, err = pcall(function()
				capturePlugin:CaptureScreenshot()
			end)
			if not ok then
				return {
					status = "error",
					message = `Screenshot capture failed: {err}`,
				}
			end

			return {
				status = "captured",
				message = "Screenshot saved to Roblox screenshots folder via plugin:CaptureScreenshot().",
			}
		end

		-- Neither API available — give a helpful message
		return {
			status = "unavailable",
			message = "Screenshot capture is not available in this Studio version. Alternative: use playtest execute with code to inspect game state programmatically, or use playtest inspect to evaluate expressions.",
		}
	end, false)
end

return { register = register }
