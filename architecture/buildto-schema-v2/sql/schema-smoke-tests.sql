-- V2 disposable PostgreSQL smoke tests. Must be run against a fresh isolated CI DB only.
BEGIN;
DO $$
DECLARE count_units integer; count_categories integer;
BEGIN
  SELECT count(*) INTO count_units FROM "UnitOfMeasure";
  SELECT count(*) INTO count_categories FROM "Category";
  IF count_units < 18 OR count_categories < 9 THEN
    RAISE EXCEPTION 'Reference seeding incomplete, UOM=%, categories=%', count_units, count_categories;
  END IF;
END; $$;
-- Create two unrelated suppliers. A cross-supplier InventoryBalance must be rejected.
INSERT INTO "Supplier" ("id","slug","legalName","displayName","updatedAt") VALUES
 ('20000000-0000-4000-8000-000000000001','smoke-supplier-a','SMOKE Supplier A','SMOKE A',now()),
 ('20000000-0000-4000-8000-000000000002','smoke-supplier-b','SMOKE Supplier B','SMOKE B',now());
INSERT INTO "Product" ("id","code","categoryId","name","specification","updatedAt") VALUES
 ('30000000-0000-4000-8000-000000000001','SMOKE-PRODUCT','10000000-0000-4000-8000-000000000001','Test cement','{}'::jsonb,now());
INSERT INTO "SupplierListing" ("id","supplierId","productId","sku","unitCode","unitPrice","updatedAt") VALUES
 ('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','SMOKE-SKU','BAG',390,now());
INSERT INTO "Warehouse" ("id","supplierId","code","name") VALUES
 ('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','SMOKE-W','Wrong Supplier Warehouse'),
 ('50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','SMOKE-C','Correct Supplier Warehouse');
DO $$ BEGIN
  BEGIN
    INSERT INTO "InventoryBalance"("id","listingId","warehouseId","updatedAt") VALUES
      ('60000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',now());
    RAISE EXCEPTION 'Cross-supplier inventory was incorrectly accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: supplier mismatch rejected';
  END;
END; $$;
INSERT INTO "InventoryBalance"("id","listingId","warehouseId","onHandQty","reservedQty","updatedAt") VALUES
 ('60000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002',10,2,now());
DO $$ BEGIN
  BEGIN
    UPDATE "InventoryBalance" SET "reservedQty"=20 WHERE id='60000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Negative available inventory incorrectly accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: oversold inventory rejected';
  END;
END; $$;
DO $$ BEGIN
  BEGIN
    INSERT INTO "PurchaseOrder" ("id", "publicNumber", "customerId", "clientRequestId", "addressSnapshot", "subtotalPaise", "discountPaise", "taxPaise", "deliveryPaise", "totalPaise", "updatedAt") VALUES
      ('70000000-0000-4000-8000-000000000001','SMOKE-ORDER','80000000-0000-4000-8000-000000000001','REQ-1','{}'::jsonb,1000,0,0,150,1000,now());
    RAISE EXCEPTION 'Incorrect monetary total was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: incorrect total rejected';
  END;
END; $$;
ROLLBACK;
