import { spawn } from "node:child_process";
import type { Readable } from "node:stream";

// Formats that most client platforms can decode natively without help.
// ogg/flac are problematic on some platforms (notably iOS/Safari), so when a
// client declares it can't play them we transcode to AAC.
const NATIVELY_SAFE = new Set(["mp3", "wav", "m4a"]);

export interface TranscodeDecision {
  transcode: boolean;
  // Container/codec we transcode to when needed.
  targetFormat: "aac";
  contentType: string;
}

// Decide whether a track needs transcoding for a given client.
// `clientCanPlay` is a set of lowercased format strings the client advertises
// it can decode natively (sent by the app based on its platform).
export function decideTranscode(
  format: string,
  clientCanPlay: Set<string> | null
): TranscodeDecision {
  const fmt = format.toLowerCase();
  if (clientCanPlay) {
    const needs = !clientCanPlay.has(fmt);
    return {
      transcode: needs,
      targetFormat: "aac",
      contentType: "audio/aac",
    };
  }
  // No hint: only transcode formats known to be broadly unsupported.
  const needs = !NATIVELY_SAFE.has(fmt);
  return { transcode: needs, targetFormat: "aac", contentType: "audio/aac" };
}

// Stream a file through ffmpeg, transcoding to ADTS AAC. Returns a Readable of
// the transcoded bytes. Not seekable via Range — the client buffers the stream.
export function transcodeToAac(filePath: string): Readable {
  const args = [
    "-hide_banner",
    "-loglevel",
    "error",
    "-i",
    filePath,
    "-vn",
    "-c:a",
    "aac",
    "-b:a",
    "192k",
    "-f",
    "adts",
    "pipe:1",
  ];
  const proc = spawn("ffmpeg", args, { stdio: ["ignore", "pipe", "pipe"] });
  proc.stderr.on("data", () => {
    /* swallow; ffmpeg logs to stderr */
  });
  proc.on("error", (err) => {
    proc.stdout.destroy(err);
  });
  return proc.stdout;
}

// Transcode a file to ADTS AAC written to `outPath`. Resolves when ffmpeg exits
// successfully. Unlike transcodeToAac (a live pipe), this produces a COMPLETE
// on-disk file that can then be served with Content-Length + Range, so players
// can buffer/seek instead of stalling or showing a permanent "buffering" state.
export function transcodeToFile(filePath: string, outPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const args = [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-i",
      filePath,
      "-vn",
      "-c:a",
      "aac",
      "-b:a",
      "192k",
      "-f",
      "adts",
      outPath,
    ];
    const proc = spawn("ffmpeg", args, { stdio: ["ignore", "ignore", "pipe"] });
    let err = "";
    proc.stderr.on("data", (d) => {
      err += d.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exited ${code}: ${err.slice(0, 500)}`));
    });
  });
}
