import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import type { FastifyInstance } from "fastify";
import { requireAuth } from "../auth/auth.js";
import { prisma } from "../db/client.js";
import { getScanStatus, scanAll, scanFolder } from "../library/scanner.js";

// Normalize an extensions selection to a stored comma string, or null (= all).
function normalizeExtensions(input: string[] | string | undefined): string | null {
  if (input == null) return null;
  const arr = Array.isArray(input) ? input : input.split(",");
  const cleaned = arr
    .map((e) => e.trim().replace(/^\./, "").toLowerCase())
    .filter(Boolean);
  return cleaned.length > 0 ? cleaned.join(",") : null;
}

export async function adminRoutes(app: FastifyInstance) {
  app.addHook("preHandler", requireAuth);

  app.get("/api/admin/folders", async () => {
    return prisma.libraryFolder.findMany({ orderBy: { addedAt: "asc" } });
  });

  app.post("/api/admin/folders", async (req, reply) => {
    const { path: folderPath, extensions } = (req.body ?? {}) as {
      path?: string;
      extensions?: string[] | string;
    };
    if (!folderPath?.trim()) return reply.code(400).send({ error: "path required" });
    const resolved = path.resolve(folderPath.trim());
    try {
      const stat = await fs.stat(resolved);
      if (!stat.isDirectory()) {
        return reply.code(400).send({ error: "path is not a directory" });
      }
    } catch {
      return reply.code(400).send({ error: "path does not exist" });
    }
    const folder = await prisma.libraryFolder.create({
      data: { path: resolved, extensions: normalizeExtensions(extensions) },
    });
    return folder;
  });

  // Update a folder's extension filter.
  app.patch("/api/admin/folders/:id", async (req) => {
    const id = Number((req.params as { id: string }).id);
    const { extensions } = (req.body ?? {}) as {
      extensions?: string[] | string;
    };
    return prisma.libraryFolder.update({
      where: { id },
      data: { extensions: normalizeExtensions(extensions) },
    });
  });

  app.delete("/api/admin/folders/:id", async (req) => {
    const id = Number((req.params as { id: string }).id);
    // deleteMany never throws on a missing row (unlike delete).
    await prisma.libraryFolder.deleteMany({ where: { id } });
    return { ok: true };
  });

  // Trigger a scan (single folder or all). Runs in background; poll status.
  app.post("/api/admin/scan", async (req, reply) => {
    const { folderId } = (req.body ?? {}) as { folderId?: number };
    if (getScanStatus().running) {
      return reply.code(409).send({ error: "scan already running" });
    }
    const run = folderId ? scanFolder(folderId) : scanAll();
    run.catch((e) => app.log.error(e));
    return { started: true };
  });

  app.get("/api/admin/scan/status", async () => getScanStatus());

  app.get("/api/admin/stats", async () => {
    const [albums, tracks, playlists] = await Promise.all([
      prisma.album.count(),
      prisma.track.count(),
      prisma.playlist.count(),
    ]);
    return { albums, tracks, playlists };
  });

  // Lightweight server-side directory browser to help pick folder paths.
  app.get("/api/admin/browse", async (req, reply) => {
    const dir = (req.query as { path?: string }).path?.trim() || os.homedir();
    const resolved = path.resolve(dir);
    try {
      const entries = await fs.readdir(resolved, { withFileTypes: true });
      const dirs = entries
        .filter((e) => e.isDirectory() && !e.name.startsWith("."))
        .map((e) => ({ name: e.name, path: path.join(resolved, e.name) }))
        .sort((a, b) => a.name.localeCompare(b.name));
      return { path: resolved, parent: path.dirname(resolved), dirs };
    } catch {
      return reply.code(400).send({ error: "cannot read directory" });
    }
  });
}
