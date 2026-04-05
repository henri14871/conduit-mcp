import { describe, it, expect } from "vitest";
import {
  generateId,
  isHeartbeat,
  isStudioRegistration,
  isBridgeError,
  isBridgeResponse,
} from "../protocol.js";

describe("generateId", () => {
  it("returns an 8-character string", () => {
    const id = generateId();
    expect(id).toHaveLength(8);
    expect(typeof id).toBe("string");
  });

  it("generates unique IDs", () => {
    const ids = new Set(Array.from({ length: 100 }, () => generateId()));
    expect(ids.size).toBe(100);
  });
});

describe("isHeartbeat", () => {
  it("returns true for heartbeat messages", () => {
    expect(isHeartbeat({ type: "heartbeat" })).toBe(true);
  });

  it("returns false for non-heartbeat", () => {
    expect(isHeartbeat({ type: "register" })).toBe(false);
    expect(isHeartbeat(null)).toBe(false);
    expect(isHeartbeat({})).toBe(false);
    expect(isHeartbeat("heartbeat")).toBe(false);
  });
});

describe("isStudioRegistration", () => {
  it("returns true for valid registration", () => {
    expect(
      isStudioRegistration({
        type: "register",
        studioId: "abc123",
        placeId: 12345,
        placeName: "My Game",
      }),
    ).toBe(true);
  });

  it("returns true without optional fields", () => {
    expect(
      isStudioRegistration({ type: "register", studioId: "abc123" }),
    ).toBe(true);
  });

  it("returns false without studioId", () => {
    expect(isStudioRegistration({ type: "register" })).toBe(false);
  });

  it("returns false for wrong type", () => {
    expect(
      isStudioRegistration({ type: "heartbeat", studioId: "abc" }),
    ).toBe(false);
  });

  it("returns false for non-objects", () => {
    expect(isStudioRegistration(null)).toBe(false);
    expect(isStudioRegistration(42)).toBe(false);
  });
});

describe("isBridgeResponse", () => {
  it("returns true for valid response", () => {
    expect(isBridgeResponse({ id: "abc", result: { data: true } })).toBe(true);
  });

  it("returns true for null result", () => {
    expect(isBridgeResponse({ id: "abc", result: null })).toBe(true);
  });

  it("returns false without id", () => {
    expect(isBridgeResponse({ result: {} })).toBe(false);
  });

  it("returns false without result", () => {
    expect(isBridgeResponse({ id: "abc" })).toBe(false);
  });
});

describe("isBridgeError", () => {
  it("returns true for valid error", () => {
    expect(
      isBridgeError({
        id: "abc",
        error: { code: "NOT_FOUND", message: "Not found" },
      }),
    ).toBe(true);
  });

  it("returns false without error field", () => {
    expect(isBridgeError({ id: "abc" })).toBe(false);
  });

  it("returns false for non-objects", () => {
    expect(isBridgeError(null)).toBe(false);
    expect(isBridgeError(undefined)).toBe(false);
  });
});
