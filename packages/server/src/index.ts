import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { Bridge } from "./bridge.js";
import { registerAllTools, type ToolRegistrationOptions } from "./tools/index.js";
import { log } from "./utils/logger.js";
import type { StudioInfo } from "./protocol.js";

export interface ServerOptions {
  mode?: "full" | "inspector";
  withCloud?: boolean;
  withRojo?: boolean;
}

export async function startServer(
  port: number = 3200,
  options: ServerOptions = {},
): Promise<void> {
  const bridge = new Bridge(port);

  const server = new McpServer(
    {
      name: "conduit-mcp",
      version: "2.0.0",
    },
    {
      instructions: [
        "Conduit bridges AI assistants to Roblox Studio via WebSocket.",
        "The Conduit plugin must be running in Roblox Studio and connected.",
        "",
        "Workflow tips:",
        "- Use `explore` first to understand the DataModel before making changes.",
        "- Use `read_script` to read source before editing with `edit_script`.",
        "- All mutations are undoable via Ctrl+Z in Studio (ChangeHistoryService).",
        "- Use `lookup_api` to check Roblox API signatures before writing Luau code.",
        "- Batch operations: `create` and `modify` accept arrays of operations.",
        "- Token budgets: pass `maxTokens` to limit response size on large DataModels.",
        "- Use `query` to find instances by class, tag, or attribute.",
        "- Use `query --action scripts` to grep across all script sources.",
        "- Use `execute_lua` as an escape hatch for anything tools don't cover.",
        "- Use `explore --action set_selection` to select instances in Studio.",
        "",
        "Multi-Studio:",
        "- Multiple Studio instances can connect simultaneously.",
        "- Use `list_studios` to see connected instances and `set_active_studio` to switch.",
        "- With a single Studio, routing is automatic.",
      ].join("\n"),
    },
  );

  const toolOptions: ToolRegistrationOptions = {
    mode: options.mode,
    withCloud: options.withCloud,
    withRojo: options.withRojo,
  };
  registerAllTools(server, bridge, toolOptions);

  bridge.on("studio-connected", (info: StudioInfo) => {
    log.info(
      `Roblox Studio connected: ${info.studioId}` +
        (info.placeName ? ` (${info.placeName})` : ""),
    );
  });

  bridge.on("studio-disconnected", (info: StudioInfo) => {
    log.warn(
      `Roblox Studio disconnected: ${info.studioId}` +
        (info.placeName ? ` (${info.placeName})` : ""),
    );
  });

  const actualPort = await bridge.start();
  log.info(`Bridge listening on port ${actualPort}`);

  const transport = new StdioServerTransport();
  await server.connect(transport);
  log.info("MCP server connected via stdio");

  // Graceful shutdown
  const shutdown = async () => {
    log.info("Shutting down...");
    await bridge.stop();
    await server.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
