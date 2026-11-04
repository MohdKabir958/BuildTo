-- PR15 additive supplier beneficiary/payout evidence guards.
-- Existing data violating single-payout/unique provider account fails CLOSED in migration.
BEGIN;
ALTER TABLE "SupplierPayoutAccount"
 ADD COLUMN "validationRef" VARCHAR(180),
 ADD COLUMN "registeredById" UUID,
 ADD COLUMN "approvedById" UUID;
CREATE UNIQUE INDEX "SupplierPayoutAccount_providerTokenRef_key" ON "SupplierPayoutAccount"("providerTokenRef");
CREATE UNIQUE INDEX "SupplierPayoutAccount_validationRef_key" ON "SupplierPayoutAccount"("validationRef");
CREATE UNIQUE INDEX "PayoutTransfer_settlementId_key" ON "PayoutTransfer"("settlementId");
CREATE UNIQUE INDEX "buildto_one_active_payout_beneficiary"
 ON "SupplierPayoutAccount"("supplierId") WHERE "active"=true;

ALTER TABLE "SupplierPayoutAccount"
 ADD CONSTRAINT "payout_beneficiary_approval_proof" CHECK (
  NOT "active" OR ("providerTokenRef" ~ '^fa_[A-Za-z0-9]{8,60}$'
   AND "validationRef" ~ '^fav_[A-Za-z0-9]{8,60}$'
   AND "bankAccountLast4" ~ '^[0-9]{4}$'
   AND "ifsc" ~ '^[A-Z]{4}0[A-Z0-9]{6}$'
   AND length(trim("accountHolder"))>=3
   AND "registeredById" IS NOT NULL AND "approvedById" IS NOT NULL
   AND "registeredById"<>"approvedById" AND "verifiedAt" IS NOT NULL)
 );
ALTER TABLE "PayoutTransfer"
 ADD CONSTRAINT "payout_transfer_positive" CHECK ("amountPaise">0);
ALTER TABLE "PayoutTransfer"
 ADD CONSTRAINT "payout_transfer_terminal_proof" CHECK (
  ("status" NOT IN ('PROCESSING','SUCCEEDED','FAILED') OR
    "providerRef" ~ '^pout_[A-Za-z0-9]{8,60}$')
  AND ("status" <> 'SUCCEEDED' OR "completedAt" IS NOT NULL)
 );

CREATE FUNCTION buildto_guard_payout_beneficiary() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW."active" OR NEW."verifiedAt" IS NOT NULL OR
    NEW."approvedById" IS NOT NULL OR NEW."registeredById" IS NULL THEN
   RAISE EXCEPTION 'Beneficiary must begin pending independent approval' USING ERRCODE='23514';
  END IF;
 ELSE
  IF NEW."supplierId" IS DISTINCT FROM OLD."supplierId" OR
   NEW."providerTokenRef" IS DISTINCT FROM OLD."providerTokenRef" OR
   NEW."bankAccountLast4" IS DISTINCT FROM OLD."bankAccountLast4" OR
   NEW."accountHolder" IS DISTINCT FROM OLD."accountHolder" OR
   NEW."ifsc" IS DISTINCT FROM OLD."ifsc" OR
   NEW."validationRef" IS DISTINCT FROM OLD."validationRef" OR
   NEW."registeredById" IS DISTINCT FROM OLD."registeredById" THEN
   RAISE EXCEPTION 'Registered beneficiary token and verified banking identity are immutable'
    USING ERRCODE='23514';
  END IF;
  IF OLD."verifiedAt" IS NOT NULL AND
   (NEW."verifiedAt" IS DISTINCT FROM OLD."verifiedAt" OR
    NEW."approvedById" IS DISTINCT FROM OLD."approvedById") THEN
   RAISE EXCEPTION 'Approved beneficiary proof cannot be rewritten' USING ERRCODE='23514';
  END IF;
  IF NEW."active" AND NOT OLD."active" AND
   (NEW."approvedById" IS NULL OR
    NEW."registeredById" IS NOT DISTINCT FROM NEW."approvedById") THEN
   RAISE EXCEPTION 'Beneficiary requires independent second approver' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_payout_beneficiary_guard
 BEFORE INSERT OR UPDATE ON "SupplierPayoutAccount"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_payout_beneficiary();

