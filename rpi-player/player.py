#!/usr/bin/env python3
"""
Headless music-player device for a Raspberry Pi Zero 2 W.

Registers itself with the musicPlayer server's Spotify-Connect-style remote hub
(`/ws`) as a playback device. Any other device (the Flutter app) can then drive
playback here; audio is streamed from `/api/stream/:id` and played through mpv
to the local ALSA output (e.g. a USB DAC).

Dependencies:
  - Python 3.9+
  - `websockets` (pip install websockets)
  - `mpv` binary on PATH (apt install mpv)

The whole thing is a single file so it drops onto a Pi with no build step.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import signal
import ssl
import sys
import tempfile
import time
import urllib.error
import urllib.request
from typing import Any, Optional
from urllib.parse import urlencode

try:
    import websockets
except ImportError:  # pragma: no cover
    print("Missing dependency: pip install websockets", file=sys.stderr)
    raise

log = logging.getLogger("rpi-player")

# Formats mpv can decode natively — advertised to the server so it serves the
# original file instead of transcoding to AAC. mpv handles all of these.
CAN_PLAY = "mp3,wav,m4a,flac,ogg,oga,aac,opus"

# Loop modes broadcast/handled internally (server state only carries "shuffle").
LOOP_NONE, LOOP_ALL, LOOP_ONE = 0, 1, 2


# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
def _load_dotenv() -> None:
    """Load a sibling .env into os.environ (without overriding real env vars).

    Keeps foreground runs working without python-dotenv; systemd already loads
    the file via EnvironmentFile, and those values win.
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    try:
        with open(path) as f:
            lines = f.readlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key, val = key.strip(), val.strip().strip('"').strip("'")
        os.environ.setdefault(key, val)


class Config:
    def __init__(self) -> None:
        self.server_url = _require_env("SERVER_URL").rstrip("/")
        # MP_* takes precedence: a bare USERNAME is often the OS login name.
        # ID/PW are accepted too (used by ~/.env.musicplayer on the Pi).
        self.username = (
            os.environ.get("MP_USERNAME")
            or os.environ.get("ID")
            or os.environ.get("USERNAME")
        )
        self.password = (
            os.environ.get("MP_PASSWORD")
            or os.environ.get("PW")
            or os.environ.get("PASSWORD")
        )
        self.token = os.environ.get("TOKEN")
        self.device_name = os.environ.get("DEVICE_NAME", "RPi Player")
        self.device_id = os.environ.get("DEVICE_ID") or _default_device_id()
        self.alsa_device = os.environ.get("ALSA_DEVICE")  # e.g. "alsa/hw:1,0"
        self.mpv_path = os.environ.get("MPV_PATH", "mpv")
        self.insecure_tls = _env_bool("INSECURE_TLS", False)
        if not self.token and not (self.username and self.password):
            raise SystemExit(
                "Provide TOKEN, or USERNAME + PASSWORD, in the environment."
            )


