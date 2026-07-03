export const config = {
  port: Number(process.env.PORT ?? 4300),
  host: process.env.HOST ?? "0.0.0.0",
  jwtSecret: process.env.JWT_SECRET ?? "change-me-to-a-long-random-secret",
  transcodeCacheDir: process.env.TRANSCODE_CACHE_DIR ?? "./.cache/transcode",
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
