import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {requireSupplierPermission} from './permissions';
import {record,requiredString,uuid,boolean,warehouseCode,warehouseAddress,
 movementData,keyHash} from './inventory-validation';

type Tx=Prisma.TransactionClient;
const BALANCE_SELECT={
 id:true,listingId:true,warehouseId:true,onHandQty:true,reservedQty:true,version:true,updatedAt:true
} as const;
function balanceDTO(b:{id:string;listingId:string;warehouseId:string;onHandQty:Prisma.Decimal;
 reservedQty:Prisma.Decimal;version:number;updatedAt:Date}) {
 return {id:b.id,listingId:b.listingId,warehouseId:b.warehouseId,
  onHandQty:b.onHandQty.toString(),reservedQty:b.reservedQty.toString(),
  availableQty:b.onHandQty.minus(b.reservedQty).toString(),
  version:b.version,updatedAt:b.updatedAt.toISOString()};
}
function warehouseDTO(w:{id:string;supplierId:string;code:string;name:string;address:Prisma.JsonValue|null;active:boolean}) {
 return {id:w.id,supplierId:w.supplierId,code:w.code,name:w.name,address:w.address,active:w.active};
}
export async function lockSupplierInventory(tx:Tx,actor:string,supplierId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierMember"
   WHERE "supplierId"=${supplierId}::uuid AND "userId"=${actor}::uuid FOR SHARE`);
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${supplierId}::uuid FOR SHARE`);
 await requireSupplierPermission(tx,actor,supplierId,'INVENTORY_WRITE');
}
export async function listWarehouses(db:PrismaClient,actor:string,supplierId:string) {
 uuid(supplierId,'supplierId');
 await requireSupplierPermission(db,actor,supplierId,'SUPPLIER_READ');
 const rows=await db.warehouse.findMany({where:{supplierId},select:{
  id:true,supplierId:true,code:true,name:true,address:true,active:true
 },orderBy:{code:'asc'},take:100});
 return rows.map(warehouseDTO);
}
export async function createWarehouse(db:PrismaClient,actor:string,supplierId:string,input:unknown) {
 uuid(supplierId,'supplierId');
 const o=record(input,['code','name','address']);
 const data={supplierId,code:warehouseCode(o.code),
  name:requiredString(o.name,'name',150),
  address:o.address===undefined?undefined:warehouseAddress(o.address),active:false};
 return serializable(db,async tx=>{
  await lockSupplierInventory(tx,actor,supplierId);
  const row=await tx.warehouse.create({data,select:{
   id:true,supplierId:true,code:true,name:true,address:true,active:true
  }});
  await tx.auditEvent.create({data:{
   actorUserId:actor,actorRole:'SUPPLIER_INVENTORY',action:'WAREHOUSE_CREATED',
   entityType:'Warehouse',entityId:row.id,
  }});
  return warehouseDTO(row);
 });
}
export async function changeWarehouse(db:PrismaClient,actor:string,supplierId:string,
 warehouseId:string,input:unknown) {
 uuid(supplierId,'supplierId');uuid(warehouseId,'warehouseId');
 const o=record(input,['name','active','address']);
 if(!Object.keys(o).length)throw new ApiError(400,'EMPTY_PATCH','Nothing to update.');
 const data:{name?:string;active?:boolean;address?:Prisma.InputJsonObject|typeof Prisma.DbNull}={};
 if(o.name!==undefined)data.name=requiredString(o.name,'name',150);
 if(o.active!==undefined)data.active=boolean(o.active,'active');
 if(o.address!==undefined)data.address=o.address===null?Prisma.DbNull:warehouseAddress(o.address)!;
 return serializable(db,async tx=>{
  await lockSupplierInventory(tx,actor,supplierId);
  const old=await tx.warehouse.findFirst({where:{id:warehouseId,supplierId},select:{id:true,active:true}});
  if(!old)throw new ApiError(404,'NOT_FOUND','Warehouse not found.');
  if(data.active===false&&old.active) {
   const balance=await tx.inventoryBalance.findFirst({where:{
    warehouseId,OR:[{onHandQty:{gt:0}},{reservedQty:{gt:0}}]
   },select:{id:true}});
   if(balance)throw new ApiError(409,'WAREHOUSE_HAS_STOCK','Move or reconcile all warehouse stock first.');
  }
  const row=await tx.warehouse.update({where:{id:warehouseId},data,select:{
   id:true,supplierId:true,code:true,name:true,address:true,active:true
  }});
  await tx.auditEvent.create({data:{
   actorUserId:actor,actorRole:'SUPPLIER_INVENTORY',action:'WAREHOUSE_UPDATED',
   entityType:'Warehouse',entityId:row.id,
  }});
  return warehouseDTO(row);
 });
}
export async function listStock(db:PrismaClient,actor:string,supplierId:string,listingId?:string) {
 uuid(supplierId,'supplierId');
 if(listingId)uuid(listingId,'listingId');
 await requireSupplierPermission(db,actor,supplierId,'SUPPLIER_READ');
 const rows=await db.inventoryBalance.findMany({
  where:{listing:{supplierId,...(listingId?{id:listingId}:{})},warehouse:{supplierId}},
  select:BALANCE_SELECT,orderBy:[{warehouseId:'asc'},{listingId:'asc'}],take:200,
 });
 return rows.map(balanceDTO);
}
export async function listMovements(db:PrismaClient,actor:string,supplierId:string,
 warehouseId:string,listingId?:string) {
 uuid(supplierId,'supplierId');uuid(warehouseId,'warehouseId');
 if(listingId)uuid(listingId,'listingId');
 await requireSupplierPermission(db,actor,supplierId,'SUPPLIER_READ');
 const w=await db.warehouse.findFirst({where:{id:warehouseId,supplierId},select:{id:true}});
 if(!w)throw new ApiError(404,'NOT_FOUND','Warehouse not found.');
 const rows=await db.stockMovement.findMany({where:{
  balance:{warehouseId,warehouse:{supplierId},...(listingId?{listingId}:{})}
 },select:{id:true,kind:true,delta:true,reason:true,createdAt:true,
  balance:{select:{listingId:true,warehouseId:true}}},
 },orderBy:[{createdAt:'desc'},{id:'desc'}],take:100});
 return rows.map(row=>({
  id:row.id,kind:row.kind,delta:row.delta.toString(),reason:row.reason,
  listingId:row.balance.listingId,warehouseId:row.balance.warehouseId,createdAt:row.createdAt.toISOString()
 }));
}
export async function adjustStock(db:PrismaClient,actor:string,supplierId:string,
 key:string,input:unknown) {
 uuid(supplierId,'supplierId');
 const command=movementData(input);
 const referenceKey=keyHash('stock:'+supplierId,key);
 const execution=await executeIdempotently(db,{
  actorId:actor,scope:'stock:'+supplierId,requestKey:key,requestPayload:input,
  expiresAt:new Date(Date.now()+24*3600_000),
  execute:async tx=>{
   await lockSupplierInventory(tx,actor,supplierId);
   // Lock supplier-scoped warehouse/listing before creating a balance.
   const warehouse=await tx.warehouse.findFirst({where:{id:command.warehouseId,supplierId},
    select:{id:true,active:true}});
   const listing=await tx.supplierListing.findFirst({where:{
     id:command.listingId,supplierId,deletedAt:null,status:{notIn:['SUSPENDED','ARCHIVED']},
   },select:{id:true}});
   if(!warehouse||!listing)throw new ApiError(404,'NOT_FOUND','Warehouse or listing not found.');
   if(!warehouse.active)throw new ApiError(409,'WAREHOUSE_INACTIVE','Activate warehouse before adjusting stock.');
   // Avoid upsert races when two suppliers' staff create the balance at once.
   await tx.$executeRaw(Prisma.sql`
    INSERT INTO "InventoryBalance" (id,"listingId","warehouseId","onHandQty","reservedQty",version,"updatedAt")
    VALUES (gen_random_uuid(),${command.listingId}::uuid,${command.warehouseId}::uuid,0,0,0,NOW())
    ON CONFLICT ("listingId","warehouseId") DO NOTHING
   `);
   const locked=await tx.$queryRaw<{id:string;onHandQty:Prisma.Decimal;
       reservedQty:Prisma.Decimal;version:number}[]>(Prisma.sql`
     SELECT id,"onHandQty","reservedQty",version FROM "InventoryBalance"
     WHERE "listingId"=${command.listingId}::uuid AND "warehouseId"=${command.warehouseId}::uuid
     FOR UPDATE
   `);
   const balance=locked[0];
   if(!balance)throw new ApiError(409,'STOCK_BALANCE_UNAVAILABLE','Stock balance unavailable.');
   if(command.expectedVersion!==balance.version)
     throw new ApiError(409,'STOCK_VERSION_CONFLICT','Refresh stock and retry with the latest version.');
   const next=balance.onHandQty.plus(command.delta);
   if(next.lt(balance.reservedQty))
     throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK','Adjustment would consume reserved or unavailable stock.');
   // Maintain the existing CHECK (onHand>=reserved>=0), plus optimistic version.
   const updated=await tx.inventoryBalance.updateMany({
    where:{id:balance.id,version:balance.version},
    data:{onHandQty:{increment:command.delta},version:{increment:1}},
   });
   if(updated.count!==1)throw new ApiError(409,'STOCK_VERSION_CONFLICT','Stock changed while updating.');
   const movement=await tx.stockMovement.create({data:{
    balanceId:balance.id,kind:command.kind,delta:command.delta,
    referenceKey,reason:command.reason,actorUserId:actor
   },select:{id:true}});
   await tx.auditEvent.create({data:{
    actorUserId:actor,actorRole:'SUPPLIER_INVENTORY',action:'STOCK_'+command.kind,
    entityType:'InventoryBalance',entityId:balance.id,
   }});
   return {result:movement.id,resultRef:movement.id,responseCode:201};
  }
 });
 // Permission is checked again on an idempotent replay.
 await requireSupplierPermission(db,actor,supplierId,'INVENTORY_WRITE');
 const movement=await db.stockMovement.findFirst({where:{
  id:execution.resultRef,balance:{listing:{supplierId},warehouse:{supplierId}}
 },select:{id:true,kind:true,delta:true,reason:true,createdAt:true,
  balance:{select:BALANCE_SELECT}
 }});
 if(!movement)throw new ApiError(404,'NOT_FOUND','Stock movement not found.');
 return {movementId:movement.id,kind:movement.kind,delta:movement.delta.toString(),
  reason:movement.reason,createdAt:movement.createdAt.toISOString(),
  currentBalance:balanceDTO(movement.balance),replayed:execution.kind==='replayed'};
}
