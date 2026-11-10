import {createHash} from 'node:crypto';
import {readFileSync,readdirSync} from 'node:fs';
import {resolve} from 'node:path';
import type {PrismaClient} from '../../generated/buildto-v21';

/** Reviewed release migrations only. Adding a migration requires a PR and a
 * deliberate update to this gate; it is never auto-trusted by file discovery. */
export const REVIEWED_V21_MIGRATIONS=[
 '20261103_buildto_v21_initial',
 '20261104_return_refund_credit_note_link',
 '20261104_payout_beneficiary_reconciliation',
 '20261107_step1_partial_shipment_allocation'
] as const;

type MigrationRecord={
 migration_name:string;checksum:string;
 finished_at:Date|null;rolled_back_at:Date|null;
};
const MIGRATION_ROOT=resolve(__dirname,'../../prisma/v21/migrations');
const checksums=REVIEWED_V21_MIGRATIONS.map(name=>({
 name,checksum:createHash('sha256').update(
  readFileSync(resolve(MIGRATION_ROOT,name,'migration.sql'))).digest('hex')
}));
/** Reject unknown migrations, incomplete/rolled back history and changed SQL.
 * No untrusted text (SQL, paths or database values) appears in the errors. */
export function assertMigrationLedgerRecords(rows:readonly MigrationRecord[]):void{
 const disk=readdirSync(MIGRATION_ROOT,{withFileTypes:true})
  .filter(f=>f.isDirectory()&&/^\d{8,14}_[A-Za-z0-9_]+$/.test(f.name))
  .map(f=>f.name).sort();
 const expected=checksums.map(x=>x.name).sort();
 if(JSON.stringify(disk)!==JSON.stringify(expected))
  throw new Error('V21_UNREVIEWED_MIGRATION_FILE: filesystem migration set needs review.');
 if(rows.length!==checksums.length)
  throw new Error('V21_MIGRATION_LEDGER_INCOMPLETE: migration history differs from the reviewed release.');
 const actual=new Map<string,MigrationRecord>();
 for(const row of rows){
  if(actual.has(row.migration_name))
   throw new Error('V21_MIGRATION_LEDGER_DUPLICATE: migration history is not unambiguous.');
  actual.set(row.migration_name,row);
 }
 for(const expectedMigration of checksums){
  const row=actual.get(expectedMigration.name);
  if(!row||!row.finished_at||row.rolled_back_at||
   row.checksum!==expectedMigration.checksum)
   throw new Error('V21_MIGRATION_CHECKSUM_MISMATCH: a reviewed migration is absent, incomplete or modified.');
 }
}
export async function assertV21AllMigrationsApplied(db:Pick<PrismaClient,'$queryRaw'>):Promise<void>{
 let rows:MigrationRecord[];
 try{
  rows=await db.$queryRaw<MigrationRecord[]>`
   SELECT migration_name,checksum,finished_at,rolled_back_at
   FROM "_prisma_migrations"
   ORDER BY started_at ASC
  `;
 }catch{
  throw new Error('V21_MIGRATION_LEDGER_REQUIRED: cannot read verified migration history.');
 }
 assertMigrationLedgerRecords(rows);
}

/** Return only aggregate counts; do not expose customer IDs, tax documents,
 * provider secrets, bank references or the underlying SQL exception to clients. */
