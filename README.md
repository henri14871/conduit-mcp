# Conduit MCP

[![npm version](https://img.shields.io/npm/v/conduit-mcp)](https://www.npmjs.com/package/conduit-mcp)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/henri14871/conduit-mcp)](https://github.com/henri14871/conduit-mcp)

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

## Why Fewer Tools Is Better

Most Roblox MCPs give the AI 40-50+ separate tools -- one per API call. That means the model burns tokens just reading tool definitions, and needs multiple round trips for basic tasks.

Conduit takes the opposite approach: **19 workflow-oriented tools**, each doing the work of 3-5 flat tools. `edit_script` handles full replace, range edits, find/replace, and cross-script refactoring in one tool. `playtest` covers start/stop, code execution, console output, runtime inspection, character navigation, and virtual input. `explore` browses the tree, manages selection, lists services, and reports studio state.

The result: the AI reads fewer tool definitions, makes fewer calls, and spends tokens on your game -- not on MCP overhead.

## How Conduit Compares

|  | **Conduit** | **Roblox Built-in** | **robloxstudio-mcp** | **Weppy** |
|---|---|---|---|---|
| **Transport** | WebSocket | Native | HTTP polling | HTTP |
| **Latency** | <50ms | Native | 200-500ms | 200-500ms |
| **Tool design** | Workflow (19 tools) | Workflow (16 tools) | 1:1 mapping (39 tools) | Action-based (22 tools, 150+ actions) |
| **License** | MIT | Closed source | MIT | AGPL (Pro = paid) |
| | | | | |
| Script range editing | Yes | Yes | Yes | Yes |
| Script grep/search | Yes | Yes | Yes | Yes |
| Multi-script refactor | Yes | -- | -- | -- |
| Console/log output | Yes | Yes | Yes | Yes |
| Runtime inspection | Yes | -- | -- | -- |
| Playtest control | Yes | Yes | Yes | Paid |
| Virtual input | Yes | Yes | -- | -- |
| Character navigation | Yes | Yes | -- | -- |
| Undo/redo | Yes | -- | Yes | -- |
| Transactional undo | Yes | -- | -- | -- |
| Multi-Studio | Yes | Yes | -- | 3 places |
| Terrain tools | Yes | -- | -- | Paid |
| Asset search/insert | Yes | Yes | Yes | Paid |
| Attributes & tags | Yes | -- | Yes | Yes |
| Screenshot | Yes | -- | Yes | -- |
| | | | | |
| Token-aware responses | Yes | -- | -- | -- |
| MCP tool annotations | Yes | -- | -- | -- |
| Built-in API reference | Yes | -- | -- | -- |
| Rojo integration | Optional | -- | -- | -- |
| Open Cloud API | Optional | -- | -- | -- |
| AI mesh generation | -- | Yes | -- | -- |

**Roblox Built-in** ships with Studio (no install) and can generate meshes/materials, but has no undo, no terrain tools, no attributes, and is closed source. **robloxstudio-mcp** (335 stars) is the community standard but uses HTTP polling and 1:1 tool mapping that bloats context. **Weppy** has the most actions but locks most behind a paid tier with AGPL licensing.

Conduit is the only open-source option with WebSocket transport, workflow-oriented tools, and full debugging capabilities (console output + runtime inspection + transactional undo).

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
