# The complete landscape of Roblox Studio MCP plugins

**The Roblox Studio MCP ecosystem has exploded to 12+ competing projects, yet every single one shares the same fundamental architectural bottleneck — HTTP polling — despite Roblox adding native WebSocket support in October 2025.** This creates a clear opening for a next-generation MCP server that uses real-time WebSocket communication, intelligent token management, and a carefully designed tool surface. Below is a full competitive analysis of every known project, the protocol landscape, Studio API capabilities, and the gaps that define the opportunity.

---

## Twelve projects, three tiers, one shared weakness

The Roblox Studio MCP market breaks into three tiers: official Roblox products, feature-rich community projects, and smaller niche efforts. Every project that interacts with a live Studio instance uses the same three-component architecture: an MCP server (communicating with AI clients via **stdio**), a localhost HTTP bridge, and a Roblox Studio plugin that **polls** the bridge for pending requests. This polling model introduces **200–500ms latency per round trip** and wastes CPU cycles on idle connections.

### Tier 1 — Official Roblox

**Roblox/studio-rust-mcp-server** (344 stars, deprecated) was released May 2025 as an open-source Rust reference implementation with just **5 tools**: `run_code`, `insert_model`, `get_console_output`, `start_stop_play`, and `run_script_in_play_mode`. It used HTTP long-polling between an `axum` web server and a Studio plugin, with stdio transport to AI clients. Roblox deprecated it on March 5, 2026 in favor of a **built-in MCP server natively embedded in Studio**.

The **built-in Studio MCP Server** (March 2026) requires zero setup — no plugins, no binaries, no npm packages. It exposes **~10 tools** including the original 5 plus `list_roblox_studios`, `set_active_studio`, `user_mouse_input`, `user_keyboard_input`, and `character_navigation`. Its killer features are **multi-Studio-instance support** (one MCP client controlling multiple Studio windows) and **virtual input simulation** for automated playtesting. However, it is closed-source, non-customizable, and has a deliberately narrow tool surface that relies on `run_code` as a catch-all rather than offering granular instance-manipulation tools.

### Tier 2 — Feature-rich community projects

**boshyxd/robloxstudio-mcp** (262 stars, 65+ tools, MIT license) is the dominant community project. It evolved rapidly from 18 tools in June 2025 to **65+ tools in v2.5.1** (March 2026), organized across 12 categories: exploration/queries (10 tools), instance management (8), script editing (7), properties (5), attributes/tags (8), terrain (4), UI building (1), code execution/playtest (5), build library (5), Creator Store assets (5), undo/redo (2), and screenshot capture (1). The plugin was rewritten in roblox-ts in v2.3.0, and the project adopted a monorepo structure in v2.4.0 that includes a separate **read-only inspector edition** with 21 tools. Its HTTP bridge runs on **port 58741** with **500ms polling intervals** and 30-second request timeouts. It supports Claude Code, Claude Desktop, Cursor, Windsurf, Codex CLI, and Gemini CLI via standard stdio transport.

**hope1026/weppy-roblox-mcp** (7 stars, freemium) takes a consolidated approach with **21 tools that dispatch to 140+ actions**, includes a web dashboard for monitoring, a VS Code extension for browsing the instance tree, and bidirectional project sync. Pro features ($paid) include bulk operations, terrain generation, spatial analysis, and multi-place support. Its one-line installer auto-registers with six different AI clients.

**Hawknet MCP** ($7.99/month, closed-source) offers **60+ tools**, multi-agent support with conflict prevention, a proprietary "Hawkmerge" undo system, and Open Cloud integration for publishing. It's the only paid-only solution in the space.

### Tier 3 — Niche and specialized projects

| Project | Tools | Unique angle | Stars |
|---------|-------|-------------|-------|
| **n4tivex/mcp-roblox-docs** | 27 | Documentation-only: 850+ classes, 35K+ members, 14K+ FastFlags searchable. No Studio connection needed | 1 |
| **CoderDayton/roblox-bridge-mcp** | 99 ops | Massive operation count via single unified tool, Bun runtime, API key auth | — |
| **Justice219/roblox-studio-mcp** | 14 | Clean modular architecture, Zod validation, Rojo-built plugin | 0 |
| **dax8it/roblox-mcp** | 30+ | Python/FastAPI, **SSE transport** (unique), Open Cloud API integration | 1 |
| **cynisca/roblox-mcp** | ~6 | macOS-only, AppleScript UI automation, screenshot timelapse capture | 0 |
| **code-and-relax fork** | 53+ | **Long polling** (instant response), 62 tests, Vector3 fix | — |

