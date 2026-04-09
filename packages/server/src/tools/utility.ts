import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { applyTokenBudget } from "../utils/formatting.js";
import { searchApi, formatSearchResults } from "../context/api-index.js";

export function register(server: McpServer, bridge: Bridge): void {
  const transactionState = new Map<string, boolean>();

  // If Studio disconnects, its transaction state is wiped — remove the entry
  bridge.on("studio-disconnected", (info: { studioId: string }) => {
    transactionState.delete(info.studioId);
  });
  server.registerTool(
    "undo_redo",
    {
      title: "Undo / Redo",
      description:
        "Trigger undo or redo in Roblox Studio's change history. Supports repeating multiple times with the count parameter.",
      inputSchema: z.object({
        action: z
          .enum(["undo", "redo"])
          .describe("Whether to undo or redo"),
        count: z
          .number()
          .int()
          .min(1)
          .default(1)
          .describe("Number of times to repeat the action"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      const result = (await bridge.send("undo_redo", {
        action: params.action,
        count: params.count,
      })) as { status: string; count: number };
      const text = `${params.action === "undo" ? "Undo" : "Redo"} x${result.count}: ${result.status}`;
      return { content: [{ type: "text", text }] };
    },
  );

  server.registerTool(
    "screenshot",
    {
      title: "Take Screenshot",
      description:
        "Capture a screenshot of the current Roblox Studio viewport. Works in both edit mode and during playtest.\n\n" +
        "The screenshot is saved to the user's Roblox screenshots folder. Base64 image data is returned when the EditableImage API is available (Roblox platform limitation).\n\n" +
        "Tip: During playtest, use this to capture the game viewport. Combine with `playtest start` + a short delay via `playtest execute` (e.g. `task.wait(2)`) to capture after the game loads.",
      inputSchema: z.object({}),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
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
          { type: "text", text: `Screenshot: ${result.message ?? result.status}` },
        ],
      };
    },
  );

  server.registerTool(
    "lookup_api",
    {
      title: "Lookup Roblox API",
      description:
        "Search the Roblox engine API reference for classes, properties, methods, events, and enums. Runs locally — no Studio connection required.",
      inputSchema: z.object({
        query: z
          .string()
          .describe("Search query, e.g. 'BasePart', 'Touched', 'TweenService'"),
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
      const results = searchApi(params.query);
      const text = formatSearchResults(results);
      return {
        content: [
          { type: "text", text: applyTokenBudget(text, params.maxTokens) },
        ],
      };
    },
  );

  server.registerTool(
    "transaction",
    {
      title: "Transaction Control",
      description:
        "Group multiple tool calls into a single Ctrl+Z undo point — essential when making several related edits that the user should be able to revert together.\n\n" +
        "**When to use:** Before starting a multi-edit session (e.g. refactoring across scripts, creating multiple instances, UI changes). " +
        "Call `begin`, make all your changes, then `commit`. The user can undo everything in one Ctrl+Z.\n\n" +
        "Actions:\n" +
        "- `begin`: Start a transaction. All subsequent writes share one undo recording.\n" +
        "- `commit`: Finish and commit all changes as one undo point.\n" +
        "- `rollback`: Cancel and revert all changes since begin.\n\n" +
        "Transactions auto-rollback after 60 seconds if not committed.",
      inputSchema: z.object({
        action: z
          .enum(["begin", "commit", "rollback"])
          .describe("Transaction action"),
        name: z
          .string()
          .optional()
          .describe("Transaction name for the undo history (for 'begin' action)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (params) => {
      const studioId = bridge.getActiveStudioId() ?? "_default";

      if (params.action === "begin") {
        try {
          const result = (await bridge.send("begin_transaction", {
            name: params.name,
          })) as { transactionId: string; status: string };
          transactionState.set(studioId, true);
          return {
            content: [
              { type: "text", text: `Transaction started: **${result.transactionId}**\nAll subsequent writes will be grouped into one undo point. Call commit or rollback to finish.` },
            ],
          };
        } catch (err: unknown) {
          transactionState.set(studioId, false);
          throw err;
        }
      }

      if (!transactionState.get(studioId)) {
        return {
          content: [
            { type: "text", text: `No active transaction. Call \`begin\` first before calling \`${params.action}\`.` },
          ],
        };
      }

      if (params.action === "commit") {
        try {
          const result = (await bridge.send("commit_transaction", {})) as {
            status: string;
          };
          return {
            content: [
              { type: "text", text: `Transaction ${result.status}. All changes are now a single undo point.` },
            ],
          };
        } finally {
          transactionState.set(studioId, false);
        }
      }

      // rollback
      try {
        const result = (await bridge.send("rollback_transaction", {})) as {
          status: string;
        };
        return {
          content: [
            { type: "text", text: `Transaction ${result.status}. All changes since begin have been reverted.` },
          ],
        };
      } finally {
        transactionState.set(studioId, false);
      }
    },
  );
}
