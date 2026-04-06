import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { formatScript, applyTokenBudget } from "../utils/formatting.js";

export function registerReadOnly(server: McpServer, bridge: Bridge): void {
  registerReadScript(server, bridge);
}

export function register(server: McpServer, bridge: Bridge): void {
  registerReadScript(server, bridge);
  registerWriteTools(server, bridge);
}

function registerReadScript(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "read_script",
    {
      title: "Read Script Source",
      description:
        "Read the Lua source code of a script instance. Optionally restrict to a line range.",
      inputSchema: z.object({
        path: z.string().describe("Path to the script instance"),
        lineRange: z
          .object({
            start: z.number().int().min(1).describe("Start line (1-based)"),
            end: z.number().int().min(1).describe("End line (1-based, inclusive)"),
          })
          .optional()
          .describe("Optional line range to read"),
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
      if (params.lineRange && params.lineRange.end < params.lineRange.start) {
        return {
          content: [{ type: "text", text: "lineRange.end must be >= lineRange.start." }],
          isError: true,
        };
      }
      const result = (await bridge.send("read_script", {
        path: params.path,
        lineRange: params.lineRange,
      })) as { source: string };
      const text = formatScript(result.source, params.path);
      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );
}

function registerWriteTools(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "edit_script",
    {
      title: "Edit Script Source",
      description:
        "Edit the Lua source code of a script. Supports four modes: 'full' replaces the entire source, 'range' replaces specific line/column ranges, 'find_replace' does text find-and-replace on one script, and 'multi_replace' does find-and-replace across multiple scripts in one undoable operation.",
      inputSchema: z.object({
        path: z.string().describe("Path to the script instance"),
        mode: z
          .enum(["full", "range", "find_replace", "multi_replace"])
          .describe("Edit mode: full, range, find_replace, or multi_replace"),
        source: z
          .string()
          .optional()
          .describe("Complete new source (for 'full' mode)"),
        edits: z
          .array(
            z.object({
              startLine: z.number().int().describe("Start line (1-based)"),
              startColumn: z.number().int().describe("Start column (1-based)"),
              endLine: z.number().int().describe("End line (1-based)"),
              endColumn: z.number().int().describe("End column (1-based)"),
              text: z.string().describe("Replacement text"),
            }),
          )
          .optional()
          .describe("Range edits (for 'range' mode)"),
        find: z
          .string()
          .optional()
          .describe("Text or pattern to find (for 'find_replace' mode)"),
        replace: z
          .string()
          .optional()
          .describe("Replacement text (for 'find_replace' mode)"),
        regex: z
          .boolean()
          .optional()
          .describe("Treat 'find' as a Lua pattern (for 'find_replace' and 'multi_replace' modes)"),
        scripts: z
          .array(z.string())
          .optional()
          .describe("Array of script paths to apply find/replace across (for 'multi_replace' mode)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      // ── lineRange validation ──────────────────────────────────
      if (
        params.mode === "range" &&
        params.edits &&
        params.edits.some((e) => e.endLine < e.startLine)
      ) {
        return {
          content: [{ type: "text", text: "Range edit has endLine < startLine." }],
          isError: true,
        };
      }

      // ── mode-specific validation ──────────────────────────────
      if (params.mode === "full" && params.source === undefined) {
        return {
          content: [{ type: "text", text: "full mode requires a `source` parameter." }],
          isError: true,
        };
      }
      if (params.mode === "range" && (!params.edits || params.edits.length === 0)) {
        return {
          content: [{ type: "text", text: "range mode requires a non-empty `edits` array." }],
          isError: true,
        };
      }
      if (params.mode === "find_replace" && !params.find) {
        return {
          content: [{ type: "text", text: "find_replace mode requires a `find` parameter." }],
          isError: true,
        };
      }

      // ── multi_replace mode ────────────────────────────────────
      if (params.mode === "multi_replace") {
        if (!params.scripts || params.scripts.length === 0) {
          return { content: [{ type: "text", text: "multi_replace mode requires a non-empty `scripts` array." }] };
        }
        if (!params.find) {
          return { content: [{ type: "text", text: "multi_replace mode requires a `find` parameter." }] };
        }

        const result = (await bridge.send("multi_replace_scripts", {
          scripts: params.scripts,
          find: params.find,
          replace: params.replace ?? "",
          regex: params.regex,
        })) as {
          results: Array<{ path: string; replacements: number }>;
          totalReplacements: number;
          scriptsModified: number;
          errors?: Array<{ path: string; error: string }>;
        };

        const lines: string[] = [
          `**Multi-script find/replace** — ${result.totalReplacements} replacements across ${result.scriptsModified} script(s)`,
          "",
        ];

        for (const r of result.results) {
          lines.push(`- \`${r.path}\`: ${r.replacements} replacement(s)`);
        }

        if (result.errors && result.errors.length > 0) {
          lines.push("", "**Errors:**");
          for (const e of result.errors) {
            lines.push(`- \`${e.path}\`: ${e.error}`);
          }
        }

        return { content: [{ type: "text", text: lines.join("\n") }] };
      }

      const result = (await bridge.send("edit_script", {
        path: params.path,
        mode: params.mode,
        source: params.source,
        edits: params.edits,
        find: params.find,
        replace: params.replace,
        regex: params.regex,
      })) as {
        path: string;
        mode: string;
        success: boolean;
        totalLines: number;
        appliedEdits?: number;
        replacements?: number;
      };
      let detail = `mode=${result.mode}, ${result.totalLines} total lines`;
      if (result.appliedEdits !== undefined) {
        detail += `, ${result.appliedEdits} edits applied`;
      }
      if (result.replacements !== undefined) {
        detail += `, ${result.replacements} replacements`;
      }
      const text = `Script **${params.path}** updated (${detail}).`;
      return { content: [{ type: "text", text }] };
    },
  );

  server.registerTool(
    "execute_lua",
    {
      title: "Execute Luau Code",
      description:
        "Run arbitrary Luau code in the Studio plugin context (edit mode — no active playtest required). Use this as an escape hatch for any operation the other tools don't cover. Has access to all Studio APIs and services.",
      inputSchema: z.object({
        code: z
          .string()
          .describe("Luau code to execute"),
        maxTokens: z
          .number()
          .optional()
          .describe("Maximum token budget for the response"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    async (params) => {
      const result = (await bridge.send("execute_lua", {
        code: params.code,
      })) as {
        status: string;
        result?: string;
        error?: string;
        output?: Array<{ message: string; messageType: string }>;
      };

      const lines: string[] = [];
      if (result.error) {
        lines.push(`**Error:** ${result.error}`);
      }
      if (result.result) {
        lines.push(`**Return value:** ${result.result}`);
      }
      if (result.output && result.output.length > 0) {
        const outputText = result.output
          .map((o) => `[${o.messageType}] ${o.message}`)
          .join("\n");
        lines.push(`**Output:**\n\`\`\`\n${outputText}\n\`\`\``);
      }

      const text =
        lines.length > 0
          ? lines.join("\n\n")
          : `Execution completed (${result.status})`;

      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );
}
