import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,requiredString,uuid,integer,quantity,rupeePrice,paise,specification} from './catalog-validation';
import {postalCode} from './delivery-validation';

export {record,requiredString,uuid,integer,quantity,rupeePrice,paise};
export function futureDate(v:unknown,name:string,maxDays=180):Date {
 if(typeof v!=='string'||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?Z$/.test(v))
  throw new ApiError(400,'INVALID_DATE','Use an ISO UTC date for '+name+'.');
 const d=new Date(v);
 if(Number.isNaN(d.getTime())||d.getTime()<=Date.now()+60000||
    d.getTime()>Date.now()+maxDays*86400000)
  throw new ApiError(400,'INVALID_DATE','Date must be in the allowed future window.');
 return d;
}
export function siteSnapshot(v:unknown):Prisma.InputJsonObject {
 const o=record(v,['city','postalCode','siteNotes']);
 return {
  city:requiredString(o.city,'city',120),
  postalCode:postalCode(o.postalCode),
  ...(o.siteNotes===undefined?{}:{siteNotes:requiredString(o.siteNotes,'siteNotes',300)})
 };
}
export type NewRfqItem={productId:string|null;description:string;quantity:Prisma.Decimal;unitCode:string;specification?:Prisma.InputJsonObject};
export function createRfqInput(v:unknown) {
 const o=record(v,['projectId','siteSnapshot','notes','responseDueAt','items']);
 if(!Array.isArray(o.items)||o.items.length<1||o.items.length>30)
  throw new ApiError(400,'INVALID_RFQ_ITEMS','RFQ requires 1 to 30 material lines.');
 const items:NewRfqItem[]=o.items.map(raw=>{
  const x=record(raw,['productId','description','quantity','unitCode','specification']);
  const unitCode=requiredString(x.unitCode,'unitCode',20);
  if(!/^[A-Z0-9][A-Z0-9._-]*$/.test(unitCode))throw new ApiError(400,'INVALID_UNIT','Invalid material unit.');
  return {
   productId:x.productId===null||x.productId===undefined?null:uuid(x.productId,'productId'),
   description:requiredString(x.description,'description',500),
   quantity:quantity(x.quantity),
   unitCode,
   ...(x.specification===undefined?{}:{specification:specification(x.specification)})
  };
 });
 return {
  projectId:o.projectId===undefined||o.projectId===null?null:uuid(o.projectId,'projectId'),
  siteSnapshot:siteSnapshot(o.siteSnapshot),
  notes:o.notes===undefined||o.notes===null?null:requiredString(o.notes,'notes',1000),
  responseDueAt:o.responseDueAt===undefined||o.responseDueAt===null?null:futureDate(o.responseDueAt,'responseDueAt',90),
  items
 };
}
export function quoteInput(v:unknown) {
 const o=record(v,['lines','deliveryPaise','deliveryTerms','validUntil']);
 if(!Array.isArray(o.lines)||o.lines.length===0||o.lines.length>30)
  throw new ApiError(400,'INVALID_QUOTE_LINES','Quote must price all RFQ lines.');
 const seen=new Set<string>();
 const lines=o.lines.map(raw=>{
  const x=record(raw,['rfqItemId','listingId','quantity','unitCode','unitPrice','taxRateBps']);
  const rfqItemId=uuid(x.rfqItemId,'rfqItemId');
  if(seen.has(rfqItemId))throw new ApiError(400,'DUPLICATE_RFQ_ITEM','Each RFQ item must appear once.');
  seen.add(rfqItemId);
  const unitCode=requiredString(x.unitCode,'unitCode',20);
  if(!/^[A-Z0-9][A-Z0-9._-]*$/.test(unitCode))throw new ApiError(400,'INVALID_UNIT','Invalid unit.');
  return {
   rfqItemId,listingId:x.listingId===undefined||x.listingId===null?null:uuid(x.listingId,'listingId'),
   quantity:quantity(x.quantity),unitCode,unitPrice:rupeePrice(x.unitPrice),
   taxRateBps:integer(x.taxRateBps,'taxRateBps',0,10000),
  };
 });
 return {
  lines,deliveryPaise:o.deliveryPaise===undefined?0n:paise(o.deliveryPaise,'deliveryPaise'),
  deliveryTerms:o.deliveryTerms===undefined||o.deliveryTerms===null?null:requiredString(o.deliveryTerms,'deliveryTerms',500),
  validUntil:o.validUntil===undefined||o.validUntil===null?null:futureDate(o.validUntil,'validUntil',90)
 };
}
const MAX_PAISE=100000000000n;
export function boundedPaise(value:bigint):bigint {
 if(value<0n||value>MAX_PAISE)throw new ApiError(400,'AMOUNT_OUT_OF_RANGE','Amount is outside supported order limits.');
 return value;
}
// UnitPrice is INR per sale unit. Quote price is tax-exclusive. Round the
// line subtotal and each line's tax to whole paise using Decimal HALF_UP.
export function quoteLineAmounts(quantity:Prisma.Decimal,unitPrice:Prisma.Decimal,taxRateBps:number){
 const netPaise=boundedPaise(BigInt(quantity.mul(unitPrice).mul(100).toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0)));
 const taxPaise=boundedPaise(BigInt(new Prisma.Decimal(netPaise.toString()).mul(taxRateBps)
  .div(10000).toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0)));
 return {netPaise,taxPaise,lineTotalPaise:boundedPaise(netPaise+taxPaise)};
}
