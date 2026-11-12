CREATE TABLE "CatalogImage" (
    "id" UUID NOT NULL,
    "mimeType" VARCHAR(40) NOT NULL,
    "bytes" BYTEA NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CatalogImage_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Product" ADD COLUMN "imageUrl" VARCHAR(200);
