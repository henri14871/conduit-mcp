import { describe, it, expect } from "vitest";
import { searchApi, formatSearchResults } from "../context/api-index.js";

describe("searchApi", () => {
  it("returns results for common classes", () => {
    const results = searchApi("BasePart");
    expect(results.length).toBeGreaterThan(0);
    expect(results.some((r) => r.name === "BasePart")).toBe(true);
  });

  it("returns empty for gibberish queries", () => {
    const results = searchApi("zzzznotarealclass12345");
    expect(results).toHaveLength(0);
  });

  it("sorts exact matches first", () => {
    const results = searchApi("Part");
    if (results.length >= 2) {
      const exactIdx = results.findIndex((r) => r.name === "Part");
      const nonExactIdx = results.findIndex(
        (r) => r.name !== "Part" && r.name.includes("Part"),
      );
      if (exactIdx !== -1 && nonExactIdx !== -1) {
        expect(exactIdx).toBeLessThan(nonExactIdx);
      }
    }
  });

  it("respects maxResults parameter", () => {
    const results = searchApi("a", 3);
    expect(results.length).toBeLessThanOrEqual(3);
  });

  it("searches across properties and methods", () => {
    const results = searchApi("Position");
    expect(results.some((r) => r.type === "property")).toBe(true);
  });
});

describe("formatSearchResults", () => {
  it("returns no-results message for empty array", () => {
    const text = formatSearchResults([]);
    expect(text).toContain("No results found");
  });

  it("formats results with type prefix", () => {
    const results = searchApi("BasePart", 3);
    const text = formatSearchResults(results);
    expect(text).toContain("###");
    expect(text).toContain("BasePart");
  });
});
