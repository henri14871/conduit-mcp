# Conduit — Project Plan

**The most powerful, non-bloated MCP bridge between AI coding assistants and game engines.**
**First target: Roblox Studio.**

*Author: Henri Elliott-Knight · Knight & Co Digital*
*License: MIT · Open Source*

---

## 1. What Conduit Is

Conduit is two things shipped as one project:

1. **Conduit Server** — a TypeScript MCP server (npm package) that AI clients connect to via stdio
2. **Conduit Plugin** — a Roblox Studio plugin (Luau) that connects to the server via WebSocket

One install command. Works with Claude Code, Codex CLI, Cursor, Windsurf, Gemini CLI, and any MCP-compatible client.

```
Claude Code ←stdio→ Conduit Server ←WebSocket→ Conduit Plugin ←API→ DataModel
```

---

## 2. Why Conduit Wins

Every existing Roblox MCP plugin shares the same weaknesses. Conduit exploits all of them:

| Problem in existing tools | Conduit's answer |
|---|---|
| **HTTP polling** (200–500ms latency per call) | **WebSocket-first** — persistent bidirectional connection via `HttpService:CreateWebStreamClient()`. Sub-50ms round trips. HTTP polling fallback for older Studio versions |
| **65+ flat tools** (boshyxd) consuming massive context windows | **15–25 workflow-oriented tools** following Block's playbook — each tool does more, total tool definitions consume fewer tokens |
| **No token awareness** — responses dump entire DataModels, kill Claude Desktop's free tier | **Token-aware responses** — configurable output limits, smart truncation, Markdown output instead of raw JSON, pagination built in |
| **No inline documentation** — AI hallucinates Roblox APIs | **Embedded Roblox API index** — bundled class/method/property reference so AI gets correct signatures without extra tool calls |
| **No tool annotations** — clients can't distinguish safe from destructive operations | **MCP tool annotations** on every tool — `readOnlyHint`, `destructiveHint`, `idempotentHint` per the 2025-06-18 spec |
| **Line-based or full-source script editing** | **Range-based editing** via `ScriptEditorService:EditSourceAsyncWithRanges()` — surgical code changes without rewriting entire scripts |
| **Multi-step setup** (install Node, npm, plugin, enable HTTP, edit config) | **One command**: `npx conduit-mcp --install` auto-installs plugin + prints config for detected AI clients |
| **Connection fragility** — stuck connections, port conflicts, false disconnects | **WebSocket with auto-reconnect**, heartbeat monitoring, graceful degradation, dynamic port selection |
| **No playtest automation** | **Playtest tools** — start/stop play, execute in play context, capture output |
| **No change tracking** | **ChangeHistoryService recording API** — every MCP operation is a single undoable action in Studio |

---

## 3. Architecture

### 3.1 Repository Structure

