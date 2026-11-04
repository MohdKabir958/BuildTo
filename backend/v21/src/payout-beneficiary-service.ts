import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';
import {publishOutbox} from './outbox';
import type {PayoutEvidenceGateway,PayoutFundAccount,PayoutValidation} from './payout-gateway';

type Tx=Prisma.TransactionClient;
const normalized=(s:string)=>s.normalize('NFKC').trim().replace(/\s+/g,' ').toUpperCase();
const accountSelect={id:true,supplierId:true,providerTokenRef:true,validationRef:true,
 bankAccountLast4:true,accountHolder:true,ifsc:true,verifiedAt:true,active:true,createdAt:true} as const;
function dto(a:any){
 return {id:a.id,supplierId:a.supplierId,providerFundAccountId:a.providerTokenRef,
  validationId:a.validationRef,maskedBankAccount:a.bankAccountLast4?'****'+a.bankAccountLast4:null,
  accountHolder:a.accountHolder,ifsc:a.ifsc,active:a.active,
  verifiedAt:a.verifiedAt?.toISOString()??null,
  bankValidationApproved:!!a.verifiedAt&&a.active,
  externalPayoutExecutionOnly:true};
}
async function check(tx:Tx,userId:string,supplierId:string){
 await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
 const membership=await tx.supplierMember.findUnique({where:{
  supplierId_userId:{supplierId,userId}},select:{active:true,revokedAt:true}});
 if(membership?.active&&!membership.revokedAt)
  throw new ApiError(403,'PAYOUT_INDEPENDENT_FINANCE_REQUIRED','Supplier personnel cannot approve their own payout destination.');
}
function crossCheck(legalName:string,account:PayoutFundAccount,validation:PayoutValidation){
 if(validation.fundAccountId!==account.id||
  normalized(validation.registeredName)!==normalized(account.holder)||
  normalized(validation.registeredName)!==normalized(legalName))
  throw new ApiError(409,'PAYOUT_BENEFICIARY_NAME_MISMATCH',
   'Bank-validated registered name must match the approved supplier legal name.');
}
async function audit(tx:Tx,userId:string,accountId:string,action:string,data:Prisma.InputJsonObject){
 await tx.auditEvent.create({data:{entityType:'SupplierPayoutAccount',entityId:accountId,
  actorUserId:userId,actorRole:'ADMIN_FINANCE',action,afterState:data}});
 await publishOutbox(tx,{eventKey:'payout-beneficiary:'+randomUUID(),
  eventType:action,aggregateType:'SupplierPayoutAccount',
  aggregateId:accountId,payload:{accountId}});
}
export async function registerBeneficiary(db:PrismaClient,userId:string,
 supplierId:string,raw:unknown,gateway:PayoutEvidenceGateway|undefined){
 if(!isUuid(supplierId))throw new ApiError(404,'NOT_FOUND','Supplier unavailable.');
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||
  Object.keys(raw).some(x=>!['fundAccountId','validationId'].includes(x)))
  throw new ApiError(400,'INVALID_PAYOUT_BENEFICIARY','Only two provider IDs accepted.');
 const data=raw as Record<string,unknown>;
 if(typeof data.fundAccountId!=='string'||!/^fa_[A-Za-z0-9]{8,60}$/.test(data.fundAccountId)||
  typeof data.validationId!=='string'||!/^fav_[A-Za-z0-9]{8,60}$/.test(data.validationId))
  throw new ApiError(400,'INVALID_PAYOUT_BENEFICIARY','Invalid provider identifiers.');
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 if(!gateway)throw new ApiError(503,'PAYOUT_PROVIDER_REQUIRED','Read-only payout provider unavailable.');
 const [fund,valid]=await Promise.all([
  gateway.fetchFundAccount(data.fundAccountId),gateway.fetchValidation(data.validationId)]);
 return serializable(db,async tx=>{
  await check(tx,userId,supplierId);
  await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${supplierId}::uuid FOR UPDATE`);
  const supplier=await tx.supplier.findUnique({where:{id:supplierId},
   select:{legalName:true,approval:true,suspendedAt:true}});
  if(!supplier||supplier.approval!=='APPROVED'||supplier.suspendedAt)
   throw new ApiError(404,'NOT_FOUND','Approved supplier unavailable.');
  crossCheck(supplier.legalName,fund,valid);
  const existing=await tx.supplierPayoutAccount.findFirst({where:{
   supplierId,providerTokenRef:fund.id,validationRef:valid.id},select:accountSelect});
  if(existing)return {beneficiary:dto(existing),replayed:true};
  if(await tx.supplierPayoutAccount.count({where:{supplierId}}))
   throw new ApiError(409,'PAYOUT_BENEFICIARY_REPLACEMENT_GATED',
    'Bank destination replacement requires an audited financial migration.');
  const created=await tx.supplierPayoutAccount.create({data:{
   supplierId,providerTokenRef:fund.id,validationRef:valid.id,
   bankAccountLast4:fund.last4,accountHolder:fund.holder,ifsc:fund.ifsc,
   registeredById:userId,active:false},select:accountSelect});
  await audit(tx,userId,created.id,'PAYOUT_BENEFICIARY_PENDING_APPROVAL',{
   supplierId,fundAccountId:fund.id,validationId:valid.id,
   last4:fund.last4,fullBankAccountStored:false});
  return {beneficiary:dto(created),replayed:false};
 });
}
export async function approveBeneficiary(db:PrismaClient,userId:string,
 accountId:string,raw:unknown,gateway:PayoutEvidenceGateway|undefined){
 if(!isUuid(accountId))throw new ApiError(404,'NOT_FOUND','Beneficiary unavailable.');
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||Object.keys(raw).length)
  throw new ApiError(400,'INVALID_PAYOUT_APPROVAL','Expected empty JSON.');
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 if(!gateway)throw new ApiError(503,'PAYOUT_PROVIDER_REQUIRED','Read-only payout provider unavailable.');
 const before=await db.supplierPayoutAccount.findUnique({where:{id:accountId},
  select:{supplierId:true,providerTokenRef:true,validationRef:true}});
 if(!before?.providerTokenRef||!before.validationRef)
  throw new ApiError(404,'NOT_FOUND','Beneficiary unavailable.');
 const [fund,valid]=await Promise.all([
  gateway.fetchFundAccount(before.providerTokenRef),
  gateway.fetchValidation(before.validationRef)]);
 return serializable(db,async tx=>{
  await check(tx,userId,before.supplierId);
  await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${before.supplierId}::uuid FOR UPDATE`);
  const [supplier,current]=await Promise.all([
   tx.supplier.findUnique({where:{id:before.supplierId},
    select:{legalName:true,approval:true,suspendedAt:true}}),
   tx.supplierPayoutAccount.findUnique({where:{id:accountId},
    select:{...accountSelect,registeredById:true,approvedById:true}})
  ]);
  if(!supplier||supplier.approval!=='APPROVED'||supplier.suspendedAt||!current)
   throw new ApiError(404,'NOT_FOUND','Verified supplier unavailable.');
  if(!current.registeredById||current.registeredById===userId)
   throw new ApiError(403,'PAYOUT_BENEFICIARY_SECOND_REVIEWER','Second finance administrator required.');
  if(current.active)return {beneficiary:dto(current),replayed:true};
  if(current.verifiedAt||current.approvedById||
   current.providerTokenRef!==fund.id||current.validationRef!==valid.id||
   current.bankAccountLast4!==fund.last4||current.ifsc!==fund.ifsc||
   normalized(current.accountHolder??'')!==normalized(fund.holder))
   throw new ApiError(409,'PAYOUT_BENEFICIARY_CHANGED','Bank provider details have changed.');
  crossCheck(supplier.legalName,fund,valid);
  const approved=await tx.supplierPayoutAccount.update({where:{id:accountId},
   data:{active:true,approvedById:userId,verifiedAt:new Date()},select:accountSelect});
  await audit(tx,userId,accountId,'PAYOUT_BENEFICIARY_INDEPENDENTLY_VERIFIED',{
   fundAccountId:fund.id,validationId:valid.id,last4:fund.last4,
   fullBankAccountStored:false,bankValidationStatus:'active'});
  return {beneficiary:dto(approved),replayed:false};
 });
}
export async function supplierBeneficiaries(db:PrismaClient,userId:string,supplierId:string){
 if(!isUuid(supplierId))throw new ApiError(404,'NOT_FOUND','Supplier unavailable.');
 await requireSupplierPermission(db,userId,supplierId,'FINANCE_READ');
 return (await db.supplierPayoutAccount.findMany({where:{supplierId},
  select:accountSelect,orderBy:{createdAt:'desc'},take:20})).map(dto);
}
