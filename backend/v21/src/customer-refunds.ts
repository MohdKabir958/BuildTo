import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {uuid} from './catalog-validation';
/** Customer-facing reconciliation status only. No execution or approval authority. */
export async function customerRefunds(db:PrismaClient,customerId:string,orderId:string){
 uuid(orderId,'orderId');
 const own=await db.purchaseOrder.findFirst({where:{id:orderId,customerId},select:{id:true}});
 if(!own)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const rows=await db.refundRequest.findMany({where:{purchaseOrderId:orderId,purchaseOrder:{customerId}},select:{id:true,returnRequestId:true,amountPaise:true,status:true,reason:true,providerRefundRef:true,completedAt:true,createdAt:true},orderBy:{createdAt:'desc'},take:100});
 return rows.map(r=>({id:r.id,returnRequestId:r.returnRequestId,amountPaise:r.amountPaise.toString(),status:r.status,reason:r.reason,reference:r.providerRefundRef,completedAt:r.completedAt?.toISOString()??null,createdAt:r.createdAt.toISOString()}));
}
