import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
try {
  const tables = await prisma.$queryRaw`
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `;
  console.log('Tables in Neon public schema (' + tables.length + '):');
  for (const t of tables) {
    console.log(' - ' + t.table_name);
  }
} catch (err) {
  console.error('Error querying tables:', err.message);
} finally {
  await prisma.$disconnect();
}
