--!strict

local Connection = require(script.Connection)
local CommandRouter = require(script.CommandRouter)
local Dashboard = require(script.Dashboard)

-- ── Resolve place name ─────────────────────────────────────────

local placeName: string = game.Name
if game.PlaceId ~= 0 then
	local ok, info = pcall(function()
		return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
	end)
	if ok and info and info.Name then
		placeName = info.Name
	end
end

-- ── Settings ────────────────────────────────────────────────────

local savedPort = plugin:GetSetting("ConduitPort")
local PORT: number = if type(savedPort) == "number" then savedPort else 3200

local savedAutoConnect = plugin:GetSetting("ConduitAutoConnect")
local AUTO_CONNECT: boolean = if savedAutoConnect == nil then true else savedAutoConnect == true

-- ── Plugin UI ────────────────────────────────────────────────────

local toolbar = plugin:CreateToolbar("Conduit MCP")
local toggleButton = toolbar:CreateButton(
	"ConduitToggle",
	"Open Conduit MCP Dashboard",
	"rbxassetid://103184859459538",
	"Conduit"
)

-- Dashboard widget
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- initially not visible
	false, -- don't override saved state
	300,   -- default width
	400,   -- default height
	250,   -- min width
	200    -- min height
)
local widget = plugin:CreateDockWidgetPluginGui("ConduitDashboard", widgetInfo)
widget.Title = "Conduit MCP"

-- ── Initialize connection, router, dashboard ────────────────────

local connection = Connection.new(PORT)
local router = CommandRouter.new(connection)
local dashboard = Dashboard.new(widget, plugin)

-- Apply saved settings to dashboard
dashboard:setPort(PORT)
dashboard:setAutoConnect(AUTO_CONNECT)
dashboard:updateStudioInfo(PORT, placeName)

-- ── Register all handlers ────────────────────────────────────────

require(script.handlers.Explore).register(router)
require(script.handlers.Instances).register(router)
require(script.handlers.Scripts).register(router)
require(script.handlers.Playtest).register(router)
require(script.handlers.Environment).register(router)
require(script.handlers.Assets).register(router)
require(script.handlers.Builds).register(router)
require(script.handlers.Utility).register(router)

-- ── Wire dashboard to connection ────────────────────────────────

local healthPollThread: thread? = nil

connection:onStatusChange(function(status)
	-- Update toolbar button active state
	if status == "connected" then
		toggleButton:SetActive(true)
	else
		toggleButton:SetActive(false)
	end

	-- Update dashboard
	dashboard:updateStatus(status)
	dashboard:updateStudioInfo(connection:getPort(), placeName)

	-- Cancel health polling whenever we leave "connected" state
	if status ~= "connected" and healthPollThread then
		task.cancel(healthPollThread)
		healthPollThread = nil
	end

	if status == "connected" then
		dashboard:startUptime()

		-- Start health polling for studio count
		if healthPollThread then
			task.cancel(healthPollThread)
		end
		healthPollThread = task.spawn(function()
			while connection:isConnected() do
				local health = connection:pollHealth()
				if health then
					local myId = connection:getStudioId()
					local isActive = health.activeStudioId == myId
					dashboard:updateStudiosInfo(health.studioCount, isActive)
				end
				task.wait(10)
			end
		end)

		print("[Conduit] Connected to MCP server")
	elseif status == "disconnected" then
		dashboard:stopUptime()
		dashboard:updateStudiosInfo(0, false)
		dashboard:updatePing(nil)

		if healthPollThread then
			task.cancel(healthPollThread)
			healthPollThread = nil
		end

		warn("[Conduit] Disconnected from MCP server")
	end
end)

-- Wire ping display
connection:onPingUpdate(function(ms)
	dashboard:updatePing(ms)
end)

-- Wire reconnect countdown
connection:onReconnectCountdown(function(remaining, _total)
	if remaining > 0 then
		dashboard:showReconnectCountdown(remaining)
	else
		dashboard:hideReconnectCountdown()
	end
end)

-- Wire activity log
router:onActivity(function(entry)
	dashboard:logActivity(entry.method, entry.status, entry.duration, entry.errorMessage)
end)

-- Wire dashboard buttons
dashboard:onConnect(function()
	connection:connect()
end)

dashboard:onDisconnect(function()
	connection:disconnect()
end)

dashboard:onPortChange(function(port)
	connection:setPort(port)
	dashboard:updateStudioInfo(port, placeName)
end)

dashboard:onAutoConnectChange(function(enabled)
	if enabled and not connection:isConnected() then
		connection:connect()
	end
end)

-- ── Toolbar button toggles dashboard visibility ─────────────────

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- ── Check HttpService ────────────────────────────────────────────

local HttpService = game:GetService("HttpService")
if not HttpService.HttpEnabled then
	warn("[Conduit] HttpService is not enabled! Go to Game Settings -> Security -> Allow HTTP Requests")
end

-- ── Auto-connect ─────────────────────────────────────────────────

if AUTO_CONNECT then
	connection:connect()
end

-- ── Cleanup ──────────────────────────────────────────────────────

plugin.Unloading:Connect(function()
	dashboard:stopUptime()
	if healthPollThread then
		task.cancel(healthPollThread)
		healthPollThread = nil
	end
	connection:disconnect()
end)
