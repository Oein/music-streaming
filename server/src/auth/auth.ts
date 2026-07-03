import argon2 from "argon2";
import jwt from "jsonwebtoken";
import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";
import { prisma } from "../db/client.js";

export interface TokenPayload {
  sub: number;
  username: string;
}

export async function verifyPassword(username: string, password: string) {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) return null;
  const ok = await argon2.verify(user.passwordHash, password);
  return ok ? user : null;
}

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: "30d" });
}

export function verifyToken(token: string): TokenPayload | null {
  try {
    return jwt.verify(token, config.jwtSecret) as unknown as TokenPayload;
  } catch {
    return null;
  }
}

// Pull a bearer token from the Authorization header OR a `token` query param
// (query is needed for <audio>/native players that can't set headers).
function extractToken(req: FastifyRequest): string | null {
  const header = req.headers.authorization;
  if (header?.startsWith("Bearer ")) return header.slice(7);
  const q = (req.query as Record<string, unknown> | undefined)?.token;
  if (typeof q === "string" && q.length > 0) return q;
  return null;
}

// Fastify preHandler that rejects unauthenticated requests.
export async function requireAuth(req: FastifyRequest, reply: FastifyReply) {
  const token = extractToken(req);
  const payload = token ? verifyToken(token) : null;
  if (!payload) {
    reply.code(401).send({ error: "unauthorized" });
    return;
  }
  (req as FastifyRequest & { user?: TokenPayload }).user = payload;
}
