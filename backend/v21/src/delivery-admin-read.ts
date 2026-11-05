import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';

export async function adminCities(db:PrismaClient,actor:string) {
 await requireAdminPermission(db,actor,'SERVICE_AREA_MANAGE');
 return db.city.findMany({
  select:{id:true,code:true,name:true,stateCode:true,countryCode:true,active:true},
  orderBy:{name:'asc'},take:300
 });
}
export async function adminAreas(db:PrismaClient,actor:string,cityId:string) {
 await requireAdminPermission(db,actor,'SERVICE_AREA_MANAGE');
 if(!isUuid(cityId))throw new ApiError(400,'INVALID_CITY','Invalid city.');
 if(!await db.city.findUnique({where:{id:cityId},select:{id:true}}))
  throw new ApiError(404,'NOT_FOUND','Delivery city not found.');
 const rows=await db.serviceArea.findMany({where:{cityId},
  select:{id:true,cityId:true,name:true,postalCodes:true,centerLat:true,centerLng:true,radiusKm:true,active:true},
  orderBy:{id:'asc'},take:300
 });
 return rows.map(x=>({...x,
  centerLat:x.centerLat?.toString()??null,centerLng:x.centerLng?.toString()??null,
  radiusKm:x.radiusKm?.toString()??null
 }));
}
