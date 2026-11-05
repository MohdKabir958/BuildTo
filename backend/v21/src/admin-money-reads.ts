import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';

type Filter={cursor?:string;limit?:number};
const validate=(q:Filter)=>{
 const limit=q.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>50)
  throw new ApiError(400,'INVALID_LIMIT','Limit must be 1–50.');
 if(q.cursor!==undefined&&!isUuid(q.cursor))
  throw new ApiError(400,'INVALID_CURSOR','Invalid UUID cursor.');
 return {limit,cursor:q.cursor};
};
/**
 * A candidate is NOT an approved refund: existing refundEvidence() rechecks
 * delivery, full return, exact issued credit note, verified capture, seller
 * independence and unsettled supplier order inside a transaction.
 */
export async function refundCandidates(db:PrismaClient,actor:string,query:Filter){
 await requireAdminPermission(db,actor,'FINANCE_MANAGE');
 const {limit,cursor}=validate(query);
 const rows=await db.returnRequest.findMany({
  where:{status:'RECEIVED',refundRequest:null,...(cursor?{id:{gt:cursor}}:{})},
  orderBy:{id:'asc'},take:limit+1,
  select:{
   id:true,supplierOrderId:true,status:true,createdAt:true,
   creditNote:{select:{id:true,kind:true,status:true,totalPaise:true,sourceInvoiceId:true}},
   supplierOrder:{select:{supplierId:true,totalPaise:true}}
  }
 });
 return {
  items:rows.slice(0,limit).map(r=>({
   id:r.id,supplierId:r.supplierOrder.supplierId,
   supplierOrderId:r.supplierOrderId,status:r.status,
   supplierTotalPaise:r.supplierOrder.totalPaise.toString(),
   creditNote:r.creditNote?{
    id:r.creditNote.id,kind:r.creditNote.kind,status:r.creditNote.status,
    totalPaise:r.creditNote.totalPaise.toString(),originalInvoiceLinked:Boolean(r.creditNote.sourceInvoiceId)
   }:null,
   createdAt:r.createdAt.toISOString(),
   fullRefundEligible:false,
   eligibilityNote:'Candidate only. Every legal, capture and settlement requirement must pass server-side before requesting.'
  })),
  nextCursor:rows.length>limit?rows[limit-1].id:null
 };
}
/**
 * Independent finance operators need masked beneficiary IDs to select an
 * approved destination. Never expose provider tokens, validation IDs, IFSC,
 * account holder, raw bank number or encrypted account data.
 */
export async function financeBeneficiaries(db:PrismaClient,actor:string,supplierId:string){
 await requireAdminPermission(db,actor,'FINANCE_MANAGE');
 if(!isUuid(supplierId))throw new ApiError(404,'NOT_FOUND','Supplier unavailable.');
 const supplier=await db.supplier.findUnique({where:{id:supplierId},select:{id:true}});
 if(!supplier)throw new ApiError(404,'NOT_FOUND','Supplier unavailable.');
 const rows=await db.supplierPayoutAccount.findMany({
  where:{supplierId},orderBy:{createdAt:'desc'},take:20,
  select:{id:true,active:true,verifiedAt:true,createdAt:true,
   bankAccountLast4:true,registeredById:true,approvedById:true}
 });
 return rows.map(r=>({
  id:r.id,supplierId,maskedBankAccount:r.bankAccountLast4?'****'+r.bankAccountLast4:null,
  active:r.active,validated:!!r.verifiedAt,independentlyApproved:
   Boolean(r.registeredById&&r.approvedById&&r.registeredById!==r.approvedById),
  createdAt:r.createdAt.toISOString()
 }));
}
