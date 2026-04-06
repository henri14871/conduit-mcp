import { EventEmitter } from "node:events";
import http from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import {
  type BridgeRequest,
  type PendingRequest,
  type StudioInfo,
  generateId,
  isHeartbeat,
  isStudioRegistration,
  isBridgeError,
  isBridgeResponse,
} from "./protocol.js";
import { log } from "./utils/logger.js";

const REQUEST_TIMEOUT_MS = 30_000;
const HEARTBEAT_CHECK_INTERVAL_MS = 5_000;
const HEARTBEAT_TIMEOUT_MS = 15_000;
const LONG_POLL_TIMEOUT_MS = 25_000;
const MAX_PORT_RETRIES = 10;

interface StudioConnection {
  ws: WebSocket;
  info: StudioInfo;
}

export class Bridge extends EventEmitter {
  private httpServer: http.Server | null = null;
  private wsServer: WebSocketServer | null = null;
  private studios = new Map<string, StudioConnection>();
  private activeStudioId: string | null = null;
  private pendingRequests = new Map<string, PendingRequest>();
  private lastHeartbeats = new Map<string, number>();
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private actualPort = 0;

  // HTTP-only studios (no WebSocket connection)
  private httpStudios = new Map<string, StudioInfo>();

  // Unregistered WebSocket connections waiting for a registration message
  private pendingWs = new Set<WebSocket>();

  // HTTP fallback state (per-studio)
  private httpPendingCommands = new Map<string, BridgeRequest[]>();
  private httpPollWaiters = new Map<
    string,
    Array<{ res: http.ServerResponse; timer: ReturnType<typeof setTimeout> }>
  >();

  constructor(private port: number = 3200) {
    super();
  }

  get isConnected(): boolean {
    // True if ANY studio is connected (WebSocket or HTTP)
    for (const [, studio] of this.studios) {
      if (studio.ws.readyState === WebSocket.OPEN) return true;
    }
    return this.httpStudios.size > 0;
  }

  get listeningPort(): number {
    return this.actualPort;
  }

  // ── Public studio management ───────────────────────────────────

  getStudios(): StudioInfo[] {
    const wsStudios = Array.from(this.studios.values()).map((s) => s.info);
    const httpOnly = Array.from(this.httpStudios.values()).filter(
      (s) => !this.studios.has(s.studioId),
    );
    return [...wsStudios, ...httpOnly];
  }

  getActiveStudioId(): string | null {
    return this.activeStudioId;
  }

  setActiveStudio(studioId: string): void {
    if (!this.studios.has(studioId) && !this.httpStudios.has(studioId)) {
      throw new Error(
        `Studio "${studioId}" is not connected. Connected studios: ${
          this.getStudios().map((s) => s.studioId).join(", ") || "none"
        }`,
      );
    }
    this.activeStudioId = studioId;
    log.info(`Active studio set to: ${studioId}`);
  }

  // ── Server lifecycle ───────────────────────────────────────────

  async start(): Promise<number> {
    return new Promise((resolve, reject) => {
      let attempts = 0;
      const tryPort = (port: number) => {
        const server = http.createServer((req, res) =>
          this.handleHttp(req, res),
        );

        server.once("error", (err: NodeJS.ErrnoException) => {
          if (err.code === "EADDRINUSE" && attempts < MAX_PORT_RETRIES) {
            attempts++;
            tryPort(port + 1);
          } else {
            reject(err);
          }
        });

        server.listen(port, "127.0.0.1", () => {
          this.httpServer = server;
          this.actualPort = port;
          this.wsServer = new WebSocketServer({ server });
          this.wsServer.on("connection", (ws) => this.handleWsConnection(ws));
          log.info(`Bridge listening on 127.0.0.1:${port}`);
          resolve(port);
        });
      };

      tryPort(this.port);
    });
  }

  async stop(): Promise<void> {
    // Reject all pending requests
    for (const [id, pending] of this.pendingRequests) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Bridge shutting down"));
      this.pendingRequests.delete(id);
    }

