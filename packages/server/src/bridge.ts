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

const REQUEST_TIMEOUT_MS = 60_000;
const HEARTBEAT_CHECK_INTERVAL_MS = 5_000;
// Plugin closes its socket at 15s without an ack; we give it a 5s margin so the
// plugin always wins the race to detect a stale link. Server-side eviction is
// the fallback for cases where the plugin is frozen and never closed.
const HEARTBEAT_TIMEOUT_MS = 20_000;
const PING_INTERVAL_MS = 10_000;
const LONG_POLL_TIMEOUT_MS = 25_000;
const MAX_PORT_RETRIES = 10;
const REGISTRATION_TIMEOUT_MS = 10_000;
// First tool call from a fresh MCP client (Codex, Claude Code) often arrives
// before the plugin has finished its WebSocket handshake. Block briefly so the
// caller doesn't either hang on the 60s request timeout or get an immediate
// PLUGIN_NOT_CONNECTED for a connection that's about to come up.
const FIRST_CONNECT_WAIT_MS = 3_000;

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
  private pingTimer: ReturnType<typeof setInterval> | null = null;
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

  /**
   * Try to shut down a stale Conduit instance on the target port.
   * Returns true if the port was freed (or was already free).
   */
  private async evictStaleInstance(port: number): Promise<boolean> {
    return new Promise((resolve) => {
      const req = http.request(
        {
          hostname: "127.0.0.1",
          port,
          path: "/shutdown",
          method: "POST",
          timeout: 2_000,
        },
        (res) => {
          res.resume(); // drain
          // Give the old server a moment to release the port
          setTimeout(() => resolve(true), 500);
        },
      );
      req.on("error", () => resolve(false)); // not running or unreachable
      req.on("timeout", () => {
        req.destroy();
        resolve(false); // timed out — bind will fail if port is still held
      });
      req.end();
    });
  }

  async start(): Promise<number> {
    // Kill any stale Conduit instance on our target port before binding
    await this.evictStaleInstance(this.port);

    return new Promise((resolve, reject) => {
      let attempts = 0;
      const tryPort = (port: number) => {
        const server = http.createServer((req, res) =>
          this.handleHttp(req, res),
        );

        server.once("error", (err: NodeJS.ErrnoException) => {
          if (err.code === "EADDRINUSE" && attempts < MAX_PORT_RETRIES) {
            attempts++;
            log.warn(
              `Port ${port} still in use after eviction — trying ${port + 1}`,
            );
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

    // Stop heartbeat and ping
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    this.stopPingInterval();

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
    timeoutMs?: number,
  ): Promise<unknown> {
    const id = generateId();
    const request: BridgeRequest = { id, method, params };
    const json = JSON.stringify(request);

    // Fail fast (after a brief grace window) when no plugin is running at all.
    // Without this, callers wait 60s for REQUEST_TIMEOUT before learning the
    // plugin isn't there — Codex/Claude Code surface that as a hung tool call.
    if (this.studios.size === 0 && this.httpStudios.size === 0) {
      await this.waitForFirstStudio(FIRST_CONNECT_WAIT_MS);
      if (this.studios.size === 0 && this.httpStudios.size === 0) {
        throw this.buildPluginNotConnectedError(method);
      }
    }

    // Resolve which studio to target
    const studio = this.resolveTargetStudio();
    const targetStudioId = this.activeStudioId;

    const effectiveTimeout = timeoutMs ?? REQUEST_TIMEOUT_MS;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(this.buildTimeoutError(method, effectiveTimeout, targetStudioId));
      }, effectiveTimeout);

      this.pendingRequests.set(id, {
        resolve,
        reject,
        timer,
        studioId: targetStudioId,
      });

      if (studio) {
        studio.ws.send(json, (err) => {
          if (err) {
            clearTimeout(timer);
            this.pendingRequests.delete(id);
            log.warn(
              `WebSocket send failed for studio "${this.activeStudioId}": ${err.message}`,
            );
            // Evict the broken connection so the next call doesn't repeat this
            this.evictStaleStudio(this.activeStudioId!);
            reject(
              new Error(
                `Failed to send to Roblox Studio: ${err.message}. The plugin connection may have dropped — it should auto-reconnect shortly. Please retry.`,
              ),
            );
          }
        });
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

  // Wait for any studio to register, up to timeoutMs. Resolves immediately if
  // one is already connected. Used to absorb the startup race between MCP
  // initialize (instant) and the plugin's WebSocket handshake (~hundreds of ms).
  private waitForFirstStudio(timeoutMs: number): Promise<void> {
    if (this.studios.size > 0 || this.httpStudios.size > 0) {
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.off("studio-connected", onConnect);
        resolve();
      }, timeoutMs);
      const onConnect = () => {
        clearTimeout(timer);
        resolve();
      };
      this.once("studio-connected", onConnect);
    });
  }

  private buildPluginNotConnectedError(method: string): Error {
    const err = new Error(
      `Cannot ${method}: the Roblox Studio plugin is not connected. ` +
        `Open Roblox Studio with the Conduit plugin enabled — it auto-connects when ` +
        `HttpService is allowed (Game Settings → Security → Allow HTTP Requests). ` +
        `Check the Conduit dashboard in Studio for connection status.`,
    );
    (err as any).code = "PLUGIN_NOT_CONNECTED";
    return err;
  }

  /**
   * Classify why a request timed out. Without this, three very different failure modes
   * ("plugin isn't running", "socket is dead", "plugin got the request but its handler
   * is stuck") all surface as the same generic "timed out" error, so callers can't
   * decide whether to retry, reconnect, or surface the hang to the user.
   *
   * We inspect studio state *at timeout fire time* (not request send time) because
   * the socket may have died mid-flight.
   */
  private buildTimeoutError(
    method: string,
    timeoutMs: number,
    targetStudioId: string | null,
  ): Error {
    const base = `Request ${method} timed out after ${timeoutMs}ms`;

    if (!targetStudioId) {
      const err = new Error(
        `${base}: no Roblox Studio plugin was connected when the request was dispatched.`,
      );
      (err as any).code = "PLUGIN_NOT_CONNECTED";
      return err;
    }

    const studio = this.studios.get(targetStudioId);
    if (!studio || studio.ws.readyState !== WebSocket.OPEN) {
      const err = new Error(
        `${base}: the plugin WebSocket for studio "${targetStudioId}" closed before a response arrived.`,
      );
      (err as any).code = "PLUGIN_DISCONNECTED";
      return err;
    }

    const lastBeat = this.lastHeartbeats.get(targetStudioId);
    const age = lastBeat !== undefined ? Date.now() - lastBeat : Infinity;
    if (age > HEARTBEAT_TIMEOUT_MS) {
      const err = new Error(
        `${base}: the plugin stopped sending heartbeats (${Math.round(age / 1000)}s ago) — Studio may be frozen.`,
      );
      (err as any).code = "PLUGIN_UNRESPONSIVE";
      return err;
    }

    // Heartbeats are fresh, socket is open — the plugin itself is alive, but the
    // specific handler didn't return. Most common cause: user-supplied Lua (execute_lua)
    // or a long mutation blocking the queue.
    const err = new Error(
      `${base}: the plugin is still responsive but the "${method}" handler did not return in time. ` +
        `This usually means user Lua is running long or the mutation queue is stalled on a prior command.`,
    );
    (err as any).code = "HANDLER_TIMEOUT";
    return err;
  }

  // ── Internal helpers ───────────────────────────────────────────

  private getActiveStudio(): StudioConnection | undefined {
    if (this.activeStudioId) {
      return this.studios.get(this.activeStudioId);
    }
    return undefined;
  }

  private isStudioAlive(studioId: string, studio: StudioConnection): boolean {
    if (studio.ws.readyState !== WebSocket.OPEN) return false;
    // Check heartbeat freshness — if we haven't heard from the studio
    // in longer than the heartbeat timeout, consider it stale
    const lastBeat = this.lastHeartbeats.get(studioId);
    if (lastBeat !== undefined && Date.now() - lastBeat > HEARTBEAT_TIMEOUT_MS) {
      log.warn(
        `Studio "${studioId}" has stale heartbeat (${Math.round((Date.now() - lastBeat) / 1000)}s ago) — evicting`,
      );
      this.evictStaleStudio(studioId);
      return false;
    }
    return true;
  }

  private evictStaleStudio(studioId: string): void {
    const studio = this.studios.get(studioId);
    if (studio) {
      studio.ws.terminate();
      this.studios.delete(studioId);
      this.lastHeartbeats.delete(studioId);
      this.failPendingForStudio(
        studioId,
        "PLUGIN_UNRESPONSIVE",
        `the plugin connection went stale and was evicted before responding`,
      );
      this.emit("studio-disconnected", studio.info);
      log.info(`Evicted stale studio: ${studioId}`);
    }
    if (this.activeStudioId === studioId) {
      // Try to find another live studio
      for (const [id, s] of this.studios) {
        if (s.ws.readyState === WebSocket.OPEN) {
          this.activeStudioId = id;
          log.info(`Auto-switched active studio to: ${id}`);
          return;
        }
      }
      this.activeStudioId = null;
    }
    if (this.studios.size === 0) {
      this.stopHeartbeatMonitor();
      this.stopPingInterval();
    }
  }

  private resolveTargetStudio(): StudioConnection | undefined {
    // If active studio is set and alive, use it
    if (this.activeStudioId) {
      const active = this.studios.get(this.activeStudioId);
      if (active && this.isStudioAlive(this.activeStudioId, active)) {
        return active;
      }
    }

    // Active studio is gone or stale — try to auto-select any live studio
    for (const [studioId, studio] of this.studios) {
      if (this.isStudioAlive(studioId, studio)) {
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

    // Close unregistered connections after timeout
    const registrationTimer = setTimeout(() => {
      if (this.pendingWs.has(ws)) {
        log.warn(
          "WebSocket failed to register within timeout — closing",
        );
        this.pendingWs.delete(ws);
        ws.close(1008, "Registration timeout");
      }
    }, REGISTRATION_TIMEOUT_MS);

    const onFirstMessage = (data: Buffer | string) => {
      try {
        const msg = JSON.parse(data.toString());

        if (isStudioRegistration(msg)) {
          clearTimeout(registrationTimer);
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
        clearTimeout(registrationTimer);
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

    const onEarlyClose = () => {
      clearTimeout(registrationTimer);
      this.pendingWs.delete(ws);
    };

    const onEarlyError = (err: Error) => {
      log.warn("WebSocket error:", err.message);
    };

    ws.on("close", onEarlyClose);
    ws.on("error", onEarlyError);

    // Expose refs so registerStudio can remove them after successful registration
    (ws as any).__earlyClose = onEarlyClose;
    (ws as any).__earlyError = onEarlyError;
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

    // Set up native WebSocket ping/pong for dead connection detection
    (ws as any).isAlive = true;
    ws.on("pong", () => {
      (ws as any).isAlive = true;
    });

    // Auto-activate: first studio, or reclaim if this studio was previously active
    if (this.activeStudioId === null || this.activeStudioId === studioId) {
      this.activeStudioId = studioId;
    }

    this.emit("studio-connected", info);
    log.info(
      `Studio registered: ${studioId}` +
        (info.placeName ? ` (${info.placeName})` : ""),
    );

    this.startHeartbeatMonitor();
    this.startPingInterval();

    // Remove early close/error listeners from handleWsConnection to avoid duplicates
    if ((ws as any).__earlyClose) {
      ws.removeListener("close", (ws as any).__earlyClose);
      delete (ws as any).__earlyClose;
    }
    if ((ws as any).__earlyError) {
      ws.removeListener("error", (ws as any).__earlyError);
      delete (ws as any).__earlyError;
    }

    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (isHeartbeat(msg)) {
          this.lastHeartbeats.set(studioId, Date.now());
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: "heartbeat_ack" }));
          }
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
        // Fail any in-flight requests routed to this studio. The plugin clears
        // its router state on reconnect, so even if the same studioId comes
        // back, those request IDs are dead. Without this, callers eat the full
        // 60s REQUEST_TIMEOUT for a reply that can never arrive.
        this.failPendingForStudio(
          studioId,
          "PLUGIN_DISCONNECTED",
          `the plugin WebSocket closed before a response arrived`,
        );
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
          this.stopPingInterval();
        }
      }
    });
  }

  private failPendingForStudio(
    studioId: string,
    code: string,
    reason: string,
  ): void {
    for (const [id, pending] of this.pendingRequests) {
      if (pending.studioId === studioId) {
        clearTimeout(pending.timer);
        this.pendingRequests.delete(id);
        const err = new Error(
          `Request aborted: ${reason} (studio: ${studioId}). ` +
            `The plugin should auto-reconnect — please retry.`,
        );
        (err as any).code = code;
        pending.reject(err);
      }
    }
  }

  private handlePluginMessage(msg: unknown): void {
    // Check isBridgeError first — both error and response have "id",
    // but error also has "error" which would be lost if checked second.
    if (isBridgeError(msg)) {
      const pending = this.pendingRequests.get(msg.id);
      if (pending) {
        clearTimeout(pending.timer);
        this.pendingRequests.delete(msg.id);
        pending.reject(new Error(`${msg.error.code}: ${msg.error.message}`));
      }
      return;
    }

    if (isBridgeResponse(msg)) {
      const pending = this.pendingRequests.get(msg.id);
      if (pending) {
        clearTimeout(pending.timer);
        this.pendingRequests.delete(msg.id);
        pending.resolve(msg.result);
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
            studio.ws.close(1001, "Heartbeat timeout");
            this.lastHeartbeats.delete(studioId);
          } else if (this.httpStudios.has(studioId)) {
            log.warn(
              `Heartbeat timeout for HTTP studio "${studioId}" — evicting`,
            );
            const info = this.httpStudios.get(studioId)!;
            this.httpStudios.delete(studioId);
            this.lastHeartbeats.delete(studioId);
            // Drop queued HTTP commands and fail in-flight requests for this
            // studio so callers don't sit on the 60s timeout.
            this.httpPendingCommands.delete(studioId);
            this.failPendingForStudio(
              studioId,
              "PLUGIN_UNRESPONSIVE",
              `the HTTP-fallback plugin stopped polling for ${Math.round(HEARTBEAT_TIMEOUT_MS / 1000)}s`,
            );
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

  private startPingInterval(): void {
    if (this.pingTimer) return; // already running
    this.pingTimer = setInterval(() => {
      for (const [studioId, studio] of this.studios) {
        const ws = studio.ws;
        if ((ws as any).isAlive === false) {
          log.warn(
            `Ping timeout for studio "${studioId}" — terminating connection`,
          );
          ws.terminate();
          return;
        }
        (ws as any).isAlive = false;
        ws.ping();
      }
    }, PING_INTERVAL_MS);
  }

  private stopPingInterval(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  // ── HTTP fallback handling ─────────────────────────────────────

  private handleHttp(
    req: http.IncomingMessage,
    res: http.ServerResponse,
  ): void {
    // CORS headers for Studio plugin — restrict to localhost origins
    const origin = req.headers.origin;
    if (
      origin &&
      (origin.startsWith("http://localhost") ||
        origin.startsWith("http://127.0.0.1"))
    ) {
      res.setHeader("Access-Control-Allow-Origin", origin);
    }
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const parsedUrl = new URL(req.url ?? "/", `http://127.0.0.1`);
    const pathname = parsedUrl.pathname;

    if (req.method === "POST" && pathname === "/shutdown") {
      // Block browser-originated requests (CSRF protection)
      if (req.headers.origin) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }
      log.info("Received shutdown request from new Conduit instance");
      res.writeHead(200);
      res.end("ok");
      // Graceful shutdown — let the response flush, then emit event
      setImmediate(() => {
        this.emit("shutdown");
      });
      return;
    }

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
      // Block browser-originated requests (CSRF protection)
      if (req.headers.origin) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }
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
        this.lastHeartbeats.set(studioId, Date.now());
        this.emit("studio-connected", info);
        log.info(`HTTP-only studio registered: ${studioId}`);
        this.startHeartbeatMonitor();
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
    const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB
    const chunks: Buffer[] = [];
    let totalSize = 0;
    req.on("data", (chunk: Buffer) => {
      totalSize += chunk.length;
      if (totalSize > MAX_BODY_SIZE) {
        req.destroy();
        res.writeHead(413);
        res.end("Request body too large");
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (totalSize > MAX_BODY_SIZE) return;
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
