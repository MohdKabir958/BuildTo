import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {publishOutbox} from './outbox';
import {requireSupplierPermission} from './permissions';
import {uuid,createRfqInput,quoteInput,quoteLineAmounts,boundedPaise} from './rfq-validation';

type Tx=Prisma.TransactionClient;
const rfqSelect={
 id:true,publicNumber:true,projectId:true,siteSnapshot:true,notes:true,status:true,
 responseDueAt:true,createdAt:true,updatedAt:true,
 items:{select:{id:true,productId:true,description:true,quantity:true,unitCode:true,specification:true},
  orderBy:{id:'asc' as const}},
} as const;
function rfqDTO(r:any){
 return {id:r.id,publicNumber:r.publicNumber,projectId:r.projectId,siteSnapshot:r.siteSnapshot,
  notes:r.notes,status:r.status,responseDueAt:r.responseDueAt?.toISOString()??null,
  createdAt:r.createdAt.toISOString(),
  items:r.items.map((x:any)=>({id:x.id,productId:x.productId,description:x.description,
   quantity:x.quantity.toString(),unitCode:x.unitCode,specification:x.specification}))};
}
const quoteSelect={
 id:true,rfqId:true,supplierId:true,quoteNumber:true,version:true,status:true,
 subtotalPaise:true,taxPaise:true,deliveryPaise:true,totalPaise:true,
 deliveryTerms:true,validUntil:true,createdAt:true,acceptedAt:true,
 lines:{select:{rfqItemId:true,listingId:true,quantity:true,unitCode:true,unitPrice:true,
  taxRateBps:true,lineTotalPaise:true},orderBy:{rfqItemId:'asc' as const}},
} as const;
function quoteDTO(q:any){
 return {id:q.id,rfqId:q.rfqId,supplierId:q.supplierId,quoteNumber:q.quoteNumber,
 version:q.version,status:q.status,subtotalPaise:q.subtotalPaise.toString(),
 taxPaise:q.taxPaise.toString(),deliveryPaise:q.deliveryPaise.toString(),
 totalPaise:q.totalPaise.toString(),deliveryTerms:q.deliveryTerms,
 validUntil:q.validUntil?.toISOString()??null,createdAt:q.createdAt.toISOString(),
 acceptedAt:q.acceptedAt?.toISOString()??null,
 lines:q.lines.map((x:any)=>({rfqItemId:x.rfqItemId,listingId:x.listingId,
 quantity:x.quantity.toString(),unitCode:x.unitCode,unitPrice:x.unitPrice.toString(),
 taxRateBps:x.taxRateBps,lineTotalPaise:x.lineTotalPaise.toString()}))};
}
async function lockedRfq(tx:Tx,id:string,customerId?:string) {
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "Rfq" WHERE id=${id}::uuid
    ${customerId?Prisma.sql`AND "customerId"=${customerId}::uuid`:Prisma.empty}
  FOR UPDATE
 `);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','RFQ not found.');
 return tx.rfq.findUniqueOrThrow({where:{id},select:rfqSelect});
}
function isOpen(r:{status:string;responseDueAt:Date|null}){
 if(r.status!=='OPEN')throw new ApiError(409,'RFQ_NOT_OPEN','RFQ is not open for quotations.');
 if(r.responseDueAt&&r.responseDueAt.getTime()<=Date.now())
  throw new ApiError(409,'RFQ_DEADLINE_PASSED','RFQ response deadline has passed.');
}
async function event(tx:Tx,rfqId:string,actor:string,action:string) {
 await tx.auditEvent.create({data:{actorUserId:actor,actorRole:'RFQ_WORKFLOW',
  action,entityType:'Rfq',entityId:rfqId}});
 await publishOutbox(tx,{eventKey:'rfq:'+randomUUID(),eventType:action,
  aggregateType:'Rfq',aggregateId:rfqId,payload:{rfqId}});
}
export async function createCustomerRfq(db:PrismaClient,customerId:string,key:string,payload:unknown) {
 const input=createRfqInput(payload);
 const result=await executeIdempotently(db,{
  actorId:customerId,scope:'rfq-create',requestKey:key,requestPayload:payload,
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   if(input.projectId){
    const project=await tx.constructionProject.findFirst({where:{
      id:input.projectId,customerId,status:'ACTIVE'
    },select:{id:true}});
    if(!project)throw new ApiError(404,'PROJECT_NOT_FOUND','Project unavailable.');
   }
   const units=await tx.unitOfMeasure.findMany({where:{code:{in:[...new Set(input.items.map(x=>x.unitCode))]},active:true},
    select:{code:true}});
   if(units.length!==new Set(input.items.map(x=>x.unitCode)).size)
    throw new ApiError(422,'INVALID_RFQ_UNIT','RFQ item unit must be active.');
   const products=input.items.filter(x=>x.productId!==null).map(x=>x.productId!) ;
   if(products.length){
    const active=await tx.product.count({where:{id:{in:products},active:true,category:{active:true}}});
    if(active!==new Set(products).size)
     throw new ApiError(422,'PRODUCT_UNAVAILABLE','Choose active catalog products.');
   }
   const rfq=await tx.rfq.create({data:{
    customerId,publicNumber:'RFQ-'+randomUUID().replaceAll('-','').slice(0,24).toUpperCase(),
    projectId:input.projectId,siteSnapshot:input.siteSnapshot,notes:input.notes,
    responseDueAt:input.responseDueAt,items:{create:input.items.map(item=>({
     productId:item.productId,description:item.description,quantity:item.quantity,
     unitCode:item.unitCode,...(item.specification?{specification:item.specification}:{})
    }))}
   },select:{id:true}});
   await event(tx,rfq.id,customerId,'RFQ_CREATED');
   return {result:rfq.id,resultRef:rfq.id,responseCode:201};
  }
 });
 const row=await db.rfq.findFirst({where:{id:result.resultRef,customerId},select:rfqSelect});
 if(!row)throw new ApiError(404,'NOT_FOUND','RFQ not found.');
 return {rfq:rfqDTO(row),replayed:result.kind==='replayed'};
}
export async function listCustomerRfqs(db:PrismaClient,userId:string) {
 const rows=await db.rfq.findMany({where:{customerId:userId},select:rfqSelect,
  orderBy:{createdAt:'desc'},take:100});
 return rows.map(rfqDTO);
}
export async function customerRfq(db:PrismaClient,userId:string,rfqId:string) {
 uuid(rfqId,'rfqId');
 const r=await db.rfq.findFirst({where:{id:rfqId,customerId:userId},
  select:{...rfqSelect,invitations:{select:{supplierId:true,invitedAt:true},take:100}}});
 if(!r)throw new ApiError(404,'NOT_FOUND','RFQ not found.');
 return {...rfqDTO(r),invitedSuppliers:r.invitations.map(i=>({supplierId:i.supplierId,invitedAt:i.invitedAt.toISOString()}))};
}
export async function openCustomerRfq(db:PrismaClient,userId:string,rfqId:string) {
 uuid(rfqId,'rfqId');
 return serializable(db,async tx=>{
  const r=await lockedRfq(tx,rfqId,userId);
  if(r.status!=='DRAFT')throw new ApiError(409,'INVALID_RFQ_STATE','Only drafts can be opened.');
  if(r.responseDueAt&&r.responseDueAt.getTime()<=Date.now())
   throw new ApiError(409,'RFQ_DEADLINE_PASSED','Select a future response deadline.');
  await tx.rfq.update({where:{id:rfqId},data:{status:'OPEN'}});
  await event(tx,rfqId,userId,'RFQ_OPENED');
  return {id:rfqId,status:'OPEN'};
 });
}
export async function inviteSupplier(db:PrismaClient,userId:string,rfqId:string,supplierId:string) {
 uuid(rfqId,'rfqId');uuid(supplierId,'supplierId');
 return serializable(db,async tx=>{
  const r=await lockedRfq(tx,rfqId,userId);
  isOpen(r);
  const supplier=await tx.supplier.findUnique({where:{id:supplierId},
   select:{approval:true,suspendedAt:true}});
  if(supplier?.approval!=='APPROVED'||supplier.suspendedAt)
   throw new ApiError(422,'SUPPLIER_UNAVAILABLE','Supplier must be approved.');
  const previous=await tx.rfqInvitation.findUnique({where:{rfqId_supplierId:{rfqId,supplierId}}});
  if(previous)return {rfqId,supplierId,alreadyInvited:true};
  await tx.rfqInvitation.create({data:{rfqId,supplierId}});
  await event(tx,rfqId,userId,'RFQ_SUPPLIER_INVITED');
  return {rfqId,supplierId,alreadyInvited:false};
 });
}
export async function cancelCustomerRfq(db:PrismaClient,userId:string,rfqId:string) {
 uuid(rfqId,'rfqId');
 return serializable(db,async tx=>{
  const r=await lockedRfq(tx,rfqId,userId);
  if(!['DRAFT','OPEN'].includes(r.status))
   throw new ApiError(409,'INVALID_RFQ_STATE','Only draft or open RFQs can be cancelled.');
  await tx.rfq.update({where:{id:rfqId},data:{status:'CANCELLED'}});
  await event(tx,rfqId,userId,'RFQ_CANCELLED');
  return {id:rfqId,status:'CANCELLED'};
 });
}
export async function invitedSupplierRfqs(db:PrismaClient,userId:string,supplierId:string) {
 uuid(supplierId,'supplierId');
 await requireSupplierPermission(db,userId,supplierId,'RFQ_QUOTE');
 const rows=await db.rfqInvitation.findMany({where:{supplierId,rfq:{
  status:'OPEN',OR:[{responseDueAt:null},{responseDueAt:{gt:new Date()}}]
 }},select:{invitedAt:true,rfq:{select:rfqSelect}},orderBy:{invitedAt:'desc'},take:100});
 return rows.map(x=>({...rfqDTO(x.rfq),invitedAt:x.invitedAt.toISOString()}));
}
async function supplierGrant(tx:Tx,userId:string,supplierId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierMember"
  WHERE "supplierId"=${supplierId}::uuid AND "userId"=${userId}::uuid FOR SHARE`);
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${supplierId}::uuid FOR SHARE`);
 await requireSupplierPermission(tx,userId,supplierId,'RFQ_QUOTE');
}
export async function submitSupplierQuote(db:PrismaClient,userId:string,supplierId:string,
 rfqId:string,payload:unknown) {
 uuid(supplierId,'supplierId');uuid(rfqId,'rfqId');
 const input=quoteInput(payload);
 return serializable(db,async tx=>{
  await supplierGrant(tx,userId,supplierId);
  const r=await lockedRfq(tx,rfqId);
  isOpen(r);
  const invitation=await tx.rfqInvitation.findUnique({where:{rfqId_supplierId:{rfqId,supplierId}}});
  if(!invitation)throw new ApiError(404,'NOT_FOUND','Invited RFQ not found.');
  if(input.lines.length!==r.items.length)
   throw new ApiError(422,'QUOTE_INCOMPLETE','All RFQ lines must be quoted exactly once.');
  const items=new Map(r.items.map(x=>[x.id,x]));
  const listingIds=input.lines.filter(x=>x.listingId).map(x=>x.listingId!);
  const listings=listingIds.length?await tx.supplierListing.findMany({where:{
   id:{in:listingIds},supplierId,deletedAt:null,status:'APPROVED',active:true,
   product:{active:true,category:{active:true}}
  },select:{id:true,productId:true,unitCode:true}}):[];
  const owned=new Map(listings.map(x=>[x.id,x]));
  let subtotal=0n,taxes=0n;
  const lines=input.lines.map(line=>{
   const item=items.get(line.rfqItemId);
   if(!item||!item.quantity.eq(line.quantity)||item.unitCode!==line.unitCode)
    throw new ApiError(422,'QUOTE_ITEM_MISMATCH','Quote quantity or units must match the RFQ.');
   if(line.listingId){
    const listing=owned.get(line.listingId);
    if(!listing||listing.unitCode!==line.unitCode||
       (item.productId!==null&&listing.productId!==item.productId))
     throw new ApiError(422,'LISTING_NOT_ELIGIBLE','Listing must be an approved matching supplier product.');
   }
   const money=quoteLineAmounts(line.quantity,line.unitPrice,line.taxRateBps);
   subtotal=boundedPaise(subtotal+money.netPaise);
   taxes=boundedPaise(taxes+money.taxPaise);
   return {...line,lineTotalPaise:money.lineTotalPaise};
  });
  const total=boundedPaise(subtotal+taxes+input.deliveryPaise);
  const previous=await tx.supplierQuote.findFirst({where:{rfqId,supplierId},
   orderBy:{version:'desc'},select:{id:true,quoteNumber:true,version:true,status:true}});
  if(previous&&!['SUBMITTED','REVISED','WITHDRAWN'].includes(previous.status))
   throw new ApiError(409,'QUOTE_LOCKED','Quote can no longer be revised.');
  const version=previous?previous.version+1:1;
  if(version>50)throw new ApiError(409,'QUOTE_VERSION_LIMIT','Too many quote revisions.');
  if(previous&&previous.status==='SUBMITTED')
   await tx.supplierQuote.update({where:{id:previous.id},data:{status:'REVISED'}});
  const quote=await tx.supplierQuote.create({data:{
   rfqId,supplierId,quoteNumber:previous?.quoteNumber??('QT-'+randomUUID().replaceAll('-','').slice(0,20).toUpperCase()),
   version,status:'SUBMITTED',deliveryTerms:input.deliveryTerms,validUntil:input.validUntil,
   subtotalPaise:subtotal,taxPaise:taxes,deliveryPaise:input.deliveryPaise,totalPaise:total,
   lines:{create:lines.map(x=>({
    rfqItemId:x.rfqItemId,listingId:x.listingId,quantity:x.quantity,unitCode:x.unitCode,
    unitPrice:x.unitPrice,taxRateBps:x.taxRateBps,lineTotalPaise:x.lineTotalPaise
   }))}
  },select:quoteSelect});
  await event(tx,rfqId,userId,'RFQ_QUOTE_SUBMITTED');
  return quoteDTO(quote);
 });
}
export async function mySupplierQuotes(db:PrismaClient,userId:string,supplierId:string,rfqId:string) {
 uuid(supplierId,'supplierId');uuid(rfqId,'rfqId');
 await requireSupplierPermission(db,userId,supplierId,'RFQ_QUOTE');
 const invitation=await db.rfqInvitation.findUnique({where:{rfqId_supplierId:{rfqId,supplierId}}});
 if(!invitation)throw new ApiError(404,'NOT_FOUND','Invited RFQ not found.');
 const quotes=await db.supplierQuote.findMany({where:{rfqId,supplierId},
  select:quoteSelect,orderBy:{version:'desc'},take:50});
 return quotes.map(quoteDTO);
}
export async function customerQuotes(db:PrismaClient,userId:string,rfqId:string) {
 uuid(rfqId,'rfqId');
 const r=await db.rfq.findFirst({where:{id:rfqId,customerId:userId},select:{id:true}});
 if(!r)throw new ApiError(404,'NOT_FOUND','RFQ not found.');
 const quotes=await db.supplierQuote.findMany({where:{rfqId,
   status:{in:['SUBMITTED','ACCEPTED','REVISED','REJECTED','WITHDRAWN']}
 },select:quoteSelect,orderBy:[{supplierId:'asc'},{version:'desc'}],take:100});
 return quotes.map(quoteDTO);
}
export async function acceptCustomerQuote(db:PrismaClient,userId:string,rfqId:string,quoteId:string) {
 uuid(rfqId,'rfqId');uuid(quoteId,'quoteId');
 return serializable(db,async tx=>{
  const r=await lockedRfq(tx,rfqId,userId);
  isOpen(r);
  const quote=await tx.supplierQuote.findFirst({where:{id:quoteId,rfqId,status:'SUBMITTED'},
   select:{id:true,supplierId:true,validUntil:true}});
  if(!quote)throw new ApiError(404,'NOT_FOUND','Submitted quote not found.');
  if(quote.validUntil&&quote.validUntil.getTime()<=Date.now())
   throw new ApiError(409,'QUOTE_EXPIRED','Quote validity has passed.');
  const supplier=await tx.supplier.findUnique({where:{id:quote.supplierId},
   select:{approval:true,suspendedAt:true}});
  if(supplier?.approval!=='APPROVED'||supplier.suspendedAt)
   throw new ApiError(409,'SUPPLIER_UNAVAILABLE','Supplier is no longer approved.');
  await tx.supplierQuote.update({where:{id:quote.id},
   data:{status:'ACCEPTED',acceptedAt:new Date(),acceptedById:userId}});
  await tx.supplierQuote.updateMany({where:{rfqId,id:{not:quote.id},status:'SUBMITTED'},
   data:{status:'REJECTED'}});
  await tx.rfq.update({where:{id:rfqId},data:{status:'AWARDED'}});
  await event(tx,rfqId,userId,'RFQ_QUOTE_ACCEPTED');
  return {rfqId,quoteId:quote.id,status:'AWARDED' as const,
   message:'Quote accepted. Order and payment will be created in the checkout workflow.'};
 });
}