CREATE FUNCTION buildto_guard_payout_transfer() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s "Settlement"%ROWTYPE; a "SupplierPayoutAccount"%ROWTYPE;
BEGIN
 SELECT * INTO s FROM "Settlement" WHERE id=NEW."settlementId";
 SELECT * INTO a FROM "SupplierPayoutAccount" WHERE id=NEW."payoutAccountId";
 IF s.id IS NULL OR a.id IS NULL OR s."supplierId" IS DISTINCT FROM a."supplierId" OR
  NEW."amountPaise" IS DISTINCT FROM s."payablePaise" THEN
  RAISE EXCEPTION 'Payout must match approved supplier payable and its own bank beneficiary'
   USING ERRCODE='23514';
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'PENDING' OR NEW."providerRef" IS NOT NULL OR
   NEW."completedAt" IS NOT NULL OR s.status<>'APPROVED' OR
   NOT a."active" OR a."verifiedAt" IS NULL THEN
   RAISE EXCEPTION 'Payout must begin as approved but unexecuted intent' USING ERRCODE='23514';
  END IF;
 ELSE
  IF NEW."settlementId" IS DISTINCT FROM OLD."settlementId" OR
   NEW."payoutAccountId" IS DISTINCT FROM OLD."payoutAccountId" OR
   NEW."amountPaise" IS DISTINCT FROM OLD."amountPaise" OR
   NEW."requestKey" IS DISTINCT FROM OLD."requestKey" THEN
   RAISE EXCEPTION 'Payout identity and amount are immutable' USING ERRCODE='23514';
  END IF;
  IF OLD."providerRef" IS NOT NULL AND
   NEW."providerRef" IS DISTINCT FROM OLD."providerRef" THEN
   RAISE EXCEPTION 'Payout provider identity cannot change' USING ERRCODE='23514';
  END IF;
  IF OLD.status IN ('SUCCEEDED','FAILED') AND NEW IS DISTINCT FROM OLD THEN
   RAISE EXCEPTION 'Terminal provider payout status is immutable' USING ERRCODE='23514';
  END IF;
  IF OLD.status='PENDING' AND NEW.status NOT IN ('PENDING','PROCESSING','SUCCEEDED','FAILED') OR
   OLD.status='PROCESSING' AND NEW.status NOT IN ('PROCESSING','SUCCEEDED','FAILED') THEN
   RAISE EXCEPTION 'Invalid payout status transition' USING ERRCODE='23514';
  END IF;
  IF NEW.status='SUCCEEDED' AND OLD.status<>'SUCCEEDED' AND NOT EXISTS(
   SELECT 1 FROM "LedgerJournal" WHERE "referenceKey"='payout:processed:'||NEW.id::text
    AND "postedAt" IS NOT NULL) THEN
   RAISE EXCEPTION 'Provider-processed payout requires balanced posted clearing journal'
    USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_payout_transfer_guard
 BEFORE INSERT OR UPDATE ON "PayoutTransfer"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_payout_transfer();

CREATE FUNCTION buildto_guard_settlement_paid() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.status='PAID' AND OLD.status<>'PAID' THEN
  IF NOT EXISTS(
   SELECT 1 FROM "PayoutTransfer" p WHERE p."settlementId"=NEW.id
    AND p."status"='SUCCEEDED' AND p."amountPaise"=NEW."payablePaise"
    AND p."providerRef" IS NOT NULL AND p."completedAt" IS NOT NULL)
    OR NEW."paidAt" IS NULL THEN
   RAISE EXCEPTION 'Paid settlement requires exact provider-processed payout'
    USING ERRCODE='23514';
  END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status='PAID' AND NEW IS DISTINCT FROM OLD THEN
  RAISE EXCEPTION 'Paid supplier settlement is immutable; post compensating journal'
   USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER buildto_settlement_paid_guard
 BEFORE UPDATE ON "Settlement"
 FOR EACH ROW EXECUTE FUNCTION buildto_guard_settlement_paid();
COMMIT;
