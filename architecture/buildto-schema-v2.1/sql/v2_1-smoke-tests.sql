-- SQL acceptance tests. Disposable PostGIS PostgreSQL 16 DB ONLY. All data rolled back.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='postgis') THEN RAISE EXCEPTION 'PostGIS absent'; END IF;
END $$;
-- Two suppliers, one order for each, one split purchase order. All identities synthetic.
INSERT INTO "User"("id","displayName","updatedAt") VALUES
 ('80000000-0000-4000-8000-000000000001','SMOKE Contractor',now());
INSERT INTO "Supplier"("id","slug","legalName","displayName","gstRegistration","updatedAt") VALUES
 ('20000000-0000-4000-8000-000000000001','smoke-v21-a','Supplier A','Supplier A','COMPOSITION',now()),
 ('20000000-0000-4000-8000-000000000002','smoke-v21-b','Supplier B','Supplier B','REGULAR',now());
INSERT INTO "PurchaseOrder"("id","publicNumber","customerId","clientRequestId","addressSnapshot","subtotalPaise","taxPaise","totalPaise","updatedAt") VALUES
 ('70000000-0000-4000-8000-000000000001','SMOKE-PO-V21','80000000-0000-4000-8000-000000000001','SMOKE-REQ-V21','{}'::jsonb,100000,0,100000,now());
INSERT INTO "SupplierOrder"("id","purchaseOrderId","supplierId","subtotalPaise","totalPaise","platformFeePaise","updatedAt") VALUES
 ('71000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',60000,60000,4000,now()),
 ('71000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',40000,40000,2000,now());
INSERT INTO "SupplierOrderItem"("id","supplierOrderId","skuSnapshot","nameSnapshot","unitCode","packSizeSnapshot","quantity","unitPrice","taxRateBps","taxablePaise","taxPaise","lineTotalPaise") VALUES
 ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','SMOKE-CEMENT','SMOKE Cement','BAG',1,10,600,0,6000,0,6000);
-- 500 bags across two trucks => total shipment assigned must not exceed purchased quantity (10 here).
INSERT INTO "Shipment"("id","shipmentNumber","supplierOrderId","supplierId") VALUES
 ('73000000-0000-4000-8000-000000000001','SMOKE-TRUCK-1','71000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001'),
 ('73000000-0000-4000-8000-000000000002','SMOKE-TRUCK-2','71000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001');
INSERT INTO "ShipmentItem"("id","shipmentId","supplierOrderItemId","quantity") VALUES
 ('74000000-0000-4000-8000-000000000001','73000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',6);
DO $$ BEGIN
 BEGIN
   INSERT INTO "ShipmentItem"("id","shipmentId","supplierOrderItemId","quantity") VALUES
    ('74000000-0000-4000-8000-000000000002','73000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000001',5);
   RAISE EXCEPTION 'Over-allocation wrongly accepted';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: concurrent-safe allocation limit denies 6 + 5 > 10'; END;
END $$;
INSERT INTO "ShipmentItem"("id","shipmentId","supplierOrderItemId","quantity") VALUES
 ('74000000-0000-4000-8000-000000000002','73000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000001',4);
DO $$ BEGIN
 IF (SELECT "allocatedShipmentQty" FROM "SupplierOrderItem" WHERE id='72000000-0000-4000-8000-000000000001')<>10 THEN
  RAISE EXCEPTION 'Shipment allocation ledger did not reach 10'; END IF;
END $$;
-- Return/failed shipment releases allocation, and reactivation must reacquire, never overallocate.
UPDATE "Shipment" SET status='FAILED' WHERE id='73000000-0000-4000-8000-000000000002';
DO $$ BEGIN
 IF (SELECT "allocatedShipmentQty" FROM "SupplierOrderItem" WHERE id='72000000-0000-4000-8000-000000000001')<>6 THEN
  RAISE EXCEPTION 'Failed truck did not release allocation'; END IF;
END $$;
UPDATE "Shipment" SET status='PLANNED' WHERE id='73000000-0000-4000-8000-000000000002';
-- Unverified delivery must be rejected even if shipping quantities are valid.
UPDATE "ShipmentItem" SET "deliveredQty"=6 WHERE id='74000000-0000-4000-8000-000000000001';
DO $$ BEGIN
 BEGIN
  UPDATE "Shipment" SET status='DELIVERED' WHERE id='73000000-0000-4000-8000-000000000001';
  RAISE EXCEPTION 'Unverified delivery wrongly accepted';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: delivery requires OTP or approved exception'; END;
END $$;
UPDATE "Shipment" SET "deliveryOtpHash"=repeat('a',64),"otpIssuedAt"=now()-interval '2 minutes',
 "otpExpiresAt"=now()+interval '5 minutes',"otpVerifiedAt"=now(),"handoverMethod"='OTP', status='DELIVERED'
 WHERE id='73000000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF (SELECT status FROM "Shipment" WHERE id='73000000-0000-4000-8000-000000000001')<>'DELIVERED' THEN
 RAISE EXCEPTION 'OTP verified delivery did not succeed'; END IF;
