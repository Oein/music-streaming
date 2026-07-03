import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import path from "node:path";
import Fastify from "fastify";
import cors from "@fastify/cors";
import fastifyStatic from "@fastify/static";
import fastifyWebsocket from "@fastify/websocket";
import { config } from "./config.js";
import { registerRemoteHub } from "./remote/hub.js";
import { authRoutes } from "./routes/auth.js";
import { libraryRoutes } from "./routes/library.js";
import { playlistRoutes } from "./routes/playlists.js";
import { streamRoutes } from "./routes/stream.js";
import { adminRoutes } from "./routes/admin.js";
import { favoriteRoutes } from "./routes/favorites.js";
import { warmLibrary } from "./transcode/warmup.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  const app = Fastify({ logger: true });

  await app.register(cors, { origin: true });
  await app.register(fastifyWebsocket);

  // Tolerate empty bodies on requests that declare application/json (e.g. a
  // DELETE sent with a JSON content-type but no body) instead of 400-ing.
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      const text = (body as string).trim();
      if (text.length === 0) return done(null, undefined);
      try {
        done(null, JSON.parse(text));
      } catch (err) {
        (err as { statusCode?: number }).statusCode = 400;
        done(err as Error, undefined);
      }
    }
  );

  // Serve the admin SPA from ../admin (static HTML/JS).
  await app.register(fastifyStatic, {
    root: path.resolve(__dirname, "../admin"),
    prefix: "/admin/",
  });

  // Serve the built Flutter web app. WEB_DIR (a mounted volume in the
  // container) overrides the bundled ../web dir when set.
  const webRoot = config.webDir || path.resolve(__dirname, "../web");
  if (existsSync(webRoot)) {
    await app.register(fastifyStatic, {
      root: webRoot,
      prefix: "/app/",
      decorateReply: false,
    });
  }

  // Serve native app artifacts (apk/ipa/dmg) for download, if present.
  // DOWNLOADS_DIR (a mounted volume) overrides the bundled ../downloads dir.
  const downloadsRoot = config.downloadsDir || path.resolve(__dirname, "../downloads");
  if (existsSync(downloadsRoot)) {
    await app.register(fastifyStatic, {
      root: downloadsRoot,
      prefix: "/downloads/",
      decorateReply: false,
      list: true,
    });
  }

  app.get("/api/health", async () => ({ ok: true }));

  await app.register(authRoutes);
  await app.register(libraryRoutes);
  await app.register(playlistRoutes);
  await app.register(streamRoutes);
  await app.register(adminRoutes);
  await app.register(favoriteRoutes);
  await app.register(registerRemoteHub);

  // Redirect root to the web app if built, otherwise the admin page.
  app.get("/", async (_req, reply) =>
    reply.redirect(existsSync(webRoot) ? "/app/" : "/admin/")
  );

  await app.listen({ port: config.port, host: config.host });
  app.log.info(`Music server listening on http://${config.host}:${config.port}`);

  // (A) Warm the transcode cache in the background so the first play of every
  // track is instant (no on-demand transcode wait). Idempotent; runs after the
  // server is already serving so it never delays startup.
  void warmLibrary(app.log);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
