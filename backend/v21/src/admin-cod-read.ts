import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';
const statuses=['RECORDED','VERIFIED','DISPUTED','REVERSED'] as const;
export async function adminCodQueue(db:PrismaClient,actor:string,q:{cursor?:string;status?:string;limit?:number}){
 await requireAdminPermission(db,actor,'FINANCE_MANAGE');
 const limit=q.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>50)
  throw new ApiError(400,'INVALID_LIMIT','COD page size must be 1–50.');
 if(q.cursor!==undefined&&!isUuid(q.cursor))
  throw new ApiError(400,'INVALID_CURSOR','Invalid COD cursor.');
 if(q.status!==undefined&&!statuses.includes(q.status as typeof statuses[number]))
  throw new ApiError(400,'INVALID_STATUS','Invalid COD receipt state.');
 const rows=await db.codCollection.findMany({
  where:{status:q.status?(q.status as typeof statuses[number]):'RECORDED',
   ...(q.cursor?{id:{gt:q.cursor}}:{})},
  select:{id:true,receiptNumber:true,supplierId:true,supplierOrderId:true,
   collectedPaise:true,currency:true,status:true,receivedAt:true,shipmentId:true},
  orderBy:{id:'asc'},take:limit+1
 });
 return {items:rows.slice(0,limit).map(r=>({
  id:r.id,receiptNumber:r.receiptNumber,supplierId:r.supplierId,supplierOrderId:r.supplierOrderId,
  collectedPaise:r.collectedPaise.toString(),currency:r.currency,status:r.status,
  receivedAt:r.receivedAt.toISOString(),shipmentId:r.shipmentId
 })),nextCursor:rows.length>limit?rows[limit-1].id:null,
 note:'A recorded COD receipt is supplier-held cash, not a platform bank deposit.'};
}
