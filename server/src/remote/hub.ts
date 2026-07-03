import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import { verifyToken } from "../auth/auth.js";

// Real-time hub enabling one device to control playback on another
// (Spotify-Connect style). All sockets belong to the single user, so any
// device may control any other.
//
// Message protocol (JSON):
//   client -> server:
//     { type: "hello", deviceId, deviceName }
//     { type: "command", target: deviceId, command, payload }  // controller -> device
//     { type: "state", state }                                 // device broadcasts its playback state
//   server -> client:
//     { type: "devices", devices: [{ id, name, playing, track }] }
//     { type: "command", from, command, payload }              // delivered to target device
//     { type: "state", from, state }                           // relayed to all other sockets

interface Conn {
  socket: WebSocket;
  deviceId: string;
  deviceName: string;
  lastState: unknown;
}

const conns = new Map<WebSocket, Conn>();

function deviceList() {
  return [...conns.values()].map((c) => ({
    id: c.deviceId,
    name: c.deviceName,
    state: c.lastState ?? null,
  }));
}

function broadcast(msg: unknown, except?: WebSocket) {
  const data = JSON.stringify(msg);
  for (const c of conns.values()) {
    if (c.socket !== except && c.socket.readyState === c.socket.OPEN) {
      c.socket.send(data);
    }
  }
}

function broadcastDevices() {
  broadcast({ type: "devices", devices: deviceList() });
}

export async function registerRemoteHub(app: FastifyInstance) {
  app.get("/ws", { websocket: true }, (socket, req) => {
    // Authenticate via ?token=
    const token = (req.query as { token?: string }).token;
    const payload = token ? verifyToken(token) : null;
    if (!payload) {
      socket.close(4401, "unauthorized");
      return;
    }

    socket.on("message", (raw: Buffer) => {
      let msg: any;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }

      switch (msg.type) {
        case "hello": {
          conns.set(socket, {
            socket,
            deviceId: String(msg.deviceId),
            deviceName: String(msg.deviceName ?? "Device"),
            lastState: null,
          });
          // Send the current device list to the newcomer and everyone else.
          socket.send(JSON.stringify({ type: "devices", devices: deviceList() }));
          broadcastDevices();
          break;
        }
        case "command": {
          // Route command to the target device's socket.
          const target = [...conns.values()].find((c) => c.deviceId === msg.target);
          if (target && target.socket.readyState === target.socket.OPEN) {
            const from = conns.get(socket)?.deviceId ?? null;
            target.socket.send(
              JSON.stringify({
                type: "command",
                from,
                command: msg.command,
                payload: msg.payload ?? null,
              })
            );
          }
          break;
        }
        case "state": {
          const conn = conns.get(socket);
          if (conn) {
            conn.lastState = msg.state;
            broadcast(
              { type: "state", from: conn.deviceId, state: msg.state },
              socket
            );
            broadcastDevices();
          }
          break;
        }
      }
    });

    socket.on("close", () => {
      conns.delete(socket);
      broadcastDevices();
    });
  });
}
