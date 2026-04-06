import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "../bridge.js";
import { log } from "../utils/logger.js";

import { register as registerExplore } from "./explore.js";
import { register as registerInstances, registerReadOnly as registerInstancesReadOnly } from "./instances.js";
import { register as registerScripts, registerReadOnly as registerScriptsReadOnly } from "./scripts.js";
import { register as registerPlaytest } from "./playtest.js";
import { register as registerEnvironment } from "./environment.js";
import { register as registerAssets } from "./assets.js";
import { register as registerUtility } from "./utility.js";
import { register as registerStudio } from "./studio.js";
import { register as registerBuilds } from "./builds.js";

export interface ToolRegistrationOptions {
  mode?: "full" | "inspector";
  withCloud?: boolean;
  withRojo?: boolean;
}

export async function registerAllTools(
  server: McpServer,
  bridge: Bridge,
  options: ToolRegistrationOptions = {},
): Promise<void> {
  const mode = options.mode ?? "full";

  // Read-only tools — always registered
  registerStudio(server, bridge);
  registerExplore(server, bridge);
  registerUtility(server, bridge);

  if (mode === "full") {
    // Write tools — only in full mode
    registerInstances(server, bridge);
    registerScripts(server, bridge);
    registerPlaytest(server, bridge);
    registerEnvironment(server, bridge);
    registerAssets(server, bridge);
    registerBuilds(server, bridge);
  } else {
    // Inspector mode — only read-only tools (query, read_script)
    registerInstancesReadOnly(server, bridge);
    registerScriptsReadOnly(server, bridge);
  }

  // Optional modules (loaded dynamically to avoid bundling when unused)
  if (options.withCloud) {
    try {
      const mod = await import("../modules/cloud.js");
      mod.register(server);
    } catch (err) {
      log.error("Failed to load cloud module:", err);
    }
  }
  if (options.withRojo) {
    try {
      const mod = await import("../modules/rojo.js");
      mod.register(server);
    } catch (err) {
      log.error("Failed to load rojo module:", err);
    }
  }
}
