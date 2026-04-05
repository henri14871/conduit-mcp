# Contributing to Conduit MCP

Thanks for your interest in contributing!

## Setup

```bash
git clone https://github.com/henri-knightco/conduit-mcp.git
cd conduit-mcp
pnpm install
pnpm build
```

## Development

**Server** (TypeScript):

```bash
pnpm dev          # watch mode — rebuilds on change
```

The MCP server lives in `packages/server/`. It communicates with AI clients via stdio and with the Studio plugin via WebSocket on port 3200.

**Plugin** (Luau):

The plugin lives in `packages/plugin/` and is built with [Rojo](https://rojo.space/):

```bash
rojo build packages/plugin --output Conduit.rbxm
```

Copy `Conduit.rbxm` to your Roblox Studio plugins folder:
- **Windows:** `%LOCALAPPDATA%/Roblox/Plugins/`
- **macOS:** `~/Documents/Roblox/Plugins/`

## Testing in Studio

1. Build the server: `pnpm build`
2. Start the server: `node packages/server/dist/cli.js`
3. Open Roblox Studio and open any place
4. Enable HttpService if prompted (Game Settings > Security > Allow HTTP Requests)
5. The plugin auto-connects -- you should see `[Conduit] Connected via WebSocket` in the output

## Pull Requests

- Describe what your PR does and why
- Run `pnpm build` before submitting -- it should pass cleanly
- Keep changes focused -- one feature or fix per PR
