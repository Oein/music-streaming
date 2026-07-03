import type { FastifyInstance } from "fastify";
import { signToken, verifyPassword } from "../auth/auth.js";

export async function authRoutes(app: FastifyInstance) {
  app.post("/api/auth/login", async (req, reply) => {
    const { username, password } = (req.body ?? {}) as {
      username?: string;
      password?: string;
    };
    if (!username || !password) {
      return reply.code(400).send({ error: "username and password required" });
    }
    const user = await verifyPassword(username, password);
    if (!user) return reply.code(401).send({ error: "invalid credentials" });
    const token = signToken({ sub: user.id, username: user.username });
    return { token, username: user.username };
  });
}
