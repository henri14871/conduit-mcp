import { randomUUID } from "node:crypto";

// ── Server → Plugin ──────────────────────────────────────────────
export interface BridgeRequest {
  id: string;
  method: string;
  params: Record<string, unknown>;
  sessionId?: string;
}

// ── Plugin → Server (success) ────────────────────────────────────
export interface BridgeResponse {
  id: string;
  result: unknown;
  tokenEstimate?: number;
}

// ── Plugin → Server (error) ──────────────────────────────────────
export interface BridgeError {
  id: string;
  error: { code: string; message: string };
}

// ── Plugin → Server (heartbeat) ──────────────────────────────────
export interface Heartbeat {
  type: "heartbeat";
}

// ── Plugin → Server (studio registration) ────────────────────────
export interface StudioRegistration {
  type: "register";
  studioId: string;
  placeId?: number;
  placeName?: string;
}

// ── Studio metadata ──────────────────────────────────────────────
export interface StudioInfo {
  studioId: string;
  placeId?: number;
  placeName?: string;
  connectedAt: number;
}

export type PluginMessage =
  | BridgeResponse
  | BridgeError
  | Heartbeat
  | StudioRegistration;

// ── Pending request tracking ─────────────────────────────────────
export interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

// ── Helpers ──────────────────────────────────────────────────────
export function generateId(): string {
  return randomUUID().slice(0, 8);
}

export function isHeartbeat(msg: unknown): msg is Heartbeat {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "type" in msg &&
    (msg as Heartbeat).type === "heartbeat"
  );
}

export function isStudioRegistration(
  msg: unknown,
): msg is StudioRegistration {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "type" in msg &&
    (msg as StudioRegistration).type === "register" &&
    "studioId" in msg
  );
}

export function isBridgeError(msg: unknown): msg is BridgeError {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "id" in msg &&
    "error" in msg
  );
}

export function isBridgeResponse(msg: unknown): msg is BridgeResponse {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "id" in msg &&
    "result" in msg
  );
}
