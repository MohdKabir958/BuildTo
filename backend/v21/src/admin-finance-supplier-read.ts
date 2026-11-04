import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';
export async function financeSupplierChoices(db:PrismaClient,actor:string,q:{cursor?:string;limit?:number}){
 await requireAdminPermission(db,actor,'FINANCE_MANAGE');
 const limit=q.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>50)
  throw new ApiError(400,'INVALID_LIMIT','Limit must be between 1 and 50.');
 if(q.cursor!==undefined&&!isUuid(q.cursor))
  throw new ApiError(400,'INVALID_CURSOR','Invalid supplier cursor.');
 const rows=await db.supplier.findMany({where:q.cursor?{id:{gt:q.cursor}}:{},
  select:{id:true,displayName:true,approval:true,suspendedAt:true},
  orderBy:{id:'asc'},take:limit+1
 });
 return {items:rows.slice(0,limit).map(x=>({
  id:x.id,displayName:x.displayName,approval:x.approval,suspended:x.suspendedAt!==null
 })),nextCursor:rows.length>limit?rows[limit-1].id:null};
}
