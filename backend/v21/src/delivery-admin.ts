import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,requireSupplierPermission} from './permissions';
import {record,requiredString,uuid,integer,boolean,cityCode,stateCode,pins,
 centerCoordinates,radiusKm,assertAreaShape,minimumPaise,feePaise} from './delivery-validation';

type Tx=Prisma.TransactionClient;
const serial=<T>(db:PrismaClient,fn:(tx:Tx)=>Promise<T>)=>
 db.$transaction(fn,{isolationLevel:Prisma.TransactionIsolationLevel.Serializable,maxWait:5000,timeout:10000});
async function admin(tx:Tx,userId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "userId" FROM "AdminMembership" WHERE "userId"=${userId}::uuid FOR SHARE`);
 await requireAdminPermission(tx,userId,'SERVICE_AREA_MANAGE');
}
async function supplierManager(tx:Tx,userId:string,supplierId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierMember" WHERE "supplierId"=${supplierId}::uuid AND "userId"=${userId}::uuid FOR SHARE`);
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Supplier" WHERE id=${supplierId}::uuid FOR SHARE`);
 await requireSupplierPermission(tx,userId,supplierId,'DELIVERY_MANAGE');
}
async function logAudit(tx:Tx,userId:string,entityType:string,entityId:string,action:string) {
 await tx.auditEvent.create({data:{actorUserId:userId,actorRole:'DELIVERY_CONFIG',action,entityType,entityId}});
}
export async function listCities(db:PrismaClient) {
 return db.city.findMany({where:{active:true},select:{id:true,code:true,name:true,stateCode:true,countryCode:true},
  orderBy:{name:'asc'},take:300});
}
export async function listAreas(db:PrismaClient,cityId:string) {
 uuid(cityId,'cityId');
 return db.serviceArea.findMany({
  where:{cityId,active:true,city:{active:true}},
  select:{id:true,cityId:true,name:true,postalCodes:true,centerLat:true,centerLng:true,radiusKm:true},
  orderBy:{name:'asc'},take:100,
 }).then(rows=>rows.map(x=>({...x,
  centerLat:x.centerLat?.toString()??null,centerLng:x.centerLng?.toString()??null,
  radiusKm:x.radiusKm?.toString()??null})));
}
export async function createCity(db:PrismaClient,userId:string,input:unknown) {
 const o=record(input,['code','name','stateCode']);
 const data={code:cityCode(o.code),name:requiredString(o.name,'name',120),
  stateCode:stateCode(o.stateCode),countryCode:'IN',active:false};
 return serial(db,async tx=>{
  await admin(tx,userId);
  const row=await tx.city.create({data,select:{id:true,code:true,name:true,stateCode:true,active:true}});
  await logAudit(tx,userId,'City',row.id,'CITY_CREATED');
  return row;
 });
}
export async function setCityActive(db:PrismaClient,userId:string,cityId:string,input:unknown) {
 uuid(cityId,'cityId');
 const o=record(input,['active']);
 const active=boolean(o.active,'active');
 return serial(db,async tx=>{
  await admin(tx,userId);
  if(!await tx.city.findUnique({where:{id:cityId}}))throw new ApiError(404,'NOT_FOUND','City not found.');
  if(!active && (await tx.serviceArea.count({where:{cityId,active:true}}))>0)
   throw new ApiError(409,'CITY_HAS_ACTIVE_AREAS','Deactivate delivery areas first.');
  const row=await tx.city.update({where:{id:cityId},data:{active},
    select:{id:true,code:true,name:true,active:true}});
  await logAudit(tx,userId,'City',cityId,'CITY_STATUS_CHANGED');
  return row;
 });
}
export async function createArea(db:PrismaClient,userId:string,input:unknown) {
 const o=record(input,['cityId','name','postalCodes','centerLat','centerLng','radiusKm']);
 const point=centerCoordinates(o.centerLat,o.centerLng);
 const data={
  cityId:uuid(o.cityId,'cityId'),name:requiredString(o.name,'name',150),
  postalCodes:pins(o.postalCodes),
  centerLat:point.centerLat??null,centerLng:point.centerLng??null,
  radiusKm:o.radiusKm===undefined?null:radiusKm(o.radiusKm),
  active:false,
 };
 assertAreaShape(data);
 return serial(db,async tx=>{
  await admin(tx,userId);
  const city=await tx.city.findUnique({where:{id:data.cityId},select:{active:true}});
  if(!city?.active)throw new ApiError(422,'CITY_INACTIVE','Choose an active city.');
  const row=await tx.serviceArea.create({data,select:{id:true,cityId:true,name:true,postalCodes:true,active:true}});
  await logAudit(tx,userId,'ServiceArea',row.id,'DELIVERY_AREA_CREATED');
  return row;
 });
}
export async function updateArea(db:PrismaClient,userId:string,areaId:string,input:unknown) {
 uuid(areaId,'areaId');
 const o=record(input,['name','postalCodes','centerLat','centerLng','radiusKm','active']);
 if(!Object.keys(o).length)throw new ApiError(400,'EMPTY_PATCH','Provide fields to change.');
 if((o.centerLat===undefined)!==(o.centerLng===undefined))
   throw new ApiError(400,'COORDINATE_PAIR_REQUIRED','Supply both center coordinates.');
 const point=o.centerLat!==undefined?centerCoordinates(o.centerLat,o.centerLng):{};
 return serial(db,async tx=>{
  await admin(tx,userId);
  const old=await tx.serviceArea.findUnique({
   where:{id:areaId},select:{id:true,cityId:true,active:true,name:true,postalCodes:true,
    centerLat:true,centerLng:true,radiusKm:true,city:{select:{active:true}}},
  });
  if(!old)throw new ApiError(404,'NOT_FOUND','Area not found.');
  const active=o.active!==undefined?boolean(o.active,'active'):old.active;
  if(active&&!old.city.active)throw new ApiError(409,'CITY_INACTIVE','City must be active.');
  const changingShape=['postalCodes','centerLat','centerLng','radiusKm'].some(k=>o[k]!==undefined);
  if(old.active&&active&&changingShape)
   throw new ApiError(409,'DEACTIVATE_AREA_FIRST','Deactivate the area before changing coverage.');
  const data={
   name:o.name===undefined?old.name:requiredString(o.name,'name',150),
   postalCodes:o.postalCodes===undefined?old.postalCodes:pins(o.postalCodes),
   centerLat:point.centerLat===undefined?old.centerLat:point.centerLat,
   centerLng:point.centerLng===undefined?old.centerLng:point.centerLng,
   radiusKm:o.radiusKm===undefined?old.radiusKm:radiusKm(o.radiusKm),
   active,
  };
  assertAreaShape(data);
  const row=await tx.serviceArea.update({where:{id:areaId},data,
   select:{id:true,cityId:true,name:true,postalCodes:true,active:true}});
  await logAudit(tx,userId,'ServiceArea',areaId,'DELIVERY_AREA_UPDATED');
  return row;
 });
}
export async function configureSupplierArea(db:PrismaClient,userId:string,supplierId:string,areaId:string,input:unknown) {
 uuid(supplierId,'supplierId');uuid(areaId,'areaId');
 const o=record(input,['active','minimumPaise']);
 const active=boolean(o.active,'active');
 const min=o.minimumPaise===undefined?0n:minimumPaise(o.minimumPaise);
 return serial(db,async tx=>{
  await supplierManager(tx,userId,supplierId);
  const area=await tx.serviceArea.findUnique({where:{id:areaId},select:{active:true,city:{select:{active:true}}}});
  if(!area||!area.active||!area.city.active)
   throw new ApiError(422,'AREA_UNAVAILABLE','Only approved active delivery areas can be selected.');
  const row=await tx.supplierServiceArea.upsert({
    where:{supplierId_areaId:{supplierId,areaId}},
    create:{supplierId,areaId,active,minimumPaise:min},
    update:{active,minimumPaise:min},
    select:{supplierId:true,areaId:true,active:true,minimumPaise:true},
  });
  await logAudit(tx,userId,'SupplierServiceArea',areaId,'SUPPLIER_AREA_CONFIGURED');
  return {...row,minimumPaise:row.minimumPaise.toString()};
 });
}
export async function configureFlatDeliveryFee(db:PrismaClient,userId:string,supplierId:string,areaId:string,input:unknown) {
 uuid(supplierId,'supplierId');uuid(areaId,'areaId');
 const o=record(input,['baseFeePaise','handlingFeePaise','freeAbovePaise']);
 const base=feePaise(o.baseFeePaise,'baseFeePaise');
 const handling=feePaise(o.handlingFeePaise,'handlingFeePaise');
 const freeAbove=o.freeAbovePaise===undefined||o.freeAbovePaise===null?null:minimumPaise(o.freeAbovePaise);
 if(base+handling>100000000000n)throw new ApiError(400,'AMOUNT_TOO_LARGE','Total delivery fee is too high.');
 return serial(db,async tx=>{
  await supplierManager(tx,userId,supplierId);
  // Lock the association: concurrent reconfiguration cannot publish two live rates.
  await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierServiceArea"
   WHERE "supplierId"=${supplierId}::uuid AND "areaId"=${areaId}::uuid FOR UPDATE`);
  const association=await tx.supplierServiceArea.findUnique({
    where:{supplierId_areaId:{supplierId,areaId}},
    select:{active:true,area:{select:{active:true,city:{select:{active:true}}}}},
  });
  if(!association?.active||!association.area.active||!association.area.city.active)
   throw new ApiError(409,'COVERAGE_NOT_ACTIVE','Enable supplier coverage before configuring the delivery fee.');
  const now=new Date();
  await tx.supplierDeliveryRate.updateMany({
    where:{supplierId,areaId,active:true},
    data:{active:false,effectiveTo:now},
  });
  const row=await tx.supplierDeliveryRate.create({data:{
    supplierId,areaId,active:true,baseFeePaise:base,handlingFeePaise:handling,
    freeAbovePaise:freeAbove,perKmPaise:0n,perTonneKmPaise:0n,perCubicMetreKmPaise:0n,
    effectiveFrom:now,
  },select:{id:true,supplierId:true,areaId:true,active:true,baseFeePaise:true,
    handlingFeePaise:true,freeAbovePaise:true,effectiveFrom:true}});
  await logAudit(tx,userId,'SupplierDeliveryRate',row.id,'DELIVERY_FLAT_RATE_CONFIGURED');
  return {...row,baseFeePaise:row.baseFeePaise.toString(),handlingFeePaise:row.handlingFeePaise.toString(),
    freeAbovePaise:row.freeAbovePaise?.toString()??null};
 });
}
export async function listSupplierCoverage(db:PrismaClient,userId:string,supplierId:string) {
 uuid(supplierId,'supplierId');
 await requireSupplierPermission(db,userId,supplierId,'SUPPLIER_READ');
 const [areas,rates]=await Promise.all([
  db.supplierServiceArea.findMany({where:{supplierId},select:{areaId:true,active:true,minimumPaise:true,area:{select:{name:true,cityId:true,active:true}}},
   take:100}),
  db.supplierDeliveryRate.findMany({where:{supplierId,active:true,effectiveTo:null},
   select:{id:true,areaId:true,baseFeePaise:true,handlingFeePaise:true,freeAbovePaise:true},take:100}),
 ]);
 return areas.map(x=>({
  areaId:x.areaId,areaName:x.area.name,cityId:x.area.cityId,
  active:x.active&&x.area.active,minimumPaise:x.minimumPaise.toString(),
  rates:rates.filter(r=>r.areaId===x.areaId).map(r=>({
   id:r.id,baseFeePaise:r.baseFeePaise.toString(),
   handlingFeePaise:r.handlingFeePaise.toString(),
   freeAbovePaise:r.freeAbovePaise?.toString()??null,
  })),
 }));
}
