import {serializable} from './transaction';
import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {listingFields,record,uuid,integer,exactDecimal,requireNonemptyPatch} from './catalog-validation';
import {requireCatalogImage} from './catalog-photos';
import {listingDTO} from './catalog-read';
import {requireAdminPermission,requireSupplierPermission} from './permissions';
import {publishOutbox} from './outbox';
import {executeIdempotently} from './idempotency';

type Tx=Prisma.TransactionClient;
const serial=serializable;
const select={
 id:true,productId:true,supplierId:true,sku:true,unitCode:true,packSize:true,
 minOrderQty:true,stepQty:true,maxOrderQty:true,unitPrice:true,mrpPaise:true,
 taxRateBps:true,taxInclusive:true,status:true,active:true,version:true,publishedAt:true,deletedAt:true,
 priceTiers:{where:{effectiveUntil:null},select:{
   minQty:true,pricePerUnit:true,effectiveFrom:true,effectiveUntil:true
 },orderBy:{minQty:'asc' as const}},
 product:{select:{name:true,imageUrl:true}},
} as const;
const knownUnits:Record<string,{name:string,dimension:'COUNT'|'MASS'|'LENGTH'|'AREA'|'VOLUME'}>={
 BAG:{name:'Bag',dimension:'COUNT'},PIECE:{name:'Piece',dimension:'COUNT'},
 BOX:{name:'Box',dimension:'COUNT'},BUNDLE:{name:'Bundle',dimension:'COUNT'},
 KG:{name:'Kg',dimension:'MASS'},TONNE:{name:'Tonne',dimension:'MASS'},
 METER:{name:'Meter',dimension:'LENGTH'},SQM:{name:'Square meter',dimension:'AREA'},
 CUM:{name:'Cubic meter',dimension:'VOLUME'},LITRE:{name:'Litre',dimension:'VOLUME'},
};
function warehouseCodes(name:string,supplierId:string,unitCode:string){
 const stem=name.toUpperCase().replace(/[^A-Z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,36)||'ITEM';
 const nonce=randomUUID().replace(/-/g,'').slice(0,6).toUpperCase();
 return {
  productCode:`${stem}-${supplierId.replace(/-/g,'').slice(0,6).toUpperCase()}${nonce}`.slice(0,80),
  sku:`${stem}-${unitCode}-${nonce}`.slice(0,100),
 };
}
async function ensureSellingUnit(tx:Tx,unitCode:string){
 const known=knownUnits[unitCode];
 const unit=await tx.unitOfMeasure.findUnique({where:{code:unitCode},select:{active:true}});
 if(unit?.active)return;
 if(!known)throw new ApiError(422,'UNIT_INACTIVE','Choose bag, kg, piece, or another unit.');
 if(unit)await tx.unitOfMeasure.update({where:{code:unitCode},data:{active:true}});
 else await tx.unitOfMeasure.create({data:{
  code:unitCode,name:known.name,dimension:known.dimension,scale:3,active:true,
 }});
}
async function supplierCategory(tx:Tx,categoryId?:string){
 if(categoryId){
  const category=await tx.category.findUnique({where:{id:categoryId},select:{active:true}});
  if(!category?.active)throw new ApiError(422,'CATEGORY_INACTIVE','Choose a category.');
  return categoryId;
 }
 const general=await tx.category.upsert({
  where:{slug:'general'},update:{active:true},
  create:{slug:'general',name:'General',active:true},select:{id:true},
 });
 return general.id;
}
async function seller(tx:Tx,actorId:string,supplierId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierMember" WHERE "userId"=${actorId}::uuid AND "supplierId"=${supplierId}::uuid FOR SHARE`);
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${supplierId}::uuid FOR SHARE`);
 await requireSupplierPermission(tx,actorId,supplierId,'CATALOG_WRITE');
}
async function reviewer(tx:Tx,actorId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "userId" FROM "AdminMembership" WHERE "userId"=${actorId}::uuid FOR SHARE`);
 await requireAdminPermission(tx,actorId,'CATALOG_APPROVE');
}
async function audit(tx:Tx,actor:string,entityId:string,action:string) {
 await tx.auditEvent.create({data:{actorUserId:actor,actorRole:action.startsWith('ADMIN')?'ADMIN_CATALOG':'SUPPLIER_CATALOG',
  action,entityType:'SupplierListing',entityId}});
 await publishOutbox(tx,{eventKey:'catalog:'+randomUUID(),aggregateType:'SupplierListing',
  aggregateId:entityId,eventType:action,payload:{listingId:entityId}});
}
async function assertCatalogReady(tx:Tx,productId:string,unitCode:string) {
 const [product,unit]=await Promise.all([
  tx.product.findUnique({where:{id:productId},select:{active:true,category:{select:{active:true}}}}),
  tx.unitOfMeasure.findUnique({where:{code:unitCode},select:{active:true}})
 ]);
 if(!product?.active || !product.category.active)throw new ApiError(422,'PRODUCT_NOT_PUBLISHED','Choose an active catalog product.');
 if(!unit?.active)throw new ApiError(422,'UNIT_INACTIVE','Choose an active unit of measure.');
}
async function findListing(tx:Tx,supplierId:string,id:string) {
 const row=await tx.supplierListing.findFirst({where:{id,supplierId,deletedAt:null},select});
 if(!row)throw new ApiError(404,'NOT_FOUND','Listing not found.');
 return row;
}
async function casUpdate(tx:Tx,id:string,version:number,data:Prisma.SupplierListingUpdateManyMutationInput) {
 const updated=await tx.supplierListing.updateMany({where:{id,version,deletedAt:null},data:{
  ...data,version:{increment:1}
 }});
 if(updated.count!==1)throw new ApiError(409,'LISTING_VERSION_CONFLICT','Refresh the listing and retry with the current version.');
}

