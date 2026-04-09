import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import {
  formatTree,
  formatInstanceList,
  applyTokenBudget,
} from "../utils/formatting.js";

export function register(server: McpServer, bridge: Bridge): void {
  // ── explore ───────────────────────────────────────────────────────
  server.registerTool(
    "explore",
    {
      title: "Explore Instance Tree",
      description:
        "Browse the Roblox instance hierarchy, get/set the current selection, or list top-level services.\n\n" +
        "Actions:\n" +
        "- `tree` (default): Browse DataModel tree from a root path with depth, filter, and property options.\n" +
        "- `get_selection`: Return the currently selected instances in Studio.\n" +
        "- `set_selection`: Select specific instances in Studio by path.\n" +
        "- `services`: List all top-level game services.\n" +
        "- `state`: Get current Studio state (playtest status, place info, undo availability).",
      inputSchema: z.object({
        action: z
          .enum(["tree", "get_selection", "set_selection", "services", "state"])
          .default("tree")
          .describe("Action to perform"),
        path: z
          .string()
          .default("game")
          .describe("Root path to explore (for 'tree' action)"),
        depth: z
          .number()
          .int()
          .min(0)
          .max(10)
          .default(2)
          .describe("How many levels deep to recurse (for 'tree' action)"),
        filter: z
          .string()
          .optional()
          .describe("Only include instances whose ClassName matches (for 'tree' action)"),
        includeProperties: z
          .boolean()
          .default(false)
          .describe("Include property values in output (for 'tree' action)"),
        paths: z
          .array(z.string())
          .optional()
          .describe("Instance paths to select (for 'set_selection' action)"),
        maxTokens: z
          .number()
          .optional()
          .describe("Maximum token budget for the response"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.action === "get_selection") {
        const result = (await bridge.send("get_selection", {})) as {
          selection: Array<{ path: string; className: string }>;
        };
        const text = formatInstanceList(result.selection);
        return {
          content: [
            { type: "text", text: applyTokenBudget(text, params.maxTokens) },
          ],
        };
      }

      if (params.action === "set_selection") {
        if (!params.paths || params.paths.length === 0) {
          return {
            content: [
              { type: "text", text: "set_selection requires a non-empty `paths` array." },
            ],
          };
        }
        const result = (await bridge.send("set_selection", {
          paths: params.paths,
        })) as { selected: number };
        return {
          content: [
            { type: "text", text: `Selected ${result.selected} instance(s).` },
          ],
        };
      }

      if (params.action === "services") {
        const result = (await bridge.send("get_services", {})) as {
          services: Array<{ name: string; className: string }>;
        };
        const text =
          result.services.length === 0
            ? "*No services found.*"
            : result.services
                .map((s) => `- **${s.name}** \`${s.className}\``)
                .join("\n");
        return {
          content: [
            { type: "text", text: applyTokenBudget(text, params.maxTokens) },
          ],
        };
      }

      if (params.action === "state") {
        const result = (await bridge.send("get_studio_state", {})) as {
          isRunning: boolean;
          isClient: boolean;
          isServer: boolean;
          placeId: number;
          gameId: number;
          placeName?: string;
          canUndo?: boolean;
          canRedo?: boolean;
        };

        let mode = "Edit";
        if (result.isRunning) {
          if (result.isClient) mode = "Playtest (Client)";
          else if (result.isServer) mode = "Playtest (Server)";
          else mode = "Running";
        }

        const lines = [
          "### Studio State",
          `- **Mode:** ${mode}`,
          `- **Place ID:** ${result.placeId}${result.placeName ? ` — ${result.placeName}` : ""}`,
          `- **Game ID:** ${result.gameId}`,
        ];

        if (result.canUndo !== undefined) {
          lines.push(`- **Can Undo:** ${result.canUndo ? "Yes" : "No"}`);
        }
        if (result.canRedo !== undefined) {
          lines.push(`- **Can Redo:** ${result.canRedo ? "Yes" : "No"}`);
        }

        return {
          content: [{ type: "text", text: lines.join("\n") }],
        };
      }

      // Default: tree
      const result = await bridge.send("explore", {
        path: params.path,
        depth: params.depth,
        filter: params.filter,
        includeProperties: params.includeProperties,
      });
      const text = formatTree(result as any, params.depth);
      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );

  // ── get_info (merged get_instance_info + list_properties) ─────────
  server.registerTool(
    "get_info",
    {
      title: "Get Instance Info",
      description:
        "Get detailed information about a single instance: class, parent, children count, properties, attributes, tags, and optionally a typed property list — all in one call.\n\n" +
        "Use this to inspect runtime UI layout (Size, Position, Transparency, Visible, Text, etc.), part properties, lighting, sounds, and more. " +
        "Reads ~60 common properties automatically. Use `propertyNames` to request only specific properties for a leaner response.\n\n" +
        "For UI debugging: check BackgroundTransparency, Visible, Size, Position, AnchorPoint, ZIndex, LayoutOrder on GuiObjects.",
      inputSchema: z.object({
        path: z
          .string()
          .describe("Path to the instance, e.g. 'game.Workspace.Part'"),
        includeProperties: z
          .boolean()
          .default(true)
          .describe("Include property values (reads ~60 common properties)"),
        propertyNames: z
          .array(z.string())
          .optional()
          .describe(
            "Request only these specific properties by name, e.g. ['Size', 'Position', 'Transparency']. " +
            "When set, only these properties are returned (much leaner than the full property dump).",
          ),
        includeAttributes: z
          .boolean()
          .default(true)
          .describe("Include custom attributes"),
        includeTags: z
          .boolean()
          .default(true)
          .describe("Include CollectionService tags"),
        includePropertyList: z
          .boolean()
          .default(false)
          .describe("Include a typed list of all discoverable properties with types and values"),
        propertyFilter: z
          .string()
          .optional()
          .describe("Filter property names by substring match (for property list)"),
        maxTokens: z
          .number()
          .optional()
          .describe("Maximum token budget for the response"),
      }),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      const result = (await bridge.send("get_info", {
        path: params.path,
        includeProperties: params.includeProperties,
        propertyNames: params.propertyNames,
        includeAttributes: params.includeAttributes,
        includeTags: params.includeTags,
        includePropertyList: params.includePropertyList,
        propertyFilter: params.propertyFilter,
      })) as {
        name: string;
        className: string;
        path: string;
        parent: string | null;
        childCount: number;
        properties?: Record<string, unknown>;
        attributes?: Record<string, unknown>;
        tags?: string[];
        propertyList?: Array<{ name: string; type: string; value: unknown }>;
      };

      const lines: string[] = [
        `### ${result.name} \`${result.className}\``,
        `- **Path:** \`${result.path}\``,
        `- **Parent:** ${result.parent ? `\`${result.parent}\`` : "none"}`,
        `- **Children:** ${result.childCount}`,
      ];

      if (result.tags && result.tags.length > 0) {
        lines.push(`- **Tags:** ${result.tags.join(", ")}`);
      }

      if (result.attributes && Object.keys(result.attributes).length > 0) {
        lines.push("", "**Attributes:**");
        for (const [k, v] of Object.entries(result.attributes)) {
          lines.push(`- ${k} = \`${JSON.stringify(v)}\``);
        }
      }

      if (result.properties && Object.keys(result.properties).length > 0) {
        lines.push("", "**Properties:**");
        for (const [k, v] of Object.entries(result.properties)) {
          lines.push(`- ${k} = \`${JSON.stringify(v)}\``);
        }
      }

      if (result.propertyList && result.propertyList.length > 0) {
        lines.push("", "**Property List:**");
        for (const p of result.propertyList) {
          lines.push(`- **${p.name}** \`${p.type}\` = \`${JSON.stringify(p.value)}\``);
        }
      }

      const text = lines.join("\n");
      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );
}
