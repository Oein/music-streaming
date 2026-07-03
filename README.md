# Personal Music Streaming

A self-hosted music streaming setup: a Node.js server that indexes music folders
on your computer and streams them, plus a Flutter app for **Android, iOS, macOS,
and Web**.

Features:
- Admin web page to add local folders and scan them into a library
- Supports `ogg`, `wav`, `mp3`, `flac` (and `m4a`); metadata + cover art extracted automatically
- Albums (auto-built from tags) and user playlists (create / reorder / delete)
- HTTP Range streaming with on-demand `ffmpeg` transcoding for formats a client can't play natively
- **Remote playback control** — control playback on another logged-in device (Spotify-Connect style) over a WebSocket hub

## Requirements
- Node.js 20+ and `ffmpeg` on the server machine
- Flutter 3.4+ for the app

## Server

```bash
cd server
npm install
cp .env.example .env          # edit JWT_SECRET, PORT, etc.
npx prisma db push            # create the SQLite database
npx tsx src/scripts/setPassword.ts <username> <password>   # create the admin user
npm run dev                   # start on http://0.0.0.0:4300
```

Open `http://localhost:4300/admin/` on the server machine, log in, add a folder
by its absolute path, and press **Scan**. Albums/tracks appear once the scan finishes.

Key endpoints (all under `/api`, bearer-token auth):
`auth/login`, `albums`, `albums/:id`, `tracks`, `playlists*`, `stream/:id`
(Range + `?canPlay=` transcode hint), `cover/:id`, `admin/folders`, `admin/scan`.
Real-time control: `GET /ws?token=...`.

## App

The `app/lib` sources and `pubspec.yaml` are provided. Generate the platform
folders once, then run:

```bash
cd app
flutter create .              # generates android/ ios/ macos/ web/ scaffolding
flutter pub get
flutter run -d chrome         # or: -d macos / an Android or iOS device
```

On first launch, enter the server URL (use your machine's LAN IP for phones,
e.g. `http://192.168.0.10:4300`) and your admin credentials.

### Remote control
Each running app registers as a device on the hub. In **Now Playing**, tap the
devices icon to pick a target: "This device" plays locally; picking another
online device forwards play/pause/seek/skip/queue commands to it and mirrors its
state. Playback state is broadcast so controllers stay in sync.

## Notes
- Transcoded streams (e.g. FLAC → AAC for iOS/Safari) are not seekable via Range;
  natively-supported formats stream the original file with full seek support.
- Format support per platform is declared by the app via the `canPlay` query
  param (see `app/lib/api/api_client.dart`), so only what a client can't decode
  gets transcoded.
