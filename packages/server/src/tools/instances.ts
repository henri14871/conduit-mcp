import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { applyTokenBudget } from "../utils/formatting.js";

export function registerReadOnly(server: McpServer, bridge: Bridge): void {
  registerQuery(server, bridge);
}

export function register(server: McpServer, bridge: Bridge): void {
  registerQuery(server, bridge);
  registerWrite(server, bridge);
}

function registerQuery(server: McpServer, bridge: Bridge): void {
  // ── query (merged query_instances + grep_scripts) ─────────────────
  server.registerTool(
    "query",
    {
      title: "Query Instances & Scripts",
      description:
        "Find instances or search script source code.\n\n" +
        "Actions:\n" +
        "- `instances` (default): Find instances by class, tag, attribute, or name pattern.\n" +
        "- `scripts`: Search across all script sources for a text pattern (grep).",
      inputSchema: z.object({
        action: z
          .enum(["instances", "scripts"])
          .default("instances")
          .describe("Query mode"),
        // Instance query params
        basePath: z
          .string()
          .default("game")
          .describe("Root path to search from"),
        filters: z
          .object({
            className: z.string().optional().describe("Only include instances of this class"),
            tag: z.string().optional().describe("Only include instances with this tag"),
            attribute: z
              .object({
                name: z.string().describe("Attribute name"),
                value: z.unknown().optional().describe("Required attribute value"),
              })
              .optional()
              .describe("Filter by attribute"),
            namePattern: z
              .string()
              .optional()
              .describe("Lua pattern to match against instance Name"),
          })
          .optional()
          .describe("Filters for instance query (AND-combined)"),
        limit: z.number().int().default(50).describe("Max results"),
        // Script grep params
        pattern: z.string().optional().describe("Text pattern to search for (for 'scripts' action)"),
        caseSensitive: z
          .boolean()
          .default(false)
          .describe("Case-sensitive search (for 'scripts' action)"),
        contextLines: z
          .number()
          .int()
          .default(1)
          .describe("Lines of context around each match (for 'scripts' action)"),
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
      if (params.action === "scripts") {
        if (!params.pattern) {
          return {
            content: [{ type: "text", text: "scripts action requires a `pattern` parameter." }],
          };
        }
        const result = (await bridge.send("grep_scripts", {
          basePath: params.basePath,
          pattern: params.pattern,
          caseSensitive: params.caseSensitive,
          contextLines: params.contextLines,
          limit: params.limit,
        })) as {
          results: Array<{
            scriptPath: string;
            lineNumber: number;
            line: string;
            context: string[];
          }>;
          totalMatches: number;
          scriptsSearched: number;
        };

        if (result.results.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: `*No matches found for "${params.pattern}" across ${result.scriptsSearched} scripts.*`,
              },
            ],
          };
        }

        const lines = result.results.map(
          (r) => `- \`${r.scriptPath}:${r.lineNumber}\`: ${r.line.trim()}`,
        );
        let text = lines.join("\n");
        if (result.totalMatches > result.results.length) {
          text += `\n\n*Showing ${result.results.length} of ${result.totalMatches} matches across ${result.scriptsSearched} scripts.*`;
        } else {
          text += `\n\n*${result.totalMatches} match(es) across ${result.scriptsSearched} scripts.*`;
        }

        return {
          content: [
            { type: "text", text: applyTokenBudget(text, params.maxTokens) },
          ],
        };
      }

      // Default: instances
      const result = (await bridge.send("query_instances", {
        basePath: params.basePath,
        filters: params.filters ?? {},
        limit: params.limit,
      })) as {
        results: Array<{ path: string; className: string; name: string }>;
        total: number;
      };

      let text: string;
      if (result.results.length === 0) {
        text = "*No instances matched the query.*";
      } else {
        const lines = result.results.map(
          (r) => `- \`${r.path}\` (${r.className})`,
        );
        text = lines.join("\n");
        if (result.total > result.results.length) {
          text += `\n\n*Showing ${result.results.length} of ${result.total} matches — increase limit or narrow filters.*`;
        }
      }

      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );
}

