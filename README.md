# Conduit MCP

[![npm version](https://img.shields.io/npm/v/conduit-mcp)](https://www.npmjs.com/package/conduit-mcp)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/henri-knightco/conduit-mcp)](https://github.com/henri-knightco/conduit-mcp)

**The first Roblox Studio MCP built on WebSocket not polling.**

```
AI Client <--stdio--> Conduit Server <--WebSocket--> Studio Plugin <--API--> DataModel
```

Every other Roblox MCP uses HTTP polling, adding 200-500ms of latency per operation. Conduit holds a persistent WebSocket connection. Commands flow instantly in both directions -- under 50ms round trips.

## Quick Start

```bash
npx conduit-mcp --install
```

Installs the Studio plugin and prints the config snippet for your AI client. Add `--auto-config` to auto-configure detected clients.

<details>
<summary>Manual setup</summary>

Add to your AI client's MCP config:

```json
{
  "mcpServers": {
    "conduit": {
      "command": "npx",
      "args": ["-y", "conduit-mcp"]
    }
  }
}
```

Install the plugin from [GitHub releases](https://github.com/henri-knightco/conduit-mcp/releases) or build from source with Rojo.

**Requires:** Node.js 18+ and Roblox Studio with HttpService enabled.

</details>

## How Conduit Compares

| Capability | Conduit | Roblox MCP | RojoMCP | MCP-Roblox |
|---|:---:|:---:|:---:|:---:|
| **Transport** | WebSocket | HTTP poll | HTTP poll | HTTP poll |
| **Latency** | <50ms | 200-500ms | 200-500ms | 200-500ms |
| **Multi-Studio** | Yes | No | No | No |
| **Script grep** | Yes | No | No | No |
| **Range editing** | Yes | No | Yes | No |
| **Multi-script refactor** | Yes | No | No | No |
| **Console/log output** | Yes | No | No | No |
| **Runtime inspection** | Yes | No | No | No |
| **Character navigation** | Yes | No | No | No |
| **Virtual input** | Yes | No | No | No |
| **Transactional undo** | Yes | No | No | No |
| **MCP tool annotations** | Yes | No | No | No |
| **Token-aware responses** | Yes | No | No | No |
| **Built-in API reference** | Yes | No | No | No |
| **Rojo integration** | Optional | No | Built-in | No |
| **Open Cloud API** | Optional | No | No | No |
| **Tool count** | 19 | 65+ | ~15 | ~20 |
| **Token efficiency** | Workflow-oriented | 1:1 API mapping | Moderate | 1:1 API mapping |

## Tools

| Tool | Description |
|------|-------------|
| `explore` | Browse instance tree, get/set selection, list services, check studio state |
| `get_info` | Class, properties, attributes, tags, and typed property list in one call |
| `query` | Find instances by class/tag/attribute/name, or grep across all scripts |
| `create` | Create or clone instances (batch) |
| `modify` | Set properties/attributes/tags per-instance or in bulk |
| `delete` | Batch-delete instances |
| `read_script` | Read script source with optional line ranges |
| `edit_script` | Full replace, range edit, find/replace, or multi-script refactor |
| `execute_lua` | Run arbitrary Luau in Studio (no playtest required) |
| `playtest` | Start/stop, execute code, get console output, inspect values, navigate character, simulate input |
| `environment` | Terrain fill/clear/read, Workspace/Lighting settings |
| `assets` | Search the Roblox catalog or insert assets by ID |
| `builds` | Export, import, or list reusable instance trees |
| `undo_redo` | Undo or redo with count parameter |
| `transaction` | Group multiple writes into a single Ctrl+Z |
| `screenshot` | Capture viewport screenshot |
| `lookup_api` | Search bundled Roblox API reference (no Studio needed) |
| `list_studios` | List connected Studio instances |
| `set_active_studio` | Switch active Studio instance |

<details>
<summary>Optional modules</summary>

| Module | Flag | Description |
|--------|------|-------------|
| Cloud | `--with-cloud` | Roblox Open Cloud API: datastores, messaging, place info |
| Rojo | `--with-rojo` | Rojo CLI wrapper: sourcemap, build |

</details>

## CLI Options

```
npx conduit-mcp                    Start the MCP server
npx conduit-mcp --install          Install plugin + show config
npx conduit-mcp --mode inspector   Read-only tools only
npx conduit-mcp --with-cloud       Enable Open Cloud module
npx conduit-mcp --with-rojo        Enable Rojo module
npx conduit-mcp --port 3201        Override bridge port
```

## Multi-Studio

Connect multiple Studio instances simultaneously. With one instance, routing is automatic.

```
> list_studios
- abc12345 — MyShooterGame (Place ID: 123456) ← active
- def67890 — MyRPGGame (Place ID: 789012)

> set_active_studio def67890
Active studio set to def67890 (MyRPGGame).
```

## Architecture

```
packages/
  server/       TypeScript MCP server (npm: conduit-mcp)
    src/
      tools/    Tool definitions (one file per domain)
      modules/  Optional modules (cloud, rojo)
      context/  Bundled Roblox API index
  plugin/       Roblox Studio plugin (Luau, built with Rojo)
    src/
      handlers/ One handler per tool domain
```

Writes execute serially. Reads run in parallel. Every mutation is a single Ctrl+Z via ChangeHistoryService.

## Compatible Clients

Claude Code, Claude Desktop, Cursor, Windsurf, Codex CLI, Gemini CLI -- any MCP client with stdio transport.

## Development

```bash
pnpm install && pnpm build    # Build
pnpm dev                      # Watch mode
pnpm test                     # Run tests
```

## Contributing

PRs welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. [Open an issue](https://github.com/henri-knightco/conduit-mcp/issues) for bugs or feature requests.

## License

MIT -- Henri Elliott-Knight / Knight & Co Digital