export async function ownListings(db:PrismaClient,actorId:string,supplierId:string) {
 uuid(supplierId,'supplierId');
 await requireSupplierPermission(db,actorId,supplierId,'SUPPLIER_READ');
 const rows=await db.supplierListing.findMany({
  where:{supplierId,deletedAt:null},select,orderBy:{createdAt:'desc'},take:100,
 });
 return rows.map(listingDTO);
}
export async function createListing(db:PrismaClient,actorId:string,supplierId:string,key:string,payload:unknown) {
 uuid(supplierId,'supplierId');
 const data=listingFields(payload);
 if(data.expectedVersion!==undefined)throw new ApiError(400,'UNEXPECTED_VERSION','Version not valid for new listing.');
 const productId=data.productId as string|undefined,unitCode=data.unitCode as string;
 const values={
  unitCode,supplierId,
  packSize:data.packSize as Prisma.Decimal,minOrderQty:data.minOrderQty as Prisma.Decimal,
  stepQty:data.stepQty as Prisma.Decimal,unitPrice:data.unitPrice as Prisma.Decimal,
  ...(data.maxOrderQty!==undefined?{maxOrderQty:data.maxOrderQty as Prisma.Decimal|null}:{}),
  ...(data.mrpPaise!==undefined?{mrpPaise:data.mrpPaise as bigint|null}:{}),
  taxRateBps:data.taxRateBps as number,taxInclusive:data.taxInclusive as boolean,
  status:'APPROVED' as const,active:true,publishedAt:new Date(),
 };
  if(values.maxOrderQty!==undefined&&values.maxOrderQty!==null&&values.maxOrderQty.lt(values.minOrderQty))
  throw new ApiError(400,'INVALID_QUANTITY_RANGE','Maximum below minimum.');
  if(values.unitPrice.lte(0))
   throw new ApiError(422,'INVALID_PUBLIC_PRICE','Unit price must be positive.');
 const saved=await executeIdempotently(db,{
  actorId,scope:'supplier-listing:'+supplierId,requestKey:key,requestPayload:payload,
  expiresAt:new Date(Date.now()+86_400_000),
  execute:async tx=>{
   await seller(tx,actorId,supplierId);
   let resolvedProduct=productId,resolvedSku=data.sku as string|undefined;
   const imageUrl=data.imageUrl as string|undefined;
   if(imageUrl)await requireCatalogImage(tx,imageUrl);
   if(!resolvedProduct){
    await ensureSellingUnit(tx,unitCode);
    const categoryId=await supplierCategory(tx,data.categoryId as string|undefined);
    const codes=warehouseCodes(data.productName as string,supplierId,unitCode);
    const product=await tx.product.create({data:{
     code:codes.productCode,name:data.productName as string,categoryId,
     specification:{},active:true,...(imageUrl?{imageUrl}:{}),
    },select:{id:true}});
    await tx.auditEvent.create({data:{
     actorUserId:actorId,actorSupplierId:supplierId,actorRole:'SUPPLIER_CATALOG',
     action:'SUPPLIER_PRODUCT_CREATED',entityType:'Product',entityId:product.id,
    }});
    resolvedProduct=product.id;
    resolvedSku=resolvedSku??codes.sku;
   }
   if(!resolvedSku)throw new ApiError(400,'SKU_REQUIRED','Enter a product code.');
   if(resolvedProduct&&imageUrl&&productId)
    await tx.product.update({where:{id:resolvedProduct},data:{imageUrl}});
   await assertCatalogReady(tx,resolvedProduct,unitCode);
   const created=await tx.supplierListing.create({data:{
    ...values,productId:resolvedProduct,sku:resolvedSku,
   },select:{id:true}});
   await audit(tx,actorId,created.id,'SUPPLIER_LISTING_CREATED');
   return {result:created.id,resultRef:created.id,responseCode:201};
  },
 });
 // Always enforce *current* DB membership, including on replay.
 await requireSupplierPermission(db,actorId,supplierId,'CATALOG_WRITE');
 const row=await db.supplierListing.findFirst({where:{id:saved.resultRef,supplierId,deletedAt:null},select});
 if(!row)throw new ApiError(404,'NOT_FOUND','Listing not found.');
 return {listing:listingDTO(row),replayed:saved.kind==='replayed'};
}
export async function updateListing(db:PrismaClient,actorId:string,supplierId:string,id:string,payload:unknown) {
 uuid(supplierId,'supplierId');uuid(id,'listingId');
 const data=listingFields(payload,true);
  const expectedVersion=data.expectedVersion as number;
 const imageUrl=data.imageUrl as string|undefined;
 delete data.expectedVersion;
 delete data.imageUrl;
 return serial(db,async tx=>{
  await seller(tx,actorId,supplierId);
  const row=await findListing(tx,supplierId,id);
  if(!['DRAFT','REJECTED','APPROVED','PENDING'].includes(row.status))
   throw new ApiError(409,'LISTING_LOCKED','Listing cannot be edited in this state.');
  if(row.version!==expectedVersion)throw new ApiError(409,'LISTING_VERSION_CONFLICT','Refresh listing before editing.');
  const nextPrice=(data.unitPrice as Prisma.Decimal|undefined)??row.unitPrice;
  if(row.priceTiers.some(tier=>tier.pricePerUnit.gt(nextPrice)))
   throw new ApiError(422,'INVALID_PRICE_TIERS','Lower the quantity prices before lowering the selling price.');
  const normalized={
   ...data,status:'APPROVED' as const,active:true,
   publishedAt:row.publishedAt??new Date(),
  };
  const nextMin=data.minOrderQty as Prisma.Decimal|undefined;
  const nextMax=data.maxOrderQty as Prisma.Decimal|null|undefined;
  const min=nextMin??row.minOrderQty,max=nextMax===undefined?row.maxOrderQty:nextMax;
  if(max!==null&&max.lt(min))throw new ApiError(400,'INVALID_QUANTITY_RANGE','Maximum below minimum.');
  if(imageUrl){
   await requireCatalogImage(tx,imageUrl);
   await tx.product.update({where:{id:row.productId},data:{imageUrl}});
  }
  await casUpdate(tx,id,expectedVersion,normalized);
  await audit(tx,actorId,id,'SUPPLIER_LISTING_UPDATED');
  const updated=await findListing(tx,supplierId,id);
  return listingDTO(updated);
 });
}
export async function submitListing(db:PrismaClient,actorId:string,supplierId:string,id:string,payload:unknown) {
 uuid(supplierId,'supplierId');uuid(id,'listingId');
 const o=record(payload,['expectedVersion']);
 const version=integer(o.expectedVersion,'expectedVersion',0,2147483647);
 return serial(db,async tx=>{
  await seller(tx,actorId,supplierId);
  const row=await findListing(tx,supplierId,id);
  if(row.version!==version)throw new ApiError(409,'LISTING_VERSION_CONFLICT','Refresh listing before submitting.');
  if(!['DRAFT','REJECTED','PENDING'].includes(row.status))throw new ApiError(409,'INVALID_LISTING_STATE','Only unpublished listings can be shown to customers.');
  await assertCatalogReady(tx,row.productId,row.unitCode);
  if(row.unitPrice.lte(0))throw new ApiError(422,'INVALID_PUBLIC_PRICE','Publishable price must be positive.');
  await casUpdate(tx,id,version,{
   status:'APPROVED',active:true,publishedAt:row.publishedAt??new Date(),
  });
  await audit(tx,actorId,id,'SUPPLIER_LISTING_PUBLISHED');
  return listingDTO(await findListing(tx,supplierId,id));
 });
}
export async function replacePriceTiers(db:PrismaClient,actorId:string,supplierId:string,id:string,payload:unknown) {
 uuid(supplierId,'supplierId');uuid(id,'listingId');
 const o=record(payload,['expectedVersion','tiers']);
 const version=integer(o.expectedVersion,'expectedVersion',0,2147483647);
 if(!Array.isArray(o.tiers)||o.tiers.length>12)throw new ApiError(400,'INVALID_PRICE_TIERS','Maximum 12 quantity tiers.');
 const tiers=o.tiers.map((t,i)=>{
  const row=record(t,['minQty','pricePerUnit']);
  return {minQty:exactDecimal(row.minQty,'minQty',15,3,true),
    pricePerUnit:exactDecimal(row.pricePerUnit,'pricePerUnit',14,4,true),position:i};
 });
 for(let i=1;i<tiers.length;i++) {
  if(tiers[i].minQty.lte(tiers[i-1].minQty))throw new ApiError(400,'INVALID_PRICE_TIERS','Tiers must be strictly increasing by quantity.');
  if(tiers[i].pricePerUnit.gt(tiers[i-1].pricePerUnit))
   throw new ApiError(400,'INVALID_PRICE_TIERS','Higher quantities cannot increase the tier price.');
 }
 return serial(db,async tx=>{
  await seller(tx,actorId,supplierId);
  const row=await findListing(tx,supplierId,id);
  if(row.version!==version)throw new ApiError(409,'LISTING_VERSION_CONFLICT','Refresh listing before replacing tiers.');
  if(!['DRAFT','REJECTED','APPROVED','PENDING'].includes(row.status))
   throw new ApiError(409,'LISTING_LOCKED','Tier prices cannot change in this state.');
  if(tiers.length&&tiers[0].pricePerUnit.gt(row.unitPrice))
   throw new ApiError(400,'INVALID_PRICE_TIERS','Tier price cannot exceed base unit price.');
  for(const tier of tiers)if(tier.minQty.lt(row.minOrderQty))
   throw new ApiError(400,'INVALID_PRICE_TIERS','Tier minimum below listing minimum order.');
  await casUpdate(tx,id,version,{
   status:'APPROVED',active:true,publishedAt:row.publishedAt??new Date(),
  });
  // Preserve formerly published tier history, but remove unapproved staged tiers.
  await tx.supplierPriceTier.deleteMany({where:{listingId:id,active:false,effectiveUntil:null}});
  await tx.$executeRaw(Prisma.sql`
    UPDATE "SupplierPriceTier" SET "active"=false,
      "effectiveUntil"=GREATEST(NOW(), "effectiveFrom" + INTERVAL '1 millisecond')
    WHERE "listingId"=${id}::uuid AND "active"=true AND "effectiveUntil" IS NULL
  `);
  const latest=await tx.supplierPriceTier.findFirst({where:{listingId:id},
    orderBy:{effectiveFrom:'desc'},select:{effectiveFrom:true}});
  const from=new Date(Math.max(Date.now(),(latest?.effectiveFrom.getTime()??0)+1));
  if(tiers.length)await tx.supplierPriceTier.createMany({data:tiers.map(t=>({
   listingId:id,minQty:t.minQty,pricePerUnit:t.pricePerUnit,active:true,effectiveFrom:from,
  }))});
  await audit(tx,actorId,id,'SUPPLIER_LISTING_TIERS_REPLACED');
  return listingDTO(await findListing(tx,supplierId,id));
 });
}
export async function pendingListings(db:PrismaClient,actor:string) {
 await requireAdminPermission(db,actor,'CATALOG_APPROVE');
 const rows=await db.supplierListing.findMany({where:{status:'PENDING',deletedAt:null},
  select,orderBy:{updatedAt:'asc'},take:100});
 return rows.map(listingDTO);
}
export async function reviewListing(db:PrismaClient,actor:string,id:string,payload:unknown) {
 uuid(id,'listingId');
 const o=record(payload,['decision','expectedVersion']);
 const decision=o.decision;
 if(!['APPROVE','REJECT','SUSPEND'].includes(String(decision)))
  throw new ApiError(400,'INVALID_REVIEW','Invalid review decision.');
 const version=integer(o.expectedVersion,'expectedVersion',0,2147483647);
 return serial(db,async tx=>{
  await reviewer(tx,actor);
  // Row lock serializes tier activation against the supplier's reprice attempt.
  await tx.$queryRaw(Prisma.sql`SELECT id FROM "SupplierListing" WHERE id=${id}::uuid FOR UPDATE`);
  const row=await tx.supplierListing.findUnique({where:{id},select});
  if(!row||row.status==='ARCHIVED'||row.deletedAt)throw new ApiError(404,'NOT_FOUND','Listing not found.');
  if(row.version!==version)throw new ApiError(409,'LISTING_VERSION_CONFLICT','Refresh listing before review.');
  if(decision==='SUSPEND' && row.status!=='APPROVED')
   throw new ApiError(409,'INVALID_LISTING_STATE','Only approved listings may be suspended.');
  if(decision!=='SUSPEND'&&row.status!=='PENDING'&&row.status!=='SUSPENDED')
   throw new ApiError(409,'INVALID_LISTING_STATE','Only pending or suspended listings may be approved or rejected.');
  if(decision==='APPROVE'){
   const supplier=await tx.supplier.findUnique({where:{id:row.supplierId},select:{approval:true,suspendedAt:true}});
   if(supplier?.approval!=='APPROVED'||supplier.suspendedAt)
    throw new ApiError(409,'SUPPLIER_NOT_APPROVED','Supplier approval required.');
   await assertCatalogReady(tx,row.productId,row.unitCode);
   if(row.unitPrice.lte(0))throw new ApiError(422,'INVALID_PUBLIC_PRICE','Unit price must be positive.');
   const currentTiers=[...row.priceTiers].sort((a,b)=>a.minQty.cmp(b.minQty));
   for(let i=0;i<currentTiers.length;i++){
     const tier=currentTiers[i];
     if(tier.minQty.lt(row.minOrderQty)||tier.pricePerUnit.gt(row.unitPrice)||tier.pricePerUnit.lte(0))
       throw new ApiError(422,'INVALID_PRICE_TIERS','Existing quantity tiers must match the submitted base price and minimum order.');
     if(i>0 && (tier.minQty.lte(currentTiers[i-1].minQty)||
       tier.pricePerUnit.gt(currentTiers[i-1].pricePerUnit)))
       throw new ApiError(422,'INVALID_PRICE_TIERS','Quantity-tier prices must decrease as quantity increases.');
   }
   await tx.supplierPriceTier.updateMany({where:{listingId:id,active:false,effectiveUntil:null},
    data:{active:true}});
  }
  await casUpdate(tx,id,version,{
   status:decision==='APPROVE'?'APPROVED':decision==='REJECT'?'REJECTED':'SUSPENDED',
   active:decision==='APPROVE',
   publishedAt:decision==='APPROVE'?new Date():null,
  });
  if(decision!=='APPROVE')await tx.supplierPriceTier.updateMany({
   where:{listingId:id,active:true},data:{active:false}
  });
  await audit(tx,actor,id,'ADMIN_LISTING_'+String(decision==='APPROVE'?'APPROVED':decision==='REJECT'?'REJECTED':'SUSPENDED'));
  return listingDTO((await tx.supplierListing.findUniqueOrThrow({where:{id},select})));
 });
}