```
conduit/
├── packages/
│   ├── server/                 # TypeScript MCP server (npm package)
│   │   ├── src/
│   │   │   ├── index.ts        # Entry point, stdio transport
│   │   │   ├── bridge.ts       # WebSocket + HTTP fallback server
│   │   │   ├── tools/          # Tool definitions (grouped by domain)
│   │   │   │   ├── explore.ts      # DataModel exploration & queries
│   │   │   │   ├── instances.ts    # Instance CRUD (batch operations)
│   │   │   │   ├── scripts.ts      # Script read/write/edit
│   │   │   │   ├── properties.ts   # Property & attribute management
│   │   │   │   ├── playtest.ts     # Play/stop/execute/output
│   │   │   │   ├── terrain.ts      # Terrain manipulation
│   │   │   │   └── assets.ts       # Creator Store / InsertService
│   │   │   ├── context/        # Roblox API reference index
│   │   │   │   └── api-index.ts    # Bundled class/method/enum data
│   │   │   ├── protocol.ts     # Request/response serialisation
│   │   │   └── utils/
│   │   │       ├── tokens.ts       # Token estimation & truncation
│   │   │       └── formatting.ts   # JSON → Markdown response formatting
│   │   ├── bin/
│   │   │   └── cli.ts          # CLI: --install, --version, --port
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   └── plugin/                 # Roblox Studio plugin (Luau)
│       ├── src/
│       │   ├── init.server.luau       # Plugin entry point
│       │   ├── Connection.luau        # WebSocket client + HTTP fallback
│       │   ├── CommandRouter.luau     # Routes commands to handlers
│       │   ├── handlers/              # One handler per tool domain
│       │   │   ├── Explore.luau
│       │   │   ├── Instances.luau
│       │   │   ├── Scripts.luau
│       │   │   ├── Properties.luau
│       │   │   ├── Playtest.luau
│       │   │   ├── Terrain.luau
│       │   │   └── Assets.luau
│       │   ├── Serialiser.luau        # Roblox datatypes → JSON
│       │   └── UndoManager.luau       # ChangeHistoryService wrapper
│       ├── default.project.json       # Rojo project file
│       └── wally.toml                 # (if needed for dependencies)
│
├── docs/
│   ├── getting-started.md
│   ├── tool-reference.md
│   ├── architecture.md
│   └── contributing.md
│
├── .github/
│   └── workflows/
│       ├── ci.yml              # Lint, test, build
│       └── release.yml         # npm publish + plugin build
│
├── package.json                # pnpm workspace root
├── pnpm-workspace.yaml
├── LICENSE                     # MIT
└── README.md
```

### 3.2 Communication Protocol

**Primary: WebSocket**

The server starts an HTTP server on a dynamic port (default 3200, auto-increments if busy). The Studio plugin connects via:

```luau
local ws = HttpService:CreateWebStreamClient(Enum.HttpWebStreamType.WebSocket, {
    Url = "ws://localhost:" .. port
})
```

Messages are newline-delimited JSON:

```json
// Server → Plugin (command)
{"id": "abc123", "method": "explore", "params": {"path": "Workspace", "depth": 2}}

// Plugin → Server (response)  
{"id": "abc123", "result": {...}, "tokenEstimate": 340}

// Plugin → Server (error)
{"id": "abc123", "error": {"code": "NOT_FOUND", "message": "Instance not found at path"}}
```

**Fallback: HTTP long-polling**

For Studio versions without WebSocket support, the plugin polls `GET /poll` with instant response when commands are pending, and posts results to `POST /result`. The server auto-detects which mode the plugin is using.

**Heartbeat:**

Plugin sends `{"type": "heartbeat"}` every 5 seconds. Server considers plugin disconnected after 15 seconds of silence. Plugin auto-reconnects with exponential backoff (1s, 2s, 4s, max 30s).

### 3.3 Transport to AI Clients

**stdio only.** This is the only transport universally supported by Claude Code, Codex CLI, Cursor, Windsurf, Claude Desktop, and Gemini CLI. The server reads JSON-RPC from stdin, writes to stdout — standard MCP SDK behaviour.

---

## 4. Tool Design

### 4.1 Design Philosophy

Following Block's playbook and Notion's v2 redesign:

- **Workflow-oriented, not API-mapped.** One tool handles a complete workflow. `edit_script` supports full replace, line range replace, range-based edit, and find-replace — all in one tool, selected by parameter.
- **15–25 tools total.** Windsurf caps at 100 tools across all servers. Claude Code performs better with fewer, well-described tools.
- **Markdown responses by default.** JSON is verbose and token-hungry. Responses use concise Markdown with structured data only when explicitly needed.
- **Token budgets on every response.** Each tool accepts an optional `maxTokens` parameter. Responses include a `truncated` flag and guidance on how to narrow the query.
- **Tool annotations on every tool.** `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint` per the MCP 2025-06-18 spec.

### 4.2 Tool Inventory

**Exploration (read-only, safe)**

| Tool | Purpose | Replaces (in boshyxd) |
|---|---|---|
| `explore` | Browse DataModel tree. Params: `path`, `depth`, `filter`, `includeProperties`. Returns Markdown tree view with configurable detail. | `get_children`, `get_descendants`, `get_descendants_tree`, `find_instances`, `get_full_hierarchy`, `get_properties`, `get_all_scripts`, `search_instances`, `get_instance_info`, `get_selected` |
| `read_script` | Read script source. Params: `path`, `lineRange` (optional). | `get_script_source`, `get_scripts_in_folder` |
| `get_selection` | Get currently selected instances in Studio. | `get_selected` |

