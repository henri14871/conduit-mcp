import { describe, it, expect } from "vitest";
import { estimateTokens, truncateToTokenBudget } from "../utils/tokens.js";

describe("estimateTokens", () => {
  it("returns 0 for empty string", () => {
    expect(estimateTokens("")).toBe(0);
  });

  it("estimates based on 4 chars per token", () => {
    expect(estimateTokens("abcd")).toBe(1);
    expect(estimateTokens("abcde")).toBe(2);
    expect(estimateTokens("a".repeat(100))).toBe(25);
  });
});

describe("truncateToTokenBudget", () => {
  it("returns text unchanged when under budget", () => {
    const text = "Hello world";
    const result = truncateToTokenBudget(text, 100);
    expect(result.text).toBe(text);
    expect(result.truncated).toBe(false);
  });

  it("truncates text that exceeds budget", () => {
    const text = "a".repeat(100);
    const result = truncateToTokenBudget(text, 5); // 5 tokens = 20 chars
    expect(result.truncated).toBe(true);
    // The truncated text starts with only 20 chars of 'a', but includes the notice
    expect(result.text.startsWith("a".repeat(20))).toBe(true);
    expect(result.text).toContain("Truncated");
  });

  it("cuts at last newline when possible", () => {
    const text = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8";
    const result = truncateToTokenBudget(text, 5);
    expect(result.truncated).toBe(true);
    // Should cut cleanly at a newline boundary
    expect(result.text).not.toMatch(/line\d[^*\n]/);
  });

  it("includes token estimates in truncation notice", () => {
    const text = "a".repeat(200);
    const result = truncateToTokenBudget(text, 10);
    expect(result.text).toContain("~10");
    expect(result.text).toContain("~50");
  });
});
