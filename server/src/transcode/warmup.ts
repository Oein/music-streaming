import { promises as fs } from "node:fs";
import path from "node:path";
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../db/client.js";
import { config } from "../config.js";
import {
  cachePathFor,
  ensureTranscoded,
  isCached,
  needsCache,
} from "./cache.js";

let running = false;

// Remove cache files that no longer belong to any current track. Track ids are
// AUTOINCREMENT (never reused), so a deleted track's `{id}_{size}.aac` becomes a
// permanent orphan otherwise. Only deletes files whose base name isn't a valid
// current-track name, so an in-flight `.part` (always for a live track) is left
// alone.
export async function cleanupOrphans(log?: FastifyBaseLogger): Promise<void> {
  const dir = config.transcodeCacheDir;
  let entries: string[];
  try {
    entries = await fs.readdir(dir);
  } catch {
    return; // dir doesn't exist yet — nothing to clean
  }

  const tracks = await prisma.track.findMany({
    select: { id: true, fileSize: true, format: true },
  });
  const valid = new Set<string>();
  for (const t of tracks) {
    if (needsCache(t.format)) valid.add(path.basename(cachePathFor(t)));
  }

  let removed = 0;
  for (const name of entries) {
    const base = name.endsWith(".part") ? name.slice(0, -5) : name;
    if (!base.endsWith(".aac")) continue;
    if (valid.has(base)) continue;
    try {
      await fs.unlink(path.join(dir, name));
      removed++;
    } catch {
      /* ignore */
    }
  }
  if (removed > 0) {
    log?.info(`transcode cache cleanup: removed ${removed} orphan file(s)`);
  }
}

// (A) Background: transcode every track that needs an AAC cache entry but
// doesn't have one yet. Sequential (concurrency 1) so it never pegs the CPU or
// competes hard with live playback. Idempotent + resumable — safe to run on
// every startup; after the first full pass it just does cheap isCached checks.
export async function warmLibrary(log?: FastifyBaseLogger): Promise<void> {
  if (running) return;
  running = true;
  try {
    // Drop caches for tracks that were deleted since last run.
    await cleanupOrphans(log);
    const tracks = await prisma.track.findMany({
      select: { id: true, fileSize: true, filePath: true, format: true },
    });
    let made = 0;
    let cached = 0;
    let skipped = 0;
    for (const t of tracks) {
      if (!needsCache(t.format)) {
        skipped++;
        continue;
      }
      if (await isCached(t)) {
        cached++;
        continue;
      }
      try {
        await ensureTranscoded(t);
        made++;
      } catch (err) {
        log?.warn({ err, id: t.id }, "warmup transcode failed");
      }
    }
    log?.info(
      `library warmup done: ${made} transcoded, ${cached} already cached, ${skipped} native`
    );
  } finally {
    running = false;
  }
}

// (B) Fire-and-forget warming of specific tracks (play-imminent: album/playlist
// opened, or the next track in the queue). Returns immediately; transcodes run
// in the background and are de-duped against everything else via the cache map.
export async function warmTracks(
  ids: number[],
  log?: FastifyBaseLogger
): Promise<void> {
  if (ids.length === 0) return;
  const tracks = await prisma.track.findMany({
    where: { id: { in: ids } },
    select: { id: true, fileSize: true, filePath: true, format: true },
  });
  for (const t of tracks) {
    if (!needsCache(t.format)) continue;
    ensureTranscoded(t).catch((err) =>
      log?.warn({ err, id: t.id }, "prewarm transcode failed")
    );
  }
}