**Mutation (write, undoable)**

| Tool | Purpose | Replaces |
|---|---|---|
| `create_instances` | Create one or more instances. Params: `operations[]` — each has `className`, `parent`, `name`, `properties`. Batch-capable. | `create_instance`, `create_script` |
| `modify_instances` | Modify existing instances. Params: `operations[]` — each has `path`, `properties`, `attributes`, `tags`, `parent` (for reparenting), `name`. Batch-capable. | `set_property`, `set_properties`, `set_attribute`, `add_tag`, `remove_tag`, `rename_instance`, `move_instance` |
| `delete_instances` | Delete instances by path. Params: `paths[]`. | `delete_instance` |
| `clone_instances` | Clone instances. Params: `sources[]`, `targetParent`. | `clone_instance` |
| `edit_script` | Edit script source. Params: `path`, `mode` (one of: `full`, `range`, `find_replace`), `source`/`edits`/`find`+`replace`. Uses range-based API when available. | `update_script_source`, `create_script`, `update_script` |

**Playtest**

| Tool | Purpose | Replaces |
|---|---|---|
| `playtest` | Start/stop playtest, execute Luau in play context, capture output. Params: `action` (start/stop/execute), `code` (for execute). | `execute_luau`, `run_play_mode_script`, `toggle_play` |

**Terrain**

| Tool | Purpose | Replaces |
|---|---|---|
| `terrain` | Fill, clear, read terrain. Params: `action`, `region`, `material`, `size`. | `fill_terrain`, `generate_terrain`, `read_terrain`, `clear_terrain` |

**Assets**

| Tool | Purpose | Replaces |
|---|---|---|
| `insert_asset` | Insert from Creator Store or Toolbox. Params: `assetId`, `parent`. | `search_assets`, `get_asset_details`, `insert_asset`, `get_free_models`, `get_asset_image` |
| `search_assets` | Search Creator Store. Params: `query`, `category`, `maxResults`. | (same as above) |

**Utility**

| Tool | Purpose | Replaces |
|---|---|---|
| `undo_redo` | Undo or redo the last operation. Params: `action` (undo/redo). | `undo`, `redo` |
| `screenshot` | Capture a viewport screenshot. Returns base64 image. | `take_screenshot` |
| `lookup_api` | Search the bundled Roblox API index. Params: `query`. Returns class/method/property/enum info. | (n4tivex equivalent, but built-in) |

**Total: 15 tools** — down from boshyxd's 65+, with equivalent or greater capability through batching and multi-mode parameters.

---

## 5. Key Technical Decisions

### 5.1 WebSocket via CreateWebStreamClient

Roblox added `HttpService:CreateWebStreamClient()` in October 2025. Key constraints:

- Max 4 concurrent WebSocket connections per plugin
- Studio-only (blocked in live experiences — fine for our use case)
- Localhost connections don't need domain approval
- Must handle connection drops and reconnection
- 2,000 requests/minute rate limit for localhost HTTP (irrelevant for WebSocket)

Conduit needs exactly 1 WebSocket connection. The remaining 3 slots stay free for the developer's own use.

### 5.2 ChangeHistoryService Recording API

Every mutating tool call is wrapped in a recording:

```luau
local id = ChangeHistoryService:TryBeginRecording("Conduit: create_instances")
-- execute operations
ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
```

This means the developer can undo any AI operation with a single Ctrl+Z. Failed operations use `Cancel` instead of `Commit`.

### 5.3 Range-Based Script Editing

`ScriptEditorService:EditSourceAsyncWithRanges()` accepts an array of edits with start/end positions. This is dramatically more efficient than replacing the entire script source because:

- The AI only needs to specify changed regions
- Multiple edits can be applied atomically
- The script editor UI doesn't flash/reset

Fallback to `UpdateSourceAsync()` for older Studio versions.

### 5.4 Token-Aware Response Formatting

