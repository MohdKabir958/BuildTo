-- Buildto V2.1 GREENFIELD baseline. Source: architecture/buildto-schema-v2.1/sql/*
-- Never run this migration against an already populated V2.1 branch.
-- Existing V2.1 databases must first pass the read-only contract check and be
-- marked applied with prisma migrate resolve (never recreate their tables).
-- The entire operation is transactional, including PostGIS, DDL and custom guards.
BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

-- Generated Prisma V2.1 DDL. No rewriting of names or money/geometry types.
-- CreateEnum
CREATE TYPE "AccountStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'CLOSED');

-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('OWNER', 'OPERATIONS', 'CATALOG', 'FINANCE', 'SUPPORT', 'AUDITOR');

-- CreateEnum
CREATE TYPE "SupplierRole" AS ENUM ('OWNER', 'MANAGER', 'CATALOG', 'INVENTORY', 'FULFILLMENT', 'FINANCE', 'VIEWER');

-- CreateEnum
CREATE TYPE "ApprovalStatus" AS ENUM ('DRAFT', 'PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "DocumentStatus" AS ENUM ('UPLOADED', 'PENDING', 'REVIEWED', 'VERIFIED', 'REJECTED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "ListingStatus" AS ENUM ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "QuantityDimension" AS ENUM ('COUNT', 'MASS', 'LENGTH', 'AREA', 'VOLUME');

-- CreateEnum
CREATE TYPE "StockReservationStatus" AS ENUM ('HELD', 'COMMITTED', 'RELEASED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "StockMovementType" AS ENUM ('RECEIPT', 'SALE', 'RESERVATION_RELEASE', 'ADJUSTMENT', 'DAMAGE', 'RETURN', 'TRANSFER_IN', 'TRANSFER_OUT');

-- CreateEnum
CREATE TYPE "ProjectStatus" AS ENUM ('ACTIVE', 'ON_HOLD', 'COMPLETED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "RfqStatus" AS ENUM ('DRAFT', 'OPEN', 'CLOSED', 'AWARDED', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "QuoteStatus" AS ENUM ('DRAFT', 'SUBMITTED', 'REVISED', 'ACCEPTED', 'REJECTED', 'WITHDRAWN', 'EXPIRED');

-- CreateEnum
CREATE TYPE "CheckoutQuoteStatus" AS ENUM ('OPEN', 'CONSUMED', 'EXPIRED', 'INVALIDATED');

-- CreateEnum
CREATE TYPE "PurchaseOrderStatus" AS ENUM ('PLACED', 'CONFIRMED', 'PARTIALLY_FULFILLED', 'PARTIALLY_CANCELLED', 'FULFILLED', 'CANCELLED', 'CLOSED');

-- CreateEnum
CREATE TYPE "SupplierOrderStatus" AS ENUM ('PENDING_ACCEPTANCE', 'CONFIRMED', 'PACKING', 'READY', 'DISPATCHED', 'PARTIALLY_DELIVERED', 'DELIVERED', 'CANCELLED', 'REJECTED');

-- CreateEnum
CREATE TYPE "ShipmentStatus" AS ENUM ('PLANNED', 'PACKED', 'DISPATCHED', 'OUT_FOR_DELIVERY', 'PARTIALLY_DELIVERED', 'DELIVERED', 'FAILED', 'RETURNED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "GstRegistrationType" AS ENUM ('UNVERIFIED', 'REGULAR', 'COMPOSITION', 'UNREGISTERED', 'EXEMPT');

-- CreateEnum
CREATE TYPE "InvoiceKind" AS ENUM ('TAX_INVOICE', 'BILL_OF_SUPPLY', 'CREDIT_NOTE', 'DEBIT_NOTE');

-- CreateEnum
CREATE TYPE "CodCollectionStatus" AS ENUM ('RECORDED', 'VERIFIED', 'DISPUTED', 'REVERSED');

-- CreateEnum
CREATE TYPE "ReceivableStatus" AS ENUM ('OPEN', 'PARTIALLY_OFFSET', 'SETTLED', 'WRITTEN_OFF');

-- CreateEnum
CREATE TYPE "DeliveryHandoverMethod" AS ENUM ('OTP', 'APPROVED_EXCEPTION');

-- CreateEnum
CREATE TYPE "PaymentMethod" AS ENUM ('UPI', 'CARD', 'NET_BANKING', 'COD', 'OTHER');

-- CreateEnum
CREATE TYPE "PaymentAttemptStatus" AS ENUM ('CREATED', 'PENDING', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PaymentProvider" AS ENUM ('RAZORPAY', 'MANUAL', 'OTHER');

-- CreateEnum
CREATE TYPE "RefundStatus" AS ENUM ('REQUESTED', 'APPROVED', 'PROCESSING', 'SUCCEEDED', 'FAILED', 'REJECTED', 'MANUAL_REVIEW');

-- CreateEnum
CREATE TYPE "InvoiceStatus" AS ENUM ('ISSUED', 'VOIDED', 'CREDITED');

-- CreateEnum
CREATE TYPE "SettlementStatus" AS ENUM ('OPEN', 'ON_HOLD', 'APPROVED', 'PROCESSING', 'PAID', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PayoutStatus" AS ENUM ('PENDING', 'PROCESSING', 'SUCCEEDED', 'FAILED');

-- CreateEnum
CREATE TYPE "ReturnStatus" AS ENUM ('REQUESTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'IN_TRANSIT', 'RECEIVED', 'RESOLVED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "SupportStatus" AS ENUM ('OPEN', 'ASSIGNED', 'IN_PROGRESS', 'WAITING_CUSTOMER', 'RESOLVED', 'CLOSED');

-- CreateEnum
CREATE TYPE "SupportPriority" AS ENUM ('LOW', 'NORMAL', 'HIGH', 'URGENT');

-- CreateEnum
CREATE TYPE "NotificationKind" AS ENUM ('ORDER', 'PAYMENT', 'SHIPMENT', 'INVENTORY', 'PROMOTION', 'SUPPORT', 'SYSTEM');

-- CreateEnum
CREATE TYPE "OutboxStatus" AS ENUM ('PENDING', 'PROCESSING', 'DELIVERED', 'FAILED', 'DEAD');

-- CreateEnum
CREATE TYPE "PromotionType" AS ENUM ('PERCENTAGE', 'FIXED_PAISE', 'FREE_DELIVERY');

-- CreateEnum
CREATE TYPE "ReviewStatus" AS ENUM ('PENDING', 'PUBLISHED', 'HIDDEN', 'REJECTED');

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "clerkUserId" TEXT,
    "email" VARCHAR(320),
    "phoneE164" VARCHAR(20),
    "displayName" VARCHAR(160) NOT NULL,
    "status" "AccountStatus" NOT NULL DEFAULT 'ACTIVE',
    "deletedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminMembership" (
    "userId" UUID NOT NULL,
    "role" "AdminRole" NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "grantedById" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMPTZ(3),

    CONSTRAINT "AdminMembership_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "UserConsent" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "policyType" VARCHAR(40) NOT NULL,
    "policyVersion" VARCHAR(40) NOT NULL,
    "acceptedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" VARCHAR(80),

    CONSTRAINT "UserConsent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Supplier" (
    "id" UUID NOT NULL,
    "slug" VARCHAR(100) NOT NULL,
    "legalName" VARCHAR(250) NOT NULL,
    "displayName" VARCHAR(200) NOT NULL,
    "businessType" VARCHAR(60),
    "gstin" VARCHAR(15),
    "gstRegistration" "GstRegistrationType" NOT NULL DEFAULT 'UNVERIFIED',
    "contactEmail" VARCHAR(320),
    "contactPhone" VARCHAR(20),
    "billingAddress" JSONB,
    "approval" "ApprovalStatus" NOT NULL DEFAULT 'PENDING',
    "verifiedAt" TIMESTAMPTZ(3),
    "suspendedAt" TIMESTAMPTZ(3),
    "operatingHours" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Supplier_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierMember" (
    "supplierId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "role" "SupplierRole" NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMPTZ(3),

    CONSTRAINT "SupplierMember_pkey" PRIMARY KEY ("supplierId","userId")
);

-- CreateTable
CREATE TABLE "MediaAsset" (
    "id" UUID NOT NULL,
    "objectKey" VARCHAR(500) NOT NULL,
    "mimeType" VARCHAR(100) NOT NULL,
    "sizeBytes" BIGINT NOT NULL,
    "sha256" VARCHAR(64),
    "ownerUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MediaAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierDocument" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "mediaId" UUID NOT NULL,
    "documentType" VARCHAR(60) NOT NULL,
    "status" "DocumentStatus" NOT NULL DEFAULT 'UPLOADED',
    "reviewNote" TEXT,
    "verifiedById" UUID,
    "expiresAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "SupplierDocument_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "City" (
    "id" UUID NOT NULL,
    "code" VARCHAR(32) NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "stateCode" VARCHAR(5) NOT NULL,
    "countryCode" CHAR(2) NOT NULL DEFAULT 'IN',
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "City_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Address" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "cityId" UUID NOT NULL,
    "label" VARCHAR(120) NOT NULL,
    "recipientName" VARCHAR(160) NOT NULL,
    "phoneE164" VARCHAR(20) NOT NULL,
    "line1" VARCHAR(250) NOT NULL,
    "line2" VARCHAR(250),
    "locality" VARCHAR(120) NOT NULL,
    "postalCode" VARCHAR(6) NOT NULL,
    "latitude" DECIMAL(10,7),
    "longitude" DECIMAL(10,7),
    "geoPoint" geography(Point,4326),
    "instructions" TEXT,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "deletedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Address_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConstructionProject" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "reference" VARCHAR(100),
    "status" "ProjectStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "ConstructionProject_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConstructionSite" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "projectId" UUID,
    "addressId" UUID NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "contactName" VARCHAR(160),
    "contactPhone" VARCHAR(20),
    "accessNotes" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConstructionSite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceArea" (
    "id" UUID NOT NULL,
    "cityId" UUID NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "postalCodes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "centerLat" DECIMAL(10,7),
    "centerLng" DECIMAL(10,7),
    "radiusKm" DECIMAL(9,2),
    "geoCenter" geography(Point,4326),
    "geoBoundary" geography(MultiPolygon,4326),
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "ServiceArea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierServiceArea" (
    "supplierId" UUID NOT NULL,
    "areaId" UUID NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "minimumPaise" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "SupplierServiceArea_pkey" PRIMARY KEY ("supplierId","areaId")
);

-- CreateTable
CREATE TABLE "SupplierDeliveryRate" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "areaId" UUID NOT NULL,
    "baseFeePaise" BIGINT NOT NULL DEFAULT 0,
    "freeAbovePaise" BIGINT,
    "perKmPaise" BIGINT NOT NULL DEFAULT 0,
    "handlingFeePaise" BIGINT NOT NULL DEFAULT 0,
    "perTonneKmPaise" BIGINT NOT NULL DEFAULT 0,
    "perCubicMetreKmPaise" BIGINT NOT NULL DEFAULT 0,
    "vehicleClass" VARCHAR(70),
    "weightCapacityKg" DECIMAL(18,3),
    "volumeCapacityM3" DECIMAL(18,3),
    "active" BOOLEAN NOT NULL DEFAULT false,
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "effectiveTo" TIMESTAMPTZ(3),

    CONSTRAINT "SupplierDeliveryRate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierFreightBracket" (
    "id" UUID NOT NULL,
    "deliveryRateId" UUID NOT NULL,
    "dimension" "QuantityDimension" NOT NULL,
    "minQuantity" DECIMAL(18,3) NOT NULL,
    "maxQuantity" DECIMAL(18,3),
    "fixedFeePaise" BIGINT NOT NULL DEFAULT 0,
    "perKmPaise" BIGINT NOT NULL DEFAULT 0,
    "perTonneKmPaise" BIGINT NOT NULL DEFAULT 0,
    "perCubicMetreKmPaise" BIGINT NOT NULL DEFAULT 0,
    "vehicleClass" VARCHAR(70),
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "SupplierFreightBracket_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Category" (
    "id" UUID NOT NULL,
    "parentId" UUID,
    "slug" VARCHAR(140) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Brand" (
    "id" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(160) NOT NULL,

    CONSTRAINT "Brand_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UnitOfMeasure" (
    "code" VARCHAR(20) NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "dimension" "QuantityDimension" NOT NULL,
    "scale" INTEGER NOT NULL DEFAULT 3,
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "UnitOfMeasure_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "Product" (
    "id" UUID NOT NULL,
    "code" VARCHAR(80) NOT NULL,
    "categoryId" UUID NOT NULL,
    "brandId" UUID,
    "name" VARCHAR(240) NOT NULL,
    "description" TEXT,
    "hsnCode" VARCHAR(12),
    "specification" JSONB NOT NULL DEFAULT '{}',
    "active" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProductUnitConversion" (
    "id" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "fromUnit" VARCHAR(20) NOT NULL,
    "toUnit" VARCHAR(20) NOT NULL,
    "multiplier" DECIMAL(24,9) NOT NULL,

    CONSTRAINT "ProductUnitConversion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierListing" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "sku" VARCHAR(100) NOT NULL,
    "unitCode" VARCHAR(20) NOT NULL,
    "packSize" DECIMAL(18,3) NOT NULL DEFAULT 1,
    "minOrderQty" DECIMAL(18,3) NOT NULL DEFAULT 1,
    "stepQty" DECIMAL(18,3) NOT NULL DEFAULT 1,
    "maxOrderQty" DECIMAL(18,3),
    "unitPrice" DECIMAL(18,4) NOT NULL,
    "mrpPaise" BIGINT,
    "taxRateBps" INTEGER NOT NULL DEFAULT 0,
    "taxInclusive" BOOLEAN NOT NULL DEFAULT true,
    "status" "ListingStatus" NOT NULL DEFAULT 'DRAFT',
    "publishedAt" TIMESTAMPTZ(3),
    "active" BOOLEAN NOT NULL DEFAULT false,
    "deletedAt" TIMESTAMPTZ(3),
    "version" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "SupplierListing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierPriceTier" (
    "id" UUID NOT NULL,
    "listingId" UUID NOT NULL,
    "minQty" DECIMAL(18,3) NOT NULL,
    "pricePerUnit" DECIMAL(18,4) NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "effectiveUntil" TIMESTAMPTZ(3),

    CONSTRAINT "SupplierPriceTier_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Warehouse" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "code" VARCHAR(80) NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "address" JSONB,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Warehouse_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventoryBalance" (
    "id" UUID NOT NULL,
    "listingId" UUID NOT NULL,
    "warehouseId" UUID NOT NULL,
    "onHandQty" DECIMAL(18,3) NOT NULL DEFAULT 0,
    "reservedQty" DECIMAL(18,3) NOT NULL DEFAULT 0,
    "version" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "InventoryBalance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventoryReservation" (
    "id" UUID NOT NULL,
    "balanceId" UUID NOT NULL,
    "orderItemId" UUID NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "state" "StockReservationStatus" NOT NULL DEFAULT 'HELD',
    "expiresAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "InventoryReservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockMovement" (
    "id" UUID NOT NULL,
    "balanceId" UUID NOT NULL,
    "kind" "StockMovementType" NOT NULL,
    "delta" DECIMAL(18,3) NOT NULL,
    "referenceKey" VARCHAR(180) NOT NULL,
    "reason" TEXT,
    "actorUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StockMovement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Rfq" (
    "id" UUID NOT NULL,
    "publicNumber" VARCHAR(40) NOT NULL,
    "customerId" UUID NOT NULL,
    "projectId" UUID,
    "siteSnapshot" JSONB NOT NULL,
    "notes" TEXT,
    "status" "RfqStatus" NOT NULL DEFAULT 'DRAFT',
    "responseDueAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Rfq_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RfqItem" (
    "id" UUID NOT NULL,
    "rfqId" UUID NOT NULL,
    "productId" UUID,
    "description" TEXT NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "unitCode" VARCHAR(20) NOT NULL,
    "specification" JSONB,

    CONSTRAINT "RfqItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RfqInvitation" (
    "rfqId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "invitedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RfqInvitation_pkey" PRIMARY KEY ("rfqId","supplierId")
);

-- CreateTable
CREATE TABLE "SupplierQuote" (
    "id" UUID NOT NULL,
    "rfqId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "quoteNumber" VARCHAR(60) NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "status" "QuoteStatus" NOT NULL DEFAULT 'DRAFT',
    "deliveryTerms" TEXT,
    "validUntil" TIMESTAMPTZ(3),
    "subtotalPaise" BIGINT NOT NULL DEFAULT 0,
    "taxPaise" BIGINT NOT NULL DEFAULT 0,
    "deliveryPaise" BIGINT NOT NULL DEFAULT 0,
    "totalPaise" BIGINT NOT NULL DEFAULT 0,
    "acceptedById" UUID,
    "acceptedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "SupplierQuote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierQuoteLine" (
    "id" UUID NOT NULL,
    "quoteId" UUID NOT NULL,
    "rfqItemId" UUID NOT NULL,
    "listingId" UUID,
    "quantity" DECIMAL(18,3) NOT NULL,
    "unitCode" VARCHAR(20) NOT NULL,
    "unitPrice" DECIMAL(18,4) NOT NULL,
    "taxRateBps" INTEGER NOT NULL DEFAULT 0,
    "lineTotalPaise" BIGINT NOT NULL,

    CONSTRAINT "SupplierQuoteLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Cart" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Cart_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CartLine" (
    "id" UUID NOT NULL,
    "cartId" UUID NOT NULL,
    "listingId" UUID NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CartLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WishlistItem" (
    "customerId" UUID NOT NULL,
    "listingId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WishlistItem_pkey" PRIMARY KEY ("customerId","listingId")
);

-- CreateTable
CREATE TABLE "Promotion" (
    "id" UUID NOT NULL,
    "code" VARCHAR(60),
    "title" VARCHAR(160) NOT NULL,
    "type" "PromotionType" NOT NULL,
    "amountPaise" BIGINT,
    "percentageBps" INTEGER,
    "capPaise" BIGINT,
    "minCartPaise" BIGINT,
    "perUserLimit" INTEGER,
    "globalLimit" INTEGER,
    "startsAt" TIMESTAMPTZ(3) NOT NULL,
    "endsAt" TIMESTAMPTZ(3) NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Promotion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PromotionRedemption" (
    "id" UUID NOT NULL,
    "promotionId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "amountPaise" BIGINT NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PromotionRedemption_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CheckoutQuote" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "addressId" UUID NOT NULL,
    "siteId" UUID,
    "cartVersion" INTEGER NOT NULL,
    "cartFingerprint" VARCHAR(64) NOT NULL,
    "addressSnapshot" JSONB NOT NULL,
    "quoteSnapshot" JSONB NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "subtotalPaise" BIGINT NOT NULL,
    "discountPaise" BIGINT NOT NULL DEFAULT 0,
    "taxPaise" BIGINT NOT NULL DEFAULT 0,
    "deliveryPaise" BIGINT NOT NULL DEFAULT 0,
    "totalPaise" BIGINT NOT NULL,
    "status" "CheckoutQuoteStatus" NOT NULL DEFAULT 'OPEN',
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CheckoutQuote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PurchaseOrder" (
    "id" UUID NOT NULL,
    "publicNumber" VARCHAR(40) NOT NULL,
    "customerId" UUID NOT NULL,
    "checkoutQuoteId" UUID,
    "projectId" UUID,
    "siteId" UUID,
    "clientRequestId" VARCHAR(120) NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "status" "PurchaseOrderStatus" NOT NULL DEFAULT 'PLACED',
    "addressSnapshot" JSONB NOT NULL,
    "subtotalPaise" BIGINT NOT NULL,
    "discountPaise" BIGINT NOT NULL DEFAULT 0,
    "taxPaise" BIGINT NOT NULL DEFAULT 0,
    "deliveryPaise" BIGINT NOT NULL DEFAULT 0,
    "totalPaise" BIGINT NOT NULL,
    "placedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "cancelledAt" TIMESTAMPTZ(3),

    CONSTRAINT "PurchaseOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierOrder" (
    "id" UUID NOT NULL,
    "purchaseOrderId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "sourceQuoteId" UUID,
    "status" "SupplierOrderStatus" NOT NULL DEFAULT 'PENDING_ACCEPTANCE',
    "subtotalPaise" BIGINT NOT NULL,
    "discountPaise" BIGINT NOT NULL DEFAULT 0,
    "taxPaise" BIGINT NOT NULL DEFAULT 0,
    "deliveryPaise" BIGINT NOT NULL DEFAULT 0,
    "platformFeePaise" BIGINT NOT NULL DEFAULT 0,
    "totalPaise" BIGINT NOT NULL,
    "codRecordedPaise" BIGINT NOT NULL DEFAULT 0,
    "codVerifiedPaise" BIGINT NOT NULL DEFAULT 0,
    "acceptedAt" TIMESTAMPTZ(3),
    "cancelledAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "SupplierOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierOrderItem" (
    "id" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "listingId" UUID,
    "skuSnapshot" VARCHAR(100) NOT NULL,
    "nameSnapshot" VARCHAR(240) NOT NULL,
    "brandSnapshot" TEXT,
    "hsnSnapshot" VARCHAR(12),
    "unitCode" VARCHAR(20) NOT NULL,
    "packSizeSnapshot" DECIMAL(18,3) NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "allocatedShipmentQty" DECIMAL(18,3) NOT NULL DEFAULT 0,
    "unitPrice" DECIMAL(18,4) NOT NULL,
    "taxRateBps" INTEGER NOT NULL,
    "taxablePaise" BIGINT NOT NULL,
    "taxPaise" BIGINT NOT NULL,
    "cgstPaise" BIGINT NOT NULL DEFAULT 0,
    "sgstPaise" BIGINT NOT NULL DEFAULT 0,
    "utgstPaise" BIGINT NOT NULL DEFAULT 0,
    "igstPaise" BIGINT NOT NULL DEFAULT 0,
    "cessPaise" BIGINT NOT NULL DEFAULT 0,
    "discountPaise" BIGINT NOT NULL DEFAULT 0,
    "lineTotalPaise" BIGINT NOT NULL,
    "attributesSnapshot" JSONB,

    CONSTRAINT "SupplierOrderItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierOrderEvent" (
    "id" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "fromStatus" "SupplierOrderStatus",
    "toStatus" "SupplierOrderStatus" NOT NULL,
    "actorUserId" UUID,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupplierOrderEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Shipment" (
    "id" UUID NOT NULL,
    "shipmentNumber" VARCHAR(50) NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "warehouseId" UUID,
    "status" "ShipmentStatus" NOT NULL DEFAULT 'PLANNED',
    "carrierName" VARCHAR(160),
    "carrierPhoneE164" VARCHAR(20),
    "vehicleLabel" VARCHAR(80),
    "trackingReference" VARCHAR(100),
    "deliveryOtpHash" VARCHAR(64),
    "otpIssuedAt" TIMESTAMPTZ(3),
    "otpExpiresAt" TIMESTAMPTZ(3),
    "otpVerifiedAt" TIMESTAMPTZ(3),
    "otpAttempts" INTEGER NOT NULL DEFAULT 0,
    "otpLockedUntil" TIMESTAMPTZ(3),
    "handoverMethod" "DeliveryHandoverMethod",
    "exceptionReason" VARCHAR(500),
    "exceptionApprovedById" UUID,
    "exceptionApprovedAt" TIMESTAMPTZ(3),
    "scheduledFrom" TIMESTAMPTZ(3),
    "scheduledTo" TIMESTAMPTZ(3),
    "dispatchedAt" TIMESTAMPTZ(3),
    "deliveredAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Shipment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShipmentItem" (
    "id" UUID NOT NULL,
    "shipmentId" UUID NOT NULL,
    "supplierOrderItemId" UUID NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "deliveredQty" DECIMAL(18,3) NOT NULL DEFAULT 0,
    "rejectedQty" DECIMAL(18,3) NOT NULL DEFAULT 0,
    "returnedQty" DECIMAL(18,3) NOT NULL DEFAULT 0,

    CONSTRAINT "ShipmentItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShipmentEvent" (
    "id" UUID NOT NULL,
    "shipmentId" UUID NOT NULL,
    "fromStatus" "ShipmentStatus",
    "toStatus" "ShipmentStatus" NOT NULL,
    "actorId" UUID,
    "detail" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShipmentEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeliveryProof" (
    "id" UUID NOT NULL,
    "shipmentId" UUID NOT NULL,
    "mediaId" UUID NOT NULL,
    "type" VARCHAR(40) NOT NULL,
    "receivedBy" VARCHAR(160),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeliveryProof_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CodCollection" (
    "id" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "shipmentId" UUID,
    "receiptNumber" VARCHAR(100) NOT NULL,
    "idempotencyKey" VARCHAR(140) NOT NULL,
    "collectedPaise" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "collectedByUserId" UUID,
    "collectorName" VARCHAR(160),
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "CodCollectionStatus" NOT NULL DEFAULT 'RECORDED',
    "verifiedByUserId" UUID,
    "verifiedAt" TIMESTAMPTZ(3),
    "journalReference" VARCHAR(180),
    "note" TEXT,

    CONSTRAINT "CodCollection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierCommissionReceivable" (
    "id" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "commissionPaise" BIGINT NOT NULL,
    "offsetPaise" BIGINT NOT NULL DEFAULT 0,
    "status" "ReceivableStatus" NOT NULL DEFAULT 'OPEN',
    "journalReference" VARCHAR(180),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "SupplierCommissionReceivable_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PaymentAttempt" (
    "id" UUID NOT NULL,
    "purchaseOrderId" UUID NOT NULL,
    "provider" "PaymentProvider" NOT NULL,
    "paymentMethod" "PaymentMethod" NOT NULL,
    "providerOrderRef" VARCHAR(180),
    "providerPayRef" VARCHAR(180),
    "idempotencyKey" VARCHAR(150) NOT NULL,
    "amountPaise" BIGINT NOT NULL,
    "capturedPaise" BIGINT NOT NULL DEFAULT 0,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "status" "PaymentAttemptStatus" NOT NULL DEFAULT 'CREATED',
    "verifiedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "PaymentAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProviderWebhookEvent" (
    "id" UUID NOT NULL,
    "provider" "PaymentProvider" NOT NULL,
    "providerEventId" VARCHAR(180) NOT NULL,
    "eventType" VARCHAR(120) NOT NULL,
    "payloadHash" VARCHAR(64) NOT NULL,
    "signatureOk" BOOLEAN NOT NULL DEFAULT false,
    "processedAt" TIMESTAMPTZ(3),
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "errorCode" VARCHAR(80),

    CONSTRAINT "ProviderWebhookEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefundRequest" (
    "id" UUID NOT NULL,
    "purchaseOrderId" UUID NOT NULL,
    "paymentAttemptId" UUID NOT NULL,
    "requestKey" VARCHAR(150) NOT NULL,
    "providerRefundRef" VARCHAR(180),
    "amountPaise" BIGINT NOT NULL,
    "status" "RefundStatus" NOT NULL DEFAULT 'REQUESTED',
    "reason" VARCHAR(300) NOT NULL,
    "approvedById" UUID,
    "approvedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "RefundRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TaxInvoice" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "invoiceNumber" VARCHAR(80) NOT NULL,
    "financialYear" VARCHAR(9) NOT NULL,
    "status" "InvoiceStatus" NOT NULL DEFAULT 'ISSUED',
    "kind" "InvoiceKind" NOT NULL DEFAULT 'TAX_INVOICE',
    "sellerSnapshot" JSONB NOT NULL,
    "buyerSnapshot" JSONB NOT NULL,
    "lineSnapshot" JSONB NOT NULL,
    "taxablePaise" BIGINT NOT NULL,
    "taxPaise" BIGINT NOT NULL,
    "cgstPaise" BIGINT NOT NULL DEFAULT 0,
    "sgstPaise" BIGINT NOT NULL DEFAULT 0,
    "utgstPaise" BIGINT NOT NULL DEFAULT 0,
    "igstPaise" BIGINT NOT NULL DEFAULT 0,
    "cessPaise" BIGINT NOT NULL DEFAULT 0,
    "totalPaise" BIGINT NOT NULL,
    "issuedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "cancelledAt" TIMESTAMPTZ(3),

    CONSTRAINT "TaxInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupplierPayoutAccount" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "providerTokenRef" VARCHAR(200),
    "bankAccountLast4" CHAR(4),
    "accountHolder" VARCHAR(160),
    "ifsc" VARCHAR(11),
    "upiIdEnc" TEXT,
    "verifiedAt" TIMESTAMPTZ(3),
    "active" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupplierPayoutAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Settlement" (
    "id" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "settlementKey" VARCHAR(100) NOT NULL,
    "periodStart" TIMESTAMPTZ(3) NOT NULL,
    "periodEnd" TIMESTAMPTZ(3) NOT NULL,
    "status" "SettlementStatus" NOT NULL DEFAULT 'OPEN',
    "grossPaise" BIGINT NOT NULL,
    "commissionPaise" BIGINT NOT NULL,
    "refundPaise" BIGINT NOT NULL DEFAULT 0,
    "adjustmentPaise" BIGINT NOT NULL DEFAULT 0,
    "payablePaise" BIGINT NOT NULL,
    "approvedById" UUID,
    "paidAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Settlement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SettlementLine" (
    "id" UUID NOT NULL,
    "settlementId" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "grossPaise" BIGINT NOT NULL,
    "commissionPaise" BIGINT NOT NULL,
    "refundPaise" BIGINT NOT NULL DEFAULT 0,
    "adjustmentPaise" BIGINT NOT NULL DEFAULT 0,
    "netPaise" BIGINT NOT NULL,

    CONSTRAINT "SettlementLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayoutTransfer" (
    "id" UUID NOT NULL,
    "settlementId" UUID NOT NULL,
    "payoutAccountId" UUID NOT NULL,
    "requestKey" VARCHAR(150) NOT NULL,
    "providerRef" VARCHAR(180),
    "amountPaise" BIGINT NOT NULL,
    "status" "PayoutStatus" NOT NULL DEFAULT 'PENDING',
    "failureCode" VARCHAR(100),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMPTZ(3),

    CONSTRAINT "PayoutTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LedgerJournal" (
    "id" UUID NOT NULL,
    "referenceKey" VARCHAR(180) NOT NULL,
    "eventType" VARCHAR(80) NOT NULL,
    "occurredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "postedAt" TIMESTAMPTZ(3),

    CONSTRAINT "LedgerJournal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LedgerAccount" (
    "id" UUID NOT NULL,
    "code" VARCHAR(80) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "LedgerAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LedgerLine" (
    "journalId" UUID NOT NULL,
    "lineNumber" INTEGER NOT NULL,
    "accountId" UUID NOT NULL,
    "debitPaise" BIGINT NOT NULL DEFAULT 0,
    "creditPaise" BIGINT NOT NULL DEFAULT 0,
    "memo" TEXT,

    CONSTRAINT "LedgerLine_pkey" PRIMARY KEY ("journalId","lineNumber")
);

-- CreateTable
CREATE TABLE "ReturnRequest" (
    "id" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "reason" VARCHAR(300) NOT NULL,
    "status" "ReturnStatus" NOT NULL DEFAULT 'REQUESTED',
    "resolutionNote" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "ReturnRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReturnItem" (
    "id" UUID NOT NULL,
    "returnId" UUID NOT NULL,
    "supplierOrderItemId" UUID NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,

    CONSTRAINT "ReturnItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReturnEvidence" (
    "id" UUID NOT NULL,
    "returnId" UUID NOT NULL,
    "mediaId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReturnEvidence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Review" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "supplierOrderId" UUID NOT NULL,
    "supplierId" UUID NOT NULL,
    "rating" INTEGER NOT NULL,
    "comment" TEXT,
    "status" "ReviewStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Review_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupportCase" (
    "id" UUID NOT NULL,
    "publicNumber" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "purchaseOrderId" UUID,
    "subject" VARCHAR(250) NOT NULL,
    "priority" "SupportPriority" NOT NULL DEFAULT 'NORMAL',
    "status" "SupportStatus" NOT NULL DEFAULT 'OPEN',
    "assigneeId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMPTZ(3),

    CONSTRAINT "SupportCase_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupportMessage" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "authorId" UUID NOT NULL,
    "body" TEXT NOT NULL,
    "internal" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupportMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Notification" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "kind" "NotificationKind" NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "body" TEXT NOT NULL,
    "deepLink" TEXT,
    "payload" JSONB,
    "readAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeviceRegistration" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "fcmTokenHash" VARCHAR(64) NOT NULL,
    "fcmTokenEnc" TEXT NOT NULL,
    "app" VARCHAR(30) NOT NULL,
    "platform" VARCHAR(30) NOT NULL,
    "disabledAt" TIMESTAMPTZ(3),
    "lastSeenAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeviceRegistration_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ContentPage" (
    "id" UUID NOT NULL,
    "slug" VARCHAR(120) NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "body" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "published" BOOLEAN NOT NULL DEFAULT false,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "ContentPage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HomeBanner" (
    "id" UUID NOT NULL,
    "title" VARCHAR(160) NOT NULL,
    "imageKey" VARCHAR(500) NOT NULL,
    "destination" TEXT,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "startsAt" TIMESTAMPTZ(3),
    "endsAt" TIMESTAMPTZ(3),

    CONSTRAINT "HomeBanner_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppSetting" (
    "key" VARCHAR(150) NOT NULL,
    "value" JSONB NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "updatedBy" UUID,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "AppSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "IdempotencyRecord" (
    "id" UUID NOT NULL,
    "actorId" UUID NOT NULL,
    "scope" VARCHAR(100) NOT NULL,
    "requestKey" VARCHAR(180) NOT NULL,
    "requestHash" VARCHAR(64) NOT NULL,
    "resultRef" VARCHAR(180),
    "responseCode" INTEGER,
    "responseHash" VARCHAR(64),
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IdempotencyRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" UUID NOT NULL,
    "actorUserId" UUID,
    "actorSupplierId" UUID,
    "actorRole" VARCHAR(60),
    "action" VARCHAR(120) NOT NULL,
    "entityType" VARCHAR(100) NOT NULL,
    "entityId" VARCHAR(100) NOT NULL,
    "requestId" VARCHAR(140),
    "ipHash" VARCHAR(64),
    "beforeState" JSONB,
    "afterState" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OutboxEvent" (
    "id" UUID NOT NULL,
    "eventKey" VARCHAR(180) NOT NULL,
    "aggregateType" VARCHAR(90) NOT NULL,
    "aggregateId" VARCHAR(100) NOT NULL,
    "eventType" VARCHAR(120) NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "OutboxStatus" NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMPTZ(3),
    "leaseUntil" TIMESTAMPTZ(3),
    "lastErrorCode" VARCHAR(120),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deliveredAt" TIMESTAMPTZ(3),

    CONSTRAINT "OutboxEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_clerkUserId_key" ON "User"("clerkUserId");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_phoneE164_key" ON "User"("phoneE164");

-- CreateIndex
CREATE INDEX "User_status_createdAt_idx" ON "User"("status", "createdAt");

-- CreateIndex
CREATE INDEX "AdminMembership_role_active_idx" ON "AdminMembership"("role", "active");

-- CreateIndex
CREATE UNIQUE INDEX "UserConsent_userId_policyType_policyVersion_key" ON "UserConsent"("userId", "policyType", "policyVersion");

-- CreateIndex
CREATE UNIQUE INDEX "Supplier_slug_key" ON "Supplier"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "Supplier_gstin_key" ON "Supplier"("gstin");

-- CreateIndex
CREATE INDEX "Supplier_approval_createdAt_idx" ON "Supplier"("approval", "createdAt");

-- CreateIndex
CREATE INDEX "SupplierMember_userId_active_idx" ON "SupplierMember"("userId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "MediaAsset_objectKey_key" ON "MediaAsset"("objectKey");

-- CreateIndex
CREATE INDEX "SupplierDocument_supplierId_documentType_status_idx" ON "SupplierDocument"("supplierId", "documentType", "status");

-- CreateIndex
CREATE UNIQUE INDEX "City_code_key" ON "City"("code");

-- CreateIndex
CREATE INDEX "City_stateCode_active_idx" ON "City"("stateCode", "active");

-- CreateIndex
CREATE INDEX "Address_userId_deletedAt_createdAt_idx" ON "Address"("userId", "deletedAt", "createdAt");

-- CreateIndex
CREATE INDEX "Address_cityId_postalCode_idx" ON "Address"("cityId", "postalCode");

-- CreateIndex
CREATE INDEX "ConstructionProject_customerId_status_idx" ON "ConstructionProject"("customerId", "status");

-- CreateIndex
CREATE INDEX "ConstructionSite_customerId_active_idx" ON "ConstructionSite"("customerId", "active");

-- CreateIndex
CREATE INDEX "ConstructionSite_projectId_idx" ON "ConstructionSite"("projectId");

-- CreateIndex
CREATE INDEX "ServiceArea_cityId_active_idx" ON "ServiceArea"("cityId", "active");

-- CreateIndex
CREATE INDEX "SupplierServiceArea_areaId_active_idx" ON "SupplierServiceArea"("areaId", "active");

-- CreateIndex
CREATE INDEX "SupplierDeliveryRate_supplierId_areaId_active_idx" ON "SupplierDeliveryRate"("supplierId", "areaId", "active");

-- CreateIndex
CREATE INDEX "SupplierFreightBracket_deliveryRateId_dimension_active_idx" ON "SupplierFreightBracket"("deliveryRateId", "dimension", "active");

-- CreateIndex
CREATE UNIQUE INDEX "Category_slug_key" ON "Category"("slug");

-- CreateIndex
CREATE INDEX "Category_parentId_active_displayOrder_idx" ON "Category"("parentId", "active", "displayOrder");

-- CreateIndex
CREATE UNIQUE INDEX "Brand_slug_key" ON "Brand"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "Product_code_key" ON "Product"("code");

-- CreateIndex
CREATE INDEX "Product_categoryId_active_idx" ON "Product"("categoryId", "active");

-- CreateIndex
CREATE INDEX "Product_brandId_active_idx" ON "Product"("brandId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "ProductUnitConversion_productId_fromUnit_toUnit_key" ON "ProductUnitConversion"("productId", "fromUnit", "toUnit");

-- CreateIndex
CREATE INDEX "SupplierListing_productId_status_active_idx" ON "SupplierListing"("productId", "status", "active");

-- CreateIndex
CREATE INDEX "SupplierListing_supplierId_status_idx" ON "SupplierListing"("supplierId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierListing_supplierId_sku_key" ON "SupplierListing"("supplierId", "sku");

-- CreateIndex
CREATE INDEX "SupplierPriceTier_listingId_active_idx" ON "SupplierPriceTier"("listingId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierPriceTier_listingId_minQty_effectiveFrom_key" ON "SupplierPriceTier"("listingId", "minQty", "effectiveFrom");

-- CreateIndex
CREATE UNIQUE INDEX "Warehouse_supplierId_code_key" ON "Warehouse"("supplierId", "code");

-- CreateIndex
CREATE INDEX "InventoryBalance_warehouseId_idx" ON "InventoryBalance"("warehouseId");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryBalance_listingId_warehouseId_key" ON "InventoryBalance"("listingId", "warehouseId");

-- CreateIndex
CREATE INDEX "InventoryReservation_state_expiresAt_idx" ON "InventoryReservation"("state", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryReservation_orderItemId_balanceId_key" ON "InventoryReservation"("orderItemId", "balanceId");

-- CreateIndex
CREATE UNIQUE INDEX "StockMovement_referenceKey_key" ON "StockMovement"("referenceKey");

-- CreateIndex
CREATE INDEX "StockMovement_balanceId_createdAt_idx" ON "StockMovement"("balanceId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Rfq_publicNumber_key" ON "Rfq"("publicNumber");

-- CreateIndex
CREATE INDEX "Rfq_customerId_status_createdAt_idx" ON "Rfq"("customerId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "Rfq_status_responseDueAt_idx" ON "Rfq"("status", "responseDueAt");

-- CreateIndex
CREATE INDEX "RfqItem_rfqId_idx" ON "RfqItem"("rfqId");

-- CreateIndex
CREATE INDEX "SupplierQuote_rfqId_status_idx" ON "SupplierQuote"("rfqId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierQuote_supplierId_quoteNumber_version_key" ON "SupplierQuote"("supplierId", "quoteNumber", "version");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierQuoteLine_quoteId_rfqItemId_key" ON "SupplierQuoteLine"("quoteId", "rfqItemId");

-- CreateIndex
CREATE UNIQUE INDEX "Cart_customerId_key" ON "Cart"("customerId");

-- CreateIndex
CREATE UNIQUE INDEX "CartLine_cartId_listingId_key" ON "CartLine"("cartId", "listingId");

-- CreateIndex
CREATE UNIQUE INDEX "Promotion_code_key" ON "Promotion"("code");

-- CreateIndex
CREATE INDEX "Promotion_active_startsAt_endsAt_idx" ON "Promotion"("active", "startsAt", "endsAt");

-- CreateIndex
CREATE UNIQUE INDEX "PromotionRedemption_orderId_key" ON "PromotionRedemption"("orderId");

-- CreateIndex
CREATE INDEX "PromotionRedemption_promotionId_customerId_idx" ON "PromotionRedemption"("promotionId", "customerId");

-- CreateIndex
CREATE INDEX "CheckoutQuote_customerId_status_expiresAt_idx" ON "CheckoutQuote"("customerId", "status", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseOrder_publicNumber_key" ON "PurchaseOrder"("publicNumber");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseOrder_checkoutQuoteId_key" ON "PurchaseOrder"("checkoutQuoteId");

-- CreateIndex
CREATE INDEX "PurchaseOrder_customerId_placedAt_idx" ON "PurchaseOrder"("customerId", "placedAt");

-- CreateIndex
CREATE INDEX "PurchaseOrder_status_placedAt_idx" ON "PurchaseOrder"("status", "placedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseOrder_customerId_clientRequestId_key" ON "PurchaseOrder"("customerId", "clientRequestId");

-- CreateIndex
CREATE INDEX "SupplierOrder_supplierId_status_createdAt_idx" ON "SupplierOrder"("supplierId", "status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierOrder_purchaseOrderId_supplierId_key" ON "SupplierOrder"("purchaseOrderId", "supplierId");

-- CreateIndex
CREATE INDEX "SupplierOrderItem_supplierOrderId_idx" ON "SupplierOrderItem"("supplierOrderId");

-- CreateIndex
CREATE INDEX "SupplierOrderItem_listingId_idx" ON "SupplierOrderItem"("listingId");

-- CreateIndex
CREATE INDEX "SupplierOrderEvent_supplierOrderId_createdAt_idx" ON "SupplierOrderEvent"("supplierOrderId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Shipment_shipmentNumber_key" ON "Shipment"("shipmentNumber");

-- CreateIndex
CREATE INDEX "Shipment_supplierOrderId_status_idx" ON "Shipment"("supplierOrderId", "status");

-- CreateIndex
CREATE INDEX "Shipment_supplierId_status_createdAt_idx" ON "Shipment"("supplierId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ShipmentItem_supplierOrderItemId_idx" ON "ShipmentItem"("supplierOrderItemId");

-- CreateIndex
CREATE UNIQUE INDEX "ShipmentItem_shipmentId_supplierOrderItemId_key" ON "ShipmentItem"("shipmentId", "supplierOrderItemId");

-- CreateIndex
CREATE INDEX "ShipmentEvent_shipmentId_createdAt_idx" ON "ShipmentEvent"("shipmentId", "createdAt");

-- CreateIndex
CREATE INDEX "DeliveryProof_shipmentId_idx" ON "DeliveryProof"("shipmentId");

-- CreateIndex
CREATE UNIQUE INDEX "CodCollection_receiptNumber_key" ON "CodCollection"("receiptNumber");

-- CreateIndex
CREATE UNIQUE INDEX "CodCollection_journalReference_key" ON "CodCollection"("journalReference");

-- CreateIndex
CREATE INDEX "CodCollection_supplierId_status_receivedAt_idx" ON "CodCollection"("supplierId", "status", "receivedAt");

-- CreateIndex
CREATE INDEX "CodCollection_supplierOrderId_status_idx" ON "CodCollection"("supplierOrderId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "CodCollection_supplierOrderId_idempotencyKey_key" ON "CodCollection"("supplierOrderId", "idempotencyKey");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierCommissionReceivable_supplierOrderId_key" ON "SupplierCommissionReceivable"("supplierOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "SupplierCommissionReceivable_journalReference_key" ON "SupplierCommissionReceivable"("journalReference");

-- CreateIndex
CREATE INDEX "SupplierCommissionReceivable_supplierId_status_idx" ON "SupplierCommissionReceivable"("supplierId", "status");

-- CreateIndex
CREATE INDEX "PaymentAttempt_purchaseOrderId_status_idx" ON "PaymentAttempt"("purchaseOrderId", "status");

-- CreateIndex
CREATE INDEX "PaymentAttempt_status_createdAt_idx" ON "PaymentAttempt"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_purchaseOrderId_idempotencyKey_key" ON "PaymentAttempt"("purchaseOrderId", "idempotencyKey");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_provider_providerOrderRef_key" ON "PaymentAttempt"("provider", "providerOrderRef");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_provider_providerPayRef_key" ON "PaymentAttempt"("provider", "providerPayRef");

-- CreateIndex
CREATE INDEX "ProviderWebhookEvent_processedAt_receivedAt_idx" ON "ProviderWebhookEvent"("processedAt", "receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "ProviderWebhookEvent_provider_providerEventId_key" ON "ProviderWebhookEvent"("provider", "providerEventId");

-- CreateIndex
CREATE UNIQUE INDEX "RefundRequest_providerRefundRef_key" ON "RefundRequest"("providerRefundRef");

-- CreateIndex
CREATE INDEX "RefundRequest_status_createdAt_idx" ON "RefundRequest"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "RefundRequest_purchaseOrderId_requestKey_key" ON "RefundRequest"("purchaseOrderId", "requestKey");

-- CreateIndex
CREATE INDEX "TaxInvoice_supplierOrderId_status_idx" ON "TaxInvoice"("supplierOrderId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "TaxInvoice_supplierId_financialYear_invoiceNumber_key" ON "TaxInvoice"("supplierId", "financialYear", "invoiceNumber");

-- CreateIndex
CREATE INDEX "SupplierPayoutAccount_supplierId_active_idx" ON "SupplierPayoutAccount"("supplierId", "active");

-- CreateIndex
CREATE INDEX "Settlement_status_periodEnd_idx" ON "Settlement"("status", "periodEnd");

-- CreateIndex
CREATE UNIQUE INDEX "Settlement_supplierId_settlementKey_key" ON "Settlement"("supplierId", "settlementKey");

-- CreateIndex
CREATE INDEX "SettlementLine_supplierOrderId_idx" ON "SettlementLine"("supplierOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "SettlementLine_settlementId_supplierOrderId_key" ON "SettlementLine"("settlementId", "supplierOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "PayoutTransfer_providerRef_key" ON "PayoutTransfer"("providerRef");

-- CreateIndex
CREATE INDEX "PayoutTransfer_status_createdAt_idx" ON "PayoutTransfer"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "PayoutTransfer_settlementId_requestKey_key" ON "PayoutTransfer"("settlementId", "requestKey");

-- CreateIndex
CREATE UNIQUE INDEX "LedgerJournal_referenceKey_key" ON "LedgerJournal"("referenceKey");

-- CreateIndex
CREATE UNIQUE INDEX "LedgerAccount_code_key" ON "LedgerAccount"("code");

-- CreateIndex
CREATE INDEX "LedgerLine_accountId_idx" ON "LedgerLine"("accountId");

-- CreateIndex
CREATE INDEX "ReturnRequest_supplierOrderId_status_idx" ON "ReturnRequest"("supplierOrderId", "status");

-- CreateIndex
CREATE INDEX "ReturnRequest_customerId_createdAt_idx" ON "ReturnRequest"("customerId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ReturnItem_returnId_supplierOrderItemId_key" ON "ReturnItem"("returnId", "supplierOrderItemId");

-- CreateIndex
CREATE UNIQUE INDEX "Review_supplierOrderId_key" ON "Review"("supplierOrderId");

-- CreateIndex
CREATE INDEX "Review_supplierId_status_createdAt_idx" ON "Review"("supplierId", "status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "SupportCase_publicNumber_key" ON "SupportCase"("publicNumber");

-- CreateIndex
CREATE INDEX "SupportCase_status_priority_createdAt_idx" ON "SupportCase"("status", "priority", "createdAt");

-- CreateIndex
CREATE INDEX "SupportCase_customerId_createdAt_idx" ON "SupportCase"("customerId", "createdAt");

-- CreateIndex
CREATE INDEX "SupportMessage_caseId_createdAt_idx" ON "SupportMessage"("caseId", "createdAt");

-- CreateIndex
CREATE INDEX "Notification_userId_createdAt_idx" ON "Notification"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "Notification_userId_readAt_idx" ON "Notification"("userId", "readAt");

-- CreateIndex
CREATE UNIQUE INDEX "DeviceRegistration_fcmTokenHash_key" ON "DeviceRegistration"("fcmTokenHash");

-- CreateIndex
CREATE INDEX "DeviceRegistration_userId_disabledAt_idx" ON "DeviceRegistration"("userId", "disabledAt");

-- CreateIndex
CREATE UNIQUE INDEX "ContentPage_slug_key" ON "ContentPage"("slug");

-- CreateIndex
CREATE INDEX "HomeBanner_active_displayOrder_idx" ON "HomeBanner"("active", "displayOrder");

-- CreateIndex
CREATE INDEX "IdempotencyRecord_expiresAt_idx" ON "IdempotencyRecord"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "IdempotencyRecord_actorId_scope_requestKey_key" ON "IdempotencyRecord"("actorId", "scope", "requestKey");

-- CreateIndex
CREATE INDEX "AuditEvent_entityType_entityId_createdAt_idx" ON "AuditEvent"("entityType", "entityId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditEvent_actorUserId_createdAt_idx" ON "AuditEvent"("actorUserId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "OutboxEvent_eventKey_key" ON "OutboxEvent"("eventKey");

-- CreateIndex
CREATE INDEX "OutboxEvent_status_nextAttemptAt_idx" ON "OutboxEvent"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "OutboxEvent_aggregateType_aggregateId_createdAt_idx" ON "OutboxEvent"("aggregateType", "aggregateId", "createdAt");

-- AddForeignKey
ALTER TABLE "AdminMembership" ADD CONSTRAINT "AdminMembership_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserConsent" ADD CONSTRAINT "UserConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierMember" ADD CONSTRAINT "SupplierMember_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierMember" ADD CONSTRAINT "SupplierMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierDocument" ADD CONSTRAINT "SupplierDocument_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierDocument" ADD CONSTRAINT "SupplierDocument_mediaId_fkey" FOREIGN KEY ("mediaId") REFERENCES "MediaAsset"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Address" ADD CONSTRAINT "Address_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Address" ADD CONSTRAINT "Address_cityId_fkey" FOREIGN KEY ("cityId") REFERENCES "City"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConstructionProject" ADD CONSTRAINT "ConstructionProject_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConstructionSite" ADD CONSTRAINT "ConstructionSite_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConstructionSite" ADD CONSTRAINT "ConstructionSite_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "ConstructionProject"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConstructionSite" ADD CONSTRAINT "ConstructionSite_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "Address"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceArea" ADD CONSTRAINT "ServiceArea_cityId_fkey" FOREIGN KEY ("cityId") REFERENCES "City"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierServiceArea" ADD CONSTRAINT "SupplierServiceArea_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierServiceArea" ADD CONSTRAINT "SupplierServiceArea_areaId_fkey" FOREIGN KEY ("areaId") REFERENCES "ServiceArea"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierDeliveryRate" ADD CONSTRAINT "SupplierDeliveryRate_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierDeliveryRate" ADD CONSTRAINT "SupplierDeliveryRate_areaId_fkey" FOREIGN KEY ("areaId") REFERENCES "ServiceArea"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierFreightBracket" ADD CONSTRAINT "SupplierFreightBracket_deliveryRateId_fkey" FOREIGN KEY ("deliveryRateId") REFERENCES "SupplierDeliveryRate"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Category" ADD CONSTRAINT "Category_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "Category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES "Brand"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductUnitConversion" ADD CONSTRAINT "ProductUnitConversion_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductUnitConversion" ADD CONSTRAINT "ProductUnitConversion_fromUnit_fkey" FOREIGN KEY ("fromUnit") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductUnitConversion" ADD CONSTRAINT "ProductUnitConversion_toUnit_fkey" FOREIGN KEY ("toUnit") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierListing" ADD CONSTRAINT "SupplierListing_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierListing" ADD CONSTRAINT "SupplierListing_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierListing" ADD CONSTRAINT "SupplierListing_unitCode_fkey" FOREIGN KEY ("unitCode") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierPriceTier" ADD CONSTRAINT "SupplierPriceTier_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Warehouse" ADD CONSTRAINT "Warehouse_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryBalance" ADD CONSTRAINT "InventoryBalance_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryBalance" ADD CONSTRAINT "InventoryBalance_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "Warehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryReservation" ADD CONSTRAINT "InventoryReservation_balanceId_fkey" FOREIGN KEY ("balanceId") REFERENCES "InventoryBalance"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryReservation" ADD CONSTRAINT "InventoryReservation_orderItemId_fkey" FOREIGN KEY ("orderItemId") REFERENCES "SupplierOrderItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockMovement" ADD CONSTRAINT "StockMovement_balanceId_fkey" FOREIGN KEY ("balanceId") REFERENCES "InventoryBalance"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Rfq" ADD CONSTRAINT "Rfq_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Rfq" ADD CONSTRAINT "Rfq_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "ConstructionProject"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RfqItem" ADD CONSTRAINT "RfqItem_rfqId_fkey" FOREIGN KEY ("rfqId") REFERENCES "Rfq"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RfqItem" ADD CONSTRAINT "RfqItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RfqItem" ADD CONSTRAINT "RfqItem_unitCode_fkey" FOREIGN KEY ("unitCode") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RfqInvitation" ADD CONSTRAINT "RfqInvitation_rfqId_fkey" FOREIGN KEY ("rfqId") REFERENCES "Rfq"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RfqInvitation" ADD CONSTRAINT "RfqInvitation_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuote" ADD CONSTRAINT "SupplierQuote_rfqId_fkey" FOREIGN KEY ("rfqId") REFERENCES "Rfq"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuote" ADD CONSTRAINT "SupplierQuote_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuote" ADD CONSTRAINT "SupplierQuote_acceptedById_fkey" FOREIGN KEY ("acceptedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuoteLine" ADD CONSTRAINT "SupplierQuoteLine_quoteId_fkey" FOREIGN KEY ("quoteId") REFERENCES "SupplierQuote"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuoteLine" ADD CONSTRAINT "SupplierQuoteLine_rfqItemId_fkey" FOREIGN KEY ("rfqItemId") REFERENCES "RfqItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuoteLine" ADD CONSTRAINT "SupplierQuoteLine_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierQuoteLine" ADD CONSTRAINT "SupplierQuoteLine_unitCode_fkey" FOREIGN KEY ("unitCode") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cart" ADD CONSTRAINT "Cart_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartLine" ADD CONSTRAINT "CartLine_cartId_fkey" FOREIGN KEY ("cartId") REFERENCES "Cart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartLine" ADD CONSTRAINT "CartLine_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WishlistItem" ADD CONSTRAINT "WishlistItem_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WishlistItem" ADD CONSTRAINT "WishlistItem_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromotionRedemption" ADD CONSTRAINT "PromotionRedemption_promotionId_fkey" FOREIGN KEY ("promotionId") REFERENCES "Promotion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromotionRedemption" ADD CONSTRAINT "PromotionRedemption_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromotionRedemption" ADD CONSTRAINT "PromotionRedemption_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "PurchaseOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CheckoutQuote" ADD CONSTRAINT "CheckoutQuote_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CheckoutQuote" ADD CONSTRAINT "CheckoutQuote_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "Address"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CheckoutQuote" ADD CONSTRAINT "CheckoutQuote_siteId_fkey" FOREIGN KEY ("siteId") REFERENCES "ConstructionSite"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseOrder" ADD CONSTRAINT "PurchaseOrder_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseOrder" ADD CONSTRAINT "PurchaseOrder_checkoutQuoteId_fkey" FOREIGN KEY ("checkoutQuoteId") REFERENCES "CheckoutQuote"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseOrder" ADD CONSTRAINT "PurchaseOrder_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "ConstructionProject"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseOrder" ADD CONSTRAINT "PurchaseOrder_siteId_fkey" FOREIGN KEY ("siteId") REFERENCES "ConstructionSite"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "SupplierOrder_purchaseOrderId_fkey" FOREIGN KEY ("purchaseOrderId") REFERENCES "PurchaseOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "SupplierOrder_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "SupplierOrder_sourceQuoteId_fkey" FOREIGN KEY ("sourceQuoteId") REFERENCES "SupplierQuote"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "SupplierOrderItem_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "SupplierOrderItem_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "SupplierListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "SupplierOrderItem_unitCode_fkey" FOREIGN KEY ("unitCode") REFERENCES "UnitOfMeasure"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierOrderEvent" ADD CONSTRAINT "SupplierOrderEvent_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Shipment" ADD CONSTRAINT "Shipment_exceptionApprovedById_fkey" FOREIGN KEY ("exceptionApprovedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Shipment" ADD CONSTRAINT "Shipment_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Shipment" ADD CONSTRAINT "Shipment_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Shipment" ADD CONSTRAINT "Shipment_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "Warehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipmentItem" ADD CONSTRAINT "ShipmentItem_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "Shipment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipmentItem" ADD CONSTRAINT "ShipmentItem_supplierOrderItemId_fkey" FOREIGN KEY ("supplierOrderItemId") REFERENCES "SupplierOrderItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipmentEvent" ADD CONSTRAINT "ShipmentEvent_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "Shipment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryProof" ADD CONSTRAINT "DeliveryProof_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "Shipment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryProof" ADD CONSTRAINT "DeliveryProof_mediaId_fkey" FOREIGN KEY ("mediaId") REFERENCES "MediaAsset"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CodCollection" ADD CONSTRAINT "CodCollection_collectedByUserId_fkey" FOREIGN KEY ("collectedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CodCollection" ADD CONSTRAINT "CodCollection_verifiedByUserId_fkey" FOREIGN KEY ("verifiedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CodCollection" ADD CONSTRAINT "CodCollection_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CodCollection" ADD CONSTRAINT "CodCollection_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CodCollection" ADD CONSTRAINT "CodCollection_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "Shipment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierCommissionReceivable" ADD CONSTRAINT "SupplierCommissionReceivable_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierCommissionReceivable" ADD CONSTRAINT "SupplierCommissionReceivable_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PaymentAttempt" ADD CONSTRAINT "PaymentAttempt_purchaseOrderId_fkey" FOREIGN KEY ("purchaseOrderId") REFERENCES "PurchaseOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundRequest" ADD CONSTRAINT "RefundRequest_purchaseOrderId_fkey" FOREIGN KEY ("purchaseOrderId") REFERENCES "PurchaseOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundRequest" ADD CONSTRAINT "RefundRequest_paymentAttemptId_fkey" FOREIGN KEY ("paymentAttemptId") REFERENCES "PaymentAttempt"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "TaxInvoice_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "TaxInvoice_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupplierPayoutAccount" ADD CONSTRAINT "SupplierPayoutAccount_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Settlement" ADD CONSTRAINT "Settlement_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SettlementLine" ADD CONSTRAINT "SettlementLine_settlementId_fkey" FOREIGN KEY ("settlementId") REFERENCES "Settlement"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SettlementLine" ADD CONSTRAINT "SettlementLine_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayoutTransfer" ADD CONSTRAINT "PayoutTransfer_settlementId_fkey" FOREIGN KEY ("settlementId") REFERENCES "Settlement"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayoutTransfer" ADD CONSTRAINT "PayoutTransfer_payoutAccountId_fkey" FOREIGN KEY ("payoutAccountId") REFERENCES "SupplierPayoutAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LedgerLine" ADD CONSTRAINT "LedgerLine_journalId_fkey" FOREIGN KEY ("journalId") REFERENCES "LedgerJournal"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LedgerLine" ADD CONSTRAINT "LedgerLine_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "LedgerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnRequest" ADD CONSTRAINT "ReturnRequest_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnRequest" ADD CONSTRAINT "ReturnRequest_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnItem" ADD CONSTRAINT "ReturnItem_returnId_fkey" FOREIGN KEY ("returnId") REFERENCES "ReturnRequest"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnItem" ADD CONSTRAINT "ReturnItem_supplierOrderItemId_fkey" FOREIGN KEY ("supplierOrderItemId") REFERENCES "SupplierOrderItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnEvidence" ADD CONSTRAINT "ReturnEvidence_returnId_fkey" FOREIGN KEY ("returnId") REFERENCES "ReturnRequest"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnEvidence" ADD CONSTRAINT "ReturnEvidence_mediaId_fkey" FOREIGN KEY ("mediaId") REFERENCES "MediaAsset"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_supplierOrderId_fkey" FOREIGN KEY ("supplierOrderId") REFERENCES "SupplierOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupportCase" ADD CONSTRAINT "SupportCase_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupportCase" ADD CONSTRAINT "SupportCase_purchaseOrderId_fkey" FOREIGN KEY ("purchaseOrderId") REFERENCES "PurchaseOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "SupportCase"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceRegistration" ADD CONSTRAINT "DeviceRegistration_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- SQL-only integrity guards (Prisma 5.22 cannot represent these in schema.prisma).
-- BUILDTO V2 POSTGRESQL INTEGRITY GUARDS — FOR GREENFIELD V2 SCHEMA ONLY.
-- Generated Prisma DDL must be applied before this file. Do not run on the current legacy DB.
-- Prisma does not model CHECK constraints, partial indexes or triggers in schema.prisma.
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE "Supplier" ADD CONSTRAINT "supplier_gstin_format" CHECK ("gstin" IS NULL OR "gstin" ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$');
ALTER TABLE "Address" ADD CONSTRAINT "address_indian_pincode" CHECK ("postalCode" ~ '^[1-9][0-9]{5}$');
ALTER TABLE "Address" ADD CONSTRAINT "address_coordinate_pair" CHECK (("latitude" IS NULL AND "longitude" IS NULL) OR ("latitude" BETWEEN 6 AND 38 AND "longitude" BETWEEN 68 AND 98));
ALTER TABLE "ServiceArea" ADD CONSTRAINT "service_area_radius" CHECK ("radiusKm" IS NULL OR ("radiusKm" > 0 AND "radiusKm" <= 500));
ALTER TABLE "ServiceArea" ADD CONSTRAINT "service_area_coordinates" CHECK (("centerLat" IS NULL AND "centerLng" IS NULL) OR ("centerLat" BETWEEN 6 AND 38 AND "centerLng" BETWEEN 68 AND 98));
ALTER TABLE "UnitOfMeasure" ADD CONSTRAINT "unit_scale_valid" CHECK ("scale" BETWEEN 0 AND 6);
ALTER TABLE "ProductUnitConversion" ADD CONSTRAINT "conversion_multiplier_positive" CHECK ("multiplier" > 0 AND "fromUnit" <> "toUnit");
ALTER TABLE "SupplierListing" ADD CONSTRAINT "listing_qty_price_valid" CHECK (
 "packSize" > 0 AND "minOrderQty" > 0 AND "stepQty" > 0 AND ("maxOrderQty" IS NULL OR "maxOrderQty" >= "minOrderQty")
 AND "unitPrice" >= 0 AND ("mrpPaise" IS NULL OR "mrpPaise" >= 0) AND "taxRateBps" BETWEEN 0 AND 10000 AND "version" >= 0
);
ALTER TABLE "SupplierPriceTier" ADD CONSTRAINT "price_tier_valid" CHECK ("minQty" > 0 AND "pricePerUnit" >= 0 AND ("effectiveUntil" IS NULL OR "effectiveUntil" > "effectiveFrom"));
ALTER TABLE "SupplierDeliveryRate" ADD CONSTRAINT "delivery_price_valid" CHECK ("baseFeePaise" >= 0 AND "perKmPaise" >= 0 AND "handlingFeePaise" >= 0 AND ("freeAbovePaise" IS NULL OR "freeAbovePaise" >= 0) AND ("effectiveTo" IS NULL OR "effectiveTo" > "effectiveFrom"));
ALTER TABLE "SupplierServiceArea" ADD CONSTRAINT "minimum_order_positive" CHECK ("minimumPaise" >= 0);
ALTER TABLE "InventoryBalance" ADD CONSTRAINT "inventory_balance_valid" CHECK ("onHandQty" >= 0 AND "reservedQty" >= 0 AND "reservedQty" <= "onHandQty" AND "version" >= 0);
ALTER TABLE "InventoryReservation" ADD CONSTRAINT "reservation_qty_positive" CHECK ("quantity" > 0);
ALTER TABLE "CartLine" ADD CONSTRAINT "cart_line_qty_positive" CHECK ("quantity" > 0);
ALTER TABLE "RfqItem" ADD CONSTRAINT "rfq_item_qty_positive" CHECK ("quantity" > 0);
ALTER TABLE "SupplierQuoteLine" ADD CONSTRAINT "rfq_quote_line_positive" CHECK ("quantity" > 0 AND "unitPrice" >= 0 AND "taxRateBps" BETWEEN 0 AND 10000 AND "lineTotalPaise" >= 0);
ALTER TABLE "SupplierQuote" ADD CONSTRAINT "supplier_quote_total_valid" CHECK ("subtotalPaise" >= 0 AND "taxPaise" >= 0 AND "deliveryPaise" >= 0 AND "totalPaise" = "subtotalPaise" + "taxPaise" + "deliveryPaise");
ALTER TABLE "CheckoutQuote" ADD CONSTRAINT "checkout_quote_total_valid" CHECK (
 "currency" = 'INR' AND "subtotalPaise" >= 0 AND "discountPaise" >= 0 AND "discountPaise" <= "subtotalPaise" AND "taxPaise" >= 0 AND "deliveryPaise" >= 0
 AND "totalPaise" = "subtotalPaise" - "discountPaise" + "taxPaise" + "deliveryPaise"
);
ALTER TABLE "PurchaseOrder" ADD CONSTRAINT "purchase_order_total_valid" CHECK (
 "currency" = 'INR' AND "subtotalPaise" >= 0 AND "discountPaise" >= 0 AND "discountPaise" <= "subtotalPaise" AND "taxPaise" >= 0 AND "deliveryPaise" >= 0
 AND "totalPaise" = "subtotalPaise" - "discountPaise" + "taxPaise" + "deliveryPaise"
);
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "supplier_order_total_valid" CHECK (
 "subtotalPaise" >= 0 AND "discountPaise" >= 0 AND "discountPaise" <= "subtotalPaise" AND "taxPaise" >= 0 AND "deliveryPaise" >= 0 AND "platformFeePaise" >= 0
 AND "totalPaise" = "subtotalPaise" - "discountPaise" + "taxPaise" + "deliveryPaise"
);
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "supplier_order_item_valid" CHECK (
 "packSizeSnapshot" > 0 AND "quantity" > 0 AND "unitPrice" >= 0 AND "taxRateBps" BETWEEN 0 AND 10000
 AND "taxablePaise" >= 0 AND "taxPaise" >= 0 AND "discountPaise" >= 0 AND "discountPaise" <= "taxablePaise"
 AND "lineTotalPaise" = "taxablePaise" + "taxPaise" - "discountPaise"
);
ALTER TABLE "ShipmentItem" ADD CONSTRAINT "shipment_line_qty_positive" CHECK ("quantity" > 0);
ALTER TABLE "Shipment" ADD CONSTRAINT "shipment_schedule_valid" CHECK ("scheduledFrom" IS NULL OR "scheduledTo" IS NULL OR "scheduledFrom" <= "scheduledTo");
ALTER TABLE "Promotion" ADD CONSTRAINT "promotion_valid" CHECK (
 "endsAt" > "startsAt" AND ("amountPaise" IS NULL OR "amountPaise" >= 0)
 AND ("percentageBps" IS NULL OR "percentageBps" BETWEEN 0 AND 10000)
 AND ("capPaise" IS NULL OR "capPaise" >= 0) AND ("minCartPaise" IS NULL OR "minCartPaise" >= 0)
 AND ("perUserLimit" IS NULL OR "perUserLimit" > 0) AND ("globalLimit" IS NULL OR "globalLimit" > 0)
 AND (("type" = 'PERCENTAGE' AND "percentageBps" IS NOT NULL) OR ("type" = 'FIXED_PAISE' AND "amountPaise" IS NOT NULL) OR "type" = 'FREE_DELIVERY')
);
ALTER TABLE "PaymentAttempt" ADD CONSTRAINT "payment_amount_valid" CHECK ("currency" = 'INR' AND "amountPaise" > 0 AND "capturedPaise" >= 0 AND "capturedPaise" <= "amountPaise");
ALTER TABLE "RefundRequest" ADD CONSTRAINT "refund_positive" CHECK ("amountPaise" > 0);
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "invoice_amount_valid" CHECK ("taxablePaise" >= 0 AND "taxPaise" >= 0 AND "totalPaise" = "taxablePaise" + "taxPaise");
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "invoice_financial_year_format" CHECK ("financialYear" ~ '^20[0-9]{2}-[0-9]{2}$');
ALTER TABLE "Settlement" ADD CONSTRAINT "settlement_amount_valid" CHECK (
 "periodStart" <= "periodEnd" AND "grossPaise" >= 0 AND "commissionPaise" >= 0 AND "refundPaise" >= 0
 AND "payablePaise" = "grossPaise" - "commissionPaise" - "refundPaise" + "adjustmentPaise"
);
ALTER TABLE "SettlementLine" ADD CONSTRAINT "settlement_line_amount_valid" CHECK (
 "grossPaise" >= 0 AND "commissionPaise" >= 0 AND "refundPaise" >= 0
 AND "netPaise" = "grossPaise" - "commissionPaise" - "refundPaise" + "adjustmentPaise"
);
ALTER TABLE "PayoutTransfer" ADD CONSTRAINT "payout_transfer_positive" CHECK ("amountPaise" > 0);
ALTER TABLE "ReturnItem" ADD CONSTRAINT "return_line_qty_positive" CHECK ("quantity" > 0);
ALTER TABLE "Review" ADD CONSTRAINT "review_rating_range" CHECK ("rating" BETWEEN 1 AND 5);
ALTER TABLE "LedgerLine" ADD CONSTRAINT "ledger_line_one_side" CHECK (
 ("debitPaise" > 0 AND "creditPaise" = 0) OR ("debitPaise" = 0 AND "creditPaise" > 0)
);
ALTER TABLE "LedgerAccount" ADD CONSTRAINT "ledger_currency_inr" CHECK ("currency" = 'INR');
ALTER TABLE "OutboxEvent" ADD CONSTRAINT "outbox_attempts_positive" CHECK ("attempts" >= 0);

CREATE UNIQUE INDEX "address_one_default_per_customer" ON "Address" ("userId") WHERE "isDefault" = true AND "deletedAt" IS NULL;
CREATE UNIQUE INDEX "one_active_supplier_payout_account" ON "SupplierPayoutAccount" ("supplierId") WHERE "active" = true;
CREATE UNIQUE INDEX "user_email_casefold_unique" ON "User" (lower("email")) WHERE "email" IS NOT NULL AND "deletedAt" IS NULL;
CREATE UNIQUE INDEX "supplier_slug_casefold_unique" ON "Supplier" (lower("slug"));
CREATE INDEX "listing_discovery_ready_idx" ON "SupplierListing" ("productId", "supplierId") WHERE "active" = true AND "status" = 'APPROVED' AND "deletedAt" IS NULL;
CREATE INDEX "outbox_pending_work_idx" ON "OutboxEvent" ("nextAttemptAt", "createdAt") WHERE "status" IN ('PENDING','FAILED');

-- Database protection against cross-supplier foreign-key combinations.
CREATE FUNCTION buildto_guard_inventory_supplier() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE listing_supplier uuid; warehouse_supplier uuid;
BEGIN
 SELECT "supplierId" INTO listing_supplier FROM "SupplierListing" WHERE id = NEW."listingId";
 SELECT "supplierId" INTO warehouse_supplier FROM "Warehouse" WHERE id = NEW."warehouseId";
 IF listing_supplier IS DISTINCT FROM warehouse_supplier THEN
   RAISE EXCEPTION 'Inventory balance listing and warehouse belong to different suppliers' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_inventory_supplier_guard BEFORE INSERT OR UPDATE ON "InventoryBalance"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_inventory_supplier();

CREATE FUNCTION buildto_guard_order_item_supplier() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE listing_supplier uuid; order_supplier uuid;
BEGIN
 IF NEW."listingId" IS NOT NULL THEN
   SELECT "supplierId" INTO listing_supplier FROM "SupplierListing" WHERE id = NEW."listingId";
   SELECT "supplierId" INTO order_supplier FROM "SupplierOrder" WHERE id = NEW."supplierOrderId";
   IF listing_supplier IS DISTINCT FROM order_supplier THEN
     RAISE EXCEPTION 'Order item listing supplier differs from supplier order' USING ERRCODE = '23514';
   END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_order_item_supplier_guard BEFORE INSERT OR UPDATE ON "SupplierOrderItem"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_order_item_supplier();

CREATE FUNCTION buildto_guard_shipment_supplier() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE order_supplier uuid; warehouse_supplier uuid;
BEGIN
 SELECT "supplierId" INTO order_supplier FROM "SupplierOrder" WHERE id = NEW."supplierOrderId";
 IF NEW."supplierId" IS DISTINCT FROM order_supplier THEN
   RAISE EXCEPTION 'Shipment supplier differs from supplier order' USING ERRCODE = '23514';
 END IF;
 IF NEW."warehouseId" IS NOT NULL THEN
   SELECT "supplierId" INTO warehouse_supplier FROM "Warehouse" WHERE id = NEW."warehouseId";
   IF warehouse_supplier IS DISTINCT FROM NEW."supplierId" THEN
     RAISE EXCEPTION 'Shipment warehouse differs from supplier' USING ERRCODE = '23514';
   END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_shipment_supplier_guard BEFORE INSERT OR UPDATE ON "Shipment"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_shipment_supplier();

CREATE FUNCTION buildto_guard_shipment_item() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE shipment_order uuid; item_order uuid;
BEGIN
 SELECT "supplierOrderId" INTO shipment_order FROM "Shipment" WHERE id = NEW."shipmentId";
 SELECT "supplierOrderId" INTO item_order FROM "SupplierOrderItem" WHERE id = NEW."supplierOrderItemId";
 IF shipment_order IS DISTINCT FROM item_order THEN
   RAISE EXCEPTION 'Shipment item does not belong to shipment supplier order' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_shipment_item_guard BEFORE INSERT OR UPDATE ON "ShipmentItem"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_shipment_item();

CREATE FUNCTION buildto_guard_refund_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE payment_order uuid;
BEGIN
 SELECT "purchaseOrderId" INTO payment_order FROM "PaymentAttempt" WHERE id = NEW."paymentAttemptId";
 IF payment_order IS DISTINCT FROM NEW."purchaseOrderId" THEN
   RAISE EXCEPTION 'Refund payment does not belong to purchase order' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_refund_payment_guard BEFORE INSERT OR UPDATE ON "RefundRequest"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_refund_payment();

CREATE FUNCTION buildto_guard_ledger_posting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total_debit numeric; total_credit numeric; n int;
BEGIN
 IF NEW."postedAt" IS NOT NULL AND OLD."postedAt" IS NULL THEN
   SELECT coalesce(sum("debitPaise"),0), coalesce(sum("creditPaise"),0), count(*)
     INTO total_debit,total_credit,n FROM "LedgerLine" WHERE "journalId"=NEW.id;
   IF n < 2 OR total_debit <= 0 OR total_debit <> total_credit THEN
     RAISE EXCEPTION 'Cannot post unbalanced ledger journal' USING ERRCODE = '23514';
   END IF;
 ELSIF OLD."postedAt" IS NOT NULL AND NEW."postedAt" IS DISTINCT FROM OLD."postedAt" THEN
   RAISE EXCEPTION 'Posted ledger journal is immutable' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_ledger_posting_guard BEFORE UPDATE OF "postedAt" ON "LedgerJournal"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_ledger_posting();
CREATE FUNCTION buildto_guard_ledger_lines() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE journal_id uuid; is_posted timestamptz;
BEGIN
 -- Never allow an UPDATE to move a line OUT of an already-posted journal.
 IF TG_OP = 'UPDATE' THEN
   SELECT "postedAt" INTO is_posted FROM "LedgerJournal" WHERE id=OLD."journalId" FOR UPDATE;
   IF is_posted IS NOT NULL THEN
     RAISE EXCEPTION 'Posted ledger lines cannot be moved or edited' USING ERRCODE = '23514';
   END IF;
 END IF;
 journal_id := CASE WHEN TG_OP = 'DELETE' THEN OLD."journalId" ELSE NEW."journalId" END;
 SELECT "postedAt" INTO is_posted FROM "LedgerJournal" WHERE id=journal_id FOR UPDATE;
 IF is_posted IS NOT NULL THEN
   RAISE EXCEPTION 'Posted ledger lines are immutable' USING ERRCODE = '23514';
 END IF;
 IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_ledger_line_guard BEFORE INSERT OR UPDATE OR DELETE ON "LedgerLine"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_ledger_lines();

CREATE FUNCTION buildto_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Append-only audit / stock-movement records cannot be modified' USING ERRCODE = '23514'; END; $$;
CREATE TRIGGER buildto_audit_immutable BEFORE UPDATE OR DELETE ON "AuditEvent"
 FOR EACH ROW EXECUTE FUNCTION buildto_append_only();
CREATE TRIGGER buildto_stock_movement_immutable BEFORE UPDATE OR DELETE ON "StockMovement"
 FOR EACH ROW EXECUTE FUNCTION buildto_append_only();


-- Financial operations must not bypass approval by inserting an already-posted journal.
CREATE FUNCTION buildto_block_preposted_journal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW."postedAt" IS NOT NULL THEN
   RAISE EXCEPTION 'Journal cannot be inserted as posted' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_new_journal_unposted BEFORE INSERT ON "LedgerJournal"
 FOR EACH ROW EXECUTE FUNCTION buildto_block_preposted_journal();

CREATE FUNCTION buildto_guard_posted_journal_immutability() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD."postedAt" IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Posted journal header is immutable' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_posted_journal_immutable BEFORE UPDATE ON "LedgerJournal"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_posted_journal_immutability();

-- Core ownership identifiers cannot be moved to a different supplier after creation.
CREATE FUNCTION buildto_immutable_supplier_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW."supplierId" IS DISTINCT FROM OLD."supplierId" THEN
   RAISE EXCEPTION 'Supplier ownership cannot be reassigned' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_listing_owner_immutable BEFORE UPDATE OF "supplierId" ON "SupplierListing"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();
CREATE TRIGGER buildto_warehouse_owner_immutable BEFORE UPDATE OF "supplierId" ON "Warehouse"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();
CREATE TRIGGER buildto_supplier_order_owner_immutable BEFORE UPDATE OF "supplierId" ON "SupplierOrder"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();
CREATE TRIGGER buildto_shipment_owner_immutable BEFORE UPDATE OF "supplierId" ON "Shipment"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();
CREATE TRIGGER buildto_invoice_owner_immutable BEFORE UPDATE OF "supplierId" ON "TaxInvoice"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();
CREATE TRIGGER buildto_quote_owner_immutable BEFORE UPDATE OF "supplierId" ON "SupplierQuote"
 FOR EACH ROW EXECUTE FUNCTION buildto_immutable_supplier_owner();

-- Refund requests lock the captured payment and reserve refund budget even before the gateway confirms.
-- This prevents two simultaneous refund requests from allocating more than captured funds.
CREATE FUNCTION buildto_guard_refund_budget() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE captured bigint; allocated numeric;
BEGIN
 IF TG_OP = 'UPDATE' AND (NEW."paymentAttemptId" IS DISTINCT FROM OLD."paymentAttemptId" OR NEW."purchaseOrderId" IS DISTINCT FROM OLD."purchaseOrderId") THEN
   RAISE EXCEPTION 'Refund ownership is immutable' USING ERRCODE = '23514';
 END IF;
 SELECT "capturedPaise" INTO captured FROM "PaymentAttempt" WHERE id=NEW."paymentAttemptId" FOR UPDATE;
 IF captured IS NULL THEN RAISE EXCEPTION 'Refund requires existing payment' USING ERRCODE = '23514'; END IF;
 SELECT coalesce(sum("amountPaise"),0) INTO allocated FROM "RefundRequest"
  WHERE "paymentAttemptId"=NEW."paymentAttemptId" AND "id"<>NEW.id AND "status" NOT IN ('REJECTED','FAILED');
 IF NEW."status" NOT IN ('REJECTED','FAILED') THEN allocated := allocated + NEW."amountPaise"; END IF;
 IF allocated > captured THEN
   RAISE EXCEPTION 'Refund requests exceed confirmed captured amount' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_refund_budget_guard BEFORE INSERT OR UPDATE ON "RefundRequest"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_refund_budget();

CREATE FUNCTION buildto_captured_amount_non_decreasing() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW."capturedPaise" < OLD."capturedPaise" THEN
   RAISE EXCEPTION 'Verified captured amount cannot decrease' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_payment_capture_monotonic BEFORE UPDATE OF "capturedPaise" ON "PaymentAttempt"
 FOR EACH ROW EXECUTE FUNCTION buildto_captured_amount_non_decreasing();

CREATE FUNCTION buildto_guard_invoice_supplier() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE order_supplier uuid;
BEGIN
 SELECT "supplierId" INTO order_supplier FROM "SupplierOrder" WHERE id=NEW."supplierOrderId";
 IF order_supplier IS DISTINCT FROM NEW."supplierId" THEN
   RAISE EXCEPTION 'Invoice supplier does not own supplier order' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_invoice_supplier_guard BEFORE INSERT OR UPDATE ON "TaxInvoice"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_invoice_supplier();

CREATE TRIGGER buildto_supplier_status_events_immutable BEFORE UPDATE OR DELETE ON "SupplierOrderEvent"
 FOR EACH ROW EXECUTE FUNCTION buildto_append_only();
CREATE TRIGGER buildto_shipment_status_events_immutable BEFORE UPDATE OR DELETE ON "ShipmentEvent"
 FOR EACH ROW EXECUTE FUNCTION buildto_append_only();

-- PostGIS indexes, delivery/COD/GST/shipments hardening.
-- BUILDTO 2.1: apply on a NEW empty target database after generated Prisma DDL
-- and after V2 integrity-guards.sql. Requires PostGIS extension before Prisma DDL.
-- This is not an in-place migration of an existing Neon production database.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

-- Spatial indexes are not modeled by Prisma 5.22. Point fields are Unsupported("geography(...)").
CREATE INDEX service_area_geocenter_gist ON "ServiceArea" USING GIST ("geoCenter") WHERE "geoCenter" IS NOT NULL;
CREATE INDEX service_area_boundary_gist ON "ServiceArea" USING GIST ("geoBoundary") WHERE "geoBoundary" IS NOT NULL;
CREATE INDEX address_geopoint_gist ON "Address" USING GIST ("geoPoint") WHERE "geoPoint" IS NOT NULL;
-- Spatial data comes from validated coordinates, never trusted user-supplied geography JSON.
CREATE FUNCTION buildto_sync_service_area_point() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW."geoCenter" := CASE WHEN NEW."centerLat" IS NULL OR NEW."centerLng" IS NULL THEN NULL
 ELSE ST_SetSRID(ST_MakePoint(NEW."centerLng"::double precision, NEW."centerLat"::double precision),4326)::geography END;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_service_area_geopoint BEFORE INSERT OR UPDATE OF "centerLat","centerLng" ON "ServiceArea"
 FOR EACH ROW EXECUTE FUNCTION buildto_sync_service_area_point();

CREATE FUNCTION buildto_sync_address_geopoint() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW."geoPoint" := CASE WHEN NEW.latitude IS NULL OR NEW.longitude IS NULL THEN NULL
 ELSE ST_SetSRID(ST_MakePoint(NEW.longitude::double precision,NEW.latitude::double precision),4326)::geography END;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_address_geopoint BEFORE INSERT OR UPDATE OF "latitude","longitude" ON "Address"
 FOR EACH ROW EXECUTE FUNCTION buildto_sync_address_geopoint();

ALTER TABLE "SupplierFreightBracket" ADD CONSTRAINT "freight_bracket_valid" CHECK (
 "dimension" IN ('MASS','VOLUME') AND "minQuantity" >= 0 AND ("maxQuantity" IS NULL OR "maxQuantity" > "minQuantity")
 AND "fixedFeePaise" >= 0 AND "perKmPaise" >= 0 AND "perTonneKmPaise" >= 0 AND "perCubicMetreKmPaise" >= 0
);
ALTER TABLE "SupplierDeliveryRate" ADD CONSTRAINT "freight_dimensions_valid" CHECK (
 "perTonneKmPaise" >= 0 AND "perCubicMetreKmPaise" >= 0 AND ("weightCapacityKg" IS NULL OR "weightCapacityKg" > 0)
 AND ("volumeCapacityM3" IS NULL OR "volumeCapacityM3" > 0)
);
-- Exclusion constraints serialize overlapping brackets for the same rate/dimension; room for a no-upper-bound bracket.
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE "SupplierFreightBracket" ADD CONSTRAINT "freight_brackets_no_overlap"
 EXCLUDE USING gist ("deliveryRateId" WITH =, "dimension" WITH =,
 numrange("minQuantity", "maxQuantity", '[)') WITH && ) WHERE ("active" = true);

-- Exact GST decomposition and bill-of-supply rules. Line snapshot consistency must also be checked by invoice service.
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "order_item_gst_split" CHECK (
 "cgstPaise" >= 0 AND "sgstPaise" >= 0 AND "utgstPaise" >= 0 AND "igstPaise" >= 0 AND "cessPaise" >= 0
 AND "taxPaise" = "cgstPaise" + "sgstPaise" + "utgstPaise" + "igstPaise" + "cessPaise"
 AND ("igstPaise" = 0 OR ("cgstPaise" = 0 AND "sgstPaise" = 0 AND "utgstPaise" = 0))
 AND ("sgstPaise" = 0 OR "utgstPaise" = 0)
);
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "invoice_gst_split" CHECK (
 "cgstPaise" >= 0 AND "sgstPaise" >= 0 AND "utgstPaise" >= 0 AND "igstPaise" >= 0 AND "cessPaise" >= 0
 AND "taxPaise" = "cgstPaise" + "sgstPaise" + "utgstPaise" + "igstPaise" + "cessPaise"
 AND ("igstPaise" = 0 OR ("cgstPaise" = 0 AND "sgstPaise" = 0 AND "utgstPaise" = 0))
 AND ("sgstPaise" = 0 OR "utgstPaise" = 0)
 AND ("kind" <> 'BILL_OF_SUPPLY' OR "taxPaise" = 0)
);
CREATE FUNCTION buildto_tax_invoice_registration_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE registration "GstRegistrationType";
BEGIN
 SELECT "gstRegistration" INTO registration FROM "Supplier" WHERE id=NEW."supplierId";
 IF NEW."kind" = 'TAX_INVOICE' AND registration IS DISTINCT FROM 'REGULAR' THEN
  RAISE EXCEPTION 'Tax invoice requires verified regular GST supplier registration' USING ERRCODE='23514';
 END IF;
 IF registration IN ('COMPOSITION','UNREGISTERED','EXEMPT','UNVERIFIED') AND NEW."taxPaise">0 THEN
  RAISE EXCEPTION 'Supplier cannot charge tax with this GST status' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_invoice_gst_registration BEFORE INSERT OR UPDATE ON "TaxInvoice"
 FOR EACH ROW EXECUTE FUNCTION buildto_tax_invoice_registration_guard();

-- OTP: HMAC-SHA256 hex, 5 tries max in service, no plaintext PIN; supervisor exception with named approver.
ALTER TABLE "Shipment" ADD CONSTRAINT "shipment_handover_valid" CHECK (
 "otpAttempts" BETWEEN 0 AND 5 AND
 ("otpVerifiedAt" IS NULL OR ("deliveryOtpHash" ~ '^[0-9a-f]{64}$' AND "otpIssuedAt" IS NOT NULL
  AND "otpExpiresAt" IS NOT NULL AND "otpVerifiedAt" BETWEEN "otpIssuedAt" AND "otpExpiresAt"))
 AND ("exceptionApprovedAt" IS NULL OR ("exceptionReason" IS NOT NULL AND length(trim("exceptionReason"))>=12 AND "exceptionApprovedById" IS NOT NULL))
 AND ("status" <> 'DELIVERED' OR
    (("handoverMethod"='OTP' AND "otpVerifiedAt" IS NOT NULL) OR
     ("handoverMethod"='APPROVED_EXCEPTION' AND "exceptionApprovedAt" IS NOT NULL)))
);
ALTER TABLE "ShipmentItem" ADD CONSTRAINT "shipment_item_quantities" CHECK (
 "deliveredQty" >= 0 AND "rejectedQty" >= 0 AND "returnedQty" >= 0
 AND "deliveredQty" + "rejectedQty" <= "quantity" AND "returnedQty" <= "deliveredQty"
);
ALTER TABLE "SupplierOrderItem" ADD CONSTRAINT "shipment_allocation_bounds" CHECK (
 "allocatedShipmentQty" >= 0 AND "allocatedShipmentQty" <= "quantity"
);

-- Each ShipmentItem acquires an atomic row-level reservation on its order line.
-- This prevents concurrent two-truck allocations overshooting the purchased quantity.
CREATE FUNCTION buildto_shipment_allocation_row() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE old_counted boolean:=false; new_counted boolean:=false; delta numeric:=0;
BEGIN
 IF TG_OP <> 'INSERT' THEN
  IF TG_OP='UPDATE' AND (OLD."shipmentId" IS DISTINCT FROM NEW."shipmentId" OR
                            OLD."supplierOrderItemId" IS DISTINCT FROM NEW."supplierOrderItemId") THEN
   RAISE EXCEPTION 'Shipment line ownership is immutable' USING ERRCODE='23514';
  END IF;
  SELECT status NOT IN ('CANCELLED','FAILED','RETURNED') INTO old_counted FROM "Shipment" WHERE id=OLD."shipmentId" FOR UPDATE;
 END IF;
 IF TG_OP <> 'DELETE' THEN
  SELECT status NOT IN ('CANCELLED','FAILED','RETURNED') INTO new_counted FROM "Shipment" WHERE id=NEW."shipmentId" FOR UPDATE;
 END IF;
 IF old_counted THEN delta:=delta-OLD."quantity"; END IF;
 IF new_counted THEN delta:=delta+NEW."quantity"; END IF;
 IF delta <> 0 THEN
  UPDATE "SupplierOrderItem" SET "allocatedShipmentQty"="allocatedShipmentQty"+delta
   WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD."supplierOrderItemId" ELSE NEW."supplierOrderItemId" END
   AND "allocatedShipmentQty"+delta >= 0 AND "allocatedShipmentQty"+delta <= "quantity";
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment allocation exceeds ordered quantity' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_shipment_item_allocation BEFORE INSERT OR UPDATE OR DELETE ON "ShipmentItem"
 FOR EACH ROW EXECUTE FUNCTION buildto_shipment_allocation_row();

-- Changing a shipment from or to a terminal exclusion updates allocations atomically.
CREATE FUNCTION buildto_shipment_status_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE old_active boolean; new_active boolean; x record; delta numeric;
BEGIN
 IF NEW.status=OLD.status THEN RETURN NEW; END IF;
 old_active:=OLD.status NOT IN ('CANCELLED','FAILED','RETURNED');
 new_active:=NEW.status NOT IN ('CANCELLED','FAILED','RETURNED');
 IF old_active IS DISTINCT FROM new_active THEN
  FOR x IN SELECT "supplierOrderItemId",quantity FROM "ShipmentItem" WHERE "shipmentId"=NEW.id ORDER BY "supplierOrderItemId" LOOP
    delta:=CASE WHEN new_active THEN x.quantity ELSE -x.quantity END;
    UPDATE "SupplierOrderItem" SET "allocatedShipmentQty"="allocatedShipmentQty"+delta
    WHERE id=x."supplierOrderItemId" AND "allocatedShipmentQty"+delta >= 0 AND "allocatedShipmentQty"+delta <= "quantity";
    IF NOT FOUND THEN RAISE EXCEPTION 'Shipment reallocation exceeds ordered quantity' USING ERRCODE='23514'; END IF;
  END LOOP;
 END IF;
 IF NEW.status='DELIVERED' THEN
  IF NOT EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id) OR
   EXISTS(SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id AND ("deliveredQty"<>"quantity" OR "rejectedQty"<>0)) THEN
    RAISE EXCEPTION 'Full delivery requires every shipment item to be confirmed delivered' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_shipment_status_allocation BEFORE UPDATE OF status ON "Shipment"
 FOR EACH ROW EXECUTE FUNCTION buildto_shipment_status_allocation();

-- Supplier-independent cancellation; parent follows child outcomes, not the other way round.
CREATE FUNCTION buildto_derive_purchase_order_status() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n int; cancelled int; delivered int; progressed int; cur "PurchaseOrderStatus"; next_status "PurchaseOrderStatus";
BEGIN
 SELECT status INTO cur FROM "PurchaseOrder" WHERE id=NEW."purchaseOrderId" FOR UPDATE;
 IF cur='CLOSED' THEN RETURN NEW; END IF;
 SELECT count(*),count(*) FILTER (WHERE status IN ('CANCELLED','REJECTED')),
        count(*) FILTER (WHERE status='DELIVERED'),
        count(*) FILTER (WHERE status NOT IN ('PENDING_ACCEPTANCE','CANCELLED','REJECTED'))
 INTO n,cancelled,delivered,progressed FROM "SupplierOrder" WHERE "purchaseOrderId"=NEW."purchaseOrderId";
 next_status:=CASE
   WHEN n=0 THEN 'PLACED'::"PurchaseOrderStatus"
   WHEN cancelled=n THEN 'CANCELLED'::"PurchaseOrderStatus"
   WHEN cancelled>0 THEN 'PARTIALLY_CANCELLED'::"PurchaseOrderStatus"
   WHEN delivered=n THEN 'FULFILLED'::"PurchaseOrderStatus"
   WHEN delivered>0 THEN 'PARTIALLY_FULFILLED'::"PurchaseOrderStatus"
   WHEN progressed>0 THEN 'CONFIRMED'::"PurchaseOrderStatus"
   ELSE 'PLACED'::"PurchaseOrderStatus" END;
 UPDATE "PurchaseOrder" SET status=next_status,"updatedAt"=now() WHERE id=NEW."purchaseOrderId" AND status IS DISTINCT FROM next_status;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_purchase_status_from_supplier_orders AFTER INSERT OR UPDATE OF status ON "SupplierOrder"
 FOR EACH ROW EXECUTE FUNCTION buildto_derive_purchase_order_status();

-- Cash-on-delivery: cash physically collected by supplier is not gateway capture.
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "supplier_cod_totals_valid" CHECK (
 "codRecordedPaise">=0 AND "codVerifiedPaise">=0 AND "codVerifiedPaise"<="codRecordedPaise"
 AND "codRecordedPaise"<="totalPaise"
);
ALTER TABLE "CodCollection" ADD CONSTRAINT "cod_collection_valid" CHECK (
 "currency"='INR' AND "collectedPaise">0 AND length(trim("receiptNumber"))>=3
 AND ("status"<>'VERIFIED' OR ("verifiedByUserId" IS NOT NULL AND "verifiedAt" IS NOT NULL AND "journalReference" IS NOT NULL))
);
ALTER TABLE "SupplierCommissionReceivable" ADD CONSTRAINT "commission_receivable_valid" CHECK (
 "commissionPaise">=0 AND "offsetPaise">=0 AND "offsetPaise"<="commissionPaise"
);
CREATE FUNCTION buildto_guard_cod_collection() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE order_supplier uuid; shipment_order uuid; delta_recorded bigint:=0; delta_verified bigint:=0; journal_posted timestamptz;
BEGIN
 SELECT "supplierId" INTO order_supplier FROM "SupplierOrder" WHERE id=NEW."supplierOrderId";
 IF order_supplier IS DISTINCT FROM NEW."supplierId" THEN RAISE EXCEPTION 'COD supplier mismatch' USING ERRCODE='23514'; END IF;
 IF NEW."shipmentId" IS NOT NULL THEN
  SELECT "supplierOrderId" INTO shipment_order FROM "Shipment" WHERE id=NEW."shipmentId";
  IF shipment_order IS DISTINCT FROM NEW."supplierOrderId" THEN RAISE EXCEPTION 'COD shipment order mismatch' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'RECORDED' THEN RAISE EXCEPTION 'COD starts recorded and unverified' USING ERRCODE='23514'; END IF;
  delta_recorded:=NEW."collectedPaise";
 ELSE
  IF OLD.status='VERIFIED' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Verified COD receipt is immutable; use compensating journal' USING ERRCODE='23514';
  END IF;
  IF NEW."supplierOrderId" IS DISTINCT FROM OLD."supplierOrderId" OR
    NEW."supplierId" IS DISTINCT FROM OLD."supplierId" OR NEW."collectedPaise"<>OLD."collectedPaise" THEN
    RAISE EXCEPTION 'COD ownership and amount cannot be rewritten' USING ERRCODE='23514';
  END IF;
  IF OLD.status='REVERSED' THEN RAISE EXCEPTION 'Reversed COD receipt is immutable' USING ERRCODE='23514'; END IF;
  IF OLD.status='RECORDED' AND NEW.status='REVERSED' THEN delta_recorded:=-NEW."collectedPaise"; END IF;
  IF OLD.status<>'VERIFIED' AND NEW.status='VERIFIED' THEN delta_verified:=NEW."collectedPaise"; END IF;
 END IF;
 IF NEW.status='VERIFIED' THEN
  SELECT "postedAt" INTO journal_posted FROM "LedgerJournal" WHERE "referenceKey"=NEW."journalReference";
  IF journal_posted IS NULL THEN RAISE EXCEPTION 'COD verification requires posted matching ledger journal' USING ERRCODE='23514'; END IF;
 END IF;
 IF delta_recorded<>0 OR delta_verified<>0 THEN
   UPDATE "SupplierOrder" SET "codRecordedPaise"="codRecordedPaise"+delta_recorded,
   "codVerifiedPaise"="codVerifiedPaise"+delta_verified
    WHERE id=NEW."supplierOrderId";
   -- supplier_cod_totals_valid enforces atomic collection limits on this row.
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_cod_allocation BEFORE INSERT OR UPDATE ON "CodCollection"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_cod_collection();

CREATE FUNCTION buildto_guard_receivable_supplier() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owner uuid; fee bigint;
BEGIN
 SELECT "supplierId","platformFeePaise" INTO owner,fee FROM "SupplierOrder" WHERE id=NEW."supplierOrderId";
 IF owner IS DISTINCT FROM NEW."supplierId" THEN RAISE EXCEPTION 'Commission receivable supplier mismatch' USING ERRCODE='23514'; END IF;
 IF NEW."commissionPaise"<>fee THEN RAISE EXCEPTION 'Commission receivable must match order marketplace fee' USING ERRCODE='23514'; END IF;
 IF TG_OP='UPDATE' AND (OLD."supplierId" IS DISTINCT FROM NEW."supplierId" OR OLD."supplierOrderId" IS DISTINCT FROM NEW."supplierOrderId") THEN
  RAISE EXCEPTION 'Commission receivable ownership immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_commission_receivable_supplier BEFORE INSERT OR UPDATE ON "SupplierCommissionReceivable"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_receivable_supplier();

COMMIT;
