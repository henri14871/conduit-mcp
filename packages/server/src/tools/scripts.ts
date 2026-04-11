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
        "Read the Lua source code of a script instance. Optionally restrict to a line range. Use outline=true to get just function signatures and top-level declarations with line numbers — much cheaper than reading the full source for large scripts.\n\n" +
        "Supports batch mode: pass `paths` (array) instead of `path` to read multiple scripts in a single call. Each entry can independently use outline or lineRange.",
      inputSchema: z.object({
        path: z.string().optional().describe("Path to a single script instance"),
        paths: z
          .array(
            z.object({
              path: z.string().describe("Script path"),
              outline: z.boolean().default(false).describe("Return outline instead of source"),
              lineRange: z
                .object({
                  start: z.number().int().min(1).describe("Start line (1-based)"),
                  end: z.number().int().min(1).describe("End line (1-based, inclusive)"),
                })
                .optional()
                .describe("Optional line range"),
            }),
          )
          .optional()
          .describe("Batch mode: read multiple scripts in one call. Each entry can independently use outline or lineRange."),
        outline: z
          .boolean()
          .default(false)
          .describe(
            "If true, return only a structural outline (function signatures, top-level locals, types, return) with line numbers instead of full source. Ideal for navigating large scripts.",
          ),
        lineRange: z
          .object({
            start: z.number().int().min(1).describe("Start line (1-based)"),
            end: z.number().int().min(1).describe("End line (1-based, inclusive)"),
          })
          .optional()
          .describe("Optional line range to read (ignored when outline=true)"),
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
      // ── batch mode ────────────────────────────────────────────
      if (params.paths && params.paths.length > 0) {
        const result = (await bridge.send("batch_read_scripts", {
          scripts: params.paths,
        })) as {
          results: Array<{
            path: string;
            source?: string;
            totalLines: number;
            lineRange?: { start: number; end: number };
            outline?: Array<{ line: number; text: string; kind: string; indent: number }>;
          }>;
          errors?: Array<{ path: string; error: string }>;
        };

        const sections: string[] = [];

        for (const r of result.results) {
          if (r.outline) {
            const lines = [`### Outline: \`${r.path}\` (${r.totalLines} lines)`, ""];
            for (const entry of r.outline) {
              const pad = " ".repeat(entry.indent);
              lines.push(`${entry.line}: ${pad}${entry.text}`);
            }
            if (r.outline.length === 0) {
              lines.push("*No functions, type definitions, or top-level declarations found.*");
            }
            sections.push(lines.join("\n"));
          } else {
            sections.push(formatScript(r.source ?? "", r.path));
          }
        }

        if (result.errors && result.errors.length > 0) {
          const errLines = ["**Errors:**"];
          for (const e of result.errors) {
            errLines.push(`- \`${e.path}\`: ${e.error}`);
          }
          sections.push(errLines.join("\n"));
        }

        const text = sections.join("\n\n---\n\n");
        return {
          content: [
            { type: "text", text: applyTokenBudget(text, params.maxTokens) },
          ],
        };
      }

      // ── single-script modes require path ────────────────────
      if (!params.paths && !params.path) {
        return {
          content: [{ type: "text", text: "Provide either `path` (single script) or `paths` (batch read)." }],
          isError: true,
        };
      }

      const path = params.path!;

      // ── outline mode ──────────────────────────────────────────
      if (params.outline) {
        const result = (await bridge.send("outline_script", {
          path,
        })) as {
          path: string;
          totalLines: number;
          outline: Array<{
            line: number;
            text: string;
            kind: string;
            indent: number;
          }>;
        };

        const lines: string[] = [
          `### Outline: \`${result.path}\` (${result.totalLines} lines)`,
          "",
        ];

        for (const entry of result.outline) {
          const pad = " ".repeat(entry.indent);
          lines.push(`${entry.line}: ${pad}${entry.text}`);
        }

        if (result.outline.length === 0) {
          lines.push("*No functions, type definitions, or top-level declarations found.*");
        }

        const text = lines.join("\n");
        return {
          content: [
            { type: "text", text: applyTokenBudget(text, params.maxTokens) },
          ],
        };
      }

      // ── full read mode ────────────────────────────────────────
      if (params.lineRange && params.lineRange.end < params.lineRange.start) {
        return {
          content: [{ type: "text", text: "lineRange.end must be >= lineRange.start." }],
          isError: true,
        };
      }
      const result = (await bridge.send("read_script", {
        path,
        lineRange: params.lineRange,
      })) as { source: string };
      const text = formatScript(result.source, path);
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
        "Edit the Lua source code of a script. Supports five modes:\n" +
        "- 'full': Replace entire source.\n" +
        "- 'range': Replace specific line/column ranges.\n" +
        "- 'find_replace': Text find-and-replace on one script.\n" +
        "- 'multi_replace': Same find-and-replace across multiple scripts.\n" +
        "- 'batch': Different find-and-replace edits across different scripts in one atomic operation. Use this when you need different changes in different scripts.\n\n" +
        "Tip: Wrap multiple edits in a transaction (begin/commit) to group them into a single Ctrl+Z undo point.",
      inputSchema: z.object({
        path: z.string().optional().describe("Path to the script instance (not needed for 'multi_replace' or 'batch' modes)"),
        mode: z
          .enum(["full", "range", "find_replace", "multi_replace", "batch"])
          .describe("Edit mode"),
        source: z
          .string()
          .optional()
          .describe("Complete new source (for 'full' mode)"),
        edits: z
          .array(
            z.object({
              startLine: z.number().int().describe("Start line (1-based)"),
              startColumn: z.number().int().default(1).describe("Start column (1-based, default: 1)"),
              endLine: z.number().int().describe("End line (1-based)"),
              endColumn: z.number().int().optional().describe("End column (1-based, default: end of line). Omit to replace through end of endLine."),
              text: z.string().describe("Replacement text"),
            }),
          )
          .optional()
          .describe("Range edits (for 'range' mode). Edits replace from startLine:startColumn through endLine:endColumn. Omitting endColumn replaces through end of endLine."),
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
        batch: z
          .array(
            z.object({
              path: z.string().describe("Script path"),
              source: z.string().optional().describe("Complete new source (for full replacement). Mutually exclusive with find/replace."),
              find: z.string().optional().describe("Text or pattern to find"),
              replace: z.string().default("").describe("Replacement text (used with find)"),
              regex: z.boolean().default(false).describe("Treat find as a Lua pattern (used with find)"),
            }),
          )
          .optional()
          .describe(
            "Array of per-script edit operations (for 'batch' mode). Each entry can either use `source` for full replacement or `find`/`replace` for targeted edits.",
          ),
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

      // ── batch mode (different edits per script) ──────────────
      if (params.mode === "batch") {
        if (!params.batch || params.batch.length === 0) {
          return {
            content: [{ type: "text", text: "batch mode requires a non-empty `batch` array." }],
            isError: true,
          };
        }

        // Validate each entry has either source or find, not both
        for (const entry of params.batch) {
          if (entry.source !== undefined && entry.find !== undefined) {
            return {
              content: [{ type: "text", text: `Batch entry for \`${entry.path}\`: provide either \`source\` or \`find\`, not both.` }],
              isError: true,
            };
          }
          if (entry.source === undefined && entry.find === undefined) {
            return {
              content: [{ type: "text", text: `Batch entry for \`${entry.path}\`: must provide either \`source\` (full replacement) or \`find\` (find/replace).` }],
              isError: true,
            };
          }
        }

        const result = (await bridge.send("batch_edit_scripts", {
          edits: params.batch,
        })) as {
          results: Array<{ path: string; success: boolean; mode: string; replacements?: number }>;
          scriptsModified: number;
          errors?: Array<{ path: string; error: string }>;
        };

        const lines: string[] = [
          `**Batch edit** — ${result.scriptsModified} script(s) modified`,
          "",
        ];

        for (const r of result.results) {
          if (r.success) {
            if (r.mode === "full") {
              lines.push(`- \`${r.path}\`: full source replaced`);
            } else {
              lines.push(`- \`${r.path}\`: ${r.replacements ?? 0} replacement(s)`);
            }
          }
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
