import type { FastifyInstance } from "fastify";
import sharp from "sharp";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";

// In-memory cache of converted WebP covers, keyed by `${id}:${size}`.
const coverCache = new Map<string, Buffer>();
const coverKey = (id: number, size: number) => `${id}:${size}`;
function getCoverCache(id: number, size: number): Buffer | undefined {
  return coverCache.get(coverKey(id, size));
}
function setCoverCache(id: number, size: number, buf: Buffer): void {
  // Simple bound to avoid unbounded growth.
  if (coverCache.size > 2000) coverCache.clear();
  coverCache.set(coverKey(id, size), buf);
}

// Build the artist label for an album: show up to 2 distinct track artists,
// and "Various Artists" when there are more.
async function albumArtistLabel(
  albumId: number,
  stored: string | null
): Promise<string | null> {
  const rows = await prisma.track.findMany({
    where: { albumId, artist: { not: null } },
    distinct: ["artist"],
    select: { artist: true },
    take: 3,
  });
  const artists = rows.map((r) => r.artist!).filter(Boolean);
  if (artists.length === 0) return stored;
  if (artists.length <= 2) return artists.join(", ");
  return "Various Artists";
}

export async function libraryRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  // List albums with track counts and a computed artist label.
  app.get("/api/albums", async () => {
    const albums = await prisma.album.findMany({
      orderBy: [{ albumArtist: "asc" }, { name: "asc" }],
      include: { _count: { select: { tracks: true } } },
    });
    return Promise.all(
      albums.map(async (a) => ({
        id: a.id,
        name: a.name,
        albumArtist: await albumArtistLabel(a.id, a.albumArtist),
        year: a.year,
        coverArtId: a.coverArtId,
        trackCount: a._count.tracks,
      }))
    );
  });

  // Album detail with ordered tracks.
  app.get("/api/albums/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const album = await prisma.album.findUnique({
      where: { id },
      include: {
        tracks: { orderBy: [{ discNo: "asc" }, { trackNo: "asc" }, { title: "asc" }] },
      },
    });
    if (!album) return reply.code(404).send({ error: "not found" });
    return {
      ...album,
      albumArtist: await albumArtistLabel(album.id, album.albumArtist),
      tracks: album.tracks.map((t) => ({
        ...t,
        coverArtId: t.coverArtId ?? album.coverArtId,
      })),
    };
  });

  // Flat track list (searchable).
  app.get("/api/tracks", async (req) => {
    const q = (req.query as { q?: string }).q?.trim();
    const tracks = await prisma.track.findMany({
      where: q
        ? {
            OR: [
              { title: { contains: q } },
              { artist: { contains: q } },
            ],
          }
        : undefined,
      orderBy: [{ artist: "asc" }, { title: "asc" }],
      take: 1000,
      include: { album: { select: { coverArtId: true } } },
    });
    return tracks.map((t) => {
      const { album, ...rest } = t;
      return { ...rest, coverArtId: t.coverArtId ?? album?.coverArtId ?? null };
    });
  });

  app.get("/api/tracks/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const track = await prisma.track.findUnique({ where: { id } });
    if (!track) return reply.code(404).send({ error: "not found" });
    return track;
  });

  // Cover art as WebP (smaller than the stored JPEG/PNG). An optional ?size=
  // resizes to a square thumbnail — useful for list/search views. Converted
  // buffers are cached in memory keyed by (id, size) since covers are immutable.
  app.get("/api/cover/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const sizeRaw = (req.query as { size?: string }).size;
    const size = sizeRaw ? Math.min(Math.max(parseInt(sizeRaw, 10) || 0, 16), 1024) : 0;

    const cached = getCoverCache(id, size);
    if (cached) {
      reply.header("Content-Type", "image/webp");
      reply.header("Cache-Control", "public, max-age=31536000, immutable");
      return reply.send(cached);
    }

    const cover = await prisma.coverArt.findUnique({ where: { id } });
    if (!cover) return reply.code(404).send({ error: "not found" });

    let img = sharp(Buffer.from(cover.data));
    if (size > 0) {
      img = img.resize(size, size, { fit: "cover" });
    }
    const webp = await img.webp({ quality: 80 }).toBuffer();
    setCoverCache(id, size, webp);

    reply.header("Content-Type", "image/webp");
    reply.header("Cache-Control", "public, max-age=31536000, immutable");
    return reply.send(webp);
  });
}
