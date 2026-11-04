-- Buildto V2.1 PR14: additive refund and statutory credit-note controls.
-- Apply only using the guarded V2.1 migration workflow to disposable CI or approved staging.
BEGIN;

ALTER TABLE "RefundRequest" ADD COLUMN "returnRequestId" UUID;
ALTER TABLE "TaxInvoice" ADD COLUMN "sourceInvoiceId" UUID,
                         ADD COLUMN "returnRequestId" UUID;
CREATE UNIQUE INDEX "RefundRequest_returnRequestId_key" ON "RefundRequest"("returnRequestId");
CREATE UNIQUE INDEX "TaxInvoice_returnRequestId_key" ON "TaxInvoice"("returnRequestId");
CREATE INDEX "TaxInvoice_sourceInvoiceId_idx" ON "TaxInvoice"("sourceInvoiceId");
ALTER TABLE "RefundRequest" ADD CONSTRAINT "RefundRequest_returnRequestId_fkey"
 FOREIGN KEY ("returnRequestId") REFERENCES "ReturnRequest"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "TaxInvoice_sourceInvoiceId_fkey"
 FOREIGN KEY ("sourceInvoiceId") REFERENCES "TaxInvoice"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TaxInvoice" ADD CONSTRAINT "TaxInvoice_returnRequestId_fkey"
 FOREIGN KEY ("returnRequestId") REFERENCES "ReturnRequest"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- No synthetic SUCCESS/APPROVED records without a reviewer, provider reference and completion time.
ALTER TABLE "RefundRequest" ADD CONSTRAINT "refund_proof_required" CHECK (
  ("status" NOT IN ('APPROVED','PROCESSING','SUCCEEDED') OR
   ("approvedById" IS NOT NULL AND "approvedAt" IS NOT NULL))
  AND ("status" NOT IN ('PROCESSING','SUCCEEDED') OR "providerRefundRef" IS NOT NULL)
  AND ("status" <> 'SUCCEEDED' OR "completedAt" IS NOT NULL)
);
CREATE FUNCTION buildto_guard_return_refund() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_id uuid; return_status "ReturnStatus";
BEGIN
 IF NEW."returnRequestId" IS NULL THEN
  RAISE EXCEPTION 'New V2.1 refunds require an immutable return link' USING ERRCODE='23514';
 END IF;
 SELECT s."purchaseOrderId",r."status" INTO parent_id,return_status
 FROM "ReturnRequest" r JOIN "SupplierOrder" s ON s.id=r."supplierOrderId"
 WHERE r.id=NEW."returnRequestId";
 IF parent_id IS DISTINCT FROM NEW."purchaseOrderId" OR return_status IS DISTINCT FROM 'RECEIVED' THEN
  RAISE EXCEPTION 'Refund belongs to received return and purchase order' USING ERRCODE='23514';
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'REQUESTED' OR NEW."providerRefundRef" IS NOT NULL OR
    NEW."approvedById" IS NOT NULL OR NEW."completedAt" IS NOT NULL THEN
   RAISE EXCEPTION 'Refund must begin as unapproved request' USING ERRCODE='23514';
  END IF;
 ELSE
  IF NEW."returnRequestId" IS DISTINCT FROM OLD."returnRequestId"
    OR NEW."paymentAttemptId" IS DISTINCT FROM OLD."paymentAttemptId"
    OR NEW."purchaseOrderId" IS DISTINCT FROM OLD."purchaseOrderId"
    OR NEW."amountPaise" IS DISTINCT FROM OLD."amountPaise"
    OR NEW."reason" IS DISTINCT FROM OLD."reason"
    OR NEW."requestKey" IS DISTINCT FROM OLD."requestKey" THEN
   RAISE EXCEPTION 'Refund contractual ownership, amount and key are immutable' USING ERRCODE='23514';
  END IF;
  IF OLD.status='SUCCEEDED' AND NEW IS DISTINCT FROM OLD THEN
   RAISE EXCEPTION 'Verified refund is immutable' USING ERRCODE='23514';
  END IF;
  IF OLD."providerRefundRef" IS NOT NULL AND NEW."providerRefundRef" IS DISTINCT FROM OLD."providerRefundRef" THEN
   RAISE EXCEPTION 'Refund provider identity is immutable' USING ERRCODE='23514';
  END IF;
  IF OLD.status='REQUESTED' AND NEW.status NOT IN ('REQUESTED','APPROVED','REJECTED') OR
    OLD.status='APPROVED' AND NEW.status NOT IN ('APPROVED','PROCESSING','SUCCEEDED','MANUAL_REVIEW') OR
    OLD.status='PROCESSING' AND NEW.status NOT IN ('PROCESSING','SUCCEEDED','MANUAL_REVIEW') OR
    OLD.status IN ('REJECTED','FAILED','MANUAL_REVIEW') AND NEW.status<>OLD.status THEN
   RAISE EXCEPTION 'Invalid refund status transition' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_return_refund_guard BEFORE INSERT OR UPDATE ON "RefundRequest"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_return_refund();

