import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {computeDiscount} from './promotion-service';
import {splitOrderGst} from './checkout-tax';
import {allocatePaise,checkedQuantity,MAX_ORDER,money,roundedPaise,taxFor} from './checkout-validation';

type Tx=Prisma.TransactionClient;
export type PricedItem={
 listingId:string;supplierId:string;productName:string;sku:string;brandName:string|null;
 hsnCode:string|null;unitCode:string;packSize:string;quantity:string;unitPrice:string;
 listingVersion:number;taxRateBps:number;taxInclusive:boolean;
 taxablePaise:string;taxPaise:string;discountPaise:string;lineTotalPaise:string;
 cgstPaise:string;sgstPaise:string;utgstPaise:string;igstPaise:string;cessPaise:string;
};
export type PricedSupplier={
 supplierId:string;areaId:string;rateId:string;
 minimumPaise:string;freeAbovePaise:string|null;
 subtotalPaise:string;discountPaise:string;taxPaise:string;deliveryPaise:string;
 totalPaise:string;
};
export type PricedCheckout={
 cartVersion:number;addressId:string;siteId:string|null;addressSnapshot:Prisma.InputJsonObject;
 promotionCode:string|null;promotionType:string|null;promotionAmountPaise:string;
 deliveryBeforePromotionPaise:string;
 subtotalPaise:string;discountPaise:string;taxPaise:string;deliveryPaise:string;
 totalPaise:string;items:PricedItem[];suppliers:PricedSupplier[];
};
type Rate={
 areaId:string;rateId:string;minimumPaise:bigint;feePaise:bigint;freeAbovePaise:bigint|null
};
async function eligibleRate(tx:Tx,addressId:string,supplierId:string):Promise<Rate> {
 const rows=await tx.$queryRaw<{
  areaId:string;rateId:string;minimumPaise:bigint;baseFeePaise:bigint;
  handlingFeePaise:bigint;freeAbovePaise:bigint|null;
 }[]>(Prisma.sql`
   SELECT sa.id AS "areaId",rate.id AS "rateId",
    ssa."minimumPaise",rate."baseFeePaise",rate."handlingFeePaise",rate."freeAbovePaise"
   FROM "Address" addr
   JOIN "City" city ON city.id=addr."cityId" AND city.active=true
   JOIN "ServiceArea" sa ON sa."cityId"=city.id AND sa.active=true
   JOIN "SupplierServiceArea" ssa ON ssa."areaId"=sa.id
    AND ssa."supplierId"=${supplierId}::uuid AND ssa.active=true
   JOIN "Supplier" supplier ON supplier.id=ssa."supplierId"
    AND supplier.approval='APPROVED' AND supplier."suspendedAt" IS NULL
   JOIN "SupplierDeliveryRate" rate ON rate."supplierId"=ssa."supplierId"
    AND rate."areaId"=sa.id AND rate.active=true
    AND rate."effectiveFrom"<=NOW()
    AND (rate."effectiveTo" IS NULL OR rate."effectiveTo">NOW())
   WHERE addr.id=${addressId}::uuid AND addr."deletedAt" IS NULL
    AND addr."postalCode"=ANY(sa."postalCodes")
    AND (
      (sa."geoBoundary" IS NOT NULL AND addr."geoPoint" IS NOT NULL
       AND ST_Covers(sa."geoBoundary"::geometry,addr."geoPoint"::geometry))
      OR (sa."geoBoundary" IS NULL AND sa."geoCenter" IS NOT NULL
       AND sa."radiusKm" IS NOT NULL AND addr."geoPoint" IS NOT NULL
       AND ST_DWithin(sa."geoCenter",addr."geoPoint",sa."radiusKm"::double precision*1000))
      OR (sa."geoBoundary" IS NULL AND sa."geoCenter" IS NULL AND sa."radiusKm" IS NULL)
    )
    AND rate."perKmPaise"=0 AND rate."perTonneKmPaise"=0
    AND rate."perCubicMetreKmPaise"=0
    AND NOT EXISTS (
      SELECT 1 FROM "SupplierFreightBracket" bracket
      WHERE bracket."deliveryRateId"=rate.id AND bracket.active=true
    )
   ORDER BY (rate."baseFeePaise"+rate."handlingFeePaise"),sa.id,rate.id
   LIMIT 1
 `);
 if(!rows.length)throw new ApiError(422,'DELIVERY_UNAVAILABLE',
  'Supplier does not have a supported delivery rate for this address. Request a freight quote.');
 const p=rows[0];
 return {areaId:p.areaId,rateId:p.rateId,minimumPaise:p.minimumPaise,
  feePaise:money(p.baseFeePaise+p.handlingFeePaise),freeAbovePaise:p.freeAbovePaise};
}
export async function lockedCartSnapshot(tx:Tx,customerId:string){
 const exists=await tx.cart.findUnique({where:{customerId},select:{id:true}});
 if(!exists)throw new ApiError(409,'CART_EMPTY','Add products before checkout.');
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Cart" WHERE id=${exists.id}::uuid FOR UPDATE`);
 const row=await tx.cart.findUniqueOrThrow({where:{id:exists.id},select:{
  id:true,version:true,lines:{select:{listingId:true,quantity:true},orderBy:{listingId:'asc'}}
 }});
 if(row.lines.length===0)throw new ApiError(409,'CART_EMPTY','Cart has no products.');
 return row;
}
export async function priceCheckout(tx:Tx,customerId:string,opts:{
 addressId:string;siteId:string|null;promotionCode:string|null
}):Promise<PricedCheckout> {
 const cart=await lockedCartSnapshot(tx,customerId);
 const addr=await tx.address.findFirst({where:{
  id:opts.addressId,userId:customerId,deletedAt:null,city:{active:true}
 },select:{
  id:true,cityId:true,recipientName:true,phoneE164:true,line1:true,line2:true,locality:true,
  postalCode:true,latitude:true,longitude:true,instructions:true,
  city:{select:{name:true,stateCode:true}}
 }});
 if(!addr)throw new ApiError(404,'ADDRESS_NOT_FOUND','Delivery address not found.');
 if(opts.siteId){
  const site=await tx.constructionSite.findFirst({where:{
   id:opts.siteId,customerId,active:true,addressId:addr.id
  },select:{id:true}});
  if(!site)throw new ApiError(404,'SITE_NOT_FOUND','Site is not available at this address.');
 }
 const addressSnapshot:Prisma.InputJsonObject={
  cityId:addr.cityId,city:addr.city.name,stateCode:addr.city.stateCode,
  recipientName:addr.recipientName,phoneE164:addr.phoneE164,line1:addr.line1,
  line2:addr.line2??'',locality:addr.locality,postalCode:addr.postalCode,
  latitude:addr.latitude?.toString()??'',longitude:addr.longitude?.toString()??'',
  instructions:addr.instructions??''
 };
 const listingIds=cart.lines.map(x=>x.listingId);
 const listings=await tx.supplierListing.findMany({where:{
  id:{in:listingIds},active:true,status:'APPROVED',publishedAt:{not:null},deletedAt:null,
  supplier:{approval:'APPROVED',suspendedAt:null},
  product:{active:true,category:{active:true}},unit:{active:true}
 },select:{
  id:true,supplierId:true,sku:true,unitCode:true,unitPrice:true,version:true,
  minOrderQty:true,maxOrderQty:true,stepQty:true,packSize:true,taxRateBps:true,taxInclusive:true,
  product:{select:{name:true,hsnCode:true,brand:{select:{name:true}}}},
  supplier:{select:{gstin:true,gstRegistration:true,verifiedAt:true}},
  priceTiers:{where:{active:true,effectiveUntil:null,effectiveFrom:{lte:new Date()}},
   select:{minQty:true,pricePerUnit:true},orderBy:{minQty:'desc'}},
  balances:{where:{warehouse:{active:true}},select:{onHandQty:true,reservedQty:true}},
 }});
 if(listings.length!==cart.lines.length)
  throw new ApiError(409,'LISTING_CHANGED','A product is no longer available. Refresh cart.');
 const byId=new Map(listings.map(l=>[l.id,l]));
 const prices:{item:PricedItem;net:bigint;tax:bigint;gross:bigint;
 gst:{gstin:string|null;gstRegistration:string;verifiedAt:Date|null}}[]=[];
 for(const line of cart.lines){
  const listing=byId.get(line.listingId)!;
  checkedQuantity(listing,line.quantity);
  const available=listing.balances.reduce((sum,b)=>sum.plus(b.onHandQty.minus(b.reservedQty)),
   new Prisma.Decimal(0));
  if(available.lt(line.quantity))throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK',
   'Requested quantity is not currently in stock.');
  const selected=listing.priceTiers.find(t=>line.quantity.gte(t.minQty));
  const unitPrice=selected?.pricePerUnit??listing.unitPrice;
  const grossOrNet=roundedPaise(line.quantity.mul(unitPrice));
  if(grossOrNet<=0n)throw new ApiError(422,'INVALID_PRICE','Listing price is too small.');
  let net:bigint,tax:bigint;
  if(listing.taxInclusive&&listing.taxRateBps>0){
   net=money(BigInt(new Prisma.Decimal(grossOrNet.toString()).mul(10000)
    .div(10000+listing.taxRateBps).toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0)));
   tax=grossOrNet-net;
  }else{
   net=grossOrNet;tax=taxFor(net,listing.taxRateBps);
  }
  prices.push({item:{
   listingId:listing.id,supplierId:listing.supplierId,productName:listing.product.name,
   sku:listing.sku,brandName:listing.product.brand?.name??null,hsnCode:listing.product.hsnCode,
   unitCode:listing.unitCode,packSize:listing.packSize.toString(),quantity:line.quantity.toString(),
   unitPrice:unitPrice.toString(),listingVersion:listing.version,taxRateBps:listing.taxRateBps,
   taxInclusive:listing.taxInclusive,taxablePaise:net.toString(),taxPaise:'0',
   discountPaise:'0',lineTotalPaise:'0',cgstPaise:'0',sgstPaise:'0',
   utgstPaise:'0',igstPaise:'0',cessPaise:'0'
  },net,tax,gross:money(net+tax),gst:listing.supplier});
 }
 const sum=(values:readonly bigint[])=>money(values.reduce((a,b)=>a+b,0n));
 const subtotal=sum(prices.map(p=>p.net));
 const supplierIds=[...new Set(prices.map(p=>p.item.supplierId))].sort();
 const groups=new Map<string,{rate:Rate;beforeFee:bigint;net:bigint;gross:bigint}>();
 for(const supplierId of supplierIds){
  const supplierLines=prices.filter(x=>x.item.supplierId===supplierId);
  const net=sum(supplierLines.map(x=>x.net)),gross=sum(supplierLines.map(x=>x.gross));
  const rate=await eligibleRate(tx,addr.id,supplierId);
  if(gross<rate.minimumPaise)
   throw new ApiError(422,'SUPPLIER_MINIMUM_NOT_MET','Supplier minimum material order not met.');
  const fee=rate.freeAbovePaise!==null&&gross>=rate.freeAbovePaise?0n:rate.feePaise;
  groups.set(supplierId,{rate,beforeFee:fee,net,gross});
 }
 const deliveryBefore=sum([...groups.values()].map(x=>x.beforeFee));
 let discount=0n,promotionType:string|null=null,promotionAmount=0n;
 if(opts.promotionCode){
  const now=new Date();
  const promo=await tx.promotion.findUnique({where:{code:opts.promotionCode}});
  if(!promo||!promo.active||promo.startsAt>now||promo.endsAt<=now)
   throw new ApiError(422,'PROMOTION_UNAVAILABLE','Promotion is unavailable or expired.');
  promotionType=promo.type;
  promotionAmount=computeDiscount(promo,subtotal,deliveryBefore);
  if(promotionAmount<=0n)throw new ApiError(422,'PROMOTION_NOT_APPLICABLE','Promotion does not reduce this order.');
  if(promo.type!=='FREE_DELIVERY')discount=promotionAmount;
 }
 const portions=allocatePaise(discount,prices.map(x=>x.net));
 for(let i=0;i<prices.length;i++){
  const p=prices[i],portion=portions[i];
  // For inclusive prices without a coupon, preserve exactly the original
  // displayed gross amount after backing GST out (avoid double rounding).
  const tax=portion===0n?p.tax:taxFor(p.net-portion,p.item.taxRateBps);
  const split=splitOrderGst(tax,p.gst,addr.city.stateCode);
  p.item.cgstPaise=split.cgstPaise.toString();p.item.sgstPaise=split.sgstPaise.toString();
  p.item.utgstPaise=split.utgstPaise.toString();p.item.igstPaise=split.igstPaise.toString();
  p.item.cessPaise=split.cessPaise.toString();
  p.item.discountPaise=portion.toString();p.item.taxPaise=tax.toString();
  p.item.lineTotalPaise=money(p.net-portion+tax).toString();
 }
 const tax=sum(prices.map(x=>BigInt(x.item.taxPaise)));
 const finalDelivery=promotionType==='FREE_DELIVERY'?0n:deliveryBefore;
 const total=money(subtotal-discount+tax+finalDelivery);
 const supplierGroups:PricedSupplier[]=supplierIds.map(supplierId=>{
  const group=groups.get(supplierId)!;
  const lines=prices.filter(x=>x.item.supplierId===supplierId).map(x=>x.item);
  const gDiscount=sum(lines.map(x=>BigInt(x.discountPaise)));
  const gTax=sum(lines.map(x=>BigInt(x.taxPaise)));
  const delivery=promotionType==='FREE_DELIVERY'?0n:group.beforeFee;
  return {supplierId,areaId:group.rate.areaId,rateId:group.rate.rateId,
   minimumPaise:group.rate.minimumPaise.toString(),
   freeAbovePaise:group.rate.freeAbovePaise?.toString()??null,
   subtotalPaise:group.net.toString(),discountPaise:gDiscount.toString(),
   taxPaise:gTax.toString(),deliveryPaise:delivery.toString(),
   totalPaise:money(group.net-gDiscount+gTax+delivery).toString()};
 });
 if(sum(supplierGroups.map(x=>BigInt(x.totalPaise)))!==total)
  throw new Error('CHECKOUT_ALLOCATION_MISMATCH');
 return {cartVersion:cart.version,addressId:addr.id,siteId:opts.siteId,
  addressSnapshot,promotionCode:opts.promotionCode,promotionType,
  promotionAmountPaise:promotionAmount.toString(),
  deliveryBeforePromotionPaise:deliveryBefore.toString(),
  subtotalPaise:subtotal.toString(),discountPaise:discount.toString(),
  taxPaise:tax.toString(),deliveryPaise:finalDelivery.toString(),totalPaise:total.toString(),
  items:prices.map(x=>x.item),suppliers:supplierGroups};
}
