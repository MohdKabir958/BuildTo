import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission,isUuid} from './permissions';
import {lockSettlement,independence,payoutEvent} from './payout-service';

/** Human attestation of an independently inspected bank debit.
 * This is not a verified bank statement API feed. */
export async function attestBankDebit(db:PrismaClient,userId:string,payoutId:string,raw:unknown){
 if(!isUuid(payoutId))throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||
  Object.keys(raw).some(k=>!['bankStatementReference','providerUtr'].includes(k)))
  throw new ApiError(400,'INVALID_BANK_EVIDENCE','Statement and UTR required.');
 const r=raw as Record<string,unknown>;
 if(typeof r.bankStatementReference!=='string'||
  !/^[A-Za-z0-9][A-Za-z0-9_./:-]{11,119}$/.test(r.bankStatementReference)||
  typeof r.providerUtr!=='string'||!/^[A-Za-z0-9_-]{8,60}$/.test(r.providerUtr))
  throw new ApiError(400,'INVALID_BANK_EVIDENCE','Invalid bank statement reference or UTR.');
 const bankReference=r.bankStatementReference as string,bankUtr=r.providerUtr as string;
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  const p=await tx.payoutTransfer.findUnique({where:{id:payoutId},
   select:{settlementId:true,status:true,providerRef:true,amountPaise:true,
    account:{select:{supplierId:true}}}});
  if(!p)throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
  await lockSettlement(tx,p.settlementId);
  await independence(tx,userId,p.account.supplierId);
  if(p.status!=='SUCCEEDED'||!p.providerRef)
   throw new ApiError(409,'BANK_PAYOUT_NOT_PROCESSED',
    'Bank-debit attestation requires a verified provider-processed payout.');
  await tx.$queryRaw(Prisma.sql`SELECT pg_advisory_xact_lock(
   hashtextextended(${'bank-statement:'+bankReference},73103)) IS NULL AS locked`);
  const existing=await tx.auditEvent.findFirst({where:{
   entityType:'PayoutTransfer',entityId:payoutId,
   action:'PAYOUT_BANK_STATEMENT_HUMAN_ATTESTED'},
   select:{afterState:true}});
  if(existing){
   const before=existing.afterState as Record<string,unknown>|null;
   if(before?.bankStatementReference!==bankReference||
    before?.providerUtr!==bankUtr)
    throw new ApiError(409,'BANK_STATEMENT_ATTESTATION_IMMUTABLE',
     'Already attested payout has different bank evidence.');
   return {payoutId,replayed:true,bankStatementAttested:true,
    bankEvidenceType:'HUMAN_ATTESTATION',bankStatementAPIReconciled:false};
  }
  const provider=await tx.auditEvent.findFirst({where:{
   entityType:'PayoutTransfer',entityId:payoutId,action:'PAYOUT_PROVIDER_PROCESSED'},
   select:{afterState:true,actorUserId:true}});
  const requested=await tx.auditEvent.findFirst({where:{
   entityType:'PayoutTransfer',entityId:payoutId,action:'PAYOUT_INTENT_RESERVED_NOT_SENT'},
   select:{actorUserId:true}});
  const evidence=provider?.afterState as Record<string,unknown>|undefined;
  if(!provider?.actorUserId||provider.actorUserId===userId||
   requested?.actorUserId===userId)
   throw new ApiError(403,'BANK_EVIDENCE_INDEPENDENT_APPROVER_REQUIRED',
    'A different finance reviewer must match the external bank statement.');
  if(evidence?.providerUtr!==bankUtr||evidence?.amountPaise!==p.amountPaise.toString())
   throw new ApiError(409,'BANK_STATEMENT_UTR_MISMATCH',
    'Bank-statement UTR or provider amount cannot be matched.');
  const duplicate=await tx.auditEvent.findFirst({where:{
   entityType:'PayoutTransfer',action:'PAYOUT_BANK_STATEMENT_HUMAN_ATTESTED',
   afterState:{path:['bankStatementReference'],equals:bankReference}
  },select:{id:true}});
  if(duplicate)throw new ApiError(409,'BANK_STATEMENT_REFERENCE_REUSED',
   'Bank statement entry is already attributed to another payout.');
  await payoutEvent(tx,userId,payoutId,'PAYOUT_BANK_STATEMENT_HUMAN_ATTESTED',{
   bankStatementReference:bankReference,providerUtr:bankUtr,
   amountPaise:p.amountPaise.toString(),bankStatementAPIReconciled:false,
   attestationType:'INDEPENDENT_MANUAL_REVIEW'});
  return {payoutId,replayed:false,bankStatementAttested:true,
   bankEvidenceType:'HUMAN_ATTESTATION',bankStatementAPIReconciled:false};
 });
}
export async function financePayoutReport(db:PrismaClient,userId:string){
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 const [items,bank]=await Promise.all([
  db.payoutTransfer.findMany({select:{id:true,status:true,amountPaise:true,
   providerRef:true,settlement:{select:{supplierId:true}}},
   orderBy:{createdAt:'desc'},take:100}),
  db.auditEvent.findMany({where:{entityType:'PayoutTransfer',
   action:'PAYOUT_BANK_STATEMENT_HUMAN_ATTESTED'},
   select:{entityId:true},orderBy:{createdAt:'desc'},take:1000})
 ]);
 const refs=new Set(bank.map(b=>b.entityId));
 return {payouts:items.map(x=>({id:x.id,supplierId:x.settlement.supplierId,
   status:x.status,amountPaise:x.amountPaise.toString(),
   providerPayoutId:x.providerRef,bankStatementAttested:refs.has(x.id)})),
  missingBankAttestation:items.filter(x=>x.status==='SUCCEEDED'&&!refs.has(x.id)).length,
  bankStatementAPIReconciled:false,
  payoutExecutionEnabledByApi:false};
}
