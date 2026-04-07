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

usage() {
  echo -e "${CYAN}Conduit MCP Publisher${NC}"
  echo ""
  echo "Usage: ./scripts/publish.sh [command] [options]"
  echo ""
  echo "Commands:"
  echo "  plugin          Build plugin and copy to Roblox Plugins"
  echo "  server [bump]   Build, bump version, and publish to npm"
  echo "                  bump: patch (default), minor, major"
  echo "  all [bump]      Do both plugin and server"
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

publish_plugin() {
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
  local bump="${1:-patch}"

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

  # Version bump
  echo -e "${CYAN}[server]${NC} Bumping version ($bump)..."
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[server]${NC} DRY RUN - would bump $bump and publish"
    npm version "$bump" --no-git-tag-version --dry-run 2>/dev/null || true
    npm publish --dry-run
  else
    npm version "$bump" --no-git-tag-version
    NEW_VERSION=$(node -p "require('./package.json').version")
    echo -e "${GREEN}[server]${NC} Version → $NEW_VERSION"

    # Publish
    echo -e "${CYAN}[server]${NC} Publishing to npm..."
    npm publish
    echo -e "${GREEN}[server]${NC} Published conduit-mcp@$NEW_VERSION!"
  fi
}

case "$COMMAND" in
  plugin)
    publish_plugin
    ;;
  server)
    publish_server "$BUMP"
    ;;
  all)
    publish_plugin
    echo ""
    publish_server "$BUMP"
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
