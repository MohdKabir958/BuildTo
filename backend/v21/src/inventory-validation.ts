import {createHash} from 'node:crypto';
import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {code,integer,record,requiredString,uuid,boolean} from './catalog-validation';
import {postalCode,stateCode} from './delivery-validation';

export {integer,record,requiredString,uuid,boolean};
export function warehouseCode(value:unknown):string {
 return code(value,'warehouseCode',80);
}
export function warehouseAddress(value:unknown):Prisma.InputJsonObject|null {
 if(value===null)return null;
 const raw=record(value,['line1','locality','city','stateCode','postalCode']);
 return {
  line1:requiredString(raw.line1,'line1',250),
  locality:requiredString(raw.locality,'locality',120),
  city:requiredString(raw.city,'city',120),
  stateCode:stateCode(raw.stateCode),
  postalCode:postalCode(raw.postalCode)
 };
}
export function stockQty(value:unknown,negativeAllowed=false):Prisma.Decimal {
 if(typeof value!=='string'||value.length>20||
     !/^-?(?:0|[1-9][0-9]{0,14})(?:\.[0-9]{1,3})?$/.test(value))
  throw new ApiError(400,'INVALID_STOCK_QUANTITY','Quantity must be an exact decimal string (up to 3 places).');
 const amount=new Prisma.Decimal(value);
 if(amount.isZero()||(!negativeAllowed&&amount.isNegative()))
  throw new ApiError(400,'INVALID_STOCK_QUANTITY','Nonzero positive quantity required.');
 if(amount.isNegative()&&!negativeAllowed)
  throw new ApiError(400,'INVALID_STOCK_QUANTITY','Negative quantity is not allowed.');
 return amount;
}
export function movementData(value:unknown) {
 const o=record(value,['listingId','warehouseId','delta','kind','reason','expectedVersion']);
 const listingId=uuid(o.listingId,'listingId');
 const warehouseId=uuid(o.warehouseId,'warehouseId');
 const kind=o.kind;
 if(!['RECEIPT','DAMAGE','ADJUSTMENT'].includes(String(kind)))
  throw new ApiError(400,'INVALID_MOVEMENT_KIND','Only stock receipt, damage and adjustment are permitted.');
 const delta=stockQty(o.delta,true);
 if(kind==='RECEIPT'&&delta.lte(0))
  throw new ApiError(400,'INVALID_STOCK_DELTA','A receipt must increase stock.');
 if(kind==='DAMAGE'&&delta.gte(0))
  throw new ApiError(400,'INVALID_STOCK_DELTA','Damage must decrease stock.');
 const reason=requiredString(o.reason,'reason',300);
 const expectedVersion=integer(o.expectedVersion,'expectedVersion',0,2147483646);
 return {listingId,warehouseId,kind:kind as 'RECEIPT'|'DAMAGE'|'ADJUSTMENT',delta,reason,expectedVersion};
}
export function keyHash(scope:string,key:string):string {
 return 'inventory:'+createHash('sha256').update(scope+'\0'+key).digest('hex');
}
export function parseWarehouseId(x:unknown){return uuid(x,'warehouseId');}
