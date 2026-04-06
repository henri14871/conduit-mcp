import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";

export function register(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "list_studios",
    {
      title: "List Connected Studios",
      description:
        "List all Roblox Studio instances currently connected to Conduit. Shows studio ID, place name, place ID, and which studio is active. Use set_active_studio to switch between them.",
      inputSchema: z.object({}),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
      const studios = bridge.getStudios();
      const activeId = bridge.getActiveStudioId();

      if (studios.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "*No Roblox Studio instances connected.* Make sure the Conduit plugin is installed and running.",
            },
          ],
        };
      }

      const lines = studios.map((s) => {
        const active = s.studioId === activeId ? " **← active**" : "";
        const place = s.placeName ? ` — ${s.placeName}` : "";
        const placeId = s.placeId ? ` (Place ID: ${s.placeId})` : "";
        const duration = Math.floor((Date.now() - s.connectedAt) / 1000);
        return `- \`${s.studioId}\`${place}${placeId} — connected ${duration}s ago${active}`;
      });

      const text = `**Connected Studios (${studios.length}):**\n${lines.join("\n")}`;
      return { content: [{ type: "text", text }] };
    },
  );

  server.registerTool(
    "set_active_studio",
    {
      title: "Set Active Studio",
      description:
        "Switch which Roblox Studio instance receives tool commands. Use list_studios to see available IDs.",
      inputSchema: z.object({
        studioId: z
          .string()
          .describe("The studio ID to set as active (from list_studios)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      try {
        bridge.setActiveStudio(params.studioId);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: message }],
          isError: true,
        };
      }
      const studios = bridge.getStudios();
      const studio = studios.find((s) => s.studioId === params.studioId);
      const name = studio?.placeName ?? "unknown";
      const text = `Active studio set to \`${params.studioId}\` (${name}).`;
      return { content: [{ type: "text", text }] };
    },
  );
}
