import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {financialYear} from './invoice-service';
import {isUuid,requireSupplierPermission} from './permissions';
import {publishOutbox} from './outbox';

type Tx=Prisma.TransactionClient;
const isObject=(x:unknown):x is Record<string,unknown>=>!!x&&typeof x==='object'&&!Array.isArray(x);
async function lockParent(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Return order unavailable.');
}
export const creditSelect={
 id:true,supplierId:true,supplierOrderId:true,invoiceNumber:true,
 financialYear:true,kind:true,status:true,sourceInvoiceId:true,returnRequestId:true,
 taxablePaise:true,taxPaise:true,cgstPaise:true,sgstPaise:true,utgstPaise:true,
 igstPaise:true,cessPaise:true,totalPaise:true,issuedAt:true
} as const;
export function creditDTO(c:{id:string;invoiceNumber:string;financialYear:string;
 kind:string;status:string;sourceInvoiceId:string|null;returnRequestId:string|null;
 taxablePaise:bigint;taxPaise:bigint;cgstPaise:bigint;sgstPaise:bigint;
 utgstPaise:bigint;igstPaise:bigint;cessPaise:bigint;totalPaise:bigint;issuedAt:Date}){
 return {id:c.id,invoiceNumber:c.invoiceNumber,financialYear:c.financialYear,
  kind:c.kind,status:c.status,sourceInvoiceId:c.sourceInvoiceId,
  returnRequestId:c.returnRequestId,currency:'INR',
  taxablePaise:c.taxablePaise.toString(),taxPaise:c.taxPaise.toString(),
  cgstPaise:c.cgstPaise.toString(),sgstPaise:c.sgstPaise.toString(),
  utgstPaise:c.utgstPaise.toString(),igstPaise:c.igstPaise.toString(),
  cessPaise:c.cessPaise.toString(),totalPaise:c.totalPaise.toString(),
  issuedAt:c.issuedAt.toISOString()};
}
const fields=['taxablePaise','taxPaise','cgstPaise','sgstPaise',
 'utgstPaise','igstPaise','cessPaise','lineTotalPaise'] as const;
/**
 * This first credit-note release deliberately supports a complete supplier return ONLY.
 * Partial GST notes require a separately approved per-line rounding+freight policy.
 * The immutable source invoice line snapshots must match the source order item IDs
 * in the exact order invoice-service originally serialized them.
 */
