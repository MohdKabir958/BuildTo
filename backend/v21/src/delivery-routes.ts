import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {listCities,listAreas,createCity,setCityActive,createArea,updateArea,
 configureSupplierArea,configureFlatDeliveryFee,listSupplierCoverage} from './delivery-admin';
import {adminCities,adminAreas} from './delivery-admin-read';
import {listMyAddresses,addMyAddress,updateMyAddress,deleteMyAddress,checkSupplierDelivery} from './delivery-customers';

const handlers=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{
  try{
   const data=await fn(req,res);
   res.status(created?201:200).json({data,requestId:res.locals.requestId});
  }catch(error){next(error);}
 };
const who=(res:Response):string=>{
 const principal=res.locals.principal as {id?:unknown}|undefined;
 if(!principal||typeof principal.id!=='string')
  throw new ApiError(401,'INVALID_SESSION','Authentication required.');
 return principal.id;
};
const q=(value:unknown,name:string):string=>{
 if(typeof value!=='string'||!value)throw new ApiError(400,'QUERY_REQUIRED','Invalid or missing '+name+'.');
 return value;
};
export function registerPublicDelivery(app:Express,db:PrismaClient){
 app.get('/api/v2/delivery/cities',handlers(()=>listCities(db)));
 app.get('/api/v2/delivery/areas',handlers(req=>listAreas(db,q(req.query.cityId,'cityId'))));
}
export function registerProtectedDelivery(app:Express,db:PrismaClient,auth:RequestHandler){
 const d='/api/v2/admin/delivery';
 app.get(d+'/cities',auth,handlers((_req,res)=>adminCities(db,who(res))));
 app.get(d+'/areas',auth,handlers((req,res)=>adminAreas(db,who(res),q(req.query.cityId,'cityId'))));
 app.post(d+'/cities',auth,handlers((req,res)=>createCity(db,who(res),req.body),true));
 app.patch(d+'/cities/:cityId',auth,handlers((req,res)=>
  setCityActive(db,who(res),req.params.cityId,req.body)));
 app.post(d+'/areas',auth,handlers((req,res)=>createArea(db,who(res),req.body),true));
 app.patch(d+'/areas/:areaId',auth,handlers((req,res)=>
  updateArea(db,who(res),req.params.areaId,req.body)));
 const a='/api/v2/me/addresses';
 app.get(a,auth,handlers((_req,res)=>listMyAddresses(db,who(res))));
 app.post(a,auth,handlers((req,res)=>addMyAddress(db,who(res),req.body),true));
 app.patch(a+'/:addressId',auth,handlers((req,res)=>updateMyAddress(db,who(res),req.params.addressId,req.body)));
 app.delete(a+'/:addressId',auth,handlers((req,res)=>deleteMyAddress(db,who(res),req.params.addressId)));
 app.get('/api/v2/delivery/suppliers/:supplierId/eligibility',auth,
  handlers((req,res)=>checkSupplierDelivery(db,who(res),req.params.supplierId,q(req.query.addressId,'addressId'))));
 const sp='/api/v2/suppliers/:supplierId/delivery';
 app.get(sp,auth,handlers((req,res)=>listSupplierCoverage(db,who(res),req.params.supplierId)));
 app.put(sp+'/areas/:areaId',auth,handlers((req,res)=>
   configureSupplierArea(db,who(res),req.params.supplierId,req.params.areaId,req.body)));
 app.put(sp+'/areas/:areaId/flat-rate',auth,handlers((req,res)=>
   configureFlatDeliveryFee(db,who(res),req.params.supplierId,req.params.areaId,req.body)));
}
