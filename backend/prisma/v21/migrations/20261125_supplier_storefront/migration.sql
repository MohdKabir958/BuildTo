ALTER TABLE "Supplier"
    ADD COLUMN "publicLatitude" DECIMAL(10,7),
    ADD COLUMN "publicLongitude" DECIMAL(10,7),
    ADD COLUMN "profileImageId" UUID,
    ADD CONSTRAINT "Supplier_public_coordinates_check" CHECK (
        ("publicLatitude" IS NULL AND "publicLongitude" IS NULL) OR
        ("publicLatitude" IS NOT NULL AND "publicLongitude" IS NOT NULL AND
         "publicLatitude" BETWEEN 6 AND 38 AND "publicLongitude" BETWEEN 68 AND 98)
    ),
    ADD CONSTRAINT "Supplier_profileImageId_fkey" FOREIGN KEY ("profileImageId")
        REFERENCES "CatalogImage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "Supplier_publicLatitude_publicLongitude_idx"
    ON "Supplier"("publicLatitude", "publicLongitude");
