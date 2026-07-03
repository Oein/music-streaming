import { promises as fs } from "node:fs";
import path from "node:path";
import { config } from "../config.js";
import { transcodeToFile } from "./transcode.js";

// Formats served directly to every client (never transcoded). Anything else
// (flac, ogg, oga, ...) gets an AAC cache entry that transcoding clients — e.g.
// web playing FLAC, or iOS playing OGG — will use.
const NATIVELY_SAFE = new Set(["mp3", "wav", "m4a"]);

export function needsCache(format: string): boolean {
  return !NATIVELY_SAFE.has(format.toLowerCase());
}

export interface CacheableTrack {
  id: number;
  fileSize: number;
  filePath: string;
  format: string;
}

// Cache path is keyed by id + source size so a replaced source invalidates it.
export function cachePathFor(track: { id: number; fileSize: number }): string {
  return path.join(
    config.transcodeCacheDir,
    `${track.id}_${track.fileSize}.aac`
  );
}

export async function isCached(track: {
  id: number;
  fileSize: number;
}): Promise<boolean> {
  try {
    await fs.access(cachePathFor(track));
    return true;
  } catch {
    return false;
  }
}

// De-dupe concurrent transcodes of the same track: on-demand playback, the
// library warmup, and play-imminent prewarming all share this map, so a track
// is only ever transcoded once even if requested from several places at once.
const inflight = new Map<string, Promise<string>>();

// Transcode `track` to a complete AAC file in the cache dir (once), returning
// its path. Writes to a .part temp file and atomically renames on success so a
// crashed/partial transcode is never served.
export async function ensureTranscoded(track: CacheableTrack): Promise<string> {
  const out = cachePathFor(track);
  try {
    await fs.access(out);
    return out; // already cached
  } catch {
    /* not cached yet */
  }

  let job = inflight.get(out);
  if (!job) {
    const tmp = `${out}.part`;
    job = (async () => {
      await fs.mkdir(config.transcodeCacheDir, { recursive: true });
      await transcodeToFile(track.filePath, tmp);
      await fs.rename(tmp, out);
      return out;
    })().finally(() => inflight.delete(out));
    inflight.set(out, job);
  }
  return job;
}
