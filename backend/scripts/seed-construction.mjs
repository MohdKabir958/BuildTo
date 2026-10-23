#!/usr/bin/env node
/**
 * Idempotent construction catalog seeder for Buildto (Neon / PostgreSQL).
 * Seeds the 9 categories, 6 suppliers, and 54 construction-material products.
 */
import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const catalogPath = path.join(root, 'demo/construction-catalog.json');

if (!existsSync(catalogPath)) {
  console.error(`Catalog file not found at ${catalogPath}`);
  process.exit(1);
}

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
const prisma = new PrismaClient();

async function main() {
  console.log('Connecting to database...');
  try {
    await prisma.$queryRaw`SELECT 1 as connected`;
    console.log('Database connection verified successfully.');
  } catch (err) {
    console.warn(`Direct DB connection check note: ${err.message}`);
    console.log('Continuing with seeding if tables exist...');
  }

  // 1. Seed Categories
  console.log(`\nSeeding ${catalog.categories.length} construction categories...`);
  for (const cat of catalog.categories) {
    await prisma.category.upsert({
      where: { slug: cat.slug },
      update: {
        name: cat.name,
        icon: cat.icon,
        sortOrder: cat.sortOrder,
        isActive: true,
        forRestaurants: true,
        forDishes: true,
        showOnHome: true,
      },
      create: {
        id: cat.id,
        name: cat.name,
        slug: cat.slug,
        icon: cat.icon,
        sortOrder: cat.sortOrder,
        isActive: true,
        forRestaurants: true,
        forDishes: true,
        showOnHome: true,
      },
    });
  }
  console.log('Categories seeded.');

  // 2. Seed Suppliers
  console.log(`\nSeeding ${catalog.suppliers.length} construction suppliers...`);
  for (const s of catalog.suppliers) {
    const ownerEmail = `${s.id}@buildto.in`;
    const user = await prisma.user.upsert({
      where: { email: ownerEmail },
      update: { name: `${s.name} Owner`, role: 'VENDOR' },
      create: {
        name: `${s.name} Owner`,
        email: ownerEmail,
        role: 'VENDOR',
        phone: `+91 98${Math.floor(10000000 + Math.random() * 90000000)}`,
      },
    });

    await prisma.vendor.upsert({
      where: { id: s.id },
      update: {
        name: s.name,
        category: s.category,
        rating: s.rating,
        totalRatingsCount: s.ratingCount,
        eta: s.eta,
        bannerImage: s.bannerImage,
        address: s.address,
        isAcceptingOrders: s.isAcceptingOrders,
        approvalStatus: 'APPROVED',
      },
      create: {
        id: s.id,
        userId: user.id,
        name: s.name,
        category: s.category,
        rating: s.rating,
        totalRatingsCount: s.ratingCount,
        eta: s.eta,
        bannerImage: s.bannerImage,
        address: s.address,
        isAcceptingOrders: s.isAcceptingOrders,
        approvalStatus: 'APPROVED',
      },
    });
  }
  console.log('Suppliers seeded.');

  // 3. Seed Products
  console.log(`\nSeeding ${catalog.products.length} construction products...`);
  let count = 0;
  for (const p of catalog.products) {
    await prisma.menuItem.upsert({
      where: { id: p.id },
      update: {
        name: p.name,
        price: p.price,
        vendorPrice: p.price * 0.9,
        category: p.category,
        categoryId: p.categoryId,
        description: p.description,
        imageUrl: p.imageUrl,
        imageUrls: p.imageUrls,
        sku: p.sku,
        productKey: p.productKey,
        unit: p.unit,
        packSize: p.packSize,
        mrpPaise: p.mrpPaise,
        stockQty: p.stockQty,
        rating: p.rating,
        ratingCount: p.ratingCount,
        approvalStatus: 'APPROVED',
        isAvailable: true,
      },
      create: {
        id: p.id,
        vendorId: p.vendorId,
        name: p.name,
        price: p.price,
        vendorPrice: p.price * 0.9,
        category: p.category,
        categoryId: p.categoryId,
        description: p.description,
        imageUrl: p.imageUrl,
        imageUrls: p.imageUrls,
        sku: p.sku,
        productKey: p.productKey,
        unit: p.unit,
        packSize: p.packSize,
        mrpPaise: p.mrpPaise,
        stockQty: p.stockQty,
        rating: p.rating,
        ratingCount: p.ratingCount,
        approvalStatus: 'APPROVED',
        isAvailable: true,
      },
    });
    count++;
  }
  console.log(`Successfully seeded ${count} products.`);

  // 4. Verification queries
  const totalCategories = await prisma.category.count();
  const totalVendors = await prisma.vendor.count();
  const totalItems = await prisma.menuItem.count();

  console.log('\n--- Buildto Neon Database Verification Summary ---');
  console.log(`Total Categories in DB: ${totalCategories}`);
  console.log(`Total Suppliers in DB:  ${totalVendors}`);
  console.log(`Total Products in DB:   ${totalItems}`);
  console.log('--------------------------------------------------');
}

main()
  .catch((e) => {
    console.error('Seeding encountered an error:', e.message);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
