<p align="center">
  <img src="branding/banner.svg" alt="Conduit MCP" width="680" />
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/conduit-mcp"><img src="https://img.shields.io/npm/v/conduit-mcp" alt="npm version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSL--1.1-blue.svg" alt="License: BSL 1.1" /></a>
  <a href="https://github.com/henri14871/conduit-mcp"><img src="https://img.shields.io/github/stars/henri14871/conduit-mcp" alt="GitHub stars" /></a>
</p>

MCP server that connects AI assistants to Roblox Studio over WebSocket instead of HTTP polling.

```
AI Client <--stdio--> Conduit Server <--WebSocket--> Studio Plugin <--API--> DataModel
```

Other Roblox MCPs poll over HTTP -- every operation adds 200-500ms of latency and the AI wastes half its context window reading 40+ tool definitions. Conduit holds a persistent WebSocket connection (<50ms round trips) and gives the AI 19 tools that actually map to how you work, not a 1:1 dump of the API.

## Get started

```bash
npx conduit-mcp --install
```

That installs the Studio plugin and prints the config for your AI client. Pass `--auto-config` to set up Claude/Cursor/Windsurf automatically.

<details>
<summary>Or set it up manually</summary>

Add this to your AI client's MCP config:

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

Grab the plugin from [releases](https://github.com/henri14871/conduit-mcp/releases) or build it yourself with Rojo. You'll need Node 18+ and HttpService enabled in Studio.

</details>

## What it can do

| Tool | What it does |
|------|-------------|
| `explore` | Browse the instance tree, get/set selection, list services, studio state |
| `get_info` | Properties, attributes, tags -- request specific ones instead of getting all 60+ |
| `query` | Find instances by class/tag/attribute/name, grep across scripts |
| `create` | Create or clone instances, supports batching |
| `modify` | Set properties/attributes/tags, one instance or many |
| `delete` | Delete instances in bulk |
| `read_script` | Full source, line ranges, outlines (just function signatures), or batch-read a bunch of scripts at once |
| `edit_script` | Full replace, range edits, find/replace, cross-script refactors, batch edits with mixed modes |
| `execute_lua` | Run Luau in Studio directly, no playtest needed |
| `playtest` | Start/stop, run code, console output, inspect runtime values, move the character, simulate input, screenshots |
| `environment` | Terrain (fill/clear/read), Workspace and Lighting settings |
| `assets` | Search the catalog, insert by asset ID |
| `builds` | Save, load, and list reusable instance trees |
| `undo_redo` | Undo or redo, with a count |
| `transaction` | Group a bunch of edits into one Ctrl+Z (timeout up to 300s for long AI sessions) |
| `screenshot` | Capture the viewport |
| `lookup_api` | Search the Roblox API reference without needing Studio |
| `list_studios` | See all connected Studio instances |
| `set_active_studio` | Switch which Studio the AI is talking to |

<details>
<summary>Optional modules</summary>

| Module | Flag | What it adds |
|--------|------|-------------|
| Cloud | `--with-cloud` | Open Cloud API -- datastores, messaging, place info |
| Rojo | `--with-rojo` | Rojo CLI wrapper -- sourcemap, build |

</details>

## Why fewer tools matters

Most Roblox MCPs expose one tool per API call. 39 tools, 150+ actions, whatever. The problem is the AI has to read all those definitions before it can do anything, and basic tasks take multiple round trips.

Conduit's 19 tools each do the work of several. `edit_script` alone handles full replace, range edits, find/replace, cross-script refactoring, and batch edits. One call instead of five. The AI reads less, calls less, and spends tokens on your actual game.

Script outlines return just function signatures without the full source -- saves a ton of tokens on big scripts. Tree exploration auto-collapses repetitive children (100 MemStorageConnections becomes 3 samples + a count). Property reads can target specific props by name instead of dumping everything.

## How it compares

|  | **Conduit** | **Roblox Built-in** | **robloxstudio-mcp** | **Weppy** |
|---|---|---|---|---|
| Transport | WebSocket | Native | HTTP polling | HTTP |
| Latency | <50ms | Native | 200-500ms | 200-500ms |
| Tools | 19 (workflow) | 16 (workflow) | 39 (1:1 mapping) | 22 tools, 150+ actions |
| License | BSL 1.1 | Closed | MIT | AGPL (Pro = paid) |

**Roblox Built-in** ships with Studio and can generate meshes, but no undo, no terrain tools, no attributes, closed source. **robloxstudio-mcp** is the community standard (335 stars) but the HTTP polling and 1:1 tool mapping bloats context fast. **Weppy** has the most actions but locks terrain, playtest, and assets behind a paid tier.

Conduit's the only open-source one with WebSocket, batch operations, runtime inspection, and transactional undo.

## Multi-Studio

Multiple Studio instances can connect at once. With one instance it just routes automatically.

```
> list_studios
- abc12345 — MyShooterGame (Place ID: 123456) ← active
- def67890 — MyRPGGame (Place ID: 789012)

> set_active_studio def67890
Active studio set to def67890 (MyRPGGame).
```

## CLI

```
npx conduit-mcp                    Start the server
npx conduit-mcp --install          Install plugin + show config
npx conduit-mcp --mode inspector   Read-only tools only
npx conduit-mcp --with-cloud       Enable Open Cloud
npx conduit-mcp --with-rojo        Enable Rojo integration
npx conduit-mcp --port 3201        Override bridge port
```

## Architecture

```
packages/
  server/       TypeScript MCP server (npm: conduit-mcp)
    src/
      tools/    One file per tool domain
      modules/  Optional modules (cloud, rojo)
      context/  Bundled Roblox API index
  plugin/       Luau Studio plugin (built with Rojo)
    src/
      handlers/ One handler per tool domain
```

Writes are serial. Reads run in parallel. Every mutation is a single Ctrl+Z via ChangeHistoryService. Transactions can group multi-edit sessions into one undo point.

## Works with

Claude Code, Claude Desktop, Cursor, Windsurf, Codex CLI, Gemini CLI -- anything that speaks MCP over stdio.

## Development

```bash
pnpm install && pnpm build
pnpm dev                      # watch mode
pnpm test
```

## Contributing

PRs welcome -- see [CONTRIBUTING.md](CONTRIBUTING.md). [Open an issue](https://github.com/henri14871/conduit-mcp/issues) for bugs or feature requests.

## License

BSL 1.1 -- see [LICENSE](LICENSE). Converts to Apache 2.0 on 2030-04-10.
