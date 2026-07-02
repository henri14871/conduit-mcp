#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/packages/plugin"
SERVER_DIR="$ROOT_DIR/packages/server"
ROBLOX_PLUGINS="$LOCALAPPDATA/Roblox/Plugins"

# Load .env if it exists (for NPM_TOKEN)
if [ -f "$ROOT_DIR/.env" ]; then
  export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

usage() {
  echo -e "${CYAN}Conduit MCP Publisher${NC}"
  echo ""
  echo "Usage: ./scripts/publish.sh [command] [options]"
  echo ""
  echo "Commands:"
  echo "  plugin          Sync version, build plugin, copy to Roblox Plugins"
  echo "  server [bump]   Bump version, rebuild plugin, publish server to npm"
  echo "                  bump: patch (default), minor, major"
  echo "  all [bump]      Same as server (plugin ships inside the npm package)"
  echo ""
  echo "Options:"
  echo "  --dry-run       Show what would happen without doing it"
  echo "  --skip-tests    Skip running tests before publish"
  exit 0
}

DRY_RUN=false
SKIP_TESTS=false

# Parse flags
ARGS=()
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    *) ARGS+=("$arg") ;;
  esac
done

COMMAND="${ARGS[0]:-}"
BUMP="${ARGS[1]:-patch}"

# Keep the plugin's reported version in lockstep with the server package —
# the server warns users when a connected plugin's version doesn't match.
sync_plugin_version() {
  local version
  version=$(cd "$SERVER_DIR" && node -p "require('./package.json').version")
  cat > "$PLUGIN_DIR/src/Version.luau" <<EOF
--!strict
-- Auto-synced from packages/server/package.json by scripts/publish.sh — do not edit manually.
return "$version"
EOF
  echo -e "${GREEN}[plugin]${NC} Version.luau → $version"
}

bump_version() {
  local bump="${1:-patch}"
  cd "$SERVER_DIR"
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[server]${NC} DRY RUN - would bump $bump"
    return
  fi
  npm version "$bump" --no-git-tag-version
  local new_version
  new_version=$(node -p "require('./package.json').version")
  echo -e "${GREEN}[server]${NC} Version → $new_version"
}

publish_plugin() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[plugin]${NC} DRY RUN - would sync Version.luau, build with Rojo, and install to $ROBLOX_PLUGINS"
    return
  fi

  sync_plugin_version

  echo -e "${CYAN}[plugin]${NC} Building with Rojo..."

  rojo build "$PLUGIN_DIR" --output "$SERVER_DIR/plugin/Conduit.rbxm"
  echo -e "${GREEN}[plugin]${NC} Built → packages/server/plugin/Conduit.rbxm"

  # Copy to root for distribution
  cp "$SERVER_DIR/plugin/Conduit.rbxm" "$ROOT_DIR/Conduit.rbxm"
  echo -e "${GREEN}[plugin]${NC} Copied → Conduit.rbxm (root)"

  # Copy to Roblox Studio plugins
  if [ -d "$ROBLOX_PLUGINS" ]; then
    cp "$SERVER_DIR/plugin/Conduit.rbxm" "$ROBLOX_PLUGINS/Conduit.rbxm"
    echo -e "${GREEN}[plugin]${NC} Installed → $ROBLOX_PLUGINS/Conduit.rbxm"
  else
    echo -e "${YELLOW}[plugin]${NC} Roblox Plugins directory not found, skipping local install"
  fi

  echo -e "${GREEN}[plugin]${NC} Done!"
}

publish_server() {
  # Run tests first
  if [ "$SKIP_TESTS" = false ]; then
    echo -e "${CYAN}[server]${NC} Running tests..."
    cd "$SERVER_DIR"
    pnpm test
    echo -e "${GREEN}[server]${NC} Tests passed!"
  fi

  # Build
  echo -e "${CYAN}[server]${NC} Building with tsup..."
  cd "$SERVER_DIR"
  pnpm build
  echo -e "${GREEN}[server]${NC} Built!"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[server]${NC} DRY RUN - would publish"
    npm publish --dry-run
  else
    NEW_VERSION=$(node -p "require('./package.json').version")
    echo -e "${CYAN}[server]${NC} Publishing to npm..."
    if [ -n "$NPM_TOKEN" ]; then
      npm publish --//registry.npmjs.org/:_authToken="$NPM_TOKEN"
    else
      echo -e "${RED}[server]${NC} NPM_TOKEN not set. Add it to .env or export it."
      exit 1
    fi
    echo -e "${GREEN}[server]${NC} Published conduit-mcp@$NEW_VERSION!"
  fi
}

# Bump FIRST so the plugin build embeds the same version the server publishes
# with — the plugin ships inside the npm tarball and reports its version to
# the server at registration.
case "$COMMAND" in
  plugin)
    publish_plugin
    ;;
  server|all)
    bump_version "$BUMP"
    publish_plugin
    echo ""
    publish_server
    echo ""
    echo -e "${GREEN}All done!${NC}"
    ;;
  --help|-h|"")
    usage
    ;;
  *)
    echo -e "${RED}Unknown command: $COMMAND${NC}"
    usage
    ;;
esac
