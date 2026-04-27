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

// ── Server → Plugin (heartbeat acknowledgment) ──────────────────
export interface HeartbeatAck {
  type: "heartbeat_ack";
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
  // Studio the request was dispatched to (null if queued for HTTP fallback before
  // any studio was known). Used to fail-fast when that specific studio drops, so
  // the caller doesn't sit on a 60s timeout waiting for a reply that can never
  // arrive (the plugin clears its router state on reconnect).
  studioId: string | null;
}

// ── Helpers ──────────────────────────────────────────────────────
export function generateId(): string {
  return randomUUID().slice(0, 16);
}

export function isHeartbeat(msg: unknown): msg is Heartbeat {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "type" in msg &&
    (msg as Heartbeat).type === "heartbeat"
  );
}

export function isHeartbeatAck(msg: unknown): msg is HeartbeatAck {
  return (
    typeof msg === "object" &&
    msg !== null &&
    "type" in msg &&
    (msg as HeartbeatAck).type === "heartbeat_ack"
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
