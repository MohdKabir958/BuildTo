import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireSupplierPermission,isUuid} from './permissions';
import {publishOutbox} from './outbox';

type Tx=Prisma.TransactionClient;
function plain(v:unknown):v is Record<string,unknown>{
 return !!v&&typeof v==='object'&&!Array.isArray(v);
}
function text(v:unknown,max=250):string{
 return typeof v==='string'&&v.trim().length>0&&v.trim().length<=max?v.trim():'';
}
function businessAddress(v:unknown){
 if(!plain(v))throw new ApiError(409,'SELLER_ADDRESS_REQUIRED','Supplier billing address is missing.');
 const line1=text(v.line1),city=text(v.city,120),stateCode=text(v.stateCode,3),
  postalCode=text(v.postalCode,10);
 if(!line1||!city||!/^[A-Z]{2}$/.test(stateCode)||!/^[1-9][0-9]{5}$/.test(postalCode))
  throw new ApiError(409,'SELLER_ADDRESS_REQUIRED','Supplier billing address must be complete and verified.');
 return {line1,city,stateCode,postalCode,locality:text(v.locality,120)};
}
function customerAddress(v:unknown){
 if(!plain(v))throw new ApiError(409,'BUYER_ADDRESS_REQUIRED','Delivery address snapshot missing.');
 const name=text(v.recipientName,160),line1=text(v.line1),city=text(v.city,120),
  stateCode=text(v.stateCode,3),postalCode=text(v.postalCode,10);
 if(!name||!line1||!city||!/^[A-Z]{2}$/.test(stateCode)||!/^[1-9][0-9]{5}$/.test(postalCode))
  throw new ApiError(409,'BUYER_ADDRESS_REQUIRED','Buyer invoice address is incomplete.');
 return {recipientName:name,line1,city,stateCode,postalCode,
  locality:text(v.locality,120),phoneE164:text(v.phoneE164,20)};
}
function financialYear(now:Date){
 const parts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Kolkata',
  year:'numeric',month:'2-digit'}).formatToParts(now);
 const year=Number(parts.find(x=>x.type==='year')?.value);
 const month=Number(parts.find(x=>x.type==='month')?.value);
 if(!Number.isInteger(year)||!Number.isInteger(month))throw new Error('INVALID_FINANCIAL_YEAR');
 const from=month>=4?year:year-1;
 return String(from)+'-'+String((from+1)%100).padStart(2,'0');
}
export {financialYear};
const selection={
 id:true,supplierId:true,supplierOrderId:true,invoiceNumber:true,financialYear:true,
 status:true,kind:true,taxablePaise:true,taxPaise:true,totalPaise:true,
 cgstPaise:true,sgstPaise:true,utgstPaise:true,igstPaise:true,cessPaise:true,
 issuedAt:true,sellerSnapshot:true,buyerSnapshot:true,lineSnapshot:true
} as const;
function dto(row:{
 id:string;supplierId:string;supplierOrderId:string;invoiceNumber:string;financialYear:string;
 status:string;kind:string;taxablePaise:bigint;taxPaise:bigint;totalPaise:bigint;
 cgstPaise:bigint;sgstPaise:bigint;utgstPaise:bigint;igstPaise:bigint;cessPaise:bigint;
 issuedAt:Date;sellerSnapshot:unknown;buyerSnapshot:unknown;lineSnapshot:unknown
}){
 return {id:row.id,supplierId:row.supplierId,supplierOrderId:row.supplierOrderId,
  invoiceNumber:row.invoiceNumber,financialYear:row.financialYear,
  status:row.status,kind:row.kind,currency:'INR',
  taxablePaise:row.taxablePaise.toString(),taxPaise:row.taxPaise.toString(),
  totalPaise:row.totalPaise.toString(),cgstPaise:row.cgstPaise.toString(),
  sgstPaise:row.sgstPaise.toString(),utgstPaise:row.utgstPaise.toString(),
  igstPaise:row.igstPaise.toString(),cessPaise:row.cessPaise.toString(),
  issuedAt:row.issuedAt.toISOString(),
  seller:row.sellerSnapshot,buyer:row.buyerSnapshot,lines:row.lineSnapshot};
}
async function lockParent(tx:Tx,id:string){
 const ids=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
 SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE
 `);
 if(!ids.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
}
export async function issueSupplierInvoice(db:PrismaClient,userId:string,
 supplierId:string,supplierOrderId:string,body:unknown){
 if(!isUuid(supplierId)||!isUuid(supplierOrderId))
  throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 if(!plain(body)||Object.keys(body).length!==0)
  throw new ApiError(400,'INVOICE_NOT_CLIENT_PRICED','Invoice fields are calculated from server-owned order snapshots.');
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'INVOICE_ISSUE');
  const found=await tx.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
   select:{purchaseOrderId:true}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
  await lockParent(tx,found.purchaseOrderId);
  const previous=await tx.taxInvoice.findFirst({where:{supplierOrderId,supplierId},
   select:selection,orderBy:{issuedAt:'asc'}});
  if(previous) {
   if(previous.status!=='ISSUED')
    throw new ApiError(409,'INVOICE_ALREADY_FINALIZED','Use a legally approved credit or replacement flow.');
   return {invoice:dto(previous),replayed:true};
  }
  const order=await tx.supplierOrder.findUniqueOrThrow({where:{id:supplierOrderId},
   select:{id:true,status:true,supplierId:true,subtotalPaise:true,discountPaise:true,
    taxPaise:true,deliveryPaise:true,totalPaise:true,
    supplier:{select:{legalName:true,gstin:true,gstRegistration:true,verifiedAt:true,
     billingAddress:true,approval:true,suspendedAt:true}},
    purchaseOrder:{select:{id:true,status:true,currency:true,addressSnapshot:true,
     publicNumber:true,payments:{select:{provider:true,paymentMethod:true,status:true}}}},
    items:{select:{id:true,skuSnapshot:true,nameSnapshot:true,hsnSnapshot:true,
     unitCode:true,quantity:true,unitPrice:true,taxRateBps:true,
     taxablePaise:true,discountPaise:true,taxPaise:true,
     cgstPaise:true,sgstPaise:true,utgstPaise:true,igstPaise:true,cessPaise:true,
     lineTotalPaise:true},orderBy:{id:'asc'}}
   }});
  if(!['DISPATCHED','PARTIALLY_DELIVERED','DELIVERED'].includes(order.status))
   throw new ApiError(409,'INVOICE_BEFORE_DISPATCH','Supplier order must have reached dispatch.');
  const supplier=order.supplier;
  if(supplier.approval!=='APPROVED'||supplier.suspendedAt||!supplier.verifiedAt)
   throw new ApiError(409,'SELLER_NOT_VERIFIED','Seller approval and verified registration are required.');
  const registration=supplier.gstRegistration;
  const taxableSale=order.items.some(i=>i.taxPaise>0n);
  let kind:'TAX_INVOICE'|'BILL_OF_SUPPLY';
  if(registration==='REGULAR'){
   if(!supplier.gstin||!/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(supplier.gstin))
    throw new ApiError(409,'SELLER_GSTIN_REQUIRED','Seller GST registration must be verified.');
   kind='TAX_INVOICE';
  }else if((registration==='COMPOSITION'||registration==='EXEMPT')&&!taxableSale){
   kind='BILL_OF_SUPPLY';
  }else{
   throw new ApiError(409,'INVOICE_GST_STATUS_UNSUPPORTED',
    'Registration status or taxable lines are not eligible for this invoice type.');
  }
  if(order.purchaseOrder.currency!=='INR'||order.items.length===0)
   throw new ApiError(409,'INVOICE_ORDER_INVALID','Order currency or items are invalid.');
  const verified=order.purchaseOrder.payments.some(p=>p.provider==='RAZORPAY'&&p.status==='CAPTURED');
  const cod=order.purchaseOrder.payments.some(p=>
   p.provider==='MANUAL'&&p.paymentMethod==='COD'&&p.status==='PENDING');
  if(!verified&&!cod)
   throw new ApiError(409,'INVOICE_PAYMENT_METHOD_REQUIRED','Invoice requires verified payment or confirmed COD method.');
  const sellerAddress=businessAddress(supplier.billingAddress);
  const buyerAddress=customerAddress(order.purchaseOrder.addressSnapshot);
  const lines=[] as Array<Record<string,string|number>>;
  let net=0n,tax=0n,cgst=0n,sgst=0n,utgst=0n,igst=0n,cess=0n,subtotal=0n,discount=0n;
  for(const i of order.items){
   if(i.taxablePaise<0n||i.discountPaise<0n||i.discountPaise>i.taxablePaise||
    i.taxPaise<0n||i.lineTotalPaise!==i.taxablePaise-i.discountPaise+i.taxPaise||
    i.taxPaise!==i.cgstPaise+i.sgstPaise+i.utgstPaise+i.igstPaise+i.cessPaise)
    throw new ApiError(409,'INVOICE_LINE_MISMATCH','Persisted order line tax breakdown is inconsistent.');
   if(i.taxPaise>0n&&(!i.hsnSnapshot||!/^[0-9]{4,8}$/.test(i.hsnSnapshot)))
    throw new ApiError(409,'INVOICE_HSN_REQUIRED','Taxable lines require approved HSN codes.');
   subtotal+=i.taxablePaise;discount+=i.discountPaise;
   net+=i.taxablePaise-i.discountPaise;
   tax+=i.taxPaise;cgst+=i.cgstPaise;sgst+=i.sgstPaise;
   utgst+=i.utgstPaise;igst+=i.igstPaise;cess+=i.cessPaise;
   lines.push({sku:i.skuSnapshot,name:i.nameSnapshot,hsn:i.hsnSnapshot??'',
    unitCode:i.unitCode,quantity:i.quantity.toString(),unitPrice:i.unitPrice.toString(),
    taxRateBps:i.taxRateBps,taxablePaise:(i.taxablePaise-i.discountPaise).toString(),
    discountPaise:i.discountPaise.toString(),taxPaise:i.taxPaise.toString(),
    cgstPaise:i.cgstPaise.toString(),sgstPaise:i.sgstPaise.toString(),
    utgstPaise:i.utgstPaise.toString(),igstPaise:i.igstPaise.toString(),
    cessPaise:i.cessPaise.toString(),lineTotalPaise:i.lineTotalPaise.toString()});
  }
  if(subtotal!==order.subtotalPaise||discount!==order.discountPaise||
   tax!==order.taxPaise||net+tax+order.deliveryPaise!==order.totalPaise)
   throw new ApiError(409,'INVOICE_TOTAL_MISMATCH','Order and line amount snapshots do not reconcile.');
  // PR08 charges delivery without classifying its GST. For taxable goods,
  // do not silently call taxable composite freight "exempt": require approved
  // freight-tax handling first. Zero-tax supply may carry zero-tax freight.
  if(order.deliveryPaise>0n&&taxableSale)
   throw new ApiError(409,'FREIGHT_GST_POLICY_REQUIRED',
    'GST treatment of freight must be approved before statutory invoicing.');
  if(kind==='BILL_OF_SUPPLY'&&tax>0n)
   throw new ApiError(409,'BILL_OF_SUPPLY_TAX_FORBIDDEN','A bill of supply cannot charge GST.');
  const taxablePaise=net+order.deliveryPaise;
  const totalPaise=taxablePaise+tax;
  const now=new Date(),fy=financialYear(now);
  const number='BT-'+supplierId.replaceAll('-','').slice(0,6).toUpperCase()+'-'+
   supplierOrderId.replaceAll('-','').slice(0,22).toUpperCase();
  const sellerSnapshot:Prisma.InputJsonObject={
   legalName:supplier.legalName,gstin:supplier.gstin??'',
   gstRegistration:registration,address:sellerAddress
  };
  const buyerSnapshot:Prisma.InputJsonObject={
   ...buyerAddress,gstin:'',buyerTaxIdentity:'UNVERIFIED_B2C',
   purchaseOrderNumber:order.purchaseOrder.publicNumber
  };
  const lineSnapshot:Prisma.InputJsonObject={
   items:lines,delivery:{amountPaise:order.deliveryPaise.toString(),
    taxPaise:'0',classification:'FREIGHT_TAX_REVIEW_REQUIRED_FOR_TAXABLE_SUPPLY'},
   policy:'GST_RATE_AND_PLACE_OF_SUPPLY_FROM_IMMUTABLE_ORDER_LINES'
  };
  const created=await tx.taxInvoice.create({data:{
   supplierId,supplierOrderId,invoiceNumber:number,financialYear:fy,status:'ISSUED',kind,
   sellerSnapshot,buyerSnapshot,lineSnapshot,
   taxablePaise,taxPaise:tax,totalPaise,
   cgstPaise:cgst,sgstPaise:sgst,utgstPaise:utgst,igstPaise:igst,cessPaise:cess
  },select:selection});
  await tx.auditEvent.create({data:{action:'SUPPLIER_INVOICE_ISSUED',
   entityType:'TaxInvoice',entityId:created.id,actorUserId:userId,
   actorRole:'SUPPLIER_FINANCE'}});
  await publishOutbox(tx,{eventKey:'invoice:'+randomUUID(),
   eventType:'SUPPLIER_INVOICE_ISSUED',aggregateType:'TaxInvoice',
   aggregateId:created.id,payload:{invoiceId:created.id,supplierOrderId}});
  return {invoice:dto(created),replayed:false};
 });
}
export async function supplierInvoices(db:PrismaClient,userId:string,supplierId:string,supplierOrderId:string){
 await requireSupplierPermission(db,userId,supplierId,'FINANCE_READ');
 const exists=await db.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
  select:{id:true}});
 if(!exists)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 const invoices=await db.taxInvoice.findMany({where:{supplierOrderId,supplierId},
  select:selection,orderBy:{issuedAt:'desc'},take:20});
 return invoices.map(dto);
}
export async function customerInvoices(db:PrismaClient,userId:string,orderId:string){
 if(!isUuid(orderId))throw new ApiError(404,'NOT_FOUND','Order not found.');
 const order=await db.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},
  select:{id:true}});
 if(!order)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const invoices=await db.taxInvoice.findMany({where:{
  supplierOrder:{purchaseOrderId:orderId}},select:selection,
  orderBy:{issuedAt:'desc'},take:100});
 return invoices.map(dto);
}
