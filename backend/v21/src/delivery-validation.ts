import {Prisma} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,requiredString,uuid,integer,boolean,paise} from './catalog-validation';

export {record,requiredString,uuid,integer,boolean,paise};
const decimal=(x:unknown,name:string,min:number,max:number):Prisma.Decimal=>{
 if(typeof x!=='string'||! /^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,7})?$/.test(x))
   throw new ApiError(400,'INVALID_COORDINATE','Latitude and longitude must be exact decimal strings.');
 const v=new Prisma.Decimal(x);
 if(v.lt(min)||v.gt(max))throw new ApiError(400,'INVALID_COORDINATE','Coordinates outside supported Indian bounds.');
 return v;
};
export function coordinates(latitude:unknown,longitude:unknown) {
 if(latitude===undefined&&longitude===undefined)return {};
 if(latitude===null&&longitude===null)return {latitude:null,longitude:null};
 if(latitude===undefined||longitude===undefined||latitude===null||longitude===null)
   throw new ApiError(400,'COORDINATE_PAIR_REQUIRED','Latitude and longitude must be provided together.');
 return {latitude:decimal(latitude,'latitude',6,38),longitude:decimal(longitude,'longitude',68,98)};
}
export function centerCoordinates(centerLat:unknown,centerLng:unknown) {
 const point=coordinates(centerLat,centerLng);
 return {
  ...('latitude' in point?{centerLat:point.latitude,centerLng:point.longitude}:{})
 };
}
export function radiusKm(x:unknown):Prisma.Decimal|null {
 if(x===null)return null;
 if(typeof x!=='string'||! /^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,2})?$/.test(x))
   throw new ApiError(400,'INVALID_RADIUS','Radius must be an exact decimal string.');
 const value=new Prisma.Decimal(x);
 if(value.lte(0)||value.gt(500))throw new ApiError(400,'INVALID_RADIUS','Radius must be greater than zero and at most 500 km.');
 return value;
}
export function postalCode(x:unknown):string {
 if(typeof x!=='string'||!/^[1-9][0-9]{5}$/.test(x))
   throw new ApiError(400,'INVALID_POSTAL_CODE','Enter a valid six-digit Indian PIN code.');
 return x;
}
export function pins(x:unknown):string[] {
 if(!Array.isArray(x)||x.length===0||x.length>100||x.some(v=>typeof v!=='string'))
   throw new ApiError(400,'INVALID_POSTAL_CODES','Provide 1 to 100 PIN codes.');
 const normalized=x.map(postalCode);
 if(new Set(normalized).size!==normalized.length)throw new ApiError(400,'DUPLICATE_POSTAL_CODE','Duplicate PIN code.');
 return normalized;
}
export function phoneE164(x:unknown) {
 if(typeof x!=='string'||!/^\+[1-9][0-9]{7,14}$/.test(x))
   throw new ApiError(400,'INVALID_PHONE','Enter a phone in international E.164 format.');
 return x;
}
export function cityCode(x:unknown) {
 if(typeof x!=='string'||!/^[A-Z0-9_-]{2,32}$/.test(x))throw new ApiError(400,'INVALID_CITY_CODE','Invalid city code.');
 return x;
}
export function stateCode(x:unknown) {
 if(typeof x!=='string'||!/^[A-Z]{2}$/.test(x))throw new ApiError(400,'INVALID_STATE_CODE','Use the two-letter state code.');
 return x;
}
export function assertAreaShape(input:{
 postalCodes:string[];centerLat:Prisma.Decimal|null;centerLng:Prisma.Decimal|null;radiusKm:Prisma.Decimal|null
}):void {
 if(!input.postalCodes.length)throw new ApiError(400,'PIN_CODES_REQUIRED','At least one PIN is required.');
 if(input.radiusKm!==null && (input.centerLat===null || input.centerLng===null))
   throw new ApiError(400,'CENTER_REQUIRED','A delivery-radius area must have a center location.');
 // A center without radius is not a usable service boundary. Never silently
 // interpret an incomplete circle as city-wide coverage.
 if(input.radiusKm===null && input.centerLat!==null)
   throw new ApiError(400,'RADIUS_REQUIRED','Set a radius for a center-based service area.');
}
export function optionalNonemptyString(x:unknown,name:string,max:number):string|null {
 if(x===null)return null;
 return requiredString(x,name,max);
}
export function minimumPaise(x:unknown) {
 const amount=paise(x,'minimumPaise');
 if(amount>100000000000n)throw new ApiError(400,'AMOUNT_TOO_LARGE','Amount exceeds supported order limit.');
 return amount;
}
export function feePaise(x:unknown,name:string):bigint {
 const amount=paise(x,name);
 if(amount>100000000000n)throw new ApiError(400,'AMOUNT_TOO_LARGE','Fee exceeds supported maximum.');
 return amount;
}
