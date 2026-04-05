--!strict

local Connection = require(script.Connection)
local CommandRouter = require(script.CommandRouter)

-- ── Configuration ────────────────────────────────────────────────

local PORT = 3200

-- ── Plugin UI ────────────────────────────────────────────────────

local toolbar = plugin:CreateToolbar("Conduit MCP")
local connectButton = toolbar:CreateButton(
	"ConduitConnect",
	"Connect to Conduit MCP server",
	"rbxassetid://0",
	"Conduit"
)

-- Status indicator via button tooltip
local function updateButtonState(status: string)
	if status == "connected" then
		connectButton:SetActive(true)
	elseif status == "connecting" then
		connectButton:SetActive(false)
	else
		connectButton:SetActive(false)
	end
end

-- ── Initialize connection & router ───────────────────────────────

local connection = Connection.new(PORT)
local router = CommandRouter.new(connection)

-- ── Register all handlers ────────────────────────────────────────

require(script.handlers.Explore).register(router)
require(script.handlers.Instances).register(router)
require(script.handlers.Scripts).register(router)
require(script.handlers.Playtest).register(router)
require(script.handlers.Environment).register(router)
require(script.handlers.Assets).register(router)
require(script.handlers.Builds).register(router)
require(script.handlers.Utility).register(router)

-- ── Connection status tracking ───────────────────────────────────

connection:onStatusChange(function(status)
	updateButtonState(status)
	if status == "connected" then
		print("[Conduit] Connected to MCP server")
	elseif status == "disconnected" then
		warn("[Conduit] Disconnected from MCP server")
	end
end)

-- ── Button toggle ────────────────────────────────────────────────

connectButton.Click:Connect(function()
	if connection:isConnected() then
		connection:disconnect()
	else
		connection:connect()
	end
end)

-- ── Check HttpService ────────────────────────────────────────────

local HttpService = game:GetService("HttpService")
if not HttpService.HttpEnabled then
	warn("[Conduit] HttpService is not enabled! Go to Game Settings → Security → Allow HTTP Requests")
end

-- ── Auto-connect ─────────────────────────────────────────────────

connection:connect()

-- ── Cleanup ──────────────────────────────────────────────────────

plugin.Unloading:Connect(function()
	connection:disconnect()
end)