    // Close all studio connections
    for (const [, studio] of this.studios) {
      studio.ws.close();
    }
    this.studios.clear();
    this.httpStudios.clear();
    this.activeStudioId = null;

    // Close pending unregistered connections
    for (const ws of this.pendingWs) {
      ws.close();
    }
    this.pendingWs.clear();

    // Stop heartbeat
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }

    // Close HTTP long-poll waiters and reject their pending requests
    for (const [, waiters] of this.httpPollWaiters) {
      for (const waiter of waiters) {
        clearTimeout(waiter.timer);
        waiter.res.writeHead(503);
        waiter.res.end();
      }
    }
    this.httpPollWaiters.clear();
    this.httpPendingCommands.clear();

    // Close servers
    await new Promise<void>((resolve) => {
      if (this.wsServer) {
        this.wsServer.close(() => {
          this.wsServer = null;
          if (this.httpServer) {
            this.httpServer.close(() => {
              this.httpServer = null;
              resolve();
            });
          } else {
            resolve();
          }
        });
      } else if (this.httpServer) {
        this.httpServer.close(() => {
          this.httpServer = null;
          resolve();
        });
      } else {
        resolve();
      }
    });
  }

  async send(
    method: string,
    params: Record<string, unknown>,
  ): Promise<unknown> {
    const id = generateId();
    const request: BridgeRequest = { id, method, params };
    const json = JSON.stringify(request);

    // Resolve which studio to target
    const studio = this.resolveTargetStudio();

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(
          new Error(
            `Request ${method} timed out after ${REQUEST_TIMEOUT_MS}ms — is the Conduit plugin running in Roblox Studio?`,
          ),
        );
      }, REQUEST_TIMEOUT_MS);

      this.pendingRequests.set(id, { resolve, reject, timer });

      if (studio) {
        studio.ws.send(json);
      } else {
        // Queue for HTTP fallback using active studio ID
        const studioId = this.activeStudioId ?? "_default";
        const queue = this.httpPendingCommands.get(studioId) ?? [];
        queue.push(request);
        this.httpPendingCommands.set(studioId, queue);
        this.flushHttpPollers(studioId);
      }
    });
  }

  // ── Internal helpers ───────────────────────────────────────────

  private getActiveStudio(): StudioConnection | undefined {
    if (this.activeStudioId) {
      return this.studios.get(this.activeStudioId);
    }
    return undefined;
  }

  private resolveTargetStudio(): StudioConnection | undefined {
    // If active studio is set and connected, use it
    const active = this.getActiveStudio();
    if (active && active.ws.readyState === WebSocket.OPEN) {
      return active;
    }

    // Active studio is gone or stale — try to auto-select any open studio
    for (const [studioId, studio] of this.studios) {
      if (studio.ws.readyState === WebSocket.OPEN) {
        this.activeStudioId = studioId;
        log.info(`Auto-selected active studio: ${studioId}`);
        return studio;
      }
    }

    // No valid WebSocket target — will fall through to HTTP fallback
    return undefined;
  }

  // ── WebSocket handling ─────────────────────────────────────────

  private handleWsConnection(ws: WebSocket): void {
    log.info("New WebSocket connection — waiting for registration");
    this.pendingWs.add(ws);

    const onFirstMessage = (data: Buffer | string) => {
      try {
        const msg = JSON.parse(data.toString());

        if (isStudioRegistration(msg)) {
          ws.removeListener("message", onFirstMessage);
          this.pendingWs.delete(ws);
          this.registerStudio(ws, {
            studioId: msg.studioId,
            placeId: msg.placeId,
            placeName: msg.placeName,
            connectedAt: Date.now(),
          });
          return;
        }

        // Legacy plugin (no registration) — assign synthetic ID
        ws.removeListener("message", onFirstMessage);
        this.pendingWs.delete(ws);
        const syntheticId = `studio-legacy-${Date.now()}`;
        log.info(
          "Legacy plugin detected (no registration), assigning ID: " +
            syntheticId,
        );
        this.registerStudio(ws, {
          studioId: syntheticId,
          connectedAt: Date.now(),
        });
        // Re-process the message we just received
        this.handlePluginMessage(msg);
      } catch (err) {
        log.warn("Failed to parse first plugin message:", err);
      }
    };

    ws.on("message", onFirstMessage);

    ws.on("close", () => {
      // If it closed before registering
      this.pendingWs.delete(ws);
    });

    ws.on("error", (err) => {
      log.warn("WebSocket error:", err.message);
    });
  }

  private registerStudio(ws: WebSocket, info: StudioInfo): void {
    const { studioId } = info;

    // If this studioId already exists, close the old connection
    const existing = this.studios.get(studioId);
    if (existing) {
      log.warn(`Studio "${studioId}" reconnected — closing old connection`);
      existing.ws.close();
    }

    this.studios.set(studioId, { ws, info });
    this.lastHeartbeats.set(studioId, Date.now());

    // Auto-activate the first studio
    if (this.activeStudioId === null) {
      this.activeStudioId = studioId;
    }

    this.emit("studio-connected", info);
    log.info(
      `Studio registered: ${studioId}` +
        (info.placeName ? ` (${info.placeName})` : ""),
    );

    this.startHeartbeatMonitor();

    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (isHeartbeat(msg)) {
          this.lastHeartbeats.set(studioId, Date.now());
          return;
        }
        this.handlePluginMessage(msg);
      } catch (err) {
        log.warn("Failed to parse plugin message:", err);
      }
    });

    ws.on("close", () => {
      const current = this.studios.get(studioId);
      if (current && current.ws === ws) {
        this.studios.delete(studioId);
        this.lastHeartbeats.delete(studioId);
        this.emit("studio-disconnected", info);
        log.info(`Studio disconnected: ${studioId}`);

        // If the active studio disconnected, auto-switch to any remaining
        if (this.activeStudioId === studioId) {
          if (this.studios.size > 0) {
            this.activeStudioId = this.studios.keys().next().value!;
            log.info(
              `Auto-switched active studio to: ${this.activeStudioId}`,
            );
          } else {
            this.activeStudioId = null;
          }
        }

        if (this.studios.size === 0) {
          this.stopHeartbeatMonitor();
        }
      }
    });
  }

  private handlePluginMessage(msg: unknown): void {
    if (isBridgeResponse(msg)) {
      const pending = this.pendingRequests.get(msg.id);
      if (pending) {
        clearTimeout(pending.timer);
        this.pendingRequests.delete(msg.id);
        pending.resolve(msg.result);
      }
      return;
    }

    if (isBridgeError(msg)) {
      const pending = this.pendingRequests.get(msg.id);
      if (pending) {
        clearTimeout(pending.timer);
        this.pendingRequests.delete(msg.id);
        pending.reject(new Error(`${msg.error.code}: ${msg.error.message}`));
      }
      return;
    }

    log.debug("Unknown message from plugin:", msg);
  }

  private startHeartbeatMonitor(): void {
    if (this.heartbeatTimer) return; // already running
    this.heartbeatTimer = setInterval(() => {
      const now = Date.now();
      for (const [studioId, lastBeat] of this.lastHeartbeats) {
        if (now - lastBeat > HEARTBEAT_TIMEOUT_MS) {
          const studio = this.studios.get(studioId);
          if (studio) {
            log.warn(
              `Heartbeat timeout for studio "${studioId}" — disconnecting`,
            );
            studio.ws.terminate();
          } else if (this.httpStudios.has(studioId)) {
            log.warn(
              `Heartbeat timeout for HTTP studio "${studioId}" — evicting`,
            );
            const info = this.httpStudios.get(studioId)!;
            this.httpStudios.delete(studioId);
            this.lastHeartbeats.delete(studioId);
            this.emit("studio-disconnected", info);
            if (this.activeStudioId === studioId) {
              const remaining = this.getStudios();
              this.activeStudioId =
                remaining.length > 0 ? remaining[0].studioId : null;
            }
          }
        }
      }
    }, HEARTBEAT_CHECK_INTERVAL_MS);
  }

  private stopHeartbeatMonitor(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  // ── HTTP fallback handling ─────────────────────────────────────

  private handleHttp(
    req: http.IncomingMessage,
    res: http.ServerResponse,
  ): void {
    // CORS headers for Studio plugin
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const parsedUrl = new URL(req.url ?? "/", `http://127.0.0.1`);
    const pathname = parsedUrl.pathname;

    if (req.method === "GET" && pathname === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          connected: this.isConnected,
          port: this.actualPort,
          studios: this.getStudios(),
          activeStudioId: this.activeStudioId,
        }),
      );
      return;
    }

    if (req.method === "GET" && pathname === "/poll") {
      const studioId =
        parsedUrl.searchParams.get("studioId") ??
        this.activeStudioId ??
        "_default";
      this.handlePoll(studioId, res);
      return;
    }

    if (req.method === "POST" && pathname === "/result") {
      this.handleResult(req, res);
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  }

  private handlePoll(studioId: string, res: http.ServerResponse): void {
    // Register this studio via HTTP if not already known
    if (!this.studios.has(studioId) && studioId !== "_default") {
      if (!this.httpStudios.has(studioId)) {
        const info: StudioInfo = {
          studioId,
          connectedAt: Date.now(),
        };
        this.httpStudios.set(studioId, info);
        this.emit("studio-connected", info);
        log.info(`HTTP-only studio registered: ${studioId}`);
      }
      this.lastHeartbeats.set(studioId, Date.now());
      if (this.activeStudioId === null) {
        this.activeStudioId = studioId;
      }
    }

    // Update heartbeat for HTTP-connected studios
    this.lastHeartbeats.set(studioId, Date.now());

    // If there are pending commands for this studio, send the oldest one
    const queue = this.httpPendingCommands.get(studioId) ?? [];
    if (queue.length > 0) {
      const cmd = queue.shift()!;
      if (queue.length === 0) {
        this.httpPendingCommands.delete(studioId);
      }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(cmd));
      return;
    }

    // Also check the default queue for backward compatibility
    if (studioId !== "_default") {
      const defaultQueue = this.httpPendingCommands.get("_default") ?? [];
      if (defaultQueue.length > 0) {
        const cmd = defaultQueue.shift()!;
        if (defaultQueue.length === 0) {
          this.httpPendingCommands.delete("_default");
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(cmd));
        return;
      }
    }

    // Long-poll: hold connection until a command is available or timeout
    const timer = setTimeout(() => {
      const waiters = this.httpPollWaiters.get(studioId);
      if (waiters) {
        const idx = waiters.findIndex((w) => w.res === res);
        if (idx !== -1) waiters.splice(idx, 1);
        if (waiters.length === 0) this.httpPollWaiters.delete(studioId);
      }
      res.writeHead(204);
      res.end();
    }, LONG_POLL_TIMEOUT_MS);

    const waiters = this.httpPollWaiters.get(studioId) ?? [];
    waiters.push({ res, timer });
    this.httpPollWaiters.set(studioId, waiters);
  }

  private handleResult(
    req: http.IncomingMessage,
    res: http.ServerResponse,
  ): void {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf-8");
      try {
        const msg = JSON.parse(body);
        this.handlePluginMessage(msg);
        res.writeHead(200);
        res.end("ok");
      } catch {
        res.writeHead(400);
        res.end("Invalid JSON");
      }
    });
  }

  private flushHttpPollers(studioId: string): void {
    const waiters = this.httpPollWaiters.get(studioId) ?? [];
    const queue = this.httpPendingCommands.get(studioId) ?? [];

    while (waiters.length > 0 && queue.length > 0) {
      const waiter = waiters.shift()!;
      const cmd = queue.shift()!;
      clearTimeout(waiter.timer);
      waiter.res.writeHead(200, { "Content-Type": "application/json" });
      waiter.res.end(JSON.stringify(cmd));
    }

    if (waiters.length === 0) this.httpPollWaiters.delete(studioId);
    if (queue.length === 0) this.httpPendingCommands.delete(studioId);
  }
}
