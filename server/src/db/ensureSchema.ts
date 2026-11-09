import { prisma } from "./client.js";

// The production image runs `node dist/index.js` without the Prisma CLI, so
// `prisma db push` never runs there. Tables added after the first deploy are
// created here on startup instead. Each statement is the DDL Prisma generates
// for schema.prisma (`prisma migrate diff --from-empty --to-schema-datamodel
// prisma/schema.prisma --script`), made idempotent, so a later `db push` sees
// no difference. Keep it in sync when these models change.
const STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS "ListenEvent" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "clientId" TEXT NOT NULL,
    "trackId" INTEGER,
    "title" TEXT NOT NULL,
    "artist" TEXT,
    "albumId" INTEGER,
    "albumName" TEXT,
    "day" TEXT NOT NULL,
    "startedAt" DATETIME NOT NULL,
    "seconds" REAL NOT NULL,
    "counted" BOOLEAN NOT NULL DEFAULT false,
    "device" TEXT,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ListenEvent_trackId_fkey" FOREIGN KEY ("trackId") REFERENCES "Track" ("id") ON DELETE SET NULL ON UPDATE CASCADE
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS "ListenEvent_clientId_key" ON "ListenEvent"("clientId")`,
  `CREATE INDEX IF NOT EXISTS "ListenEvent_day_idx" ON "ListenEvent"("day")`,
  `CREATE INDEX IF NOT EXISTS "ListenEvent_trackId_idx" ON "ListenEvent"("trackId")`,
];

export async function ensureSchema(): Promise<void> {
  for (const sql of STATEMENTS) await prisma.$executeRawUnsafe(sql);
}
