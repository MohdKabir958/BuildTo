import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';

type PlainRecord=Record<string,unknown>;
export function record(input:unknown,fields:readonly string[]):PlainRecord {
  if(input===null||typeof input!=='object'||Array.isArray(input)||
     Object.getPrototypeOf(input)!==Object.prototype)throw new ApiError(400,'INVALID_INPUT','Expected JSON object.');
  const obj=input as PlainRecord;
  if(Object.keys(obj).some(k=>!fields.includes(k)||k==='__proto__'||k==='constructor'||k==='prototype'))
    throw new ApiError(400,'UNKNOWN_FIELD','Request contains unsupported fields.');
  return obj;
}
export function requiredString(x:unknown,name:string,max=160):string {
  if(typeof x!=='string'||!x.trim()||x.trim().length>max||/[\x00-\x1f\x7f]/.test(x))
    throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Invalid '+name+'.');
  return x.trim();
}
export function slug(x:unknown,name='slug',max=140):string {
  const v=requiredString(x,name,max);
  if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(v))throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Invalid '+name+'.');
  return v;
}
export function code(x:unknown,name:string,max=100):string {
  const v=requiredString(x,name,max);
  if(!/^[A-Z0-9][A-Z0-9._-]*$/.test(v))throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Use uppercase letters, digits, dot, dash or underscore.');
  return v;
}
export function uuid(x:unknown,name='id'):string {
  if(typeof x!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x))
    throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Invalid identifier.');
  return x;
}
export function integer(x:unknown,name:string,low:number,high:number):number {
  if(typeof x!=='number'||!Number.isInteger(x)||x<low||x>high)
    throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Invalid integer.');
  return x;
}
export function boolean(x:unknown,name:string):boolean {
  if(typeof x!=='boolean')throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Boolean required.');
  return x;
}
export function exactDecimal(x:unknown,name:string,integerDigits:number,fractionDigits:number,positive=false):Prisma.Decimal {
  if(typeof x!=='string'||x.length>integerDigits+fractionDigits+1||
     !new RegExp('^(?:0|[1-9][0-9]{0,'+(integerDigits-1)+'})(?:\\.[0-9]{1,'+fractionDigits+'})?$').test(x))
    throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Use an exact decimal string.');
  const value=new Prisma.Decimal(x);
  if(positive?value.lte(0):value.lt(0))throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Quantity or price outside permitted range.');
  return value;
}
export function rupeePrice(x:unknown,name='unitPrice'){return exactDecimal(x,name,14,4,true);}
export function quantity(x:unknown,name='quantity'){return exactDecimal(x,name,15,3,true);}
export function paise(x:unknown,name='mrpPaise'):bigint {
  if(typeof x!=='string'||!/^(?:0|[1-9][0-9]{0,18})$/.test(x))
    throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Paise must be an integer string.');
  const amount=BigInt(x);
  if(amount>9223372036854775807n)throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Value too large.');
  return amount;
}
export function specification(x:unknown):Prisma.InputJsonObject {
  if(x===null||typeof x!=='object'||Array.isArray(x)||Object.getPrototypeOf(x)!==Object.prototype)
    throw new ApiError(400,'INVALID_SPECIFICATION','Specification must be a JSON object.');
  // The public specification shape is intentionally bounded. Category-specific
  // required keys must be agreed before accepting rich/free-form nested schemas.
  const o=x as PlainRecord;
  if(Object.keys(o).length>24)throw new ApiError(400,'SPECIFICATION_LIMIT','Too many specification fields.');
  const clean:Record<string,string|boolean|number>={};
  for(const [k,v] of Object.entries(o)){
    if(!/^[a-z][A-Za-z0-9_]{0,39}$/.test(k)||!(typeof v==='boolean'||typeof v==='string'||(typeof v==='number'&&Number.isFinite(v)))||
       (typeof v==='string'&&(v.length>240||/[\x00-\x1f\x7f]/.test(v))))
      throw new ApiError(400,'INVALID_SPECIFICATION','Invalid specification field.');
    clean[k]=v;
  }
  return clean;
}
export function requireNonemptyPatch(o:PlainRecord){
  if(Object.keys(o).length===0)throw new ApiError(400,'EMPTY_PATCH','Nothing to update.');
}
export function listingFields(x:unknown,partial=false) {
  const o=record(x,['sku','productId','unitCode','packSize','minOrderQty','stepQty','maxOrderQty','unitPrice','mrpPaise','taxRateBps','taxInclusive','expectedVersion']);
  if(partial)requireNonemptyPatch(o);
  const out:Record<string,unknown>={};
  if(!partial){out.productId=uuid(o.productId,'productId');out.sku=code(o.sku,'sku');out.unitCode=code(o.unitCode,'unitCode',20);}
  else {
    if(o.productId!==undefined||o.sku!==undefined||o.unitCode!==undefined)
      throw new ApiError(400,'IMMUTABLE_LISTING_IDENTITY','Product, unit and SKU cannot be edited in-place.');
  }
  for(const k of ['packSize','minOrderQty','stepQty'] as const) {
    if(o[k]!==undefined)out[k]=quantity(o[k],k);
    else if(!partial)out[k]=new Prisma.Decimal(1);
  }
  if(o.maxOrderQty!==undefined)out.maxOrderQty=o.maxOrderQty===null?null:quantity(o.maxOrderQty,'maxOrderQty');
  if(o.unitPrice!==undefined)out.unitPrice=rupeePrice(o.unitPrice);
  else if(!partial)throw new ApiError(400,'UNIT_PRICE_REQUIRED','Unit price is required.');
  if(o.mrpPaise!==undefined)out.mrpPaise=o.mrpPaise===null?null:paise(o.mrpPaise);
  if(o.taxRateBps!==undefined)out.taxRateBps=integer(o.taxRateBps,'taxRateBps',0,10000);
  else if(!partial)out.taxRateBps=0;
  if(o.taxInclusive!==undefined)out.taxInclusive=boolean(o.taxInclusive,'taxInclusive');
  else if(!partial)out.taxInclusive=true;
  if(partial){
    if(o.expectedVersion===undefined)throw new ApiError(428,'VERSION_REQUIRED','Expected listing version is required.');
    out.expectedVersion=integer(o.expectedVersion,'expectedVersion',0,2147483647);
    if(Object.keys(out).length===1)throw new ApiError(400,'EMPTY_PATCH','No editable listing fields.');
  }
  if(out.maxOrderQty!==undefined&&out.maxOrderQty!==null&&out.minOrderQty!==undefined&&
    (out.maxOrderQty as Prisma.Decimal).lt(out.minOrderQty as Prisma.Decimal))
    throw new ApiError(400,'INVALID_QUANTITY_RANGE','Maximum must not be below minimum.');
  return out;
}
