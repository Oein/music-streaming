import type { FastifyInstance } from "fastify";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";

export async function favoriteRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  app.get("/api/favorites", async () => {
    const favs = await prisma.favoriteTrack.findMany({
      orderBy: { createdAt: "desc" },
      include: { track: { include: { album: { select: { coverArtId: true } } } } },
    });
    return favs.map((f) => {
      const { album, ...rest } = f.track;
      return { ...rest, coverArtId: f.track.coverArtId ?? album?.coverArtId ?? null };
    });
  });

  app.get("/api/favorites/ids", async () => {
    const favs = await prisma.favoriteTrack.findMany({
      select: { trackId: true },
    });
    return favs.map((f) => f.trackId);
  });

  app.post("/api/favorites/:trackId", async (req) => {
    const trackId = Number((req.params as { trackId: string }).trackId);
    await prisma.favoriteTrack.upsert({
      where: { trackId },
      create: { trackId },
      update: {},
    });
    return { ok: true, liked: true };
  });

  app.delete("/api/favorites/:trackId", async (req) => {
    const trackId = Number((req.params as { trackId: string }).trackId);
    await prisma.favoriteTrack.deleteMany({ where: { trackId } });
    return { ok: true, liked: false };
  });
}
