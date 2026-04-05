#!/usr/bin/env node

import { parseArgs } from "node:util";
import { homedir, platform } from "node:os";
import { join } from "node:path";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { startServer } from "./index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

const { values } = parseArgs({
  options: {
    install: { type: "boolean", default: false },
    "auto-config": { type: "boolean", default: false },
    port: { type: "string", default: "3200" },
    mode: { type: "string", default: "full" },
    "with-cloud": { type: "boolean", default: false },
    "with-rojo": { type: "boolean", default: false },
    version: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
  strict: false,
});

if (values.version) {
  const pkg = JSON.parse(
    readFileSync(join(__dirname, "..", "package.json"), "utf-8"),
  );
  console.log(`conduit-mcp v${pkg.version}`);
  process.exit(0);
}

if (values.help) {
  console.log(`
conduit-mcp — WebSocket-first MCP bridge for Roblox Studio

Usage:
  npx conduit-mcp              Start the MCP server (stdio transport)
  npx conduit-mcp --install    Install the Studio plugin & show config
  npx conduit-mcp --version    Print version

Options:
  --install        Install the Conduit plugin to Roblox Studio
  --auto-config    Also write config to detected AI clients
  --port <number>  Override default bridge port (default: 3200)
  --mode <mode>    Tool mode: 'full' (default) or 'inspector' (read-only tools only)
  --with-cloud     Enable Cloud module (requires ROBLOX_CLOUD_API_KEY env var)
  --with-rojo      Enable Rojo module (requires rojo on PATH)
  --help           Show this help message
`);
  process.exit(0);
}

if (values.install) {
  await install(values["auto-config"] as boolean);
  process.exit(0);
}

// Validate mode
const mode = (values.mode as string) || "full";
if (mode !== "full" && mode !== "inspector") {
  console.error(`Unknown mode: ${mode}. Expected 'full' or 'inspector'.`);
  process.exit(1);
}

// Default: start the MCP server
const port = parseInt(values.port as string) || 3200;
await startServer(port, {
  mode: mode as "full" | "inspector",
  withCloud: values["with-cloud"] as boolean,
  withRojo: values["with-rojo"] as boolean,
});

// ── Install logic ────────────────────────────────────────────────

async function install(autoConfig: boolean): Promise<void> {
  console.log("Conduit MCP — Installation\n");

  // Step 1: Install plugin
  const pluginInstalled = installPlugin();

  // Step 2: Detect & configure AI clients
  const clients = detectClients();

  if (clients.length === 0) {
    console.log("No AI clients detected. Add this to your client's MCP config:\n");
    printConfigSnippet();
  } else {
    console.log(`\nDetected AI clients: ${clients.map((c) => c.name).join(", ")}\n`);

    for (const client of clients) {
      if (autoConfig) {
        writeClientConfig(client);
      } else {
        console.log(`${client.name} — add this to ${client.configPath}:\n`);
        printConfigSnippet();
      }
    }
  }

  console.log(pluginInstalled ? "\nInstallation complete!" : "\nPlugin installation failed — install manually from GitHub releases.");
  console.log("\nNext steps:");
  console.log("  1. Open Roblox Studio");
  console.log("  2. Enable HttpService (Game Settings > Security > Allow HTTP Requests)");
  console.log("  3. The Conduit plugin will auto-connect when the MCP server starts");
}

function installPlugin(): boolean {
  const pluginSrc = join(__dirname, "..", "plugin", "Conduit.rbxm");

  if (!existsSync(pluginSrc)) {
    console.log("Plugin file not found at: " + pluginSrc);
    return false;
  }

  const pluginsDir = getPluginsDir();
  if (!pluginsDir) {
    console.log("Could not determine Roblox Studio plugins directory for this platform.");
    return false;
  }

  if (!existsSync(pluginsDir)) {
    mkdirSync(pluginsDir, { recursive: true });
  }

  const dest = join(pluginsDir, "Conduit.rbxm");
  copyFileSync(pluginSrc, dest);
  console.log(`Plugin installed to: ${dest}`);
  return true;
}

function getPluginsDir(): string | null {
  const os = platform();
  if (os === "win32") {
    const localAppData = process.env.LOCALAPPDATA;
    if (localAppData) {
      return join(localAppData, "Roblox", "Plugins");
    }
    return join(homedir(), "AppData", "Local", "Roblox", "Plugins");
  }
  if (os === "darwin") {
    return join(homedir(), "Documents", "Roblox", "Plugins");
  }
  return null;
}

interface ClientInfo {
  name: string;
  configPath: string;
  configKey: string;
}

function detectClients(): ClientInfo[] {
  const home = homedir();
  const candidates: ClientInfo[] = [
    {
      name: "Claude Code",
      configPath: join(home, ".claude", "settings.json"),
      configKey: "mcpServers",
    },
    {
      name: "Cursor",
      configPath: join(home, ".cursor", "mcp.json"),
      configKey: "mcpServers",
    },
    {
      name: "Windsurf",
      configPath: join(home, ".windsurf", "mcp.json"),
      configKey: "mcpServers",
    },
    {
      name: "Claude Desktop (Windows)",
      configPath: join(
        process.env.APPDATA || join(home, "AppData", "Roaming"),
        "Claude",
        "claude_desktop_config.json",
      ),
      configKey: "mcpServers",
    },
    {
      name: "Claude Desktop (macOS)",
      configPath: join(
        home,
        "Library",
        "Application Support",
        "Claude",
        "claude_desktop_config.json",
      ),
      configKey: "mcpServers",
    },
  ];

  return candidates.filter((c) => {
    try {
      return existsSync(dirname(c.configPath));
    } catch {
      return false;
    }
  });
}

function printConfigSnippet(): void {
  const snippet = {
    conduit: {
      command: "npx",
      args: ["-y", "conduit-mcp"],
    },
  };
  console.log(JSON.stringify(snippet, null, 2));
}

function writeClientConfig(client: ClientInfo): void {
  try {
    let config: Record<string, unknown> = {};
    if (existsSync(client.configPath)) {
      config = JSON.parse(readFileSync(client.configPath, "utf-8"));
    }

    const servers = (config[client.configKey] as Record<string, unknown>) ?? {};
    servers["conduit"] = {
      command: "npx",
      args: ["-y", "conduit-mcp"],
    };
    config[client.configKey] = servers;

    const dir = dirname(client.configPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    writeFileSync(client.configPath, JSON.stringify(config, null, 2) + "\n");
    console.log(`${client.name} — config written to ${client.configPath}`);
  } catch (err) {
    console.log(`${client.name} — failed to write config: ${err}`);
  }
}