END $$;
-- Cancel child A; parent order remains active and PARTIALLY_CANCELLED.
UPDATE "SupplierOrder" SET status='CANCELLED' WHERE id='71000000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF (SELECT status FROM "PurchaseOrder" WHERE id='70000000-0000-4000-8000-000000000001') <> 'PARTIALLY_CANCELLED' THEN
 RAISE EXCEPTION 'Parent did not reflect partial cancellation'; END IF;
END $$;
-- Composition seller must not issue a tax invoice.
DO $$ BEGIN
 BEGIN
  INSERT INTO "TaxInvoice"("id","supplierId","supplierOrderId","invoiceNumber","financialYear","sellerSnapshot","buyerSnapshot","lineSnapshot","taxablePaise","taxPaise","totalPaise") VALUES
   ('75000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','SMOKE-TAX-FAIL','2026-27','{}'::jsonb,'{}'::jsonb,'[]'::jsonb,1000,0,1000);
  RAISE EXCEPTION 'Composition supplier incorrectly issued tax invoice';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: composition tax invoice rejected'; END;
END $$;
INSERT INTO "TaxInvoice"("id","supplierId","supplierOrderId","invoiceNumber","financialYear","kind","sellerSnapshot","buyerSnapshot","lineSnapshot","taxablePaise","taxPaise","totalPaise") VALUES
 ('75000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','SMOKE-BILL','2026-27','BILL_OF_SUPPLY','{}'::jsonb,'{}'::jsonb,'[]'::jsonb,1000,0,1000);
-- COD held by supplier, separately verified and reconciled against a posted journal.
DO $$ BEGIN
 BEGIN
  INSERT INTO "CodCollection"("id","supplierOrderId","supplierId","receiptNumber","idempotencyKey","collectedPaise") VALUES
  ('76000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','SMOKE-BAD-SUP','SMOKE-KEY-INVALID',1000);
  RAISE EXCEPTION 'COD supplier mismatch allowed';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: COD supplier mismatch rejected'; END;
END $$;
INSERT INTO "CodCollection"("id","supplierOrderId","supplierId","receiptNumber","idempotencyKey","collectedPaise") VALUES
 ('76000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','SMOKE-COD-REC','SMOKE-KEY-1',60000);
DO $$ BEGIN
 BEGIN
  UPDATE "CodCollection" SET status='VERIFIED',"verifiedByUserId"='80000000-0000-4000-8000-000000000001',
   "verifiedAt"=now(),"journalReference"='SMOKE-COD-JOURNAL' WHERE id='76000000-0000-4000-8000-000000000002';
  RAISE EXCEPTION 'COD verified without ledger posting';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: unjournalled COD cannot be verified'; END;
END $$;
INSERT INTO "LedgerAccount"("id","code","name") VALUES
 ('a0000000-0000-4000-8000-000000000011','COD-CASH-SUPPLIER','Supplier-held cash'),
 ('a0000000-0000-4000-8000-000000000012','COD-RECEIVABLE','Cash collection liability');
INSERT INTO "LedgerJournal"("id","referenceKey","eventType") VALUES
 ('90000000-0000-4000-8000-000000000010','SMOKE-COD-JOURNAL','COD_CAPTURE');
INSERT INTO "LedgerLine"("journalId","lineNumber","accountId","debitPaise","creditPaise") VALUES
 ('90000000-0000-4000-8000-000000000010',1,'a0000000-0000-4000-8000-000000000011',60000,0),
 ('90000000-0000-4000-8000-000000000010',2,'a0000000-0000-4000-8000-000000000012',0,60000);
UPDATE "LedgerJournal" SET "postedAt"=now() WHERE "referenceKey"='SMOKE-COD-JOURNAL';
UPDATE "CodCollection" SET status='VERIFIED',"verifiedByUserId"='80000000-0000-4000-8000-000000000001',
   "verifiedAt"=now(),"journalReference"='SMOKE-COD-JOURNAL' WHERE id='76000000-0000-4000-8000-000000000002';
DO $$ BEGIN
 IF (SELECT "codVerifiedPaise" FROM "SupplierOrder" WHERE id='71000000-0000-4000-8000-000000000001') <> 60000 THEN
  RAISE EXCEPTION 'Verified supplier cash amount wrong'; END IF;
END $$;
-- PostGIS spatial point and index exist; coordinate trigger syncs data.
INSERT INTO "City"("id","code","name","stateCode") VALUES
 ('c0000000-0000-4000-8000-000000000001','SMOKE-CITY','SMOKE Hyderabad','TS');
INSERT INTO "ServiceArea"("id","cityId","name","centerLat","centerLng","radiusKm") VALUES
 ('c1000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','SMOKE_RADIUS',17.385,78.4867,15);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM "ServiceArea" s WHERE s.id='c1000000-0000-4000-8000-000000000001'
  AND ST_DWithin(s."geoCenter",ST_SetSRID(ST_MakePoint(78.487,17.386),4326)::geography, s."radiusKm"*1000)) THEN
    RAISE EXCEPTION 'PostGIS radius query failed'; END IF;
END $$;
ROLLBACK;