function registerWrite(server: McpServer, bridge: Bridge): void {
  // ── create (merged create_instances + clone_instances) ────────────
  server.registerTool(
    "create",
    {
      title: "Create or Clone Instances",
      description:
        "Create new instances or clone existing ones.\n\n" +
        "Actions:\n" +
        "- `new` (default): Create instances with className, parent, name, and properties.\n" +
        "- `clone`: Clone existing instances to a target parent.",
      inputSchema: z.object({
        action: z
          .enum(["new", "clone"])
          .default("new")
          .describe("Create mode"),
        // For 'new' action
        operations: z
          .array(
            z.object({
              className: z.string().describe("Roblox class, e.g. 'Part'"),
              parent: z.string().describe("Parent path, e.g. 'game.Workspace'"),
              name: z.string().describe("Instance name"),
              properties: z.record(z.unknown()).optional().describe("Initial properties"),
            }),
          )
          .optional()
          .describe("Instances to create (for 'new' action)"),
        // For 'clone' action
        sources: z
          .array(z.string())
          .optional()
          .describe("Paths of instances to clone (for 'clone' action)"),
        targetParent: z
          .string()
          .optional()
          .describe("Parent to place clones under (for 'clone' action)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.action === "clone") {
        if (!params.sources || params.sources.length === 0) {
          return { content: [{ type: "text", text: "clone action requires a non-empty `sources` array." }] };
        }
        if (!params.targetParent) {
          return { content: [{ type: "text", text: "clone action requires a `targetParent`." }] };
        }
        const result = (await bridge.send("clone_instances", {
          sources: params.sources,
          targetParent: params.targetParent,
        })) as {
          cloned: Array<{ path: string; className: string; name: string }>;
        };
        const text = result.cloned
          .map((r) => `- \`${r.path}\` (${r.className})`)
          .join("\n");
        return { content: [{ type: "text", text }] };
      }

      // Default: new
      if (!params.operations || params.operations.length === 0) {
        return { content: [{ type: "text", text: "new action requires a non-empty `operations` array." }] };
      }
      const result = (await bridge.send("create_instances", {
        operations: params.operations,
      })) as {
        created: Array<{ path: string; className: string; name: string }>;
      };
      const text = result.created
        .map((r) => `- \`${r.path}\` (${r.className})`)
        .join("\n");
      return { content: [{ type: "text", text }] };
    },
  );

  // ── modify (merged modify_instances + batch_modify) ───────────────
  server.registerTool(
    "modify",
    {
      title: "Modify Instances",
      description:
        "Modify existing instances.\n\n" +
        "Modes:\n" +
        "- `targeted` (default): Per-instance modifications with properties, attributes, tags, name, parent.\n" +
        "- `bulk`: Set one property to the same value across many instances.",
      inputSchema: z.object({
        mode: z
          .enum(["targeted", "bulk"])
          .default("targeted")
          .describe("Modification mode"),
        // For 'targeted' mode
        operations: z
          .array(
            z.object({
              path: z.string().describe("Path to instance"),
              properties: z.record(z.unknown()).optional().describe("Properties to set"),
              attributes: z.record(z.unknown()).optional().describe("Attributes to set"),
              tags: z
                .object({
                  add: z.array(z.string()).optional().describe("Tags to add"),
                  remove: z.array(z.string()).optional().describe("Tags to remove"),
                })
                .optional()
                .describe("Tag modifications"),
              name: z.string().optional().describe("New name"),
              parent: z.string().optional().describe("New parent path"),
            }),
          )
          .optional()
          .describe("Per-instance modifications (for 'targeted' mode)"),
        // For 'bulk' mode
        paths: z
          .array(z.string())
          .optional()
          .describe("Instance paths (for 'bulk' mode)"),
        property: z
          .string()
          .optional()
          .describe("Property name (for 'bulk' mode)"),
        value: z.unknown().optional().describe("Property value (for 'bulk' mode)"),
        strict: z
          .boolean()
          .default(false)
          .describe("If true, any single failure rolls back the entire batch (for 'bulk' mode)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.mode === "bulk") {
        if (!params.paths || params.paths.length === 0) {
          return { content: [{ type: "text", text: "bulk mode requires a non-empty `paths` array." }] };
        }
        if (!params.property) {
          return { content: [{ type: "text", text: "bulk mode requires a `property` name." }] };
        }
        const result = (await bridge.send("batch_modify", {
          paths: params.paths,
          property: params.property,
          value: params.value,
          strict: params.strict,
        })) as {
          modified: number;
          failed: Array<{ path: string; error: string }>;
        };

        let text = `Modified **${params.property}** on ${result.modified} instance(s).`;
        if (result.failed.length > 0) {
          text +=
            "\n\nFailed:\n" +
            result.failed.map((f) => `- \`${f.path}\`: ${f.error}`).join("\n");
        }
        return { content: [{ type: "text", text }] };
      }

      // Default: targeted
      if (!params.operations || params.operations.length === 0) {
        return { content: [{ type: "text", text: "targeted mode requires a non-empty `operations` array." }] };
      }
      const result = (await bridge.send("modify_instances", {
        operations: params.operations,
      })) as {
        modified: Array<{ path: string; modified: string[] }>;
      };
      const text = result.modified
        .map((r) => `- \`${r.path}\` — modified: ${r.modified.join(", ")}`)
        .join("\n");
      return { content: [{ type: "text", text }] };
    },
  );

  // ── delete ────────────────────────────────────────────────────────
  server.registerTool(
    "delete",
    {
      title: "Delete Instances",
      description:
        "Permanently delete one or more instances by path. Destructive — use undo_redo to revert.",
      inputSchema: z.object({
        paths: z
          .array(z.string())
          .describe("Paths of instances to delete"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      const result = (await bridge.send("delete_instances", {
        paths: params.paths,
      })) as { deleted: string[] };
      const text = result.deleted
        .map((p) => `- \`${p}\` — deleted`)
        .join("\n");
      return { content: [{ type: "text", text }] };
    },
  );
}
