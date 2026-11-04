import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';

/** Finance-only evidence inventory. Never expose full bank number or provider credentials. */
export async function adminBeneficiaryQueue(db:PrismaClient,adminId:string,query:{limit?:number;cursor?:string}={}) {
 await requireAdminPermission(db,adminId,'FINANCE_MANAGE');
 const limit=query.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>100)
  throw new ApiError(400,'INVALID_LIMIT','Limit must be between 1 and 100.');
 if(query.cursor!==undefined&&!isUuid(query.cursor))
  throw new ApiError(400,'INVALID_CURSOR','Invalid beneficiary cursor.');
 const rows=await db.supplierPayoutAccount.findMany({
  where:query.cursor?{id:{gt:query.cursor}}:{},
  select:{id:true,supplierId:true,bankAccountLast4:true,accountHolder:true,ifsc:true,
   active:true,createdAt:true,verifiedAt:true,registeredById:true,approvedById:true,
   supplier:{select:{displayName:true,approval:true}}},
  orderBy:{id:'asc'},take:limit+1
 });
 const page=rows.slice(0,limit);
 return {items:page.map(row=>({
  id:row.id,supplierId:row.supplierId,supplierName:row.supplier.displayName,
  supplierApproval:row.supplier.approval,maskedBankAccount:row.bankAccountLast4?'****'+row.bankAccountLast4:null,
  holderName:row.accountHolder,ifsc:row.ifsc,active:row.active,
  registeredById:row.registeredById,approvedById:row.approvedById,
  createdAt:row.createdAt.toISOString(),verifiedAt:row.verifiedAt?.toISOString()??null,
  bankStatementVerifiedByApi:false,
 })),nextCursor:rows.length>limit?page[page.length-1].id:null};
}
