import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

let cached: string | null = null;

/**
 * Version of this conduit-mcp package. Resolved from package.json at runtime:
 * one level up when running from the published dist/ bundle, two levels up
 * when running from src/ (dev, vitest).
 */
export function getServerVersion(): string {
  if (cached) return cached;
  const here = dirname(fileURLToPath(import.meta.url));
  for (const rel of ["..", join("..", "..")]) {
    try {
      const pkg = JSON.parse(
        readFileSync(join(here, rel, "package.json"), "utf-8"),
      );
      if (pkg.name === "conduit-mcp" && typeof pkg.version === "string") {
        const version: string = pkg.version;
        cached = version;
        return version;
      }
    } catch {
      // keep walking
    }
  }
  cached = "unknown";
  return cached;
}
