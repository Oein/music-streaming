import type { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";

// Listening statistics.
//
// Playback devices (the app, rpi-player) measure how long each track actually
// played and report it as listen events. Everything here aggregates those
// events; "day" is always the listener's local calendar date as reported by
// the device, so a day boundary never depends on the server's timezone.

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
// A listen counts as a "play" after 30s, or half the track if it is shorter.
const PLAY_THRESHOLD_SEC = 30;
const MAX_BATCH = 500;

interface IncomingEvent {
  clientId?: unknown;
  trackId?: unknown;
  day?: unknown;
  startedAt?: unknown;
  seconds?: unknown;
  device?: unknown;
}

type Range = { from?: string; to?: string };

function rangeFrom(query: unknown): Range {
  const q = (query ?? {}) as Record<string, string | undefined>;
  return {
    from: q.from && DAY_RE.test(q.from) ? q.from : undefined,
    to: q.to && DAY_RE.test(q.to) ? q.to : undefined,
  };
}

function rangeSql({ from, to }: Range): Prisma.Sql {
  const parts: Prisma.Sql[] = [];
  if (from) parts.push(Prisma.sql`day >= ${from}`);
  if (to) parts.push(Prisma.sql`day <= ${to}`);
  return parts.length ? Prisma.sql`WHERE ${Prisma.join(parts, " AND ")}` : Prisma.empty;
}

const num = (v: unknown) => Number(v ?? 0);

// Tracks in the shape the app's Track.fromJson expects, keyed by id, with the
// album cover as a fallback (same as the favorites route).
async function trackMap(ids: number[]) {
  const tracks = await prisma.track.findMany({
    where: { id: { in: ids } },
    include: { album: { select: { coverArtId: true } } },
  });
  return new Map(
    tracks.map((t) => {
      const { album, filePath: _f, mtimeMs: _m, ...rest } = t;
      return [t.id, { ...rest, coverArtId: t.coverArtId ?? album?.coverArtId ?? null }];
    })
  );
}

export async function statsRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  // Record (or update) listen events. Idempotent per clientId; a re-sent event
  // only ever grows, so out-of-order retries can't shrink a listen.
  app.post("/api/stats/listens", async (req, reply) => {
    const body = (req.body ?? {}) as { events?: IncomingEvent[] };
    const events = Array.isArray(body.events) ? body.events.slice(0, MAX_BATCH) : [];
    const valid = events.filter(
      (e) =>
        typeof e.clientId === "string" &&
        e.clientId.length > 0 &&
        e.clientId.length <= 100 &&
        Number.isInteger(e.trackId) &&
        typeof e.day === "string" &&
        DAY_RE.test(e.day) &&
        typeof e.seconds === "number" &&
        Number.isFinite(e.seconds) &&
        e.seconds > 0
    );
    if (valid.length === 0) return { ok: true, accepted: 0 };

    const ids = [...new Set(valid.map((e) => e.trackId as number))];
    const tracks = await prisma.track.findMany({
      where: { id: { in: ids } },
      include: { album: { select: { id: true, name: true } } },
    });
    const byId = new Map(tracks.map((t) => [t.id, t]));

    let accepted = 0;
    await prisma.$transaction(async (tx) => {
      for (const e of valid) {
        const track = byId.get(e.trackId as number);
        if (!track) continue; // unknown track: nothing to attribute it to
        // One listen can't run (much) past the end of the track.
        const cap = track.duration ? track.duration + 5 : 24 * 3600;
        const seconds = Math.min(e.seconds as number, cap);
        const threshold = track.duration
          ? Math.min(PLAY_THRESHOLD_SEC, track.duration / 2)
          : PLAY_THRESHOLD_SEC;
        const startedAt = new Date((e.startedAt as string | number) ?? Date.now());
        const clientId = e.clientId as string;

        const existing = await tx.listenEvent.findUnique({ where: { clientId } });
        if (existing) {
          if (seconds > existing.seconds) {
            await tx.listenEvent.update({
              where: { clientId },
              data: { seconds, counted: seconds >= threshold },
            });
          }
        } else {
          await tx.listenEvent.create({
            data: {
              clientId,
              trackId: track.id,
              title: track.title,
              artist: track.artist,
              albumId: track.album?.id ?? null,
              albumName: track.album?.name ?? null,
              day: e.day as string,
              startedAt: Number.isNaN(startedAt.getTime()) ? new Date() : startedAt,
              seconds,
              counted: seconds >= threshold,
              device: typeof e.device === "string" ? e.device.slice(0, 100) : null,
            },
          });
        }
        accepted++;
      }
    });
    reply.code(200);
    return { ok: true, accepted };
  });

  // Per-day totals for the heatmap.
  app.get("/api/stats/calendar", async (req) => {
    const where = rangeSql(rangeFrom(req.query));
    const rows = await prisma.$queryRaw<{ day: string; seconds: unknown; plays: unknown }[]>`
      SELECT day, SUM(seconds) AS seconds, SUM(counted) AS plays
      FROM ListenEvent ${where}
      GROUP BY day ORDER BY day`;
    return {
      days: rows.map((r) => ({ day: r.day, seconds: num(r.seconds), plays: num(r.plays) })),
    };
  });

  // What was played on one day, most listened first.
  app.get("/api/stats/day/:day", async (req, reply) => {
    const day = (req.params as { day: string }).day;
    if (!DAY_RE.test(day)) return reply.code(400).send({ error: "day must be YYYY-MM-DD" });
    const rows = await prisma.$queryRaw<
      { trackId: number | null; title: string; artist: string | null; albumName: string | null; seconds: unknown; plays: unknown }[]
    >`
      SELECT trackId, MAX(title) AS title, MAX(artist) AS artist, MAX(albumName) AS albumName,
             SUM(seconds) AS seconds, SUM(counted) AS plays
      FROM ListenEvent WHERE day = ${day}
      GROUP BY COALESCE(CAST(trackId AS TEXT), 'x:' || title)
      ORDER BY seconds DESC`;
    const tracks = await trackMap(rows.flatMap((r) => (r.trackId == null ? [] : [r.trackId])));
    const items = rows.map((r) => ({
      track: r.trackId == null ? null : tracks.get(r.trackId) ?? null,
      title: r.title,
      artist: r.artist,
      albumName: r.albumName,
      seconds: num(r.seconds),
      plays: num(r.plays),
    }));
    return {
      day,
      seconds: items.reduce((s, i) => s + i.seconds, 0),
      plays: items.reduce((s, i) => s + i.plays, 0),
      tracks: items,
    };
  });

  // Most played tracks / albums / artists in a date range (all time if no
  // range). Ranked by plays, then listening time.
  app.get("/api/stats/top", async (req) => {
    const range = rangeFrom(req.query);
    const limit = Math.min(Math.max(Number((req.query as { limit?: string }).limit) || 10, 1), 50);
    const where = rangeSql(range);

    const [totals] = await prisma.$queryRaw<{ seconds: unknown; plays: unknown; days: unknown }[]>`
      SELECT SUM(seconds) AS seconds, SUM(counted) AS plays, COUNT(DISTINCT day) AS days
      FROM ListenEvent ${where}`;

    const trackRows = await prisma.$queryRaw<
      { trackId: number | null; title: string; artist: string | null; albumName: string | null; seconds: unknown; plays: unknown }[]
    >`
      SELECT trackId, MAX(title) AS title, MAX(artist) AS artist, MAX(albumName) AS albumName,
             SUM(seconds) AS seconds, SUM(counted) AS plays
      FROM ListenEvent ${where}
      GROUP BY COALESCE(CAST(trackId AS TEXT), 'x:' || title)
      ORDER BY plays DESC, seconds DESC LIMIT ${limit}`;

    const albumRows = await prisma.$queryRaw<
      { albumId: number | null; albumName: string | null; seconds: unknown; plays: unknown }[]
    >`
      SELECT albumId, MAX(albumName) AS albumName, SUM(seconds) AS seconds, SUM(counted) AS plays
      FROM ListenEvent ${where}
      GROUP BY COALESCE(CAST(albumId AS TEXT), 'x:' || COALESCE(albumName, ''))
      ORDER BY plays DESC, seconds DESC LIMIT ${limit}`;

    const artistRows = await prisma.$queryRaw<{ artist: string; seconds: unknown; plays: unknown }[]>`
      SELECT artist, SUM(seconds) AS seconds, SUM(counted) AS plays
      FROM ListenEvent ${where === Prisma.empty ? Prisma.sql`WHERE artist IS NOT NULL` : Prisma.sql`${where} AND artist IS NOT NULL`}
      GROUP BY artist
      ORDER BY plays DESC, seconds DESC LIMIT ${limit}`;

    const tracks = await trackMap(trackRows.flatMap((r) => (r.trackId == null ? [] : [r.trackId])));
    const albumIds = albumRows.flatMap((r) => (r.albumId == null ? [] : [r.albumId]));
    const albums = new Map(
      (await prisma.album.findMany({ where: { id: { in: albumIds } } })).map((a) => [a.id, a])
    );

    return {
      from: range.from ?? null,
      to: range.to ?? null,
      seconds: num(totals?.seconds),
      plays: num(totals?.plays),
      days: num(totals?.days),
      tracks: trackRows.map((r) => ({
        track: r.trackId == null ? null : tracks.get(r.trackId) ?? null,
        title: r.title,
        artist: r.artist,
        albumName: r.albumName,
        seconds: num(r.seconds),
        plays: num(r.plays),
      })),
      albums: albumRows.map((r) => {
        const a = r.albumId == null ? undefined : albums.get(r.albumId);
        return {
          album: a
            ? { id: a.id, name: a.name, albumArtist: a.albumArtist, year: a.year, coverArtId: a.coverArtId, trackCount: 0 }
            : null,
          name: a?.name ?? r.albumName ?? "Unknown album",
          seconds: num(r.seconds),
          plays: num(r.plays),
        };
      }),
      artists: artistRows.map((r) => ({ name: r.artist, seconds: num(r.seconds), plays: num(r.plays) })),
    };
  });
}
