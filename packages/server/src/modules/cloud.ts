import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { log } from "../utils/logger.js";

const BASE_URL = "https://apis.roblox.com";

function getApiKey(): string {
  const key = process.env.ROBLOX_CLOUD_API_KEY;
  if (!key) {
    throw new Error(
      "ROBLOX_CLOUD_API_KEY environment variable is not set. " +
        "Get an API key from https://create.roblox.com/credentials",
    );
  }
  return key;
}

async function cloudFetch(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<unknown> {
  const apiKey = getApiKey();
  const url = `${BASE_URL}${path}`;
  const res = await fetch(url, {
    method: options.method ?? "GET",
    headers: {
      "x-api-key": apiKey,
      "Content-Type": "application/json",
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Cloud API error ${res.status}: ${text}`);
  }

  const contentType = res.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    return res.json();
  }
  return res.text();
}

export function register(server: McpServer): void {
  server.registerTool(
    "cloud",
    {
      title: "Roblox Open Cloud",
      description:
        "Interact with the Roblox Open Cloud API. Requires ROBLOX_CLOUD_API_KEY env var.\n\n" +
        "Actions:\n" +
        "- `datastore_get`: Read a key from a standard datastore.\n" +
        "- `datastore_set`: Write a key to a standard datastore.\n" +
        "- `datastore_list`: List keys in a standard datastore.\n" +
        "- `messaging_publish`: Publish a message to a MessagingService topic.\n" +
        "- `place_info`: Get information about a place.",
      inputSchema: z.object({
        action: z
          .enum([
            "datastore_get",
            "datastore_set",
            "datastore_list",
            "messaging_publish",
            "place_info",
          ])
          .describe("Cloud API action"),
        universeId: z.number().int().describe("Roblox Universe ID"),
        // Datastore params
        datastoreName: z
          .string()
          .optional()
          .describe("Datastore name (for datastore actions)"),
        key: z
          .string()
          .optional()
          .describe("Datastore entry key (for get/set)"),
        value: z
          .unknown()
          .optional()
          .describe("Value to store (for datastore_set)"),
        scope: z
          .string()
          .optional()
          .describe("Datastore scope (optional, default 'global')"),
        prefix: z
          .string()
          .optional()
          .describe("Key prefix filter (for datastore_list)"),
        limit: z
          .number()
          .int()
          .default(10)
          .describe("Max results (for datastore_list)"),
        // Messaging params
        topic: z
          .string()
          .optional()
          .describe("MessagingService topic (for messaging_publish)"),
        message: z
          .string()
          .optional()
          .describe("Message to publish (for messaging_publish)"),
        // Place params
        placeId: z
          .number()
          .int()
          .optional()
          .describe("Place ID (for place_info)"),
      }),
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    async (params) => {
      const { universeId } = params;

      if (params.action === "datastore_get") {
        if (!params.datastoreName || !params.key) {
          return {
            content: [
              { type: "text", text: "datastore_get requires `datastoreName` and `key`." },
            ],
          };
        }
        const scope = params.scope ?? "global";
        const path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries/entry?datastoreName=${encodeURIComponent(params.datastoreName)}&entryKey=${encodeURIComponent(params.key)}&scope=${encodeURIComponent(scope)}`;
        const result = await cloudFetch(path);
        return {
          content: [
            {
              type: "text",
              text: `**${params.datastoreName}/${params.key}:**\n\`\`\`json\n${JSON.stringify(result, null, 2)}\n\`\`\``,
            },
          ],
        };
      }

      if (params.action === "datastore_set") {
        if (!params.datastoreName || !params.key) {
          return {
            content: [
              { type: "text", text: "datastore_set requires `datastoreName`, `key`, and `value`." },
            ],
          };
        }
        const scope = params.scope ?? "global";
        const path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries/entry?datastoreName=${encodeURIComponent(params.datastoreName)}&entryKey=${encodeURIComponent(params.key)}&scope=${encodeURIComponent(scope)}`;
        const result = await cloudFetch(path, {
          method: "POST",
          body: params.value,
        });
        return {
          content: [
            {
              type: "text",
              text: `Set **${params.datastoreName}/${params.key}** successfully.\n\`\`\`json\n${JSON.stringify(result, null, 2)}\n\`\`\``,
            },
          ],
        };
      }

      if (params.action === "datastore_list") {
        if (!params.datastoreName) {
          return {
            content: [
              { type: "text", text: "datastore_list requires `datastoreName`." },
            ],
          };
        }
        const scope = params.scope ?? "global";
        let path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries?datastoreName=${encodeURIComponent(params.datastoreName)}&scope=${encodeURIComponent(scope)}&limit=${params.limit}`;
        if (params.prefix) {
          path += `&prefix=${encodeURIComponent(params.prefix)}`;
        }
        const result = (await cloudFetch(path)) as { keys?: Array<{ key: string }> };
        const keys = result.keys?.map((k) => k.key) ?? [];
        return {
          content: [
            {
              type: "text",
              text: keys.length > 0
                ? `**Keys in ${params.datastoreName}:**\n${keys.map((k) => `- \`${k}\``).join("\n")}`
                : `*No keys found in ${params.datastoreName}.*`,
            },
          ],
        };
      }

      if (params.action === "messaging_publish") {
        if (!params.topic || !params.message) {
          return {
            content: [
              { type: "text", text: "messaging_publish requires `topic` and `message`." },
            ],
          };
        }
        const path = `/messaging-service/v1/universes/${universeId}/topics/${encodeURIComponent(params.topic)}`;
        await cloudFetch(path, {
          method: "POST",
          body: { message: params.message },
        });
        return {
          content: [
            {
              type: "text",
              text: `Message published to topic **${params.topic}**.`,
            },
          ],
        };
      }

      if (params.action === "place_info") {
        const placeId = params.placeId;
        if (!placeId) {
          return {
            content: [
              { type: "text", text: "place_info requires `placeId`." },
            ],
          };
        }
        const path = `/universes/v1/${universeId}/places/${placeId}`;
        const result = await cloudFetch(path);
        return {
          content: [
            {
              type: "text",
              text: `**Place info:**\n\`\`\`json\n${JSON.stringify(result, null, 2)}\n\`\`\``,
            },
          ],
        };
      }

      return { content: [{ type: "text", text: "Unknown cloud action." }] };
    },
  );
}
