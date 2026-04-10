# Conduit MCP - WebSocket bridge for AI coding in Studio

Are you tired of slow mcp tools created with by AI without any thought put into them that require 10+ calls to do simple multi-script edits, and waste half your context window just reading tool definitions?

**Conduit** is an MCP server that connects AI assistants (Claude, Cursor, Windsurf, etc.) to Roblox Studio over WebSocket instead of HTTP polling. Every request takes <50ms instead of 200-500ms, and the AI burns way fewer tokens per interaction because the tools are designed around actual workflows and not just 1:1 API mappings.

[image of the plugin GUI connected in Studio]

## How it works

```
AI Client <--stdio--> Conduit Server <--WebSocket--> Studio Plugin
```

You run `npx conduit-mcp`, open Studio, and the plugin auto-connects. That's it. Your AI can now read scripts, edit code, create instances, run playtests, inspect values at runtime; all through a persistent connection.

## What it can do

- **Read & edit scripts** — line ranges, find/replace, batch multi-script refactors in one call
- **Script outlines** — returns function signatures without dumping full source, saves a ton of tokens on big scripts
- **Explore the tree** — browse instances, get properties, query by class/tag/attribute, grep across scripts
- **Create, modify, delete** instances in bulk
- **Playtest control** — start/stop, execute code, read console output, inspect runtime values
- **Terrain & environment** — fill, clear, read terrain, tweak Lighting/Workspace settings
- **Transactional undo** — group a bunch of AI edits into a single Ctrl+Z
- **Multi-Studio support** — connect multiple Studio instances at once

[image of AI editing a script through Conduit in real-time]

## Install

```bash
npx conduit-mcp --install
```

This installs the Studio plugin and shows the config snippet for your AI client. Add `--auto-config` if you want it to set up Claude/Cursor automatically.

Or add it manually to your MCP config:
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

## Why I built this

I was using other MCP tools for a while and kept running into the same problems.. the AI would waste half its context window just reading tool definitions, every operation had noticeable lag from HTTP polling, and multi-script edits required like 10 separate calls. Conduit collapses all of that into 19 workflow-oriented tools over a persistent WebSocket. The difference is pretty immediately obvious when you use it.

[image of before/after token usage comparison, or a short clip of a fast multi-edit]

## Links

- GitHub: https://github.com/henri14871/conduit-mcp
- npm: `conduit-mcp`

Still actively working on this. Open to feedback and feature suggestions. lmk if you run into any issues or have ideas.
