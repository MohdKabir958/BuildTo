import type {PrismaClient} from '../../generated/buildto-v21';
import {requireAdminPermission} from './permissions';

// All counts are database-wide observed records, not forecasts or cached badges.
// The API returns no private identities, contact data, order IDs or raw ledger rows.
export async function adminOverview(db:PrismaClient,actor:string){
 const access=await requireAdminPermission(db,actor,'ADMIN_READ');
 const readAt=new Date();
 const sevenDaysAgo=new Date(readAt.getTime()-7*24*60*60*1000);
 const [supplierCount,pendingSuppliers,activeSuppliers,pendingListings,orders,ordersLast7d,
  pendingSupplierOrders,openSupport,openReturns,deliveryExceptions,failedShipments,
  pendingRefunds,pendingPayouts]=await Promise.all([
   db.supplier.count(),
   db.supplier.count({where:{approval:{in:['PENDING','UNDER_REVIEW']}}}),
   db.supplier.count({where:{approval:'APPROVED',suspendedAt:null}}),
   db.supplierListing.count({where:{status:'PENDING',deletedAt:null}}),
   db.purchaseOrder.count(),
   db.purchaseOrder.count({where:{placedAt:{gte:sevenDaysAgo}}}),
   db.supplierOrder.count({where:{status:'PENDING_ACCEPTANCE'}}),
   db.supportCase.count({where:{status:{in:['OPEN','ASSIGNED','IN_PROGRESS','WAITING_CUSTOMER']}}}),
   db.returnRequest.count({where:{status:{in:['REQUESTED','UNDER_REVIEW','APPROVED','IN_TRANSIT','RECEIVED']}}}),
   db.shipment.count({where:{handoverMethod:'APPROVED_EXCEPTION',exceptionApprovedAt:{not:null}}}),
   db.shipment.count({where:{status:'FAILED'}}),
   db.refundRequest.count({where:{status:{in:['REQUESTED','APPROVED','PROCESSING','MANUAL_REVIEW']}}}),
   db.payoutTransfer.count({where:{status:{in:['PENDING','PROCESSING','FAILED']}}})
  ]);
 const base={
  asOf:readAt.toISOString(),windowStart7d:sevenDaysAgo.toISOString(),
  supplierCount,pendingSuppliers,activeSuppliers,pendingListings,totalOrders:orders,
  ordersPlacedLast7d:ordersLast7d,pendingSupplierOrders,openSupportCases:openSupport,
  unresolvedReturnClaims:openReturns,deliveryExceptionsApproved:deliveryExceptions,
  failedShipments,financialActionCounts:{pendingRefunds,pendingPayouts},
  metricsInterpretation:{
   totalOrders:'Recorded purchase orders, regardless of payment outcome',
   ordersPlacedLast7d:'Orders placed during the preceding rolling 7 x 24 hours',
   pendingListings:'All pending un-deleted supplier listing records',
   supplierCount:'All supplier records including pending/rejected/suspended',
   finance:'Capture evidence is not verified bank credit and is not recognized revenue'
  }
 };
 if(access.role!=='OWNER'&&access.role!=='FINANCE')
  return {...base,financeEvidence:null};
 // Distinguish provider-verified captured funds from approved settlements, COD,
 // net revenue and actual platform bank deposits. Do not sum placed-order totals.
 const captures=await db.paymentAttempt.aggregate({
  where:{status:'CAPTURED',verifiedAt:{not:null},currency:'INR'},
  _sum:{capturedPaise:true},_count:{id:true}
 });
 return {...base,financeEvidence:{
  verifiedGatewayCaptureEvidencePaise:(captures._sum.capturedPaise??0n).toString(),
  verifiedCaptureCount:captures._count.id,currency:'INR',
  bankCreditVerified:false,netRevenueCalculated:false,settlementAvailableNotImplied:true
 }};
}
