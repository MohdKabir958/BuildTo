-- Step 1: shipment allocation measures accepted/active quantity.
-- Never mutate the immutable greenfield migration; this applies to both
-- existing V2.1 staging databases and disposable CI PostGIS databases.
BEGIN;

CREATE OR REPLACE FUNCTION buildto_shipment_allocation_row()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE old_state "ShipmentStatus"; new_state "ShipmentStatus";
        old_counted numeric:=0; new_counted numeric:=0; delta numeric:=0;
BEGIN
 IF TG_OP='UPDATE' AND
    (OLD."shipmentId" IS DISTINCT FROM NEW."shipmentId" OR
     OLD."supplierOrderItemId" IS DISTINCT FROM NEW."supplierOrderItemId") THEN
  RAISE EXCEPTION 'Shipment line ownership is immutable' USING ERRCODE='23514';
 END IF;
 IF TG_OP<>'INSERT' THEN
  SELECT status INTO old_state FROM "Shipment" WHERE id=OLD."shipmentId" FOR UPDATE;
  IF old_state NOT IN ('CANCELLED','FAILED','RETURNED') THEN
   old_counted:=OLD."quantity"-CASE WHEN old_state='PARTIALLY_DELIVERED'
     THEN OLD."rejectedQty" ELSE 0 END;
  END IF;
 END IF;
 IF TG_OP<>'DELETE' THEN
  SELECT status INTO new_state FROM "Shipment" WHERE id=NEW."shipmentId" FOR UPDATE;
  IF new_state NOT IN ('CANCELLED','FAILED','RETURNED') THEN
   new_counted:=NEW."quantity"-CASE WHEN new_state='PARTIALLY_DELIVERED'
     THEN NEW."rejectedQty" ELSE 0 END;
  END IF;
 END IF;
 delta:=new_counted-old_counted;
 IF delta<>0 THEN
  UPDATE "SupplierOrderItem" SET "allocatedShipmentQty"="allocatedShipmentQty"+delta
   WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD."supplierOrderItemId"
     ELSE NEW."supplierOrderItemId" END
   AND "allocatedShipmentQty"+delta>=0
   AND "allocatedShipmentQty"+delta<="quantity";
  IF NOT FOUND THEN
   RAISE EXCEPTION 'Shipment allocation exceeds ordered quantity' USING ERRCODE='23514';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION buildto_shipment_status_allocation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE x record; prior numeric; next_amount numeric; delta numeric;
BEGIN
 IF NEW.status=OLD.status THEN RETURN NEW; END IF;
 IF NEW.status='PARTIALLY_DELIVERED' THEN
  IF NOT EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id) OR
     EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id
       AND "deliveredQty"+"rejectedQty"<>"quantity") OR
     NOT EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id
       AND "rejectedQty">0) OR
     NOT EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id
       AND "deliveredQty">0) OR
     NEW."handoverMethod" NOT IN ('OTP','APPROVED_EXCEPTION') THEN
   RAISE EXCEPTION 'Partial shipment needs verified accepted and rejected quantities'
     USING ERRCODE='23514';
  END IF;
 END IF;
 FOR x IN SELECT "supplierOrderItemId","quantity","rejectedQty"
   FROM "ShipmentItem" WHERE "shipmentId"=NEW.id
   ORDER BY "supplierOrderItemId"
 LOOP
  prior:=CASE WHEN OLD.status IN ('CANCELLED','FAILED','RETURNED') THEN 0
   WHEN OLD.status='PARTIALLY_DELIVERED' THEN x."quantity"-x."rejectedQty"
   ELSE x."quantity" END;
  next_amount:=CASE WHEN NEW.status IN ('CANCELLED','FAILED','RETURNED') THEN 0
   WHEN NEW.status='PARTIALLY_DELIVERED' THEN x."quantity"-x."rejectedQty"
   ELSE x."quantity" END;
  delta:=next_amount-prior;
  IF delta<>0 THEN
   UPDATE "SupplierOrderItem" SET "allocatedShipmentQty"="allocatedShipmentQty"+delta
    WHERE id=x."supplierOrderItemId" AND "allocatedShipmentQty"+delta>=0
     AND "allocatedShipmentQty"+delta<="quantity";
   IF NOT FOUND THEN
    RAISE EXCEPTION 'Shipment reallocation exceeds ordered quantity' USING ERRCODE='23514';
   END IF;
  END IF;
 END LOOP;
 IF NEW.status='DELIVERED' THEN
  IF NOT EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id) OR
   EXISTS (SELECT 1 FROM "ShipmentItem" WHERE "shipmentId"=NEW.id
     AND ("deliveredQty"<>"quantity" OR "rejectedQty"<>0)) THEN
   RAISE EXCEPTION 'Full delivery requires every shipment item confirmed'
    USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;

COMMIT;
