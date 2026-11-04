import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {executeIdempotently} from './idempotency';
import {record,uuid,requiredString,integer,stockQty,keyHash} from './inventory-validation';
import {lockSupplierInventory} from './inventory-stock';
import {requireSupplierPermission} from './permissions';

export async function transferStock(db:PrismaClient,actor:string,supplierId:string,
 key:string,input:unknown) {
 uuid(supplierId,'supplierId');
 const o=record(input,['listingId','fromWarehouseId','toWarehouseId',
  'quantity','reason','expectedFromVersion','expectedToVersion']);
 const listingId=uuid(o.listingId,'listingId');
 const fromWarehouseId=uuid(o.fromWarehouseId,'fromWarehouseId');
 const toWarehouseId=uuid(o.toWarehouseId,'toWarehouseId');
 if(fromWarehouseId===toWarehouseId)
  throw new ApiError(400,'SAME_WAREHOUSE','Transfer requires different warehouses.');
 const qty=stockQty(o.quantity);
 const reason=requiredString(o.reason,'reason',300);
 const expectedFrom=integer(o.expectedFromVersion,'expectedFromVersion',0,2147483646);
 const expectedTo=integer(o.expectedToVersion,'expectedToVersion',0,2147483646);
 const pairRef=keyHash('transfer:'+supplierId,key);
 const execution=await executeIdempotently(db,{
  actorId:actor,scope:'transfer:'+supplierId,requestKey:key,requestPayload:input,
  expiresAt:new Date(Date.now()+86400_000),
  execute:async tx=>{
   await lockSupplierInventory(tx,actor,supplierId);
   const warehouses=await tx.warehouse.findMany({where:{
    id:{in:[fromWarehouseId,toWarehouseId]},supplierId,active:true
   },select:{id:true}});
   const listing=await tx.supplierListing.findFirst({where:{
    id:listingId,supplierId,deletedAt:null,status:{notIn:['SUSPENDED','ARCHIVED']}
   },select:{id:true}});
   if(warehouses.length!==2||!listing)
    throw new ApiError(404,'NOT_FOUND','Active warehouses or listing not found.');
   // Create the destination row if absent. The serializable transaction and
   // unique constraint protect concurrent first transfers into that warehouse.
   await tx.$executeRaw(Prisma.sql`
     INSERT INTO "InventoryBalance" (id,"listingId","warehouseId","onHandQty","reservedQty",version,"updatedAt")
     VALUES (gen_random_uuid(),${listingId}::uuid,${toWarehouseId}::uuid,0,0,0,NOW())
     ON CONFLICT ("listingId","warehouseId") DO NOTHING
   `);
   type Locked={id:string;warehouseId:string;onHandQty:Prisma.Decimal;
     reservedQty:Prisma.Decimal;version:number};
   // Both rows lock in deterministic balance ID order. Both mutations then
   // commit with their paired, append-only stock movements.
   const rows=await tx.$queryRaw<Locked[]>(Prisma.sql`
     SELECT id,"warehouseId","onHandQty","reservedQty",version FROM "InventoryBalance"
     WHERE "listingId"=${listingId}::uuid
       AND "warehouseId" IN (${fromWarehouseId}::uuid,${toWarehouseId}::uuid)
     ORDER BY id FOR UPDATE
   `);
   const src=rows.find(x=>x.warehouseId===fromWarehouseId);
   const dst=rows.find(x=>x.warehouseId===toWarehouseId);
   if(!src||!dst)throw new ApiError(409,'STOCK_BALANCE_UNAVAILABLE','Stock balance is missing.');
   if(src.version!==expectedFrom||dst.version!==expectedTo)
    throw new ApiError(409,'STOCK_VERSION_CONFLICT','Refresh stock balances before transferring.');
   if(src.onHandQty.minus(src.reservedQty).lt(qty))
    throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK','Transfer would consume reserved or unavailable stock.');
   const [out,incoming]=await Promise.all([
    tx.inventoryBalance.updateMany({where:{id:src.id,version:src.version},
     data:{onHandQty:{decrement:qty},version:{increment:1}}}),
    tx.inventoryBalance.updateMany({where:{id:dst.id,version:dst.version},
     data:{onHandQty:{increment:qty},version:{increment:1}}}),
   ]);
   if(out.count!==1||incoming.count!==1)
    throw new ApiError(409,'STOCK_VERSION_CONFLICT','Stock changed while transferring.');
   const movement=await tx.stockMovement.create({data:{
    balanceId:src.id,kind:'TRANSFER_OUT',delta:qty.neg(),
    referenceKey:pairRef+':out',actorUserId:actor,reason,
   },select:{id:true}});
   await tx.stockMovement.create({data:{
    balanceId:dst.id,kind:'TRANSFER_IN',delta:qty,
    referenceKey:pairRef+':in',actorUserId:actor,reason,
   }});
   await tx.auditEvent.create({data:{
    actorUserId:actor,actorRole:'SUPPLIER_INVENTORY',action:'STOCK_TRANSFERRED',
    entityType:'InventoryBalance',entityId:src.id,
   }});
   return {result:movement.id,resultRef:movement.id,responseCode:201};
  }
 });
 // Revalidate grants even for a replayed key.
 await requireSupplierPermission(db,actor,supplierId,'INVENTORY_WRITE');
 const out=await db.stockMovement.findFirst({where:{
  id:execution.resultRef,balance:{listing:{supplierId},warehouse:{supplierId}}
 },select:{id:true,delta:true,reason:true,createdAt:true,
   balance:{select:{warehouseId:true,listingId:true}}
 }});
 const incoming=await db.stockMovement.findUnique({where:{referenceKey:pairRef+':in'},
  select:{id:true,balance:{select:{warehouseId:true,listingId:true}}}});
 if(!out||!incoming||out.balance.listingId!==incoming.balance.listingId)
  throw new ApiError(404,'NOT_FOUND','Transfer record not found.');
 return {transferOutId:out.id,transferInId:incoming.id,
  listingId,fromWarehouseId:out.balance.warehouseId,toWarehouseId:incoming.balance.warehouseId,
  quantity:out.delta.abs().toString(),reason:out.reason,
  replayed:execution.kind==='replayed'};
}
