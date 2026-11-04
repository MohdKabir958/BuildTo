import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,uuid,integer,quantity,requiredString} from './catalog-validation';

export {record,uuid,integer,quantity};
export function cartChange(input:unknown){
 const o=record(input,['quantity','expectedVersion']);
 return {quantity:quantity(o.quantity),expectedVersion:integer(o.expectedVersion,'expectedVersion',0,2147483646)};
}
export function cartVersion(input:unknown){
 const o=record(input,['expectedVersion']);
 return integer(o.expectedVersion,'expectedVersion',0,2147483646);
}
export function checkoutInput(input:unknown){
 const o=record(input,['addressId','siteId','expectedCartVersion','promotionCode']);
 let promotionCode:null|string=null;
 if(o.promotionCode!==undefined&&o.promotionCode!==null){
  promotionCode=requiredString(o.promotionCode,'promotionCode',60).toUpperCase();
  if(!/^[A-Z0-9][A-Z0-9_-]{2,59}$/.test(promotionCode))
   throw new ApiError(400,'INVALID_PROMOTION_CODE','Invalid promotion code.');
 }
 return {addressId:uuid(o.addressId,'addressId'),
  siteId:o.siteId===undefined||o.siteId===null?null:uuid(o.siteId,'siteId'),
  expectedCartVersion:integer(o.expectedCartVersion,'expectedCartVersion',0,2147483646),
  promotionCode};
}
export function placementInput(input:unknown){
 const o=record(input,['clientRequestId']);
 const clientRequestId=requiredString(o.clientRequestId,'clientRequestId',120);
 if(!/^[A-Za-z0-9._:-]{8,120}$/.test(clientRequestId))
  throw new ApiError(400,'INVALID_CLIENT_REQUEST_ID','Use an 8–120 character request ID.');
 return {clientRequestId};
}
export const MAX_ORDER=100000000000n;
export function money(x:bigint){
 if(x<0n||x>MAX_ORDER)throw new ApiError(422,'AMOUNT_OUT_OF_RANGE','Order exceeds supported amount.');
 return x;
}
export function roundedPaise(x:Prisma.Decimal):bigint{
 return money(BigInt(x.mul(100).toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0)));
}
export function taxFor(taxablePaise:bigint,bps:number){
 return money(BigInt(new Prisma.Decimal(taxablePaise.toString()).mul(bps)
  .div(10000).toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0)));
}
export function allocatePaise(total:bigint,weights:readonly bigint[]):bigint[]{
 const sum=weights.reduce((a,b)=>a+b,0n);
 if(total===0n)return weights.map(()=>0n);
 if(sum<=0n||total>sum)throw new ApiError(422,'DISCOUNT_ALLOCATION_INVALID','Discount exceeds eligible items.');
 const base=weights.map(w=>total*w/sum),remainders=weights.map(w=>total*w%sum);
 let remaining=total-base.reduce((a,b)=>a+b,0n);
 const indices=weights.map((_,i)=>i).sort((a,b)=>{
  const d=remainders[a]-remainders[b];
  return d===0n?a-b:d>0n?-1:1;
 });
 for(let i=0;remaining>0n;i++,remaining--)base[indices[i]]++;
 return base;
}
export function checkedQuantity(listing:{
 minOrderQty:Prisma.Decimal;stepQty:Prisma.Decimal;maxOrderQty:Prisma.Decimal|null
},amount:Prisma.Decimal){
 if(amount.lt(listing.minOrderQty)||listing.maxOrderQty&&amount.gt(listing.maxOrderQty)||
  !amount.minus(listing.minOrderQty).mod(listing.stepQty).isZero())
  throw new ApiError(422,'INVALID_ORDER_QUANTITY','Quantity does not match supplier minimum, step or maximum.');
}