-- A statutory GST credit note is identified with the exact original supplier tax invoice
-- and a physically received return. Amounts are strictly FULL-INVOICE in PR14.
-- Source invoice is not deleted, financial snapshots are never rewritten.
CREATE FUNCTION buildto_guard_return_credit_note() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE original "TaxInvoice"%ROWTYPE; returned_supplier_order uuid; return_status "ReturnStatus";
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD."kind"='CREDIT_NOTE' OR EXISTS(SELECT 1 FROM "TaxInvoice" WHERE "sourceInvoiceId"=OLD.id) THEN
   RAISE EXCEPTION 'Linked statutory invoice evidence is append-only' USING ERRCODE='23514';
  END IF;
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD."kind"='CREDIT_NOTE' AND NEW IS DISTINCT FROM OLD THEN
   RAISE EXCEPTION 'Issued GST credit note is immutable' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM "TaxInvoice" WHERE "sourceInvoiceId"=OLD.id) AND
    (NEW."totalPaise" IS DISTINCT FROM OLD."totalPaise" OR
     NEW."taxablePaise" IS DISTINCT FROM OLD."taxablePaise" OR
     NEW."taxPaise" IS DISTINCT FROM OLD."taxPaise" OR
     NEW."cgstPaise" IS DISTINCT FROM OLD."cgstPaise" OR
     NEW."sgstPaise" IS DISTINCT FROM OLD."sgstPaise" OR
     NEW."utgstPaise" IS DISTINCT FROM OLD."utgstPaise" OR
     NEW."igstPaise" IS DISTINCT FROM OLD."igstPaise" OR
     NEW."cessPaise" IS DISTINCT FROM OLD."cessPaise" OR
     NEW."invoiceNumber" IS DISTINCT FROM OLD."invoiceNumber" OR
     NEW."financialYear" IS DISTINCT FROM OLD."financialYear" OR
     NEW."issuedAt" IS DISTINCT FROM OLD."issuedAt" OR
     NEW."supplierOrderId" IS DISTINCT FROM OLD."supplierOrderId" OR
     NEW."sellerSnapshot" IS DISTINCT FROM OLD."sellerSnapshot" OR
     NEW."buyerSnapshot" IS DISTINCT FROM OLD."buyerSnapshot" OR
     NEW."lineSnapshot" IS DISTINCT FROM OLD."lineSnapshot" OR
     NEW."status" IS DISTINCT FROM OLD."status") THEN
   RAISE EXCEPTION 'Source invoice for issued credit note is immutable' USING ERRCODE='23514';
  END IF;
 END IF;
 IF NEW."kind"='CREDIT_NOTE' THEN
  IF NEW."sourceInvoiceId" IS NULL OR NEW."returnRequestId" IS NULL THEN
   RAISE EXCEPTION 'Credit notes require source and returned order' USING ERRCODE='23514';
  END IF;
  SELECT * INTO original FROM "TaxInvoice" WHERE id=NEW."sourceInvoiceId" FOR UPDATE;
  SELECT "supplierOrderId","status" INTO returned_supplier_order,return_status
   FROM "ReturnRequest" WHERE id=NEW."returnRequestId";
  IF original.id IS NULL OR original."kind"<>'TAX_INVOICE' OR original."status"<>'ISSUED'
    OR original."supplierId" IS DISTINCT FROM NEW."supplierId"
    OR original."supplierOrderId" IS DISTINCT FROM NEW."supplierOrderId"
    OR returned_supplier_order IS DISTINCT FROM NEW."supplierOrderId"
    OR return_status IS DISTINCT FROM 'RECEIVED' THEN
   RAISE EXCEPTION 'Credit note must reverse original tax invoice for received return' USING ERRCODE='23514';
  END IF;
  IF NEW."totalPaise" <> original."totalPaise" OR
    NEW."taxablePaise" <> original."taxablePaise" OR
    NEW."taxPaise" <> original."taxPaise" OR
    NEW."cgstPaise" <> original."cgstPaise" OR
    NEW."sgstPaise" <> original."sgstPaise" OR
    NEW."utgstPaise" <> original."utgstPaise" OR
    NEW."igstPaise" <> original."igstPaise" OR
    NEW."cessPaise" <> original."cessPaise" THEN
   RAISE EXCEPTION 'PR14 only permits exact full-invoice tax credit' USING ERRCODE='23514';
  END IF;
  IF TG_OP='UPDATE' AND
   (NEW."sourceInvoiceId" IS DISTINCT FROM OLD."sourceInvoiceId" OR
    NEW."returnRequestId" IS DISTINCT FROM OLD."returnRequestId") THEN
   RAISE EXCEPTION 'Credit note ownership is immutable' USING ERRCODE='23514';
  END IF;
 ELSIF NEW."sourceInvoiceId" IS NOT NULL OR NEW."returnRequestId" IS NOT NULL THEN
  RAISE EXCEPTION 'Only credit notes may link return or original tax invoice' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_return_credit_note_guard BEFORE INSERT OR UPDATE OR DELETE ON "TaxInvoice"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_return_credit_note();

COMMIT;
