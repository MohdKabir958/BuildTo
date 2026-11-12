BEGIN;
ALTER TABLE "MediaAsset" ADD COLUMN "purpose" VARCHAR(30) NOT NULL DEFAULT 'EVIDENCE', ADD COLUMN "productId" UUID, ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "MediaAsset" ADD CONSTRAINT "MediaAsset_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT;
ALTER TABLE "MediaAsset" ADD CONSTRAINT "MediaAsset_public_image_guard" CHECK ("purpose" IN ('EVIDENCE','CATALOG_IMAGE') AND ("productId" IS NULL OR ("purpose"='CATALOG_IMAGE' AND "mimeType"='image/png')) AND "position">=0 AND "position"<12);
CREATE INDEX "MediaAsset_productId_position_idx" ON "MediaAsset" ("productId","position");
COMMIT;
