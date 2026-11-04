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

-- Double-entry journal cannot be preposted, posted while unbalanced, or changed after posting.
DO $$ BEGIN
 BEGIN
   INSERT INTO "LedgerJournal"("id","referenceKey","eventType","postedAt") VALUES
    ('90000000-0000-4000-8000-000000000001','SMOKE-BAD-JOURNAL','SMOKE',now());
   RAISE EXCEPTION 'Inserted a preposted journal';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: preposted journal rejected'; END;
END; $$;
INSERT INTO "LedgerJournal"("id","referenceKey","eventType") VALUES
 ('90000000-0000-4000-8000-000000000002','SMOKE-GOOD-JOURNAL','SMOKE');
DO $$ BEGIN
 BEGIN
   UPDATE "LedgerJournal" SET "postedAt"=now() WHERE id='90000000-0000-4000-8000-000000000002';
   RAISE EXCEPTION 'Posted an unbalanced journal';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: unbalanced journal rejected'; END;
END; $$;
INSERT INTO "LedgerAccount"("id","code","name") VALUES
 ('a0000000-0000-4000-8000-000000000001','SMOKE-RECEIVABLE','SMOKE receivable'),
 ('a0000000-0000-4000-8000-000000000002','SMOKE-CLEARING','SMOKE clearing');
INSERT INTO "LedgerLine"("journalId","lineNumber","accountId","debitPaise","creditPaise") VALUES
 ('90000000-0000-4000-8000-000000000002',1,'a0000000-0000-4000-8000-000000000001',1000,0),
 ('90000000-0000-4000-8000-000000000002',2,'a0000000-0000-4000-8000-000000000002',0,1000);
UPDATE "LedgerJournal" SET "postedAt"=now() WHERE id='90000000-0000-4000-8000-000000000002';
DO $$ BEGIN
 BEGIN
   UPDATE "LedgerLine" SET "debitPaise"=3000 WHERE "journalId"='90000000-0000-4000-8000-000000000002' AND "lineNumber"=1;
   RAISE EXCEPTION 'Modified posted journal line';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: posted journal immutable'; END;
END; $$;

ROLLBACK;
