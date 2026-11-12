import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {executeIdempotently} from './idempotency';
import {placementInput,record,uuid,money} from './checkout-validation';
import {quoteLineAmounts} from './rfq-validation';
import {splitOrderGst} from './checkout-tax';
import {requireCommissionPolicy,commissionPaise} from './commission-policy';
import {outbox,reserveStock,getCustomerOrder} from './order-service';

// RFQ customer accepts the quote first; this separate action converts the
// negotiated supplier terms into an unpaid order. It NEVER creates payment.
export async function placeAcceptedRfqOrder(db:PrismaClient,customerId:string,
 rfqId:string,quoteId:string,key:string,payload:unknown) {
 uuid(rfqId,'rfqId');uuid(quoteId,'quoteId');
 const data=record(payload,['clientRequestId','addressId']);
 const {clientRequestId}=placementInput({clientRequestId:data.clientRequestId});
 const addressId=uuid(data.addressId,'addressId');
 const saved=await executeIdempotently(db,{
  actorId:customerId,scope:'rfq-to-order',requestKey:key,
  requestPayload:{rfqId,quoteId,addressId,clientRequestId},
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   // Two attempts for the same accepted quote must not create two orders.
   const locked=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
     SELECT id FROM "SupplierQuote" WHERE id=${quoteId}::uuid
      AND "rfqId"=${rfqId}::uuid FOR UPDATE
   `);
   if(!locked.length)throw new ApiError(404,'NOT_FOUND','Accepted quote not found.');
   const quote=await tx.supplierQuote.findFirst({where:{id:quoteId,rfqId,status:'ACCEPTED'},
    include:{supplier:true,rfq:true,lines:{include:{rfqItem:true}}}});
   if(!quote||quote.rfq.customerId!==customerId)
    throw new ApiError(404,'NOT_FOUND','Accepted quote not found.');
   if(quote.rfq.status!=='AWARDED'||!quote.acceptedAt)
    throw new ApiError(409,'RFQ_NOT_AWARDED','RFQ must be awarded first.');
   const expiry=quote.validUntil??new Date(quote.acceptedAt.getTime()+7*86400000);
   if(expiry.getTime()<=Date.now())
    throw new ApiError(409,'QUOTE_EXPIRED','Negotiated quote has expired.');
   if(quote.supplier.approval!=='APPROVED'||quote.supplier.suspendedAt)
    throw new ApiError(409,'SUPPLIER_UNAVAILABLE','Supplier is no longer approved.');
   if(await tx.supplierOrder.findFirst({where:{sourceQuoteId:quoteId},select:{id:true}}))
    throw new ApiError(409,'QUOTE_ALREADY_ORDERED','Accepted quotation has already been ordered.');
   const address=await tx.address.findFirst({where:{
     id:addressId,userId:customerId,deletedAt:null,city:{active:true}
   },select:{
    cityId:true,recipientName:true,phoneE164:true,line1:true,line2:true,
    locality:true,postalCode:true,latitude:true,longitude:true,instructions:true,
    city:{select:{name:true,stateCode:true}}
   }});
   if(!address)throw new ApiError(404,'ADDRESS_NOT_FOUND','Delivery address unavailable.');
   const site=quote.rfq.siteSnapshot;
   if(!site||typeof site!=='object'||Array.isArray(site))
    throw new ApiError(409,'INVALID_RFQ_SITE','RFQ location is invalid.');
   const snapshot=site as Record<string,unknown>;
   if(snapshot.postalCode!==address.postalCode||
      typeof snapshot.city!=='string'||
      snapshot.city.trim().toLocaleLowerCase('en-IN')!==address.city.name.trim().toLocaleLowerCase('en-IN'))
    throw new ApiError(422,'RFQ_ADDRESS_MISMATCH',
     'The delivery address must match the accepted RFQ location.');
   const addressSnapshot:Prisma.InputJsonObject={
    cityId:address.cityId,city:address.city.name,stateCode:address.city.stateCode,
    recipientName:address.recipientName,phoneE164:address.phoneE164,
    line1:address.line1,line2:address.line2??'',locality:address.locality,
    postalCode:address.postalCode,latitude:address.latitude?.toString()??'',
    longitude:address.longitude?.toString()??'',instructions:address.instructions??''
   };
   let taxable=0n,taxes=0n;
   const detail=[];
   if(!quote.lines.length||quote.lines.length!==await tx.rfqItem.count({where:{rfqId}}))
    throw new ApiError(409,'QUOTE_INCOMPLETE','Quotation no longer covers the full RFQ.');
   const sorted=[...quote.lines].sort((a,b)=>a.rfqItemId.localeCompare(b.rfqItemId));
   for(const line of sorted){
    const amount=quoteLineAmounts(line.quantity,line.unitPrice,line.taxRateBps);
    if(!line.lineTotalPaise||line.lineTotalPaise!==amount.lineTotalPaise||
       line.rfqItem.rfqId!==rfqId||line.rfqItem.unitCode!==line.unitCode||
       !line.rfqItem.quantity.eq(line.quantity))
     throw new ApiError(409,'QUOTE_PRICE_MISMATCH','Supplier quotation details have changed.');
    taxable=money(taxable+amount.netPaise);
    taxes=money(taxes+amount.taxPaise);
    const split=splitOrderGst(amount.taxPaise,quote.supplier,address.city.stateCode);
    const listing=line.listingId?await tx.supplierListing.findFirst({where:{
     id:line.listingId,supplierId:quote.supplierId,active:true,
     status:'APPROVED',deletedAt:null,unitCode:line.unitCode,
     product:{active:true,category:{active:true}}
    },select:{id:true,sku:true,packSize:true,product:{select:{name:true,hsnCode:true,brand:{select:{name:true}}}}}}):null;
    if(line.listingId&&!listing)
     throw new ApiError(409,'LISTING_UNAVAILABLE','Quoted supplier listing is no longer active.');
    const name=(listing?.product.name??line.rfqItem.description).trim();
    if(!name||name.length>240)throw new ApiError(422,'RFQ_LINE_NAME','Material description must be 1–240 characters.');
    detail.push({
     listingId:listing?.id??null,
     skuSnapshot:listing?.sku??('RFQ-'+line.rfqItemId.replaceAll('-','').slice(0,20).toUpperCase()),
     nameSnapshot:name,brandSnapshot:listing?.product.brand?.name??null,
     hsnSnapshot:listing?.product.hsnCode??null,
     unitCode:line.unitCode,packSizeSnapshot:listing?.packSize??new Prisma.Decimal(1),
     quantity:line.quantity,unitPrice:line.unitPrice,taxRateBps:line.taxRateBps,
     taxablePaise:amount.netPaise,taxPaise:amount.taxPaise,
     cgstPaise:split.cgstPaise,sgstPaise:split.sgstPaise,
     utgstPaise:split.utgstPaise,igstPaise:split.igstPaise,cessPaise:0n,
     lineTotalPaise:amount.lineTotalPaise,
     attributesSnapshot:{rfqId,rfqItemId:line.rfqItemId,quotedPrice:true},
    });
   }
   if(taxable!==quote.subtotalPaise||taxes!==quote.taxPaise||
      money(taxable+taxes+quote.deliveryPaise)!==quote.totalPaise)
    throw new ApiError(409,'QUOTE_PRICE_MISMATCH','Negotiated quotation totals no longer match.');
   if(await tx.purchaseOrder.findUnique({where:{
      customerId_clientRequestId:{customerId,clientRequestId}
    },select:{id:true}}))
    throw new ApiError(409,'CLIENT_REQUEST_ID_REUSED','Use a new request ID.');
   const commissionPolicy=await requireCommissionPolicy(tx);
   const parent=await tx.purchaseOrder.create({data:{
    customerId,clientRequestId,publicNumber:'BT-RFQ-'+randomUUID().replaceAll('-','').slice(0,24).toUpperCase(),
    currency:'INR',status:'PLACED',
    projectId:quote.rfq.projectId,addressSnapshot,
    subtotalPaise:quote.subtotalPaise,taxPaise:quote.taxPaise,discountPaise:0n,
    deliveryPaise:quote.deliveryPaise,totalPaise:quote.totalPaise
   },select:{id:true}});
   const order=await tx.supplierOrder.create({data:{
    purchaseOrderId:parent.id,supplierId:quote.supplierId,sourceQuoteId:quote.id,
    ...(quote.freightSnapshot?{freightSnapshot:quote.freightSnapshot as Prisma.InputJsonObject}:{}),
    platformFeePaise:commissionPaise(quote.subtotalPaise,0n,commissionPolicy.rateBps),
    status:'PENDING_ACCEPTANCE',subtotalPaise:quote.subtotalPaise,
    taxPaise:quote.taxPaise,discountPaise:0n,deliveryPaise:quote.deliveryPaise,
    totalPaise:quote.totalPaise
   },select:{id:true}});
   const expiresAt=new Date(Date.now()+20*60000);
   for(const line of detail){
    const item=await tx.supplierOrderItem.create({data:{
     supplierOrderId:order.id,...line
    },select:{id:true}});
    if(line.listingId)await reserveStock(tx,item.id,line.listingId,quote.supplierId,
      line.quantity.toFixed(3),expiresAt);
    // Bespoke RFQ lines have no warehouse balance to reserve. The supplier
    // must confirm procurement before PR 09 authorizes payment/dispatch.
   }
   await outbox(tx,parent.id,customerId,'RFQ_ORDER_AWAITING_SUPPLIER_PAYMENT');
   return {result:parent.id,resultRef:parent.id,responseCode:201};
  }
 });
 return {order:await getCustomerOrder(db,customerId,saved.resultRef),
  replayed:saved.kind==='replayed'};
}