The **notpoiu/roblox-executor-mcp** (8 stars) targets the running game client via third-party executors, not Studio development, and is ethically questionable. The **kkoreilly/roblox-mcp** repository was not found — it appears to have been deleted or made private.

---

## Architectural deep-dive reveals the WebSocket opportunity

Every Studio-interacting MCP server follows the same data flow:

```
AI Client ←stdio→ MCP Server ←HTTP→ Bridge Server ←polling→ Studio Plugin ←API→ DataModel
```

The critical bottleneck is the **plugin-to-bridge communication**. Roblox Studio plugins cannot listen on ports (no HTTP server capability), so they must act as HTTP *clients* polling an external server. Most implementations poll every **200–500ms**, meaning every tool call has a minimum round-trip latency of up to 500ms even for trivial operations.

**The game-changer nobody has exploited**: In October 2025, Roblox added `HttpService:CreateWebStreamClient()` with full **WebSocket support** in Studio plugins. This enables persistent bidirectional connections with the bridge server, eliminating polling entirely. A WebSocket-based architecture would look like:

```
AI Client ←stdio→ MCP Server ←WebSocket→ Studio Plugin ←API→ DataModel
```

This collapses the three-tier architecture into two components. The MCP server runs an HTTP + WebSocket server; the Studio plugin connects once via WebSocket and receives commands instantly. **No existing project uses this architecture.** The code-and-relax fork moved to long polling (a partial improvement), but WebSocket provides true real-time bidirectional communication with zero polling overhead.

Key constraints: Studio limits WebSocket connections to **4 concurrent** and requires Studio-only context (blocked in live experiences). The plugin must handle reconnection gracefully since WebSocket connections can drop.

---

## MCP protocol: what every client actually supports

The MCP specification is at version **2025-11-25**, but client support varies dramatically. The research reveals a clear compatibility matrix:

**stdio is the only universally supported transport.** Claude Desktop supports only stdio for local servers. Codex CLI supports stdio and Streamable HTTP but not SSE. GitHub Copilot supports stdio and Streamable HTTP. Only Claude Code and Windsurf support all three transports. For maximum compatibility, **stdio is non-negotiable**.

**Tools are the only universally supported primitive.** Resources work in Cursor (since v1.6) and Windsurf but not in GitHub Copilot's cloud agent. Prompts have partial support. Sampling is rare. For a Roblox MCP that targets every client, **tools must carry all functionality**.

Critical client-specific constraints worth designing around:

- **Windsurf caps at 100 total tools** across all MCP servers — tool count matters
- **Claude Code warns at 10,000 tokens** per tool output (configurable via `MAX_MCP_OUTPUT_TOKENS`)
- **Claude Code supports Tool Search** for large tool sets, auto-discovering relevant tools on demand
- **Cursor limits server+tool name to ~60 characters** combined
- **Codex CLI** supports per-tool enable/disable via `enabled_tools` and `disabled_tools` in TOML config