Every response goes through the formatting pipeline:

1. **Raw data** from Studio (JSON)
2. **Filtering** — strip internal Roblox services (CoreGui, CorePackages, etc.) unless explicitly requested
3. **Formatting** — convert to concise Markdown
4. **Token estimation** — approximate token count using character-based heuristic (1 token ≈ 4 chars)
5. **Truncation** — if over budget, truncate with a summary: `"Showing 20 of 847 children. Use filter parameter to narrow results."`

Default budget: 4,000 tokens per response (configurable via `CONDUIT_MAX_TOKENS` env var).

### 5.5 Roblox Datatype Serialisation

The plugin includes a comprehensive serialiser covering all Roblox datatypes:

- **Primitives**: string, number, boolean, nil
- **Vectors**: Vector2, Vector3, Vector3int16
- **Spatial**: CFrame (position + orientation matrix), UDim, UDim2
- **Color**: Color3, BrickColor
- **Complex**: NumberSequence, ColorSequence, NumberRange, Ray, Region3
- **Enums**: Serialised as `{Enum = "EnumType", Value = "EnumName"}`
- **Instances**: Serialised as path strings (`"Workspace.Map.SpawnPoint"`)

The deserialiser reconstructs these from JSON when setting properties.

### 5.6 Embedded API Index

A pre-built, compressed JSON index of the Roblox API covering:

- All classes with inheritance chains
- All properties with types and read/write access
- All methods with parameter signatures
- All events with parameter types
- All enums with their values

This is generated from the official Roblox API dump and bundled with the npm package. The `lookup_api` tool searches it locally — no network requests, no extra MCP server needed, no token waste from n4tivex's 27 separate tools.

Target size: <500KB compressed. Updated with each Conduit release.

---

## 6. Installation & Onboarding

### 6.1 One-Command Install

```bash
npx conduit-mcp --install
```

This command:

1. Detects the OS and Roblox Studio plugins directory
   - Windows: `%LOCALAPPDATA%/Roblox/Plugins/`
   - macOS: `~/Documents/Roblox/Plugins/`
2. Copies the compiled plugin (`.rbxm` file) into the plugins directory
3. Detects installed AI clients by checking for config files:
   - Claude Code: `~/.claude/settings.json`
   - Claude Desktop: platform-specific path
   - Cursor: `~/.cursor/mcp.json`
   - Windsurf: `~/.windsurf/mcp.json`
   - Codex CLI: `~/.codex/config.toml`
4. Prints the correct config snippet for each detected client
5. Optionally auto-writes the config with `--auto-config` flag

### 6.2 Manual Setup

For users who prefer manual control:

```bash
npm install -g conduit-mcp
```

Then add to their AI client config:

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

And install the plugin from the GitHub releases page or Roblox Creator Store.

### 6.3 In-Studio Setup

On first run, the plugin:

1. Checks if `HttpService.HttpEnabled` is true — if not, shows a clear prompt
2. Attempts WebSocket connection to `ws://localhost:3200`
3. Falls back to HTTP polling if WebSocket fails
4. Shows connection status in a small toolbar widget (green/yellow/red dot)

---

## 7. Development Roadmap

### Phase 1 — Foundation (Weeks 1–2)

- [ ] Initialise pnpm monorepo (`packages/server`, `packages/plugin`)
- [ ] Set up TypeScript build pipeline with `@modelcontextprotocol/sdk`
- [ ] Implement WebSocket bridge server (HTTP + WS on same port)
- [ ] Build Luau plugin skeleton with Rojo
- [ ] Implement WebSocket client in plugin using `CreateWebStreamClient`
- [ ] Implement HTTP long-polling fallback
- [ ] Heartbeat + auto-reconnect logic
- [ ] Build `Connection.luau` (handles both modes transparently)
- [ ] Build `CommandRouter.luau` (dispatches commands to handlers)
- [ ] Build `Serialiser.luau` (all Roblox datatypes)
- [ ] Build `UndoManager.luau` (ChangeHistoryService recording wrapper)

### Phase 2 — Core Tools (Weeks 3–4)

