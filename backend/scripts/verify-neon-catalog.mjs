import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('--- VERIFYING LIVE NEON DATABASE CATALOG ---');
  
  // 1. Categories
  const categories = await prisma.category.findMany({
    orderBy: { sortOrder: 'asc' },
    select: { id: true, name: true, slug: true, icon: true },
  });
  console.log(`\nCategories (${categories.length}):`);
  for (const c of categories) {
    console.log(`  - [${c.id}] ${c.name} (${c.slug})`);
  }

  // 2. Suppliers
  const vendors = await prisma.vendor.findMany({
    select: { id: true, name: true, category: true, rating: true, isAcceptingOrders: true, address: true },
  });
  console.log(`\nSuppliers / Vendors (${vendors.length}):`);
  for (const v of vendors) {
    console.log(`  - [${v.id}] ${v.name} | Rating: ${v.rating} | Open: ${v.isAcceptingOrders} | ${v.address}`);
  }

  // 3. Products count and sample
  const productsCount = await prisma.menuItem.count();
  console.log(`\nTotal Construction Products in DB: ${productsCount}`);

  const sampleProducts = await prisma.menuItem.findMany({
    take: 10,
    select: {
      id: true,
      name: true,
      price: true,
      packSize: true,
      category: true,
      vendor: { select: { name: true } },
    },
  });
  console.log('\nSample Construction Materials:');
  for (const p of sampleProducts) {
    console.log(`  - ${p.name} | ₹${p.price} | Pack: ${p.packSize} | Cat: ${p.category} | Supplier: ${p.vendor?.name}`);
  }
  
  // 4. Products grouped by category
  console.log('\nProducts count per category:');
  for (const cat of categories) {
    const count = await prisma.menuItem.count({
      where: { category: cat.name },
    });
    console.log(`  - ${cat.name}: ${count} products`);
  }

  console.log('\n--------------------------------------------');
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
