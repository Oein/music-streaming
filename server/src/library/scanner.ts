import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { parseFile } from "music-metadata";
import { AUDIO_EXTENSIONS } from "../config.js";
import { prisma } from "../db/client.js";

export interface ScanStatus {
  running: boolean;
  folderId: number | null;
  folderPath: string | null;
  filesFound: number;
  filesProcessed: number;
  added: number;
  updated: number;
  removed: number;
  errors: number;
  startedAt: number | null;
  finishedAt: number | null;
  lastError: string | null;
}

const status: ScanStatus = {
  running: false,
  folderId: null,
  folderPath: null,
  filesFound: 0,
  filesProcessed: 0,
  added: 0,
  updated: 0,
  removed: 0,
  errors: 0,
  startedAt: null,
  finishedAt: null,
  lastError: null,
};

export function getScanStatus(): ScanStatus {
  return { ...status };
}

async function* walk(
  dir: string,
  allowed: Set<string>
): AsyncGenerator<string> {
  let entries: import("node:fs").Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(full, allowed);
    } else if (entry.isFile()) {
      if (allowed.has(path.extname(entry.name).toLowerCase())) {
        yield full;
      }
    }
  }
}

// Resolve a folder's extension filter to a set of dotted, lowercased
// extensions (e.g. {".mp3", ".flac"}). Falls back to all supported types.
function resolveAllowed(extensions: string | null): Set<string> {
  if (!extensions?.trim()) return AUDIO_EXTENSIONS;
  const chosen = extensions
    .split(",")
    .map((e) => "." + e.trim().replace(/^\./, "").toLowerCase())
    .filter((e) => AUDIO_EXTENSIONS.has(e));
  return chosen.length > 0 ? new Set(chosen) : AUDIO_EXTENSIONS;
}

async function upsertCoverArt(
  picture: { format: string; data: Uint8Array } | undefined
): Promise<number | null> {
  if (!picture) return null;
  const buf = Buffer.from(picture.data);
  const hash = createHash("sha1").update(buf).digest("hex");
  const existing = await prisma.coverArt.findUnique({ where: { hash } });
  if (existing) return existing.id;
  const created = await prisma.coverArt.create({
    data: { hash, mime: picture.format, data: buf },
  });
  return created.id;
}

const COVER_NAMES = ["cover", "folder", "front", "album"];
const COVER_EXTS = [".jpg", ".jpeg", ".png", ".webp"];

async function findFolderCover(dir: string): Promise<number | null> {
  try {
    const entries = await fs.readdir(dir);
    for (const name of COVER_NAMES) {
      for (const ext of COVER_EXTS) {
        const match = entries.find(
          (e) => e.toLowerCase() === name + ext
        );
        if (match) {
          const full = path.join(dir, match);
          const data = await fs.readFile(full);
          const mime =
            ext === ".png" ? "image/png" :
            ext === ".webp" ? "image/webp" : "image/jpeg";
          return upsertCoverArt({ format: mime, data });
        }
      }
    }
  } catch {}
  return null;
}

async function upsertAlbum(
  name: string,
  albumArtist: string | null,
  groupKey: string,
  year: number | null,
  coverArtId: number | null
): Promise<number> {
  const album = await prisma.album.upsert({
    where: { groupKey },
    update: {
      year: year ?? undefined,
      coverArtId: coverArtId ?? undefined,
      // Fill in a display album-artist if we later learn one.
      albumArtist: albumArtist ?? undefined,
    },
    create: { name, albumArtist, groupKey, year, coverArtId },
  });
  return album.id;
}

// Some files ship with corrupted tags where non-ASCII characters were already
// replaced by U+FFFD () before the file reached us. In that case the tag is
// unrecoverable, but the filename often preserves the correct characters — so
// derive the title from the filename (stripping a leading track number and a
// trailing " - Artist").
function recoverTitle(
  tagTitle: string | undefined,
  filePath: string,
  artist: string | null
): string {
  const base = path.basename(filePath, path.extname(filePath));
  const hasMojibake = (s: string | undefined) => !!s && s.includes("�");

  if (tagTitle && !hasMojibake(tagTitle)) return tagTitle;

  if (!hasMojibake(base)) {
    let name = base.replace(/^\s*\d+\s*[.\-]\s*/, ""); // strip "06. " / "06 - "
    if (artist && !hasMojibake(artist)) {
      const suffix = ` - ${artist}`;
      if (name.endsWith(suffix)) name = name.slice(0, -suffix.length);
    }
    name = name.trim();
    if (name) return name;
  }
  // Fall back to whatever we have.
  return tagTitle || base;
}