export async function issueReturnCreditNote(db:PrismaClient,userId:string,
 supplierId:string,returnId:string,body:unknown){
 if(!isUuid(supplierId)||!isUuid(returnId))
  throw new ApiError(404,'NOT_FOUND','Return unavailable.');
 if(!isObject(body)||Object.keys(body).length)
  throw new ApiError(400,'CREDIT_NOTE_SERVER_PRICED','Credit-note amounts are never client supplied.');
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'INVOICE_ISSUE');
  const source=await tx.returnRequest.findFirst({where:{
   id:returnId,supplierOrder:{supplierId}
  },select:{id:true,status:true,reason:true,createdAt:true,supplierOrderId:true,
   supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!source)throw new ApiError(404,'NOT_FOUND','Return unavailable.');
  await lockParent(tx,source.supplierOrder.purchaseOrderId);
  const issued=await tx.taxInvoice.findFirst({where:{returnRequestId:returnId,kind:'CREDIT_NOTE'},
   select:creditSelect});
  if(issued)return {creditNote:creditDTO(issued),replayed:true};
  if(source.status!=='RECEIVED')
   throw new ApiError(409,'CREDIT_NOTE_RETURN_NOT_RECEIVED',
    'Independent return approval and physical receipt are required before issuing a GST credit.');
  const fulfiller=await tx.auditEvent.findFirst({where:{
   entityType:'ReturnRequest',entityId:returnId,action:'SUPPLIER_RETURN_PHYSICALLY_RECEIVED'
  },orderBy:{createdAt:'desc'},select:{actorUserId:true}});
  if(!fulfiller||fulfiller.actorUserId===userId)
   throw new ApiError(403,'CREDIT_NOTE_INDEPENDENT_FINANCE_REQUIRED',
    'The staff member receiving goods cannot also issue the statutory tax credit.');
  const order=await tx.supplierOrder.findFirst({where:{id:source.supplierOrderId,supplierId},
   select:{id:true,status:true,subtotalPaise:true,discountPaise:true,taxPaise:true,
    totalPaise:true,deliveryPaise:true,platformFeePaise:true,
    supplier:{select:{gstRegistration:true,gstin:true,approval:true,suspendedAt:true}},
    items:{orderBy:{id:'asc'},select:{id:true,skuSnapshot:true,
     hsnSnapshot:true,quantity:true,taxablePaise:true,discountPaise:true,
     taxPaise:true,cgstPaise:true,sgstPaise:true,utgstPaise:true,
     igstPaise:true,cessPaise:true,lineTotalPaise:true,
     shipmentLines:{select:{deliveredQty:true,shipment:{select:{
      status:true,deliveredAt:true,handoverMethod:true,
      otpVerifiedAt:true,exceptionApprovedAt:true}}}}}},
    invoices:{where:{kind:'TAX_INVOICE',status:'ISSUED'},
     select:{id:true,invoiceNumber:true,financialYear:true,sellerSnapshot:true,
      buyerSnapshot:true,lineSnapshot:true,taxablePaise:true,taxPaise:true,
      cgstPaise:true,sgstPaise:true,utgstPaise:true,igstPaise:true,
      cessPaise:true,totalPaise:true,creditNotes:{select:{id:true}}}},
    settlementLines:{where:{settlement:{status:{not:'CANCELLED'}}},
     select:{id:true}},
    returnRequests:{where:{status:{notIn:['CANCELLED','REJECTED']}},
     select:{id:true,items:{select:{supplierOrderItemId:true,quantity:true}}}}
   }});
  if(!order||order.status!=='DELIVERED'||order.supplier.approval!=='APPROVED'||
    order.supplier.suspendedAt||order.supplier.gstRegistration!=='REGULAR'||
    !order.supplier.gstin)
   throw new ApiError(409,'CREDIT_NOTE_SUPPLIER_INVALID','Verified regular GST seller and delivered order required.');
  if(order.deliveryPaise!==0n||order.settlementLines.length)
   throw new ApiError(409,'CREDIT_NOTE_FINANCIAL_HOLD',
    'Freight-tax allocations or existing settlement must be resolved before issuing credit.');
  if(order.invoices.length!==1||order.invoices[0].creditNotes.length)
   throw new ApiError(409,'CREDIT_NOTE_SOURCE_REQUIRED',
    'One issued, not-yet-credited GST tax invoice is required.');
  const origin=order.invoices[0];
  const claims=order.returnRequests;
  if(claims.length!==1||claims[0].id!==returnId)
   throw new ApiError(409,'CREDIT_NOTE_MULTIPLE_RETURNS',
    'Only one full supplier-order return can be credited in this release.');
  const returns=new Map(claims[0].items.map(i=>[i.supplierOrderItemId,i.quantity]));
  if(!order.items.length||returns.size!==order.items.length||order.items.some(item=>
    !returns.get(item.id)?.eq(item.quantity)||
    !item.shipmentLines.length||
    !item.shipmentLines.filter(l=>l.shipment.status==='DELIVERED'&&l.shipment.deliveredAt&&
      (l.shipment.handoverMethod==='OTP'&&l.shipment.otpVerifiedAt||
       l.shipment.handoverMethod==='APPROVED_EXCEPTION'&&l.shipment.exceptionApprovedAt))
      .reduce((s,l)=>s.plus(l.deliveredQty),new Prisma.Decimal(0)).eq(item.quantity)))
   throw new ApiError(409,'CREDIT_NOTE_PARTIAL_UNSUPPORTED',
    'Partial or unverified supplier return requires a separate approved tax-allocation flow.');
  if(origin.totalPaise!==order.totalPaise||
   origin.taxablePaise+origin.taxPaise!==origin.totalPaise||
   origin.taxablePaise!==order.subtotalPaise-order.discountPaise||
   origin.taxPaise!==order.taxPaise||
   origin.taxPaise!==origin.cgstPaise+origin.sgstPaise+origin.utgstPaise+
    origin.igstPaise+origin.cessPaise)
   throw new ApiError(409,'CREDIT_NOTE_INVOICE_MISMATCH','Original invoice and seller tax snapshots disagree.');
  if(!isObject(origin.sellerSnapshot)||!isObject(origin.buyerSnapshot)||
   !isObject(origin.lineSnapshot)||!Array.isArray(origin.lineSnapshot.items)||
   origin.lineSnapshot.items.length!==order.items.length)
   throw new ApiError(409,'CREDIT_NOTE_SOURCE_SNAPSHOT_REQUIRED',
    'Original invoice requires complete immutable statutory line snapshots.');
  const totals={taxablePaise:0n,taxPaise:0n,cgstPaise:0n,
   sgstPaise:0n,utgstPaise:0n,igstPaise:0n,cessPaise:0n,
   lineTotalPaise:0n};
  if(origin.sellerSnapshot.gstin!==order.supplier.gstin)
   throw new ApiError(409,'CREDIT_NOTE_SELLER_GSTIN_MISMATCH',
    'Original statutory GST seller identity does not reconcile.');
  for(const item of order.items){
   if(item.taxablePaise<item.discountPaise||item.discountPaise<0n||
     item.taxPaise!==item.cgstPaise+item.sgstPaise+item.utgstPaise+
       item.igstPaise+item.cessPaise||
     item.lineTotalPaise!==item.taxablePaise-item.discountPaise+item.taxPaise||
     item.taxPaise>0n&&(!item.hsnSnapshot||!/^[0-9]{4,8}$/.test(item.hsnSnapshot)))
    throw new ApiError(409,'CREDIT_NOTE_SOURCE_TAX_INVALID',
     'Tax decomposition or HSN for original line cannot be verified.');
   totals.taxablePaise+=item.taxablePaise-item.discountPaise;
   totals.taxPaise+=item.taxPaise;
   totals.cgstPaise+=item.cgstPaise;
   totals.sgstPaise+=item.sgstPaise;
   totals.utgstPaise+=item.utgstPaise;
   totals.igstPaise+=item.igstPaise;
   totals.cessPaise+=item.cessPaise;
   totals.lineTotalPaise+=item.lineTotalPaise;
  }
  if(totals.taxablePaise!==origin.taxablePaise||
    totals.taxPaise!==origin.taxPaise||
    totals.cgstPaise!==origin.cgstPaise||
    totals.sgstPaise!==origin.sgstPaise||
    totals.utgstPaise!==origin.utgstPaise||
    totals.igstPaise!==origin.igstPaise||
    totals.cessPaise!==origin.cessPaise||
    totals.lineTotalPaise!==origin.totalPaise)
   throw new ApiError(409,'CREDIT_NOTE_TOTALS_INVALID',
    'Every original seller tax component and invoice total must reconcile.');
  for(let i=0;i<order.items.length;i++){
   const row=origin.lineSnapshot.items[i],item=order.items[i];
   if(!isObject(row)||row.sku!==item.skuSnapshot||
    row.quantity!==item.quantity.toString()||
    row.hsn!==(item.hsnSnapshot??''))
    throw new ApiError(409,'CREDIT_NOTE_LINE_MISMATCH',
     'Original invoice item identity and quantity must reconcile.');
   for(const name of fields){
    const expected=name==='taxablePaise'?
     item.taxablePaise-item.discountPaise:item[name];
    if(row[name]!==expected.toString())
     throw new ApiError(409,'CREDIT_NOTE_LINE_MISMATCH',
      'Original line tax amounts must be exact and immutable.');
   }
  }
  const now=new Date(),fy=financialYear(now);
  const number='BTCN-'+supplierId.replaceAll('-','').slice(0,7).toUpperCase()+
   '-'+returnId.replaceAll('-','').slice(0,20).toUpperCase();
  const credit=await tx.taxInvoice.create({data:{
   supplierId,supplierOrderId:source.supplierOrderId,
   sourceInvoiceId:origin.id,returnRequestId:returnId,
   invoiceNumber:number,financialYear:fy,status:'ISSUED',kind:'CREDIT_NOTE',
   taxablePaise:origin.taxablePaise,taxPaise:origin.taxPaise,
   totalPaise:origin.totalPaise,cgstPaise:origin.cgstPaise,
   sgstPaise:origin.sgstPaise,utgstPaise:origin.utgstPaise,
   igstPaise:origin.igstPaise,cessPaise:origin.cessPaise,
   sellerSnapshot:origin.sellerSnapshot as Prisma.InputJsonObject,
   buyerSnapshot:origin.buyerSnapshot as Prisma.InputJsonObject,
   lineSnapshot:{
    originalInvoiceId:origin.id,originalInvoiceNumber:origin.invoiceNumber,
    originalFinancialYear:origin.financialYear,returnRequestId:returnId,
    creditType:'FULL_SUPPLIER_RETURN',reason:source.reason,
    items:origin.lineSnapshot.items as Prisma.InputJsonArray,
    originalInvoiceSnapshotDigest:'COPIED_EXACT_ORIGINAL_LINES'
   }
  },select:creditSelect});
  await tx.auditEvent.create({data:{entityType:'TaxInvoice',entityId:credit.id,
   actorUserId:userId,actorSupplierId:supplierId,actorRole:'SUPPLIER_FINANCE',
   action:'FULL_RETURN_GST_CREDIT_NOTE_ISSUED',
   afterState:{returnRequestId:returnId,originalInvoiceId:origin.id,
    creditNoteId:credit.id,amountPaise:credit.totalPaise.toString()}}});
  await publishOutbox(tx,{eventKey:'credit-note:'+credit.id,
   eventType:'FULL_RETURN_GST_CREDIT_NOTE_ISSUED',
   aggregateType:'TaxInvoice',aggregateId:credit.id,
   payload:{creditNoteId:credit.id,returnRequestId:returnId}});
  return {creditNote:creditDTO(credit),replayed:false};
 });
}
