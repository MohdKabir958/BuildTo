-- BUILDTO V2 POSTGRESQL INTEGRITY GUARDS — FOR GREENFIELD V2 SCHEMA ONLY.
-- Generated Prisma DDL must be applied before this file. Do not run on the current legacy DB.
-- Prisma does not model CHECK constraints, partial indexes or triggers in schema.prisma.
BEGIN;
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

COMMIT;
