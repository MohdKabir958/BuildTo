import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

console.log('Testing Neon database connection...');
const prisma = new PrismaClient();

try {
  const result = await prisma.$queryRaw`SELECT 1 as test, current_database() as db, version() as ver`;
  console.log('Neon Connection SUCCESS:', result);
} catch (err) {
  console.error('Neon Connection ERROR:', err.message);
} finally {
  await prisma.$disconnect();
}