def _require_env(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        raise SystemExit(f"Missing required env var: {name}")
    return val


def _env_bool(name: str, default: bool) -> bool:
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


def _default_device_id() -> str:
    # Stable-ish per host: reuse machine-id when available.
    try:
        with open("/etc/machine-id") as f:
            return "rpi-" + f.read().strip()[:16]
    except OSError:
        return "rpi-" + format(int(time.time() * 1000), "x")


# --------------------------------------------------------------------------- #
# Auth
# --------------------------------------------------------------------------- #
def obtain_token(cfg: Config) -> str:
    if cfg.token:
        return cfg.token
    body = json.dumps({"username": cfg.username, "password": cfg.password}).encode()
    req = urllib.request.Request(
        f"{cfg.server_url}/api/auth/login",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    ctx = _tls_ctx(cfg)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Login failed: HTTP {e.code} {e.read().decode(errors='replace')}")
    except urllib.error.URLError as e:
        raise SystemExit(f"Login failed: {e.reason}")
    token = data.get("token")
    if not token:
        raise SystemExit(f"Login response had no token: {data}")
    log.info("Authenticated as %s", cfg.username)
    return token


def _tls_ctx(cfg: Config) -> Optional[ssl.SSLContext]:
    if not cfg.server_url.startswith("https"):
        return None
    ctx = ssl.create_default_context()
    if cfg.insecure_tls:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


# --------------------------------------------------------------------------- #
# mpv control via JSON IPC over a unix socket
# --------------------------------------------------------------------------- #
class Mpv:
    """Thin async wrapper around `mpv --input-ipc-server`."""

    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.proc: Optional[asyncio.subprocess.Process] = None
        self.reader: Optional[asyncio.StreamReader] = None
        self.writer: Optional[asyncio.StreamWriter] = None
        self._sock_path = os.path.join(
            tempfile.gettempdir(), f"mpv-rpi-{os.getpid()}.sock"
        )
        self._req_id = 0
        # live playback state, updated from observed properties / events
        self.time_pos = 0.0
        self.duration = 0.0
        self.paused = True
        self.idle = True
        self._on_eof = None  # callback set by the device layer

    async def start(self) -> None:
        args = [
            self.cfg.mpv_path,
            "--idle=yes",
            "--no-video",
            "--no-terminal",
            "--force-seekable=yes",
            f"--input-ipc-server={self._sock_path}",
            "--cache=yes",
        ]
        if self.cfg.alsa_device:
            args.append(f"--audio-device={self.cfg.alsa_device}")
        log.info("Starting mpv: %s", " ".join(args))
        self.proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await self._connect_socket()
        # Observe the properties we mirror into device state.
        await self._send({"command": ["observe_property", 1, "time-pos"]})
        await self._send({"command": ["observe_property", 2, "duration"]})
        await self._send({"command": ["observe_property", 3, "pause"]})
        await self._send({"command": ["observe_property", 4, "core-idle"]})
        asyncio.create_task(self._read_loop())

    async def _connect_socket(self) -> None:
        # Pi Zero cold-starts mpv slowly, so wait generously (~30s).
        for _ in range(300):
            if self.proc and self.proc.returncode is not None:
                raise SystemExit(f"mpv exited early (code {self.proc.returncode})")
            if os.path.exists(self._sock_path):
                try:
                    self.reader, self.writer = await asyncio.open_unix_connection(
                        self._sock_path
                    )
                    return
                except (ConnectionRefusedError, FileNotFoundError):
                    pass
            await asyncio.sleep(0.1)
        raise SystemExit("mpv IPC socket never came up")

    async def _read_loop(self) -> None:
        assert self.reader
        try:
            while True:
                line = await self.reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                self._handle(msg)
        except (asyncio.CancelledError, ConnectionResetError):
            pass

    def _handle(self, msg: dict) -> None:
        event = msg.get("event")
        if event == "property-change":
            name, data = msg.get("name"), msg.get("data")
            if name == "time-pos" and data is not None:
                self.time_pos = float(data)
            elif name == "duration" and data is not None:
                self.duration = float(data)
            elif name == "pause":
                self.paused = bool(data)
            elif name == "core-idle":
                self.idle = bool(data)
        elif event == "end-file":
            # Natural end of a track -> advance. Ignore user-initiated stops.
            if msg.get("reason") == "eof" and self._on_eof:
                asyncio.create_task(self._on_eof())

    async def _send(self, obj: dict) -> None:
        if not self.writer:
            return
        self._req_id += 1
        obj.setdefault("request_id", self._req_id)
        try:
            self.writer.write((json.dumps(obj) + "\n").encode())
            await self.writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            log.warning("mpv IPC write failed")

    # --- high-level commands ------------------------------------------------ #
    async def load(self, url: str) -> None:
        self.time_pos = 0.0
        self.duration = 0.0
        await self._send({"command": ["loadfile", url, "replace"]})
        await self.set_pause(False)

    async def stop(self) -> None:
        await self._send({"command": ["stop"]})

    async def set_pause(self, paused: bool) -> None:
        self.paused = paused
        await self._send({"command": ["set_property", "pause", paused]})

    async def seek(self, seconds: float) -> None:
        await self._send({"command": ["seek", seconds, "absolute"]})

    async def set_volume(self, value_0_1: float) -> None:
        pct = max(0, min(100, round(value_0_1 * 100)))
        await self._send({"command": ["set_property", "volume", pct]})

    async def shutdown(self) -> None:
        try:
            await self._send({"command": ["quit"]})
        except Exception:
            pass
        if self.proc and self.proc.returncode is None:
            try:
                self.proc.terminate()
                await asyncio.wait_for(self.proc.wait(), timeout=3)
            except (asyncio.TimeoutError, ProcessLookupError):
                self.proc.kill()
        try:
            os.unlink(self._sock_path)
        except OSError:
            pass


# --------------------------------------------------------------------------- #
# Playback device: owns the queue and mirrors the app's remote protocol
# --------------------------------------------------------------------------- #
class Device:
    def __init__(self, cfg: Config, token: str, mpv: Mpv) -> None:
        self.cfg = cfg
        self.token = token
        self.mpv = mpv
        self.queue: list[dict] = []
        self.index: int = -1
        self.volume: float = 1.0
        self.shuffle: bool = False
        self.loop: int = LOOP_NONE
        self.send_state = None  # set by the ws layer: async fn(dict)
        mpv._on_eof = self._on_track_end

    # --- helpers ------------------------------------------------------------ #
    def _stream_url(self, track: dict) -> str:
        q = urlencode({"canPlay": CAN_PLAY, "token": self.token})
        return f"{self.cfg.server_url}/api/stream/{track['id']}?{q}"

    async def _play_index(self, idx: int) -> None:
        if not (0 <= idx < len(self.queue)):
            return
        self.index = idx
        track = self.queue[idx]
        log.info("Playing [%d/%d] %s", idx + 1, len(self.queue), track.get("title"))
        await self.mpv.load(self._stream_url(track))
        await self.mpv.set_volume(self.volume)

    def _next_index(self, forward: bool = True) -> Optional[int]:
        if not self.queue:
            return None
        if self.loop == LOOP_ONE:
            return self.index
        if self.shuffle and len(self.queue) > 1:
            choices = [i for i in range(len(self.queue)) if i != self.index]
            return random.choice(choices)
        nxt = self.index + (1 if forward else -1)
        if 0 <= nxt < len(self.queue):
            return nxt
        if self.loop == LOOP_ALL:
            return nxt % len(self.queue)
        return None  # ran off the end with no loop

    async def _on_track_end(self) -> None:
        nxt = self._next_index(forward=True)
        if nxt is not None:
            await self._play_index(nxt)
        else:
            await self.mpv.set_pause(True)

    # --- command dispatch --------------------------------------------------- #
    async def handle_command(self, command: str, payload: Any) -> None:
        payload = payload or {}
        if command == "play":
            if self.mpv.idle and 0 <= self.index < len(self.queue):
                await self._play_index(self.index)
            else:
                await self.mpv.set_pause(False)
        elif command == "pause":
            await self.mpv.set_pause(True)
        elif command == "next":
            nxt = self._next_index(forward=True)
            if nxt is not None:
                await self._play_index(nxt)
        elif command == "previous":
            # Restart current track if we're past a few seconds, else go back.
            if self.mpv.time_pos > 3:
                await self.mpv.seek(0)
            else:
                nxt = self._next_index(forward=False)
                await self._play_index(nxt if nxt is not None else self.index)
        elif command == "seek":
            await self.mpv.seek(float(payload.get("position", 0)) / 1000.0)
        elif command == "jump":
            await self._play_index(int(payload.get("index", 0)))
        elif command == "volume":
            self.volume = max(0.0, min(1.0, float(payload.get("value", 1.0))))
            await self.mpv.set_volume(self.volume)
        elif command == "shuffle":
            self.shuffle = not self.shuffle
        elif command == "loop":
            self.loop = (self.loop + 1) % 3
        elif command == "playQueue":
            tracks = payload.get("tracks") or []
            start = int(payload.get("startIndex", 0))
            self.queue = [dict(t) for t in tracks]
            if self.queue:
                await self._play_index(max(0, min(start, len(self.queue) - 1)))
            else:
                self.index = -1
                await self.mpv.stop()
        elif command == "enqueue":
            track = payload.get("track")
            if track:
                self.queue.append(dict(track))
        elif command == "playNext":
            track = payload.get("track")
            if track:
                self.queue.insert(self.index + 1, dict(track))
        elif command == "dequeue":
            i = int(payload.get("index", -1))
            if 0 <= i < len(self.queue):
                self.queue.pop(i)
                if i < self.index:
                    self.index -= 1
                elif i == self.index:
                    # removed the playing track
                    if self.index >= len(self.queue):
                        self.index = len(self.queue) - 1
                    if 0 <= self.index < len(self.queue):
                        await self._play_index(self.index)
                    else:
                        await self.mpv.stop()
        else:
            log.debug("Unknown command: %s", command)
        await self._broadcast()

    # --- state broadcast ---------------------------------------------------- #
    def _current(self) -> Optional[dict]:
        if 0 <= self.index < len(self.queue):
            return self.queue[self.index]
        return None

    def state(self, include_queue: bool) -> dict:
        cur = self._current()
        st: dict[str, Any] = {
            "trackId": cur.get("id") if cur else None,
            "title": cur.get("title") if cur else None,
            "artist": cur.get("artist") if cur else None,
            "format": cur.get("format") if cur else None,
            "coverArtId": cur.get("coverArtId") if cur else None,
            "playing": (not self.mpv.paused) and not self.mpv.idle,
            "position": int(max(0.0, self.mpv.time_pos) * 1000),
            "duration": int(max(0.0, self.mpv.duration) * 1000),
            "volume": self.volume,
            "queueIndex": self.index if self.index >= 0 else None,
            "shuffle": self.shuffle,
        }
        if include_queue:
            st["queue"] = self.queue
        return st

    async def _broadcast(self, include_queue: bool = True) -> None:
        if self.send_state:
            await self.send_state(self.state(include_queue))


# --------------------------------------------------------------------------- #
# WebSocket hub connection
# --------------------------------------------------------------------------- #
async def run_ws(cfg: Config, token: str, device: Device, stop: asyncio.Event) -> None:
    base = cfg.server_url.replace("https://", "wss://").replace("http://", "ws://")
    uri = f"{base}/ws?token={token}"
    ssl_ctx = _tls_ctx(cfg) if base.startswith("wss") else None

    async with websockets.connect(uri, ssl=ssl_ctx, ping_interval=20) as ws:
        log.info("Connected to hub as device '%s' (%s)", cfg.device_name, cfg.device_id)

        async def send_state(state: dict) -> None:
            try:
                await ws.send(json.dumps({"type": "state", "state": state}))
            except websockets.ConnectionClosed:
                pass

        device.send_state = send_state
        await ws.send(json.dumps({
            "type": "hello",
            "deviceId": cfg.device_id,
            "deviceName": cfg.device_name,
        }))
        await device._broadcast()

        ticker = asyncio.create_task(_state_ticker(device, stop))

        async def recv_loop() -> None:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if msg.get("type") == "command":
                    await device.handle_command(msg.get("command"), msg.get("payload"))

        recv = asyncio.create_task(recv_loop())
        stop_waiter = asyncio.create_task(stop.wait())
        try:
            # Return as soon as the socket closes OR a shutdown signal arrives,
            # so SIGTERM doesn't block on the idle recv loop.
            await asyncio.wait(
                {recv, stop_waiter}, return_when=asyncio.FIRST_COMPLETED
            )
        finally:
            ticker.cancel()
            recv.cancel()
            stop_waiter.cancel()
            if stop.is_set():
                await ws.close()


async def _state_ticker(device: Device, stop: asyncio.Event) -> None:
    """Periodically push position/volume; include the full queue occasionally."""
    tick = 0
    while not stop.is_set():
        await asyncio.sleep(0.5)
        tick += 1
        try:
            await device._broadcast(include_queue=(tick % 10 == 0))
        except Exception:
            pass


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
async def amain() -> None:
    _load_dotenv()
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    cfg = Config()
    stop = asyncio.Event()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass

    mpv = Mpv(cfg)
    await mpv.start()

    backoff = 1
    try:
        while not stop.is_set():
            try:
                token = obtain_token(cfg)
                device = Device(cfg, token, mpv)
                await run_ws(cfg, token, device, stop)
                backoff = 1
            except SystemExit:
                raise
            except Exception as e:  # network drop, auth expiry, etc.
                if stop.is_set():
                    break
                log.warning("Hub connection lost (%s); reconnecting in %ss", e, backoff)
                # If a fixed TOKEN was given it may have expired; drop it so we
                # re-login with credentials next round (when available).
                if cfg.username and cfg.password:
                    cfg.token = None
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30)
    finally:
        await mpv.shutdown()
        log.info("Shut down.")


def main() -> None:
    try:
        asyncio.run(amain())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