Tool annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`) from spec version 2025-06-18 are supported by newer clients and provide valuable safety metadata. Structured output via `outputSchema` enables machine-parseable responses alongside human-readable text.

---

## Roblox Studio plugin APIs are far richer than any MCP exposes

A comprehensive audit of Studio's plugin API surface reveals capabilities that no existing MCP server fully exploits:

**ScriptEditorService** provides `GetEditorSource()`, `UpdateSourceAsync()`, `EditSourceAsyncWithRanges()` for precise range-based editing, `OpenScriptDocumentAsync()`, and event hooks for `TextDocumentDidOpen`, `TextDocumentDidClose`, and `TextDocumentDidChange`. The range-based editing API is particularly powerful — it enables surgical code modifications without rewriting entire scripts. Most MCP servers use only full-source read/write or line-based operations; **none use range-based editing**.

**ChangeHistoryService** has a modern Recording API (`TryBeginRecording`/`FinishRecording`) that boshyxd migrated to in v2.4.0, plus programmatic `Undo()`/`Redo()` and event hooks for `OnRecordingStarted`/`OnRecordingFinished`. This enables proper undo integration where every MCP operation is a single undoable action.

**HttpService** now supports both **WebSocket** and **SSE** via `CreateWebStreamClient()`, with up to 4 concurrent connections, no domain approval needed for localhost, and a **2,000 requests/minute** rate limit for localhost HTTP. WebSocket connections can persist indefinitely with automatic ping/pong handling.

**Selection**, **CollectionService** (tags), **DataModel traversal**, **Instance creation/destruction/cloning**, **Terrain manipulation**, and **InsertService** are all fully accessible. Plugins can also register custom **autocomplete callbacks** and **script analysis callbacks** via ScriptEditorService — enabling an MCP to provide AI-powered autocomplete and linting directly in the Studio editor.

Plugins **cannot**: access the filesystem, spawn processes, run an HTTP server, use raw TCP/UDP sockets, or access `roblox.com` domains. The security sandbox is strict but the API surface within it is extensive.

---

## What the best MCP servers get right

Analysis of the top-performing MCP servers across all domains reveals consistent design principles that most Roblox MCP servers violate:

**Notion's v1→v2 redesign is the canonical lesson.** Notion's first MCP server mapped each API endpoint to one tool — high tool count, massive JSON responses, poor token efficiency. Version 2 consolidated tools around user tasks, converted outputs to **Markdown instead of JSON** (dramatically reducing token consumption), and introduced "data sources" as an abstraction layer. This is exactly the trap boshyxd's 65+ tools fall into — more tools means more context window consumed by tool definitions alone.

**Block's playbook from 60+ internal MCP servers** recommends **5–15 tools per server**, with progressive consolidation over time. Their Linear integration evolved from 30+ tools to a pattern where `get_issue_info(issue_id, info_category)` replaced 7 separate tools. The sweet spot is tools designed around **workflows, not API operations**.

**GitHub's MCP server** (28,300 stars, 51 tools) solves the large-tool-count problem with **toggleable toolsets** and **dynamic tool discovery** — tools are grouped into categories that can be selectively enabled, preventing all 51 tools from loading into context simultaneously.

**Key anti-patterns** observed in the Roblox MCP ecosystem:

- **1:1 API mapping**: Creating separate tools for `get_attribute`, `set_attribute`, `get_attributes`, `delete_attribute`, `get_tags`, `add_tag`, `remove_tag`, `get_tagged` when a consolidated metadata tool would suffice
- **Data dumping**: Returning all scripts including core Roblox scripts, instantly killing Claude Desktop's token budget
- **Ignoring token budgets**: No pagination, truncation, or smart filtering in responses
- **Flat tool namespaces**: 65+ tools listed without grouping or progressive disclosure

The Playwright MCP server demonstrates the value of **smart context representation** — using accessibility tree snapshots instead of full HTML DOM. Applied to Roblox, this means returning concise structural summaries of the DataModel rather than raw property dumps.

---

## Community pain points define the opportunity space

Analysis across GitHub issues, DevForum threads (300+ comments across multiple posts), and Reddit reveals five dominant pain categories:

**Connection reliability is the #1 complaint.** GitHub issues #26, #33, #38 and multiple DevForum reports document connections getting stuck when switching places, false disconnects, plugins entering waiting loops, and EADDRINUSE port conflicts. The polling architecture is fundamentally fragile — missed polls, stale heartbeats, and port conflicts create cascading failures.

**Token efficiency is the #2 complaint.** User "artembon" on DevForum captured it perfectly: "Claude often tries to get all scripts in the game, and the plugin returns all scripts including core roblox scripts. That instantly kills the chat." Free-tier Claude Desktop users are particularly affected. No existing MCP implements pagination, smart filtering, or token-aware truncation.

**Setup complexity deters adoption.** Requiring Node.js, npm, plugin installation, HTTP Request enabling, and client-specific config editing creates a multi-step onboarding that loses users. The Roblox built-in MCP solves this with zero setup, but offers only basic functionality. Documentation staleness (GitHub #32 — settings path changed) compounds the problem.

**Missing Roblox datatype support** was a recurring issue (GitHub #25) — Color3, Vector3, UDim2, CFrame values couldn't be set through property tools until fixed in later versions. This reflects a broader gap: the complexity of Roblox's type system (Enums, CFrames, NumberSequences, ColorSequences, etc.) requires careful serialization logic.

**AI hallucination of Roblox APIs** is a meta-problem. RoCode's developer articulated it: "I got sick of asking for code and getting back deprecated APIs, functions that don't exist, or scripts that try to write to ServerStorage from a LocalScript." This is solvable by combining **n4tivex/mcp-roblox-docs** (27 documentation tools covering 850+ classes) with a Studio interaction server — a combination no project currently offers.

---

## The gap analysis: what a best-in-class Roblox MCP needs

Mapping every capability across all existing projects reveals clear whitespace:

| Capability | Built-in | boshyxd | Weppy | Others | **Gap** |
|-----------|----------|---------|-------|--------|---------|
| WebSocket transport to plugin | ❌ | ❌ | ❌ | ❌ | **Nobody uses it** |
| Token-aware responses | ❌ | ❌ | ❌ | ❌ | **Nobody implements it** |
| Inline API documentation | ❌ | ❌ | ❌ | n4tivex only | **Not combined with Studio tools** |
| Tool annotations (readOnly/destructive) | ❌ | ❌ | ❌ | ❌ | **Nobody uses MCP annotations** |
| Range-based script editing | ❌ | ❌ | ❌ | ❌ | **All use line-based or full replace** |
| Dynamic tool discovery/grouping | ❌ | ❌ | ❌ | ❌ | **All load everything** |
| Script change events (watch mode) | ❌ | ❌ | ❌ | ❌ | **No reactive notifications** |
| Virtual input / playtest automation | ✅ | Partial | ❌ | ❌ | Built-in only |
| Multi-instance support | ✅ | ❌ | ❌ | ❌ | Built-in only |
| Custom autocomplete via MCP | ❌ | ❌ | ❌ | ❌ | **Unexplored API** |
| Structured output schemas | ❌ | ❌ | ❌ | ❌ | **Nobody uses outputSchema** |
| Consolidated workflow tools | ❌ | ❌ | Partial | ❌ | **Most use 1:1 API mapping** |
| Proper error recovery guidance | ❌ | ❌ | ❌ | ❌ | **Errors lack actionable context** |

---

## Designing the optimal architecture

Based on this complete landscape analysis, the ideal Roblox Studio MCP server would exploit every identified gap:

**WebSocket-first communication** eliminates the polling bottleneck. The MCP server starts an HTTP + WebSocket server on localhost. The Studio plugin connects via `HttpService:CreateWebStreamClient(WebSocket, {Url="ws://localhost:PORT"})` once, then receives commands and returns results over the persistent connection. Fallback to HTTP polling ensures compatibility with older Studio versions.

**Workflow-oriented tool design** with **15–25 tools** organized into logical groups, consolidating boshyxd's 65 tools without losing capability. Following Block's playbook: `explore_datamodel(path, depth, filter)` replaces 5 separate query tools; `modify_instances(operations[])` handles create, delete, clone, reparent in batch; `edit_script(path, edits[])` supports range-based, line-based, and full-source editing in one tool with proper diffing.

**Token-aware responses** with configurable output limits, smart truncation ("showing 20 of 847 scripts — use filter parameter to narrow"), and Markdown-formatted output instead of raw JSON. Every response includes a token estimate and offers pagination when results exceed thresholds.

**Embedded Roblox API context** by bundling a lightweight version of n4tivex's documentation index, so the AI assistant has access to correct API signatures, enum values, and class hierarchies without consuming extra tool calls or relying on potentially-hallucinated training data.

**Tool annotations on every tool** marking read-only tools (`get_*`), destructive tools (`delete_*`), and idempotent operations, enabling clients to show appropriate confirmation UIs and batch safe operations.

**Zero-config installation** via `npx -y roblox-studio-mcp@latest --install-plugin` that auto-installs the Studio plugin and outputs config JSON for the detected AI client, following Weppy's one-line-install pattern.

## Conclusion

The Roblox Studio MCP ecosystem is young, fragmented, and ripe for disruption. Roblox's built-in server is authoritative but deliberately minimal. boshyxd's project leads the community with 65+ tools but suffers from architectural debt (polling), token inefficiency, and connection fragility. Nobody has exploited Studio's WebSocket support, tool annotations, range-based script editing, or token-aware response design. The n4tivex documentation server and Studio interaction servers remain separate projects that should be unified. The competitive moat for a new entrant is clear: **real-time WebSocket communication, workflow-oriented tool consolidation (not 65 separate tools), built-in Roblox API knowledge, and aggressive token efficiency** — all open-source, free, and compatible with every MCP client via stdio transport. The community is vocal about what they need; the gap is purely in execution.