- [ ] `explore` — DataModel traversal with depth, filtering, token budgets
- [ ] `read_script` — source reading with optional line ranges
- [ ] `get_selection` — current Studio selection
- [ ] `create_instances` — batch instance creation
- [ ] `modify_instances` — batch property/attribute/tag modification
- [ ] `delete_instances` — batch deletion
- [ ] `clone_instances` — batch cloning
- [ ] `edit_script` — full/range/find-replace modes
- [ ] `undo_redo` — undo/redo wrapper
- [ ] Token-aware response formatting pipeline
- [ ] Markdown output formatting

### Phase 3 — Extended Tools (Week 5)

- [ ] `playtest` — start/stop/execute
- [ ] `terrain` — fill/clear/read
- [ ] `insert_asset` — Creator Store integration
- [ ] `search_assets` — Creator Store search
- [ ] `screenshot` — viewport capture
- [ ] `lookup_api` — embedded API index + search

### Phase 4 — Polish & Ship (Week 6)

- [ ] CLI installer (`--install`, `--auto-config`)
- [ ] Plugin `.rbxm` build pipeline (Rojo)
- [ ] Comprehensive README with animated GIF demos
- [ ] Tool reference documentation
- [ ] GitHub Actions CI/CD (lint, test, build, publish)
- [ ] npm publish as `conduit-mcp`
- [ ] Roblox Creator Store plugin listing
- [ ] DevForum launch post
- [ ] GitHub release v1.0.0

### Phase 5 — Post-Launch (Ongoing)

- [ ] Community feedback triage
- [ ] Multi-instance Studio support (connect to multiple Studio windows)
- [ ] Plugin auto-update checking
- [ ] Additional engine adapters (Unity, Godot) — when demand warrants

---

## 8. Competitive Positioning

### What to say on DevForum / README

**Conduit is the first Roblox Studio MCP server built on WebSocket, not HTTP polling.** Every other MCP plugin — including Roblox's own deprecated `studio-rust-mcp-server` — uses HTTP polling with 200–500ms latency per round trip. Conduit uses Studio's native WebSocket support (added October 2025) for real-time bidirectional communication.

**15 tools, not 65.** More tools doesn't mean more power — it means more tokens wasted on tool definitions and more confusion for AI models. Conduit's 15 tools cover the same functionality through batching and multi-mode parameters, while consuming a fraction of the context window.

**Token-aware by design.** Every response respects configurable token budgets. No more "Claude ran out of context because the MCP dumped 847 scripts including CoreGui."

**Built-in Roblox API knowledge.** The AI doesn't need to guess or hallucinate Roblox APIs. Conduit bundles a searchable index of every class, method, property, and enum.

**One command to install.** `npx conduit-mcp --install` — detects your AI client, installs the plugin, prints your config. Done.

### What NOT to say

- Don't trash boshyxd or other projects by name — acknowledge them respectfully
- Don't claim "best" — let the feature list speak for itself
- Don't oversell multi-engine support until it actually exists

---

## 9. Tech Stack Summary

| Component | Technology |
|---|---|
| MCP Server | TypeScript, `@modelcontextprotocol/sdk`, Node.js 18+ |
| Bridge | `ws` library (WebSocket server) + `http` (fallback) |
| Plugin | Luau, built with Rojo |
| Build | pnpm workspaces, tsup (bundling), Rojo (plugin) |
| CI/CD | GitHub Actions |
| Package | npm (`conduit-mcp`) |
| Plugin dist | `.rbxm` via Rojo, optionally Creator Store |
| License | MIT |

---

## 10. Success Metrics

After 3 months:

- **GitHub stars**: 100+ (boshyxd has 262 after ~10 months)
- **npm weekly downloads**: 200+
- **DevForum thread engagement**: 50+ replies
- **Open issues resolved within 48h**: 80%+
- **Connection reliability**: <1% dropped connections per session
- **Average tool response latency**: <100ms (vs 200–500ms for polling-based competitors)

---

*This is Conduit. WebSocket-first. Token-aware. Workflow-oriented. Open source. Free.*
*Built by Henri Elliott-Knight.*
