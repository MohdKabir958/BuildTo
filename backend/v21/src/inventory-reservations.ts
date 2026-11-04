import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {uuid,stockQty} from './inventory-validation';

// Checkout (PR 08) will invoke these helpers INSIDE its order database transaction.
// Never expose a public reservation endpoint that accepts arbitrary order-item IDs.
type Tx=Prisma.TransactionClient;
type OrderRow={id:string;listingId:string|null;quantity:Prisma.Decimal;supplierId:string};
type BalanceRow={id:string;listingId:string;warehouseId:string;
 onHandQty:Prisma.Decimal;reservedQty:Prisma.Decimal;version:number};
async function lockOrderItem(tx:Tx,orderItemId:string):Promise<OrderRow> {
 const rows=await tx.$queryRaw<OrderRow[]>(Prisma.sql`
  SELECT item.id,item."listingId",item.quantity,orders."supplierId"
  FROM "SupplierOrderItem" item
  JOIN "SupplierOrder" orders ON orders.id=item."supplierOrderId"
  WHERE item.id=${orderItemId}::uuid FOR UPDATE OF item
 `);
 if(!rows[0])throw new ApiError(404,'ORDER_ITEM_NOT_FOUND','Order item not found.');
 return rows[0];
}
async function lockBalance(tx:Tx,balanceId:string):Promise<BalanceRow> {
 const rows=await tx.$queryRaw<BalanceRow[]>(Prisma.sql`
  SELECT id,"listingId","warehouseId","onHandQty","reservedQty",version
  FROM "InventoryBalance" WHERE id=${balanceId}::uuid FOR UPDATE
 `);
 if(!rows[0])throw new ApiError(404,'STOCK_BALANCE_NOT_FOUND','Stock balance not found.');
 return rows[0];
}
function assertExpiry(expiresAt:Date) {
 if(!(expiresAt instanceof Date)||!Number.isFinite(expiresAt.getTime())||
    expiresAt.getTime()<Date.now()+10_000||expiresAt.getTime()>Date.now()+24*3600_000)
  throw new ApiError(400,'INVALID_RESERVATION_EXPIRY','Reservation needs a near-term future expiry.');
}
export interface HoldStockCommand {
 supplierId:string;orderItemId:string;warehouseId:string;
 quantity:string;expiresAt:Date;
}
export async function holdOrderItemStock(tx:Tx,cmd:HoldStockCommand) {
 uuid(cmd.supplierId,'supplierId');uuid(cmd.orderItemId,'orderItemId');
 uuid(cmd.warehouseId,'warehouseId');assertExpiry(cmd.expiresAt);
 const quantity=stockQty(cmd.quantity);
 const orderItem=await lockOrderItem(tx,cmd.orderItemId);
 if(orderItem.supplierId!==cmd.supplierId||!orderItem.listingId)
  throw new ApiError(404,'ORDER_ITEM_NOT_FOUND','Order item not found.');
 const warehouse=await tx.warehouse.findFirst({where:{
  id:cmd.warehouseId,supplierId:cmd.supplierId,active:true
 },select:{id:true}});
 if(!warehouse)throw new ApiError(404,'WAREHOUSE_NOT_FOUND','Active warehouse not found.');
 const listing=await tx.supplierListing.findFirst({where:{
  id:orderItem.listingId,supplierId:cmd.supplierId,status:'APPROVED',
  active:true,deletedAt:null,
 },select:{id:true}});
 if(!listing)throw new ApiError(409,'LISTING_UNAVAILABLE','Listing is not available for checkout.');
 const balance=await tx.inventoryBalance.findUnique({where:{
  listingId_warehouseId:{listingId:listing.id,warehouseId:cmd.warehouseId}
 },select:{id:true}});
 if(!balance)throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK','Warehouse has no stock for the selected item.');
 const locked=await lockBalance(tx,balance.id);
 const existing=await tx.inventoryReservation.findUnique({where:{
  orderItemId_balanceId:{orderItemId:cmd.orderItemId,balanceId:locked.id}
 }});
 if(existing) {
  if(existing.state==='HELD'&&existing.quantity.eq(quantity)&&
     existing.expiresAt&&existing.expiresAt.getTime()>Date.now())
   return {reservationId:existing.id,replayed:true};
  throw new ApiError(409,'RESERVATION_ALREADY_EXISTS','An incompatible reservation already exists for this order item and warehouse.');
 }
 const reserved=await tx.inventoryReservation.aggregate({where:{
  orderItemId:cmd.orderItemId,state:{in:['HELD','COMMITTED']}
 },_sum:{quantity:true}});
 const already=reserved._sum.quantity??new Prisma.Decimal(0);
 if(already.plus(quantity).gt(orderItem.quantity))
  throw new ApiError(409,'ORDER_QUANTITY_EXCEEDED','Reservations exceed the purchased item quantity.');
 if(locked.onHandQty.minus(locked.reservedQty).lt(quantity))
  throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK','Not enough unreserved stock.');
 const changed=await tx.inventoryBalance.updateMany({where:{
  id:locked.id,version:locked.version
 },data:{reservedQty:{increment:quantity},version:{increment:1}}});
 if(changed.count!==1)throw new ApiError(409,'STOCK_VERSION_CONFLICT','Stock changed while reserving.');
 const created=await tx.inventoryReservation.create({data:{
  orderItemId:cmd.orderItemId,balanceId:locked.id,quantity,expiresAt:cmd.expiresAt,
  state:'HELD'
 },select:{id:true}});
 return {reservationId:created.id,replayed:false};
}
// Explicit release/expiration. A later checkout workflow will call it on payment
// failure/cancellation and will reclaim expired holds during recovery.
export async function releaseOrderItemStock(tx:Tx,reservationId:string,
 state:'RELEASED'|'EXPIRED'='RELEASED') {
 uuid(reservationId,'reservationId');
 const found=await tx.inventoryReservation.findUnique({where:{id:reservationId},
  select:{id:true,orderItemId:true,balanceId:true}});
 if(!found)throw new ApiError(404,'RESERVATION_NOT_FOUND','Reservation not found.');
 await lockOrderItem(tx,found.orderItemId);
 const bal=await lockBalance(tx,found.balanceId);
 const reservation=await tx.inventoryReservation.findUniqueOrThrow({where:{id:reservationId}});
 if(reservation.state===state)return {reservationId,state,replayed:true};
 if(reservation.state!=='HELD')
  throw new ApiError(409,'RESERVATION_NOT_HELD','Reservation has already been finalized.');
 const updated=await tx.inventoryReservation.updateMany({
  where:{id:reservationId,state:'HELD'},data:{state}
 });
 if(updated.count!==1)throw new ApiError(409,'RESERVATION_CHANGED','Reservation was modified.');
 const changed=await tx.inventoryBalance.updateMany({where:{
  id:bal.id,version:bal.version
 },data:{reservedQty:{decrement:reservation.quantity},version:{increment:1}}});
 if(changed.count!==1)throw new ApiError(409,'STOCK_VERSION_CONFLICT','Stock changed while releasing.');
 return {reservationId,state,replayed:false};
}
export async function commitOrderItemStock(tx:Tx,reservationId:string) {
 uuid(reservationId,'reservationId');
 const found=await tx.inventoryReservation.findUnique({where:{id:reservationId},
  select:{id:true,orderItemId:true,balanceId:true}});
 if(!found)throw new ApiError(404,'RESERVATION_NOT_FOUND','Reservation not found.');
 await lockOrderItem(tx,found.orderItemId);
 const bal=await lockBalance(tx,found.balanceId);
 const reservation=await tx.inventoryReservation.findUniqueOrThrow({where:{id:reservationId}});
 if(reservation.state==='COMMITTED')
  return {reservationId,state:'COMMITTED' as const,replayed:true};
 if(reservation.state!=='HELD')
  throw new ApiError(409,'RESERVATION_NOT_HELD','Cannot consume a released or expired reservation.');
 if(reservation.expiresAt&&reservation.expiresAt.getTime()<=Date.now())
  throw new ApiError(409,'RESERVATION_EXPIRED','Reservation expired; recheck stock.');
 if(bal.reservedQty.lt(reservation.quantity)||bal.onHandQty.lt(reservation.quantity))
  throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK','Reserved stock is no longer available.');
 const updated=await tx.inventoryReservation.updateMany({
  where:{id:reservationId,state:'HELD'},data:{state:'COMMITTED'}
 });
 if(updated.count!==1)throw new ApiError(409,'RESERVATION_CHANGED','Reservation changed while committing.');
 const balance=await tx.inventoryBalance.updateMany({where:{
  id:bal.id,version:bal.version
 },data:{reservedQty:{decrement:reservation.quantity},
   onHandQty:{decrement:reservation.quantity},version:{increment:1}}});
 if(balance.count!==1)throw new ApiError(409,'STOCK_VERSION_CONFLICT','Stock changed while committing.');
 await tx.stockMovement.create({data:{
  balanceId:bal.id,kind:'SALE',delta:reservation.quantity.neg(),
  referenceKey:'sale:'+reservationId,reason:'Committed supplier order stock',
 }});
 return {reservationId,state:'COMMITTED' as const,replayed:false};
}
