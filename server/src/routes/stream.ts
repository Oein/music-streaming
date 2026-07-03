import { createReadStream, promises as fs } from "node:fs";
import path from "node:path";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";
import { decideTranscode } from "../transcode/transcode.js";
import { ensureTranscoded } from "../transcode/cache.js";
import { warmTracks } from "../transcode/warmup.js";

const MIME_BY_EXT: Record<string, string> = {
  mp3: "audio/mpeg",
  ogg: "audio/ogg",
  oga: "audio/ogg",
  wav: "audio/wav",
  flac: "audio/flac",
  m4a: "audio/mp4",
};

// Serve a complete on-disk file with HTTP Range support (Content-Length +
// 206 partial responses), so clients can buffer ahead and seek.
async function serveFile(
  req: FastifyRequest,
  reply: FastifyReply,
  filePath: string,
  contentType: string
) {
  const size = (await fs.stat(filePath)).size;
  reply.header("Content-Type", contentType);
  reply.header("Accept-Ranges", "bytes");

  const range = req.headers.range;
  if (range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (match) {
      const start = match[1] ? parseInt(match[1], 10) : 0;
      const end = match[2] ? parseInt(match[2], 10) : size - 1;
      if (start >= size || end >= size || start > end) {
        reply.header("Content-Range", `bytes */${size}`);
        return reply.code(416).send();
      }
      reply.code(206);
      reply.header("Content-Range", `bytes ${start}-${end}/${size}`);
      reply.header("Content-Length", end - start + 1);
      return reply.send(createReadStream(filePath, { start, end }));
    }
  }

  reply.header("Content-Length", size);
  return reply.send(createReadStream(filePath));
}

export async function streamRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  // (B) Play-imminent warming: the client posts track ids it's about to play
  // (album/playlist opened, next in queue) so the AAC cache is ready before the
  // user hits play. Fire-and-forget: returns 202 immediately.
  app.post("/api/prewarm", async (req, reply) => {
    const body = req.body as { ids?: unknown } | undefined;
    const ids = Array.isArray(body?.ids)
      ? body.ids.map(Number).filter((n) => Number.isFinite(n))
      : [];
    void warmTracks(ids, req.log);
    return reply.code(202).send({ ok: true, queued: ids.length });
  });

  // GET /api/stream/:id?canPlay=mp3,wav,flac&token=...
  app.get("/api/stream/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const track = await prisma.track.findUnique({ where: { id } });
    if (!track) return reply.code(404).send({ error: "not found" });

    try {
      await fs.access(track.filePath);
    } catch {
      return reply.code(410).send({ error: "file missing on disk" });
    }

    const canPlayRaw = (req.query as { canPlay?: string }).canPlay;
    const clientCanPlay = canPlayRaw
      ? new Set(
          canPlayRaw
            .split(",")
            .map((s) => s.trim().toLowerCase())
            .filter(Boolean)
        )
      : null;

    const decision = decideTranscode(track.format, clientCanPlay);

    // Transcoded path: transcode once to a cached file, then serve it like any
    // other file (Content-Length + Range). This replaces the old live ffmpeg
    // pipe, which — being non-seekable with no Content-Length — made players
    // stall mid-playback and show a permanent "buffering" state.
    if (decision.transcode) {
      try {
        const cached = await ensureTranscoded(track);
        return await serveFile(req, reply, cached, decision.contentType);
      } catch (err) {
        req.log.error({ err }, "transcode failed");
        return reply.code(500).send({ error: "transcode failed" });
      }
    }

    // Original file, served with Range support.
    const ext = path.extname(track.filePath).slice(1).toLowerCase();
    const contentType = MIME_BY_EXT[ext] ?? "application/octet-stream";
    return serveFile(req, reply, track.filePath, contentType);
  });
}