async function indexFile(filePath: string): Promise<"added" | "updated" | "skipped"> {
  const stat = await fs.stat(filePath);
  const existing = await prisma.track.findUnique({ where: { filePath } });
  if (existing && existing.mtimeMs === stat.mtimeMs) return "skipped";

  const meta = await parseFile(filePath, { duration: true });
  const common = meta.common;
  const fmt = meta.format;
  const ext = path.extname(filePath).slice(1).toLowerCase();

  let coverArtId = await upsertCoverArt(common.picture?.[0]);
  if (coverArtId == null) {
    coverArtId = await findFolderCover(path.dirname(filePath));
  }
  const albumName = common.album?.trim() || path.basename(path.dirname(filePath));
  const albumArtistTag = common.albumartist?.trim() || null;
  const displayArtist = albumArtistTag ?? common.artist?.trim() ?? null;
  const groupKey = albumArtistTag
    ? `artist:${albumArtistTag}::${albumName}`
    : `dir:${path.dirname(filePath)}::${albumName}`;
  const albumId = await upsertAlbum(
    albumName,
    displayArtist,
    groupKey,
    common.year ?? null,
    coverArtId
  );

  const rawArtist = common.artist?.trim() ?? null;

  const data = {
    filePath,
    title: recoverTitle(common.title?.trim(), filePath, rawArtist),
    artist: rawArtist,
    albumId,
    trackNo: common.track?.no ?? null,
    discNo: common.disk?.no ?? null,
    duration: fmt.duration ?? null,
    format: ext,
    bitrate: fmt.bitrate ? Math.round(fmt.bitrate) : null,
    sampleRate: fmt.sampleRate ?? null,
    fileSize: stat.size,
    mtimeMs: stat.mtimeMs,
    coverArtId,
  };

  if (existing) {
    await prisma.track.update({ where: { filePath }, data });
    return "updated";
  }
  await prisma.track.create({ data });
  return "added";
}

// Scan a single library folder. Rejects if a scan is already running.
export async function scanFolder(folderId: number): Promise<void> {
  if (status.running) throw new Error("A scan is already running");
  const folder = await prisma.libraryFolder.findUnique({ where: { id: folderId } });
  if (!folder) throw new Error("Folder not found");

  Object.assign(status, {
    running: true,
    folderId: folder.id,
    folderPath: folder.path,
    filesFound: 0,
    filesProcessed: 0,
    added: 0,
    updated: 0,
    removed: 0,
    errors: 0,
    startedAt: Date.now(),
    finishedAt: null,
    lastError: null,
  });

  try {
    const allowed = resolveAllowed(folder.extensions);
    const files: string[] = [];
    for await (const f of walk(folder.path, allowed)) files.push(f);
    status.filesFound = files.length;

    for (const file of files) {
      try {
        const result = await indexFile(file);
        if (result === "added") status.added++;
        else if (result === "updated") status.updated++;
      } catch (e) {
        status.errors++;
        status.lastError = `${file}: ${(e as Error).message}`;
      }
      status.filesProcessed++;
    }

    // Prune DB tracks under this folder that were not seen this scan — i.e.
    // files that were deleted on disk or whose extension is now excluded by
    // the folder's filter. Keeps the library in sync with disk + settings.
    const prefix = folder.path.endsWith(path.sep)
      ? folder.path
      : folder.path + path.sep;
    const found = new Set(files);
    const under = await prisma.track.findMany({
      where: { filePath: { startsWith: prefix } },
      select: { id: true, filePath: true },
    });
    const staleIds = under
      .filter((t) => !found.has(t.filePath))
      .map((t) => t.id);
    if (staleIds.length > 0) {
      await prisma.track.deleteMany({ where: { id: { in: staleIds } } });
      status.removed = staleIds.length;
    }
    // Drop albums left with no tracks.
    await prisma.album.deleteMany({ where: { tracks: { none: {} } } });

    await prisma.libraryFolder.update({
      where: { id: folder.id },
      data: { lastScannedAt: new Date() },
    });
  } finally {
    status.running = false;
    status.finishedAt = Date.now();
  }
}

// Scan all folders sequentially.
export async function scanAll(): Promise<void> {
  const folders = await prisma.libraryFolder.findMany();
  for (const folder of folders) {
    await scanFolder(folder.id);
  }
}
