import { describe, it, expect, afterEach } from "vitest";
import http from "node:http";
import { WebSocket } from "ws";
import { Bridge } from "../bridge.js";

const BASE_PORT = 4700; // away from the default 3200 so a locally running Conduit doesn't interfere

const bridges: Bridge[] = [];

async function startBridge(port: number): Promise<Bridge> {
  const bridge = new Bridge(port);
  bridges.push(bridge);
  await bridge.start();
  return bridge;
}

afterEach(async () => {
  await Promise.all(bridges.map((b) => b.stop().catch(() => {})));
  bridges.length = 0;
});

function request(
  port: number,
  path: string,
  method = "GET",
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { hostname: "127.0.0.1", port, path, method, timeout: 3_000 },
      (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () =>
          resolve({ status: res.statusCode ?? 0, body }),
        );
      },
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("request timeout"));
    });
    req.end();
  });
}

describe("Bridge multi-instance coexistence", () => {
  it("second instance binds the next port without killing the first", async () => {
    const first = await startBridge(BASE_PORT);
    first.clientAliveCheck = () => true;

    const second = await startBridge(BASE_PORT);

    expect(first.listeningPort).toBe(BASE_PORT);
    expect(second.listeningPort).toBe(BASE_PORT + 1);

    // Both must be healthy — the old behavior evicted the first instance.
    const firstHealth = await request(first.listeningPort, "/health");
    const secondHealth = await request(second.listeningPort, "/health");
    expect(firstHealth.status).toBe(200);
    expect(JSON.parse(firstHealth.body).status).toBe("ok");
    expect(secondHealth.status).toBe(200);
    expect(JSON.parse(secondHealth.body).status).toBe("ok");
  });

  it("refuses /shutdown while the MCP client is attached", async () => {
    const bridge = await startBridge(BASE_PORT + 10);
    bridge.clientAliveCheck = () => true;

    const res = await request(bridge.listeningPort, "/shutdown", "POST");
    expect(res.status).toBe(409);

    // Still serving
    const health = await request(bridge.listeningPort, "/health");
    expect(health.status).toBe(200);
  });

  it("honors /shutdown when no client is attached", async () => {
    const bridge = await startBridge(BASE_PORT + 20);
    bridge.clientAliveCheck = () => false;

    const gotShutdown = new Promise<void>((resolve) =>
      bridge.once("shutdown", () => resolve()),
    );
    const res = await request(bridge.listeningPort, "/shutdown", "POST");
    expect(res.status).toBe(200);
    await gotShutdown;
  });
});

describe("Bridge studio registration", () => {
  it("registers a WebSocket studio and reports it in /health", async () => {
    const bridge = await startBridge(BASE_PORT + 30);

    const ws = new WebSocket(`ws://127.0.0.1:${bridge.listeningPort}`);
    await new Promise<void>((resolve, reject) => {
      ws.on("open", () => resolve());
      ws.on("error", reject);
    });
    ws.send(
      JSON.stringify({
        type: "register",
        studioId: "studio-test-1",
        placeId: 123,
        placeName: "TestPlace",
      }),
    );

    await new Promise<void>((resolve) =>
      bridge.once("studio-connected", () => resolve()),
    );

    const health = JSON.parse(
      (await request(bridge.listeningPort, "/health")).body,
    );
    expect(health.connected).toBe(true);
    expect(health.studios).toHaveLength(1);
    expect(health.studios[0].studioId).toBe("studio-test-1");
    expect(health.activeStudioId).toBe("studio-test-1");

    ws.close();
  });

  it("acks heartbeats from a registered studio", async () => {
    const bridge = await startBridge(BASE_PORT + 40);

    const ws = new WebSocket(`ws://127.0.0.1:${bridge.listeningPort}`);
    await new Promise<void>((resolve, reject) => {
      ws.on("open", () => resolve());
      ws.on("error", reject);
    });
    ws.send(JSON.stringify({ type: "register", studioId: "studio-hb" }));
    await new Promise<void>((resolve) =>
      bridge.once("studio-connected", () => resolve()),
    );

    const ack = new Promise<unknown>((resolve) => {
      ws.on("message", (data) => resolve(JSON.parse(data.toString())));
    });
    ws.send(JSON.stringify({ type: "heartbeat" }));
    expect(await ack).toEqual({ type: "heartbeat_ack" });

    ws.close();
  });

  it("upgrades an HTTP-fallback studio to WebSocket and re-dispatches queued commands", async () => {
    const bridge = await startBridge(BASE_PORT + 50);

    // Studio shows up via HTTP poll (no command queued -> long poll parks).
    // Use a short-lived poll request we abort right after registration.
    const pollReq = http.request({
      hostname: "127.0.0.1",
      port: bridge.listeningPort,
      path: "/poll?studioId=studio-up",
      method: "GET",
    });
    pollReq.on("error", () => {}); // aborted below on purpose
    pollReq.end();
    await new Promise<void>((resolve) =>
      bridge.once("studio-connected", () => resolve()),
    );

    // Abort the poll first so the command below is queued rather than answered
    // by the parked poller; give the server a beat to process the close.
    pollReq.destroy();
    await new Promise((resolve) => setTimeout(resolve, 100));

    const pending = bridge.send("ping_method", {}, 5_000);
    pending.catch(() => {}); // resolved via the WS path below or times out

    // Now the studio connects via WebSocket with the same studioId.
    const ws = new WebSocket(`ws://127.0.0.1:${bridge.listeningPort}`);
    await new Promise<void>((resolve, reject) => {
      ws.on("open", () => resolve());
      ws.on("error", reject);
    });

    const firstCommand = new Promise<any>((resolve) => {
      ws.on("message", (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.method === "ping_method") resolve(msg);
      });
    });
    ws.send(JSON.stringify({ type: "register", studioId: "studio-up" }));

    // The queued command must be re-dispatched over the socket.
    const cmd = await firstCommand;
    expect(cmd.method).toBe("ping_method");

    // Reply and make sure the original send() resolves.
    ws.send(JSON.stringify({ id: cmd.id, result: { pong: true } }));
    await expect(pending).resolves.toEqual({ pong: true });

    ws.close();
  });
});
