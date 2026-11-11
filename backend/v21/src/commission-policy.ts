import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission} from './permissions';

// Deliberate policy configuration: zero commission is allowed only when an administrator
// explicitly chooses it. Missing/corrupt policy must not silently create fee-free orders.
export const COMMISSION_POLICY_KEY='marketplace.commission.v1';
export type CommissionPolicy={rateBps:number;version:number;basis:'NET_MATERIALS'};
type Tx=Prisma.TransactionClient;
function decode(value:Prisma.JsonValue,version:number):CommissionPolicy {
 if(!value||typeof value!=='object'||Array.isArray(value)||
    value.basis!=='NET_MATERIALS'||value.schemaVersion!==1||
    !Number.isInteger(value.rateBps)||(value.rateBps as number)<0||(value.rateBps as number)>5000)
  throw new ApiError(503,'COMMISSION_POLICY_INVALID','Marketplace commission configuration is invalid.');
 return {rateBps:value.rateBps as number,version,basis:'NET_MATERIALS'};
}
export async function requireCommissionPolicy(tx:Tx):Promise<CommissionPolicy> {
 const row=await tx.appSetting.findUnique({where:{key:COMMISSION_POLICY_KEY},select:{value:true,version:true}});
 if(!row)throw new ApiError(409,'COMMISSION_POLICY_NOT_CONFIGURED',
  'Marketplace commission policy must be approved before checkout.');
 return decode(row.value,row.version);
}
export function commissionPaise(subtotalPaise:bigint,discountPaise:bigint,rateBps:number):bigint {
 if(subtotalPaise<0n||discountPaise<0n||discountPaise>subtotalPaise||
    !Number.isInteger(rateBps)||rateBps<0||rateBps>5000)
  throw new Error('INVALID_COMMISSION_INPUT');
 // The seller pays commission on net, tax-exclusive MATERIALS only:
 // exclude GST, delivery fees and promotional discounts. Round once to the paise.
 return ((subtotalPaise-discountPaise)*BigInt(rateBps)+5000n)/10000n;
}
export async function getCommissionPolicy(db:PrismaClient,actorId:string) {
 await requireAdminPermission(db,actorId,'FINANCE_MANAGE');
 const row=await db.appSetting.findUnique({where:{key:COMMISSION_POLICY_KEY},select:{value:true,version:true}});
 return row?{configured:true,...decode(row.value,row.version)}:
  {configured:false,rateBps:null,version:0,basis:'NET_MATERIALS' as const};
}
export async function setCommissionPolicy(db:PrismaClient,actorId:string,input:unknown) {
 if(!input||typeof input!=='object'||Array.isArray(input))
  throw new ApiError(400,'INVALID_COMMISSION_POLICY','Expected a policy object.');
 const d=input as Record<string,unknown>;
 if(Object.keys(d).some(k=>!['rateBps','expectedVersion','reason'].includes(k))||
    !Number.isInteger(d.rateBps)||!(typeof d.rateBps==='number'&&d.rateBps>=0&&d.rateBps<=5000)||
    !Number.isInteger(d.expectedVersion)||!(typeof d.expectedVersion==='number'&&d.expectedVersion>=0&&d.expectedVersion<=1000000000)||
    typeof d.reason!=='string'||d.reason.trim().length<12||d.reason.trim().length>300)
  throw new ApiError(400,'INVALID_COMMISSION_POLICY','Rate, expected version and audit reason are required.');
 const rateBps=d.rateBps as number,expectedVersion=d.expectedVersion as number;
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,actorId,'FINANCE_MANAGE');
  const old=await tx.appSetting.findUnique({where:{key:COMMISSION_POLICY_KEY}});
  if((old?.version??0)!==expectedVersion)
   throw new ApiError(409,'COMMISSION_POLICY_VERSION_CONFLICT','Commission policy changed. Reload and retry.');
  if(old)decode(old.value,old.version);
  const value={schemaVersion:1,basis:'NET_MATERIALS',rateBps};
  if(old){
   const updated=await tx.appSetting.updateMany({
    where:{key:COMMISSION_POLICY_KEY,version:expectedVersion},
    data:{value,version:expectedVersion+1,updatedBy:actorId}
   });
   if(updated.count!==1)throw new ApiError(409,'COMMISSION_POLICY_VERSION_CONFLICT','Commission policy changed.');
  }else{
   await tx.appSetting.create({data:{key:COMMISSION_POLICY_KEY,value,version:1,updatedBy:actorId}});
  }
  await tx.auditEvent.create({data:{
   actorUserId:actorId,actorRole:'FINANCE',action:'COMMISSION_POLICY_UPDATED',
   entityType:'AppSetting',entityId:COMMISSION_POLICY_KEY,
   beforeState:{version:old?.version??0,rateBps:old?decode(old.value,old.version).rateBps:null},
   afterState:{version:expectedVersion+1,rateBps,reason:(d.reason as string).trim()}
  }});
  return {configured:true,rateBps,version:expectedVersion+1,basis:'NET_MATERIALS' as const};
 });
}
