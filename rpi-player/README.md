# RPi playback device

A headless music-player "device" for a **Raspberry Pi Zero 2 W**. It registers
with the musicPlayer server's Spotify-Connect-style remote hub, so any other
device — the Flutter app — can drive playback here. Audio is streamed from the
server and played locally through **mpv** to a USB DAC (or any ALSA output).

```
 ┌──────────────┐   command over /ws    ┌──────────────────┐
 │ Flutter app  │ ────────────────────▶ │ RPi (this)       │
 │ (controller) │ ◀──────────────────── │  device + mpv    │
 └──────────────┘   state broadcast      └────────┬─────────┘
        ▲                                          │ /api/stream/:id
        │                                          ▼
        └──────────  musicPlayer server  ──────────┘  ──▶ USB DAC
```

The Pi does not hold any music. It streams each track from the server on demand
(`GET /api/stream/:id`) and advertises every format mpv can decode, so the
server serves originals without transcoding.

## Why this design

The server already ships a remote hub (`server/src/remote/hub.ts`) and the app
already speaks its protocol. This device just implements the *other* half of
that protocol in ~450 lines of dependency-light Python — no new server code, and
the Pi shows up in the app's existing device picker automatically.

## Requirements

- Raspberry Pi OS (or any Linux) with `mpv` and Python 3.9+
- One pip dependency: `websockets`
- The Pi and the server on the same network (or a reachable URL)

## Install

```bash
git clone <this repo> && cd musicPlayer/rpi-player
./install.sh            # installs mpv + venv + deps, seeds .env
nano .env               # set SERVER_URL, credentials, ALSA_DEVICE
```

Find your USB DAC's ALSA name:

```bash
mpv --audio-device=help      # look for something like alsa/hw:1,0
```

Set it as `ALSA_DEVICE` in `.env` (leave unset to use the system default).

## Run

Foreground (for testing):

```bash
./venv/bin/python player.py
```

As a service (starts on boot, auto-restarts):

```bash
# Edit User= and paths in the unit file if you didn't install under /home/pi
sudo cp musicplayer-rpi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now musicplayer-rpi
journalctl -u musicplayer-rpi -f     # watch logs
```

Then open the Flutter app, tap the device picker, and pick **RPi Player**.

## Configuration (`.env`)

| Var | Required | Notes |
|-----|----------|-------|
| `SERVER_URL` | yes | e.g. `http://192.168.0.10:4300`, no trailing slash |
| `MP_USERNAME` / `MP_PASSWORD` | one of these or `TOKEN` | preferred: allows auto re-login on token expiry |
| `TOKEN` | — | a pre-issued 30-day JWT instead of credentials |
| `DEVICE_NAME` | no | shown in the app (default `RPi Player`) |
| `DEVICE_ID` | no | defaults to one derived from `/etc/machine-id` |
| `ALSA_DEVICE` | no | e.g. `alsa/hw:1,0`; unset = system default |
| `MPV_PATH` | no | if mpv isn't on PATH |
| `INSECURE_TLS` | no | `1` for HTTPS servers with self-signed certs |

## Supported remote commands

Matches the app's protocol exactly: `play`, `pause`, `next`, `previous`,
`seek`, `jump`, `volume`, `shuffle`, `loop`, `playQueue`, `enqueue`,
`playNext`, `dequeue`. The device owns the queue and broadcasts playback state
(`trackId`, `position`, `duration`, `playing`, `volume`, `queueIndex`,
`shuffle`, `queue`) back to the app.

## Notes for the Pi Zero 2 W

- 512 MB RAM is plenty: Python + mpv idle at a few tens of MB.
- Streaming FLAC over Wi-Fi is fine; mpv buffers with `--cache=yes`.
- Prefer a wired-quality USB DAC over the Zero's (absent) 3.5 mm jack — the
  Zero 2 W has no analog audio out, so USB or HDMI audio is required.
- If audio stutters, try a smaller format by *not* advertising FLAC: the server
  will transcode to AAC. (Edit `CAN_PLAY` in `player.py`.)

## Troubleshooting

- **No sound / wrong output** — run `mpv --audio-device=help`, set the exact
  `alsa/...` string in `.env`, and make sure your user is in the `audio` group
  (`groups | grep audio`).
- **Device not in the app** — check `journalctl -u musicplayer-rpi -f`; a
  "Connected to hub" line means it registered. Verify `SERVER_URL` is reachable
  from the Pi (`curl $SERVER_URL/api/health`).
- **Auth errors** — confirm credentials with
  `curl -XPOST $SERVER_URL/api/auth/login -H 'content-type: application/json' -d '{"username":"...","password":"..."}'`.
