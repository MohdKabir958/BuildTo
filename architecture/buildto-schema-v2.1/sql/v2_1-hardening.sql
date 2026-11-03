-- BUILDTO 2.1: apply on a NEW empty target database after generated Prisma DDL
-- and after V2 integrity-guards.sql. Requires PostGIS extension before Prisma DDL.
-- This is not an in-place migration of an existing Neon production database.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

-- Spatial indexes are not modeled by Prisma 5.22. Point fields are Unsupported("geography(...)").
CREATE INDEX service_area_geocenter_gist ON "ServiceArea" USING GIST ("geoCenter") WHERE "geoCenter" IS NOT NULL;
CREATE INDEX service_area_boundary_gist ON "ServiceArea" USING GIST ("geoBoundary") WHERE "geoBoundary" IS NOT NULL;
-- Spatial data comes from validated coordinates, never trusted user-supplied geography JSON.
CREATE FUNCTION buildto_sync_service_area_point() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW."geoCenter" := CASE WHEN NEW."centerLat" IS NULL OR NEW."centerLng" IS NULL THEN NULL
 ELSE ST_SetSRID(ST_MakePoint(NEW."centerLng"::double precision, NEW."centerLat"::double precision),4326)::geography END;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_service_area_geopoint BEFORE INSERT OR UPDATE OF "centerLat","centerLng" ON "ServiceArea"
 FOR EACH ROW EXECUTE FUNCTION buildto_sync_service_area_point();

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
  SELECT status NOT IN ('CANCELLED','FAILED','RETURNED') INTO old_counted FROM "Shipment" WHERE id=OLD."shipmentId";
 END IF;
 IF TG_OP <> 'DELETE' THEN
  SELECT status NOT IN ('CANCELLED','FAILED','RETURNED') INTO new_counted FROM "Shipment" WHERE id=NEW."shipmentId";
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
