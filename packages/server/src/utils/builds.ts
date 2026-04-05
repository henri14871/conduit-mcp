import { homedir } from "node:os";
import { join } from "node:path";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
} from "node:fs";

const BUILDS_DIR = join(homedir(), ".conduit", "builds");

function ensureDir(): void {
  if (!existsSync(BUILDS_DIR)) {
    mkdirSync(BUILDS_DIR, { recursive: true });
  }
}

export interface BuildMetadata {
  name: string;
  description?: string;
  createdAt: string;
  rootClassName: string;
  childCount: number;
}

export interface BuildFile {
  name: string;
  description?: string;
  createdAt: string;
  root: unknown;
}

export function saveBuild(
  name: string,
  root: unknown,
  description?: string,
): BuildMetadata {
  ensureDir();
  const rootObj = root as { className?: string; children?: unknown[] };
  const data: BuildFile = {
    name,
    description,
    createdAt: new Date().toISOString(),
    root,
  };
  const filePath = join(BUILDS_DIR, `${name}.json`);
  writeFileSync(filePath, JSON.stringify(data, null, 2), "utf-8");
  return {
    name,
    description,
    createdAt: data.createdAt,
    rootClassName: rootObj.className ?? "unknown",
    childCount: rootObj.children?.length ?? 0,
  };
}

export function loadBuild(name: string): BuildFile {
  const filePath = join(BUILDS_DIR, `${name}.json`);
  if (!existsSync(filePath)) {
    throw new Error(`Build "${name}" not found. Use builds --action list to see available builds.`);
  }
  return JSON.parse(readFileSync(filePath, "utf-8")) as BuildFile;
}

export function listBuilds(): BuildMetadata[] {
  ensureDir();
  const files = readdirSync(BUILDS_DIR).filter((f) => f.endsWith(".json"));
  return files.map((f) => {
    const filePath = join(BUILDS_DIR, f);
    try {
      const data = JSON.parse(readFileSync(filePath, "utf-8")) as BuildFile;
      const rootObj = data.root as { className?: string; children?: unknown[] };
      return {
        name: data.name,
        description: data.description,
        createdAt: data.createdAt,
        rootClassName: rootObj.className ?? "unknown",
        childCount: rootObj.children?.length ?? 0,
      };
    } catch {
      const stat = statSync(filePath);
      return {
        name: f.replace(".json", ""),
        createdAt: stat.mtime.toISOString(),
        rootClassName: "unknown",
        childCount: 0,
      };
    }
  });
}
