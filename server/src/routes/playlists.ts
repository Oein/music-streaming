import type { FastifyInstance } from "fastify";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";

export async function playlistRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  app.get("/api/playlists", async () => {
    const playlists = await prisma.playlist.findMany({
      orderBy: { createdAt: "desc" },
      include: { _count: { select: { tracks: true } } },
    });
    return playlists.map((p) => ({
      id: p.id,
      name: p.name,
      createdAt: p.createdAt,
      trackCount: p._count.tracks,
    }));
  });

  app.get("/api/playlists/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const playlist = await prisma.playlist.findUnique({
      where: { id },
      include: {
        tracks: {
          orderBy: { position: "asc" },
          include: { track: { include: { album: { select: { coverArtId: true } } } } },
        },
      },
    });
    if (!playlist) return reply.code(404).send({ error: "not found" });
    return {
      id: playlist.id,
      name: playlist.name,
      createdAt: playlist.createdAt,
      tracks: playlist.tracks.map((pt) => {
        const { album, ...rest } = pt.track;
        return { position: pt.position, ...rest, coverArtId: pt.track.coverArtId ?? album?.coverArtId ?? null };
      }),
    };
  });

  app.post("/api/playlists", async (req, reply) => {
    const { name } = (req.body ?? {}) as { name?: string };
    if (!name?.trim()) return reply.code(400).send({ error: "name required" });
    const playlist = await prisma.playlist.create({ data: { name: name.trim() } });
    return playlist;
  });

  app.patch("/api/playlists/:id", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const { name } = (req.body ?? {}) as { name?: string };
    if (!name?.trim()) return reply.code(400).send({ error: "name required" });
    const playlist = await prisma.playlist.update({
      where: { id },
      data: { name: name.trim() },
    });
    return playlist;
  });

  app.delete("/api/playlists/:id", async (req) => {
    const id = Number((req.params as { id: string }).id);
    await prisma.playlist.deleteMany({ where: { id } });
    return { ok: true };
  });

  // Append a track to the end of the playlist.
  app.post("/api/playlists/:id/tracks", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const { trackId } = (req.body ?? {}) as { trackId?: number };
    if (!trackId) return reply.code(400).send({ error: "trackId required" });
    const last = await prisma.playlistTrack.findFirst({
      where: { playlistId: id },
      orderBy: { position: "desc" },
    });
    const position = (last?.position ?? -1) + 1;
    await prisma.playlistTrack.create({ data: { playlistId: id, trackId, position } });
    return { ok: true, position };
  });

  // Replace the full ordered track list (used for reorder + remove).
  app.put("/api/playlists/:id/tracks", async (req, reply) => {
    const id = Number((req.params as { id: string }).id);
    const { trackIds } = (req.body ?? {}) as { trackIds?: number[] };
    if (!Array.isArray(trackIds)) {
      return reply.code(400).send({ error: "trackIds array required" });
    }
    await prisma.$transaction(async (tx) => {
      await tx.playlistTrack.deleteMany({ where: { playlistId: id } });
      // Two-phase not needed since we deleted all rows first.
      for (let i = 0; i < trackIds.length; i++) {
        await tx.playlistTrack.create({
          data: { playlistId: id, trackId: trackIds[i], position: i },
        });
      }
    });
    return { ok: true };
  });
}
