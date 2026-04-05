import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { applyTokenBudget } from "../utils/formatting.js";

const Vector3Schema = z.object({
  x: z.number().describe("X coordinate"),
  y: z.number().describe("Y coordinate"),
  z: z.number().describe("Z coordinate"),
});

const RegionSchema = z.object({
  min: Vector3Schema.describe("Minimum corner of the region"),
  max: Vector3Schema.describe("Maximum corner of the region"),
});

export function register(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "environment",
    {
      title: "Environment & Terrain",
      description:
        "Manage terrain and workspace/lighting settings.\n\n" +
        "Actions:\n" +
        "- `terrain_fill`: Fill a region with a material.\n" +
        "- `terrain_clear`: Clear terrain in a region (or all).\n" +
        "- `terrain_read`: Read terrain data in a region.\n" +
        "- `settings_get`: Get Workspace and Lighting properties.\n" +
        "- `settings_set`: Set Workspace and Lighting properties.",
      inputSchema: z.object({
        action: z
          .enum(["terrain_fill", "terrain_clear", "terrain_read", "settings_get", "settings_set"])
          .describe("Environment action"),
        // Terrain params
        region: RegionSchema.optional().describe("Region for terrain operations"),
        material: z
          .string()
          .optional()
          .describe("Terrain material name (for 'terrain_fill'), e.g. 'Grass'"),
        size: Vector3Schema.optional().describe("Size override for terrain fill"),
        // Settings params
        settings: z
          .record(z.unknown())
          .optional()
          .describe("Settings to set (for 'settings_set'). Keys: 'Workspace.Gravity', 'Lighting.ClockTime', etc."),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.action === "settings_get") {
        const result = (await bridge.send("workspace_settings", {
          action: "get",
        })) as { settings: Record<string, unknown> };

        const lines = ["**Current Settings:**", ""];
        for (const [k, v] of Object.entries(result.settings)) {
          lines.push(`- **${k}** = \`${JSON.stringify(v)}\``);
        }
        return { content: [{ type: "text", text: lines.join("\n") }] };
      }

      if (params.action === "settings_set") {
        if (!params.settings) {
          return { content: [{ type: "text", text: "settings_set requires a `settings` object." }] };
        }
        const result = (await bridge.send("workspace_settings", {
          action: "set",
          settings: params.settings,
        })) as { modified?: string[] };

        const text = `Updated ${result.modified?.length ?? 0} setting(s): ${result.modified?.join(", ") ?? "none"}`;
        return { content: [{ type: "text", text }] };
      }

      // Terrain actions — map to the existing terrain command names
      const terrainAction = params.action.replace("terrain_", "");
      const result = (await bridge.send("terrain", {
        action: terrainAction,
        region: params.region,
        material: params.material,
        size: params.size,
      })) as {
        status?: string;
        material?: string;
        region?: unknown;
        resolution?: number;
        totalVoxels?: number;
        filledVoxels?: number;
        materials?: Record<string, number>;
      };

      let text: string;
      if (terrainAction === "read" && result.materials) {
        const data = {
          region: result.region,
          resolution: result.resolution,
          totalVoxels: result.totalVoxels,
          filledVoxels: result.filledVoxels,
          materials: result.materials,
        };
        text = `**Terrain data:**\n\`\`\`json\n${JSON.stringify(data, null, 2)}\n\`\`\``;
        text = applyTokenBudget(text, undefined);
      } else {
        text = `Terrain ${terrainAction}: ${result.status}`;
      }

      return { content: [{ type: "text", text }] };
    },
  );
}
