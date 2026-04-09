import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { applyTokenBudget } from "../utils/formatting.js";

// Track playtest session start time so get_output can filter stale logs
let playtestStartedAt: number | null = null;

export function register(server: McpServer, bridge: Bridge): void {
  server.registerTool(
    "playtest",
    {
      title: "Playtest Control & Virtual Input",
      description:
        "Control Roblox Studio playtesting and simulate user input.\n\n" +
        "Actions:\n" +
        "- `start`: Begin a playtest session. Defaults to Play mode (F5, full client with player character). Set mode='run' for Run mode (F8, server-only, no player).\n" +
        "- `stop`: End the current playtest.\n" +
        "- `execute`: Run Lua code in the running game context.\n" +
        "- `get_output`: Get console/log output from Studio (works in edit mode and during playtest).\n" +
        "- `inspect`: Evaluate a Luau expression and return the typed result (requires active playtest).\n" +
        "- `navigate`: Walk the player character to a position using PathfindingService (requires client playtest).\n" +
        "- `mouse_click`: Simulate a mouse click at screen coordinates.\n" +
        "- `mouse_move`: Move the virtual mouse to screen coordinates.\n" +
        "- `key_press`: Press and release a key.\n" +
        "- `key_down`: Hold a key down.\n" +
        "- `key_up`: Release a held key.\n" +
        "- `screenshot`: Capture the viewport during playtest. Useful for seeing the game state visually.",
      inputSchema: z.object({
        action: z
          .enum(["start", "stop", "execute", "get_output", "inspect", "navigate", "mouse_click", "mouse_move", "key_press", "key_down", "key_up", "screenshot"])
          .describe("Playtest action"),
        mode: z
          .enum(["play", "run"])
          .default("play")
          .describe("Playtest mode: 'play' (F5, full client with player) or 'run' (F8, server-only). Default: play"),
        code: z
          .string()
          .optional()
          .describe("Lua code to execute (for 'execute' action)"),
        // get_output params
        messageTypes: z
          .array(z.string())
          .optional()
          .describe("Filter by message types: 'MessageOutput', 'MessageWarning', 'MessageError', 'MessageInfo' (for 'get_output')"),
        since: z
          .number()
          .optional()
          .describe("Only return logs with timestamp >= this value (for 'get_output')"),
        limit: z
          .number()
          .optional()
          .describe("Maximum number of log entries to return (for 'get_output')"),
        // inspect params
        expression: z
          .string()
          .optional()
          .describe("Luau expression to evaluate, e.g. 'game.Players.Player1.Character.Humanoid.Health' (for 'inspect')"),
        // navigate params
        target: z
          .object({
            x: z.number(),
            y: z.number(),
            z: z.number(),
          })
          .optional()
          .describe("Target position to navigate to (for 'navigate')"),
        targetPath: z
          .string()
          .optional()
          .describe("Instance path to navigate to — uses its Position (for 'navigate')"),
        timeout: z
          .number()
          .optional()
          .describe("Navigation timeout in seconds, default 15 (for 'navigate')"),
        // Virtual input params
        x: z.number().optional().describe("Screen X coordinate (for mouse actions)"),
        y: z.number().optional().describe("Screen Y coordinate (for mouse actions)"),
        button: z
          .enum(["Left", "Right", "Middle"])
          .default("Left")
          .describe("Mouse button (for 'mouse_click')"),
        key: z
          .string()
          .optional()
          .describe("Key name matching Enum.KeyCode, e.g. 'W', 'Space', 'Return' (for key actions)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    async (params) => {
      // ── get_output ──────────────────────────────────────────────
      if (params.action === "get_output") {
        // Auto-filter to current playtest session if no explicit `since` provided
        const since = params.since ?? playtestStartedAt ?? undefined;
        const result = (await bridge.send("get_log_output", {
          messageTypes: params.messageTypes,
          since,
          limit: params.limit,
        })) as {
          logs: Array<{ message: string; messageType: string; timestamp: number }>;
          total: number;
        };

        if (result.logs.length === 0) {
          return { content: [{ type: "text", text: "No log output found." }] };
        }

        const header = `**Console Output** (${result.logs.length}${result.logs.length < result.total ? ` of ${result.total}` : ""} entries)`;
        const logText = result.logs
          .map((l) => `[${l.messageType}] ${l.message}`)
          .join("\n");
        const text = `${header}\n\n\`\`\`\n${logText}\n\`\`\``;

        return {
          content: [{ type: "text", text: applyTokenBudget(text, undefined) }],
        };
      }

      // ── inspect ─────────────────────────────────────────────────
      if (params.action === "inspect") {
        if (!params.expression) {
          return {
            content: [{ type: "text", text: "inspect action requires an `expression` parameter." }],
          };
        }
        const result = (await bridge.send("playtest_inspect", {
          expression: params.expression,
        })) as {
          value: unknown;
          type: string;
          expression: string;
        };

        const valueStr = typeof result.value === "object"
          ? JSON.stringify(result.value, null, 2)
          : String(result.value);
        const text = `**Expression:** \`${result.expression}\`\n**Type:** \`${result.type}\`\n**Value:** ${valueStr}`;
        return { content: [{ type: "text", text }] };
      }

      // ── navigate ────────────────────────────────────────────────
      if (params.action === "navigate") {
        if (!params.target && !params.targetPath) {
          return {
            content: [{ type: "text", text: "navigate action requires either `target` or `targetPath`." }],
          };
        }
        const result = (await bridge.send("playtest_navigate", {
          target: params.target,
          targetPath: params.targetPath,
          timeout: params.timeout,
        })) as {
          status: string;
          position?: { x: number; y: number; z: number };
          message?: string;
        };

        const posStr = result.position
          ? `(${result.position.x.toFixed(1)}, ${result.position.y.toFixed(1)}, ${result.position.z.toFixed(1)})`
          : "unknown";
        const text = `**Navigation:** ${result.status}\n**Final position:** ${posStr}${result.message ? `\n${result.message}` : ""}`;
        return { content: [{ type: "text", text }] };
      }

      // ── screenshot ─────────────────────────────────────────────
      if (params.action === "screenshot") {
        const result = (await bridge.send("screenshot", {})) as {
          status: string;
          imageBase64?: string;
          mimeType?: string;
          message?: string;
        };

        if (result.imageBase64 && result.mimeType) {
          return {
            content: [
              {
                type: "image" as const,
                data: result.imageBase64,
                mimeType: result.mimeType,
              },
            ],
          };
        }

        return {
          content: [
            { type: "text", text: `Playtest screenshot: ${result.message ?? result.status}` },
          ],
        };
      }

      // ── virtual input ───────────────────────────────────────────
      if (
        params.action === "mouse_click" ||
        params.action === "mouse_move" ||
        params.action === "key_press" ||
        params.action === "key_down" ||
        params.action === "key_up"
      ) {
        if (
          (params.action === "mouse_click" || params.action === "mouse_move") &&
          (params.x === undefined || params.y === undefined)
        ) {
          return {
            content: [{ type: "text", text: `${params.action} requires \`x\` and \`y\` parameters.` }],
            isError: true,
          };
        }
        if (
          (params.action === "key_press" || params.action === "key_down" || params.action === "key_up") &&
          !params.key
        ) {
          return {
            content: [{ type: "text", text: `${params.action} requires a \`key\` parameter.` }],
            isError: true,
          };
        }
        const result = (await bridge.send("virtual_input", {
          action: params.action,
          x: params.x,
          y: params.y,
          button: params.button,
          key: params.key,
        })) as { status: string; message?: string };

        return {
          content: [
            { type: "text", text: result.message ?? `Virtual input ${params.action}: ${result.status}` },
          ],
        };
      }

      // ── execute validation ─────────────────────────────────────
      if (params.action === "execute" && !params.code) {
        return {
          content: [{ type: "text", text: "execute action requires a `code` parameter." }],
          isError: true,
        };
      }

      // Original playtest actions (start/stop/execute)
      const result = (await bridge.send("playtest", {
        action: params.action,
        code: params.code,
        mode: params.mode,
      })) as {
        status: string;
        mode?: string;
        message?: string;
        result?: string;
        error?: string;
        output?: Array<{ message: string; messageType: string }>;
      };

      // Track playtest session timing for log filtering
      if (params.action === "start" && result.status === "started") {
        playtestStartedAt = Date.now() / 1000; // LogService timestamps are in seconds
      } else if (params.action === "stop" && result.status === "stopped") {
        playtestStartedAt = null;
      }

      let text: string;
      if (params.action === "execute") {
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
        text =
          lines.length > 0
            ? lines.join("\n\n")
            : `Execution completed (${result.status})`;
        text = applyTokenBudget(text, undefined);
      } else {
        const modeInfo = result.mode ? ` (${result.mode} mode)` : "";
        const extra = result.message ? `\n${result.message}` : "";
        text = `Playtest ${params.action}${modeInfo}: ${result.status}${extra}`;
      }

      return { content: [{ type: "text", text }] };
    },
  );
}
