BEGIN;
ALTER TABLE "SupplierQuote" ADD COLUMN "freightSnapshot" JSONB;
ALTER TABLE "SupplierOrder" ADD COLUMN "freightSnapshot" JSONB;
ALTER TABLE "SupplierQuote" ADD CONSTRAINT "supplier_quote_freight_amount" CHECK ("freightSnapshot" IS NULL OR (jsonb_typeof("freightSnapshot")='object' AND ("freightSnapshot"->>'amountPaise') ~ '^[0-9]+$' AND ("freightSnapshot"->>'amountPaise')::numeric="deliveryPaise"));
ALTER TABLE "SupplierOrder" ADD CONSTRAINT "supplier_order_freight_amount" CHECK ("freightSnapshot" IS NULL OR (jsonb_typeof("freightSnapshot")='object' AND ("freightSnapshot"->>'amountPaise') ~ '^[0-9]+$' AND ("freightSnapshot"->>'amountPaise')::numeric="deliveryPaise"));
CREATE FUNCTION buildto_freight_snapshot_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW."freightSnapshot" IS DISTINCT FROM OLD."freightSnapshot" THEN
  RAISE EXCEPTION 'Accepted freight calculation is immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER buildto_quote_freight_immutable BEFORE UPDATE OF "freightSnapshot" ON "SupplierQuote" FOR EACH ROW EXECUTE FUNCTION buildto_freight_snapshot_immutable();
CREATE TRIGGER buildto_order_freight_immutable BEFORE UPDATE OF "freightSnapshot" ON "SupplierOrder" FOR EACH ROW EXECUTE FUNCTION buildto_freight_snapshot_immutable();
COMMIT;
