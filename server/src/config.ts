export const config = {
  port: Number(process.env.PORT ?? 4300),
  host: process.env.HOST ?? "0.0.0.0",
  jwtSecret: process.env.JWT_SECRET ?? "change-me-to-a-long-random-secret",
  transcodeCacheDir: process.env.TRANSCODE_CACHE_DIR ?? "./.cache/transcode",
  // Static roots. Empty falls back to the bundled ../web and ../downloads dirs
  // (see index.ts); set these to mount points when running in a container.
  webDir: process.env.WEB_DIR ?? "",
  downloadsDir: process.env.DOWNLOADS_DIR ?? "",
};

// Audio file extensions we index. Extend as needed.
export const AUDIO_EXTENSIONS = new Set([
  ".ogg",
  ".oga",
  ".wav",
  ".mp3",
  ".flac",
  ".m4a",
]);
