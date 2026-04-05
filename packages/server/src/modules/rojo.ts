import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { log } from "../utils/logger.js";

const execFileAsync = promisify(execFile);

async function runRojo(
  args: string[],
  cwd?: string,
): Promise<{ stdout: string; stderr: string }> {
  try {
    return await execFileAsync("rojo", args, {
      cwd,
      timeout: 30_000,
    });
  } catch (err: any) {
    if (err.code === "ENOENT") {
      throw new Error(
        "rojo command not found. Install it with: cargo install rojo, or via aftman/foreman.",
      );
    }
    throw new Error(`rojo ${args.join(" ")} failed: ${err.stderr || err.message}`);
  }
}

export function register(server: McpServer): void {
  server.registerTool(
    "rojo",
    {
      title: "Rojo Integration",
      description:
        "Interact with Rojo for filesystem <-> Studio syncing. Requires `rojo` on PATH.\n\n" +
        "Actions:\n" +
        "- `sourcemap`: Generate a sourcemap JSON showing Studio <-> filesystem mapping.\n" +
        "- `build`: Build a .rbxm/.rbxmx/.rbxl file from a Rojo project.\n" +
        "- `version`: Show installed Rojo version.",
      inputSchema: z.object({
        action: z
          .enum(["sourcemap", "build", "version"])
          .describe("Rojo action"),
        project: z
          .string()
          .optional()
          .describe("Path to .project.json file (defaults to default.project.json in cwd)"),
        output: z
          .string()
          .optional()
          .describe("Output file path (for 'build' action)"),
      }),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (params) => {
      if (params.action === "version") {
        const { stdout } = await runRojo(["--version"]);
        return {
          content: [{ type: "text", text: stdout.trim() }],
        };
      }

      if (params.action === "sourcemap") {
        const args = ["sourcemap"];
        if (params.project) {
          args.push(params.project);
        }
        args.push("--output", "-"); // Output to stdout
        const { stdout } = await runRojo(args);
        try {
          const sourcemap = JSON.parse(stdout);
          const summary = formatSourcemap(sourcemap);
          return {
            content: [{ type: "text", text: summary }],
          };
        } catch {
          return {
            content: [{ type: "text", text: `**Raw sourcemap:**\n\`\`\`json\n${stdout}\n\`\`\`` }],
          };
        }
      }

      if (params.action === "build") {
        if (!params.output) {
          return {
            content: [{ type: "text", text: "build action requires an `output` path." }],
          };
        }
        const args = ["build"];
        if (params.project) {
          args.push(params.project);
        }
        args.push("--output", params.output);
        const { stdout, stderr } = await runRojo(args);
        const message = stdout || stderr || "Build completed.";
        return {
          content: [
            { type: "text", text: `Rojo build complete: **${params.output}**\n${message.trim()}` },
          ],
        };
      }

      return { content: [{ type: "text", text: "Unknown rojo action." }] };
    },
  );
}

function formatSourcemap(sourcemap: any, depth = 0, indent = ""): string {
  if (!sourcemap || !sourcemap.name) return "";

  let line = `${indent}- **${sourcemap.name}** \`${sourcemap.className ?? ""}\``;
  if (sourcemap.filePaths && sourcemap.filePaths.length > 0) {
    line += ` → ${sourcemap.filePaths[0]}`;
  }

  let result = line + "\n";

  if (sourcemap.children && depth < 3) {
    for (const child of sourcemap.children) {
      result += formatSourcemap(child, depth + 1, indent + "  ");
    }
  } else if (sourcemap.children && sourcemap.children.length > 0) {
    result += `${indent}  *… ${sourcemap.children.length} children*\n`;
  }

  return result;
}
