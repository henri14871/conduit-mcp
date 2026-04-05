import { describe, it, expect } from "vitest";
import {
  formatTree,
  formatInstanceList,
  formatScript,
  applyTokenBudget,
} from "../utils/formatting.js";

describe("formatTree", () => {
  it("formats a single node", () => {
    const result = formatTree(
      { name: "Part", className: "Part", children: [] },
      0,
    );
    expect(result).toContain("**Part**");
    expect(result).toContain("`Part`");
  });

  it("includes properties when present", () => {
    const result = formatTree({
      name: "Part",
      className: "Part",
      properties: { Anchored: true, Size: "4, 1, 2" },
    });
    expect(result).toContain("Anchored=true");
    expect(result).toContain('Size="4, 1, 2"');
  });

  it("recurses into children with proper indentation", () => {
    const result = formatTree(
      {
        name: "Workspace",
        className: "Workspace",
        children: [
          { name: "Part", className: "Part" },
          { name: "Model", className: "Model" },
        ],
      },
      2,
    );
    expect(result).toContain("  - **Part**");
    expect(result).toContain("  - **Model**");
  });

  it("shows child count when depth is 0", () => {
    const result = formatTree(
      {
        name: "Workspace",
        className: "Workspace",
        children: [
          { name: "A", className: "Part" },
          { name: "B", className: "Part" },
        ],
      },
      0,
    );
    expect(result).toContain("2 children");
  });
});

describe("formatInstanceList", () => {
  it("returns no-results message for empty array", () => {
    expect(formatInstanceList([])).toBe("*No instances found.*");
  });

  it("formats instance entries", () => {
    const result = formatInstanceList([
      { path: "game.Workspace.Part", className: "Part" },
    ]);
    expect(result).toContain("game.Workspace.Part");
    expect(result).toContain("`Part`");
  });
});

describe("formatScript", () => {
  it("wraps source in lua code block with path header", () => {
    const result = formatScript("print('hello')", "game.ServerScriptService.Test");
    expect(result).toContain("### game.ServerScriptService.Test");
    expect(result).toContain("```lua");
    expect(result).toContain("print('hello')");
  });
});

describe("applyTokenBudget", () => {
  it("returns text unchanged when under default budget", () => {
    const text = "short text";
    expect(applyTokenBudget(text)).toBe(text);
  });

  it("truncates when over explicit budget", () => {
    const text = "a".repeat(500);
    const result = applyTokenBudget(text, 10);
    expect(result.length).toBeLessThan(text.length);
    expect(result).toContain("Truncated");
  });

  it("passes through with custom budget", () => {
    const text = "a".repeat(100);
    const result = applyTokenBudget(text, 1000);
    expect(result).toBe(text);
  });
});
