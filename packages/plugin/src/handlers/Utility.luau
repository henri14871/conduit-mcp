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
		local capturePlugin: any = plugin

		-- Try to capture and return base64 if possible
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

			-- CaptureScreenshot() is side-effect-only in current Roblox API
			-- It saves to the user's screenshots folder but does not return data.
			-- Base64 image return requires EditableImage API support.
			return {
				status = "captured",
				message = "Screenshot captured to file via plugin:CaptureScreenshot(). Base64 return requires EditableImage API support (not yet available in plugin context).",
			}
		end

		return {
			status = "unavailable",
			message = "Screenshot capture is not supported in the current environment. plugin:CaptureScreenshot() is unavailable.",
		}
	end, false)
end

return { register = register }
