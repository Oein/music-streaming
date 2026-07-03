// Usage: tsx src/scripts/setPassword.ts <username> <password>
// Creates or updates the single admin user.
import argon2 from "argon2";
import { prisma } from "../db/client.js";

async function main() {
  const [username, password] = process.argv.slice(2);
  if (!username || !password) {
    console.error("Usage: tsx src/scripts/setPassword.ts <username> <password>");
    process.exit(1);
  }
  const passwordHash = await argon2.hash(password);
  await prisma.user.upsert({
    where: { username },
    update: { passwordHash },
    create: { username, passwordHash },
  });
  console.log(`User "${username}" saved.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
