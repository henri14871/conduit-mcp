import { estimateTokens, truncateToTokenBudget } from "./tokens.js";

const DEFAULT_TOKEN_BUDGET = 4000;

interface TreeNode {
  name: string;
  className: string;
  children?: TreeNode[];
  properties?: Record<string, unknown>;
}

export function formatTree(
  data: TreeNode,
  depth: number = 0,
  indent: string = "",
): string {
  let line = `${indent}- **${data.name}** \`${data.className}\``;

  if (data.properties && Object.keys(data.properties).length > 0) {
    const props = Object.entries(data.properties)
      .map(([k, v]) => `${k}=${formatValue(v)}`)
      .join(", ");
    line += ` (${props})`;
  }

  let result = line + "\n";

  if (data.children && depth > 0) {
    for (const child of data.children) {
      result += formatTree(child, depth - 1, indent + "  ");
    }
  } else if (data.children && data.children.length > 0) {
    result += `${indent}  *… ${data.children.length} children*\n`;
  }

  return result;
}

export function formatInstanceList(
  instances: Array<{ path: string; className: string }>,
): string {
  if (instances.length === 0) return "*No instances found.*";
  return instances.map((i) => `- **${i.path}** \`${i.className}\``).join("\n");
}

export function formatScript(source: string, path: string): string {
  return `### ${path}\n\`\`\`lua\n${source}\n\`\`\``;
}

export function applyTokenBudget(
  text: string,
  maxTokens?: number,
): string {
  const budget = maxTokens ?? DEFAULT_TOKEN_BUDGET;
  const { text: result } = truncateToTokenBudget(text, budget);
  return result;
}

function formatValue(v: unknown): string {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "string") return `"${v}"`;
  if (typeof v === "object") {
    const obj = v as Record<string, unknown>;
    if (obj.Type) return `${obj.Type}(…)`;
    return JSON.stringify(v);
  }
  return String(v);
}
