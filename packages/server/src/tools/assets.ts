import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { applyTokenBudget } from "../utils/formatting.js";

export function register(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "assets",
    {
      title: "Asset Search & Insert",
      description:
        "Search the Roblox asset catalog or insert assets by ID.\n\n" +
        "Actions:\n" +
        "- `search`: Search for models, meshes, images, audio.\n" +
        "- `insert`: Insert an asset into the game by ID.",
      inputSchema: z.object({
        action: z
          .enum(["search", "insert"])
          .describe("Asset action"),
        // Search params
        query: z
          .string()
          .optional()
          .describe("Search query (for 'search' action)"),
        category: z
          .string()
          .optional()
          .describe("Asset category: 'models', 'decals', 'images', etc. (for 'search')"),
        maxResults: z
          .number()
          .int()
          .default(10)
          .describe("Max search results (for 'search')"),
        // Insert params
        assetId: z
          .number()
          .int()
          .optional()
          .describe("Roblox asset ID (for 'insert' action)"),
        parent: z
          .string()
          .optional()
          .describe("Parent path to insert under (for 'insert' action)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    async (params) => {
      if (params.action === "insert") {
        if (!params.assetId) {
          return { content: [{ type: "text", text: "insert action requires an `assetId`." }] };
        }
        if (!params.parent) {
          return { content: [{ type: "text", text: "insert action requires a `parent` path." }] };
        }
        const result = (await bridge.send("insert_asset", {
          assetId: params.assetId,
          parent: params.parent,
        })) as {
          assetId: number;
          inserted: Array<{ path: string; className: string; name: string }>;
        };
        const text =
          result.inserted.length === 1
            ? `Inserted asset **${params.assetId}** at \`${result.inserted[0].path}\``
            : `Inserted asset **${params.assetId}**:\n` +
              result.inserted
                .map((i) => `- \`${i.path}\` (${i.className})`)
                .join("\n");
        return { content: [{ type: "text", text }] };
      }

      // Default: search
      if (!params.query) {
        return { content: [{ type: "text", text: "search action requires a `query`." }] };
      }
      const result = (await bridge.send("search_assets", {
        query: params.query,
        category: params.category,
        maxResults: params.maxResults,
      })) as {
        results: Array<{ assetId: number; name: string; creatorName: string }>;
      };

      let text: string;
      if (result.results.length === 0) {
        text = "*No assets found matching your query.*";
      } else {
        text = result.results
          .map((a) => `- **${a.name}** (ID: ${a.assetId}) by ${a.creatorName}`)
          .join("\n");
      }
      return {
        content: [{ type: "text", text: applyTokenBudget(text, undefined) }],
      };
    },
  );
}
