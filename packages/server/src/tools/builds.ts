import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { saveBuild, loadBuild, listBuilds } from "../utils/builds.js";

export function register(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "builds",
    {
      title: "Build Library",
      description:
        "Export, import, or list reusable instance trees (build library).\n\n" +
        "Actions:\n" +
        "- `export`: Serialize an instance tree and save it as a named build.\n" +
        "- `import`: Reconstruct a saved build under a target parent.\n" +
        "- `list`: List all saved builds.",
      inputSchema: z.object({
        action: z
          .enum(["export", "import", "list"])
          .describe("Build library action"),
        // Export params
        path: z
          .string()
          .optional()
          .describe("Path to instance to export (for 'export' action)"),
        name: z
          .string()
          .optional()
          .describe("Build name (for 'export' and 'import' actions)"),
        description: z
          .string()
          .optional()
          .describe("Build description (for 'export' action)"),
        // Import params
        targetParent: z
          .string()
          .optional()
          .describe("Parent path to import under (for 'import' action)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.action === "list") {
        const builds = listBuilds();
        if (builds.length === 0) {
          return {
            content: [
              { type: "text", text: "*No builds saved. Use `builds --action export` to save one.*" },
            ],
          };
        }
        const lines = builds.map(
          (b) =>
            `- **${b.name}** \`${b.rootClassName}\` (${b.childCount} children) — ${b.createdAt}${b.description ? `\n  ${b.description}` : ""}`,
        );
        return {
          content: [{ type: "text", text: lines.join("\n") }],
        };
      }

      if (params.action === "export") {
        if (!params.path) {
          return { content: [{ type: "text", text: "export action requires a `path`." }] };
        }
        if (!params.name) {
          return { content: [{ type: "text", text: "export action requires a `name`." }] };
        }

        // Ask plugin to serialize the instance tree
        const serialized = await bridge.send("export_build", {
          path: params.path,
        });

        const meta = saveBuild(params.name, serialized, params.description);
        return {
          content: [
            {
              type: "text",
              text: `Build **${meta.name}** saved.\n- Root: \`${meta.rootClassName}\`\n- Children: ${meta.childCount}\n- Created: ${meta.createdAt}`,
            },
          ],
        };
      }

      if (params.action === "import") {
        if (!params.name) {
          return { content: [{ type: "text", text: "import action requires a `name`." }] };
        }
        if (!params.targetParent) {
          return { content: [{ type: "text", text: "import action requires a `targetParent`." }] };
        }

        const build = loadBuild(params.name);

        const result = (await bridge.send("import_build", {
          tree: build.root,
          targetParent: params.targetParent,
        })) as { path: string; className: string; childCount: number };

        return {
          content: [
            {
              type: "text",
              text: `Build **${params.name}** imported at \`${result.path}\` (${result.className}, ${result.childCount} children).`,
            },
          ],
        };
      }

      return { content: [{ type: "text", text: "Unknown builds action." }] };
    },
  );
}