export interface V21IntegrityCounts{
 unbalancedPostedJournals:number;
 paidWithoutProcessedTransfer:number;
 processedTransferWithoutPaidSettlement:number;
 providerProcessedTransferWithoutJournal:number;
 refundProcessedWithoutJournal:number;
 malformedCreditNotes:number;
 invalidActiveBeneficiaries:number;
}
export const INTEGRITY_COUNTERS=[
 'unbalancedPostedJournals','paidWithoutProcessedTransfer',
 'processedTransferWithoutPaidSettlement','providerProcessedTransferWithoutJournal',
 'refundProcessedWithoutJournal','malformedCreditNotes','invalidActiveBeneficiaries'
] as const;
export function assertV21FinancialCounts(counts:V21IntegrityCounts):void{
 if(INTEGRITY_COUNTERS.some(key=>!Number.isSafeInteger(counts[key])||
   counts[key]<0||counts[key]>0))
  throw new Error('V21_FINANCIAL_INTEGRITY_BLOCKED: finance records require independent investigation.');
}
export async function inspectV21FinanceIntegrity(db:Pick<PrismaClient,'$queryRaw'>):Promise<V21IntegrityCounts>{
 let rows:V21IntegrityCounts[];
 try{
  rows=await db.$queryRaw<V21IntegrityCounts[]>`
   SELECT
    (SELECT COUNT(*)::integer FROM "LedgerJournal" j
      WHERE j."postedAt" IS NOT NULL AND
       (SELECT COALESCE(SUM(l."debitPaise"),0)
        FROM "LedgerLine" l WHERE l."journalId"=j.id)
       <> (SELECT COALESCE(SUM(l."creditPaise"),0)
        FROM "LedgerLine" l WHERE l."journalId"=j.id)
    ) AS "unbalancedPostedJournals",
    (SELECT COUNT(*)::integer FROM "Settlement" s
      WHERE s.status='PAID' AND NOT EXISTS(
        SELECT 1 FROM "PayoutTransfer" p
        WHERE p."settlementId"=s.id AND p.status='SUCCEEDED'
         AND p."amountPaise"=s."payablePaise"
         AND p."providerRef" IS NOT NULL AND p."completedAt" IS NOT NULL)
    ) AS "paidWithoutProcessedTransfer",
    (SELECT COUNT(*)::integer FROM "PayoutTransfer" p
      JOIN "Settlement" s ON s.id=p."settlementId"
      WHERE p.status='SUCCEEDED' AND
       (s.status<>'PAID' OR s."paidAt" IS NULL OR
        p."completedAt" IS NULL OR p."providerRef" IS NULL OR
        p."amountPaise"<>s."payablePaise")
    ) AS "processedTransferWithoutPaidSettlement",
    (SELECT COUNT(*)::integer FROM "PayoutTransfer" p
      WHERE p.status='SUCCEEDED' AND NOT EXISTS(
       SELECT 1 FROM "LedgerJournal" j
       WHERE j."referenceKey"='payout:processed:'||p.id::text
         AND j."postedAt" IS NOT NULL)
    ) AS "providerProcessedTransferWithoutJournal",
    (SELECT COUNT(*)::integer FROM "RefundRequest" r
      WHERE r.status='SUCCEEDED' AND NOT EXISTS(
       SELECT 1 FROM "LedgerJournal" j
       WHERE j."referenceKey"='refund:processed:'||r.id::text
         AND j."postedAt" IS NOT NULL)
    ) AS "refundProcessedWithoutJournal",
    (SELECT COUNT(*)::integer FROM "TaxInvoice" c
      LEFT JOIN "TaxInvoice" origin ON origin.id=c."sourceInvoiceId"
      LEFT JOIN "ReturnRequest" rr ON rr.id=c."returnRequestId"
      WHERE c.kind='CREDIT_NOTE' AND
       (origin.id IS NULL OR origin.kind<>'TAX_INVOICE' OR
        origin.status<>'ISSUED' OR rr.status<>'RECEIVED' OR
        c."supplierOrderId"<>origin."supplierOrderId" OR
        c."supplierId"<>origin."supplierId" OR
        c."supplierOrderId"<>rr."supplierOrderId" OR
        c."totalPaise"<>origin."totalPaise" OR
        c."taxPaise"<>origin."taxPaise" OR
        c."taxablePaise"<>origin."taxablePaise")
    ) AS "malformedCreditNotes",
    (SELECT COUNT(*)::integer FROM "SupplierPayoutAccount" a
      WHERE a."active"=true AND
       (a."verifiedAt" IS NULL OR a."registeredById" IS NULL OR
        a."approvedById" IS NULL OR
        a."approvedById"=a."registeredById" OR
        a."providerTokenRef" IS NULL OR a."validationRef" IS NULL)
    ) AS "invalidActiveBeneficiaries"
  `;
 }catch{
  throw new Error('V21_FINANCIAL_INSPECTION_FAILED: read-only finance inspection unavailable.');
 }
 if(rows.length!==1||!rows[0])
  throw new Error('V21_FINANCIAL_INSPECTION_FAILED: invalid inspection result.');
 assertV21FinancialCounts(rows[0]);
 return rows[0];
}
/** Startup, CI and explicit staging preflight; no schema modification. */
export async function assertV21ReleaseIntegrity(db:Pick<PrismaClient,'$queryRaw'>):Promise<void>{
 await assertV21AllMigrationsApplied(db);
 await inspectV21FinanceIntegrity(db);
}
