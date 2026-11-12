import {serializable} from './transaction';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,requiredString,uuid,boolean,postalCode,phoneE164,coordinates,optionalNonemptyString} from './delivery-validation';

type Tx=Prisma.TransactionClient;
const serial=serializable;
const selected={
 id:true,cityId:true,label:true,recipientName:true,phoneE164:true,
 line1:true,line2:true,locality:true,postalCode:true,latitude:true,longitude:true,
 isDefault:true,createdAt:true,city:{select:{name:true,stateCode:true}},
} as const;
function output(row:any){
 return {
  id:row.id,cityId:row.cityId,cityName:row.city.name,stateCode:row.city.stateCode,
  label:row.label,recipientName:row.recipientName,phoneE164:row.phoneE164,
  line1:row.line1,line2:row.line2,locality:row.locality,
  postalCode:row.postalCode,latitude:row.latitude?.toString()??null,
  longitude:row.longitude?.toString()??null,
  isDefault:row.isDefault,createdAt:row.createdAt.toISOString(),
 };
}
const allowed=['cityId','label','recipientName','phoneE164','line1','line2',
 'locality','postalCode','latitude','longitude','isDefault'];
function normalize(input:unknown,partial=false) {
 const o=record(input,allowed);
 if(partial&&!Object.keys(o).length)throw new ApiError(400,'EMPTY_PATCH','Nothing to change.');
 const c=coordinates(o.latitude,o.longitude);
 const d:Record<string,unknown>={...c};
 if(!partial||o.cityId!==undefined)d.cityId=uuid(o.cityId,'cityId');
 for(const k of ['label','recipientName','line1','locality'] as const){
  if(!partial||o[k]!==undefined)d[k]=requiredString(o[k],k,k==='line1'?250:k==='recipientName'?160:120);
 }
 if(o.line2!==undefined)d.line2=optionalNonemptyString(o.line2,'line2',250);
 if(!partial||o.phoneE164!==undefined)d.phoneE164=phoneE164(o.phoneE164);
 if(!partial||o.postalCode!==undefined)d.postalCode=postalCode(o.postalCode);
 if(o.isDefault!==undefined)d.isDefault=boolean(o.isDefault,'isDefault');
 if(!partial&&o.isDefault===undefined)d.isDefault=false;
 return d;
}
async function lockUser(tx:Tx,userId:string) {
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`SELECT id FROM "User"
   WHERE id=${userId}::uuid AND status='ACTIVE' AND "deletedAt" IS NULL FOR UPDATE`);
 if(!rows.length)throw new ApiError(403,'ACCOUNT_SUSPENDED','Account unavailable.');
}
async function cityAvailable(tx:Tx,cityId:string) {
 const city=await tx.city.findUnique({where:{id:cityId},select:{active:true}});
 if(!city?.active)throw new ApiError(422,'CITY_UNAVAILABLE','Choose an active city.');
}
export async function listMyAddresses(db:PrismaClient,userId:string) {
 const rows=await db.address.findMany({where:{userId,deletedAt:null},select:selected,
  orderBy:[{isDefault:'desc'},{createdAt:'desc'}],take:30});
 return rows.map(output);
}
export async function addMyAddress(db:PrismaClient,userId:string,input:unknown) {
 const data=normalize(input) as {
  cityId:string;label:string;recipientName:string;phoneE164:string;line1:string;
  line2?:string|null;locality:string;postalCode:string;
  latitude?:Prisma.Decimal|null;longitude?:Prisma.Decimal|null;isDefault:boolean;
 };
 return serial(db,async tx=>{
  await lockUser(tx,userId);
  await cityAvailable(tx,data.cityId);
  const count=await tx.address.count({where:{userId,deletedAt:null}});
  const isDefault=data.isDefault||count===0;
  if(isDefault)await tx.address.updateMany({where:{userId,isDefault:true,deletedAt:null},data:{isDefault:false}});
  const row=await tx.address.create({data:{...data,userId,isDefault},select:selected});
  return output(row);
 });
}
export async function updateMyAddress(db:PrismaClient,userId:string,addressId:string,input:unknown) {
 uuid(addressId,'addressId');
 const data=normalize(input,true) as Record<string,unknown>;
 return serial(db,async tx=>{
  await lockUser(tx,userId);
  const old=await tx.address.findFirst({where:{id:addressId,userId,deletedAt:null},select:{id:true}});
  if(!old)throw new ApiError(404,'NOT_FOUND','Address not found.');
  if(data.cityId!==undefined)await cityAvailable(tx,data.cityId as string);
  if(data.isDefault===true)
   await tx.address.updateMany({where:{userId,isDefault:true,deletedAt:null,id:{not:addressId}},
    data:{isDefault:false}});
  const row=await tx.address.update({where:{id:addressId},data,select:selected});
  return output(row);
 });
}
export async function deleteMyAddress(db:PrismaClient,userId:string,addressId:string) {
 uuid(addressId,'addressId');
 return serial(db,async tx=>{
  await lockUser(tx,userId);
  const old=await tx.address.findFirst({where:{id:addressId,userId,deletedAt:null},select:{id:true,isDefault:true}});
  if(!old)throw new ApiError(404,'NOT_FOUND','Address not found.');
  // Preserve references from previous orders; the address is soft-deleted.
  await tx.address.update({where:{id:addressId},data:{deletedAt:new Date(),isDefault:false}});
  if(old.isDefault){
    const replacement=await tx.address.findFirst({
      where:{userId,deletedAt:null},orderBy:{createdAt:'desc'},select:{id:true}
    });
    if(replacement)await tx.address.update({where:{id:replacement.id},data:{isDefault:true}});
  }
  return {deleted:true};
 });
}

type Eligibility={areaId:string;minimumPaise:bigint;baseFeePaise:bigint;handlingFeePaise:bigint;freeAbovePaise:bigint|null};
export async function checkSupplierDelivery(db:PrismaClient,userId:string,supplierId:string,addressId:string) {
 uuid(supplierId,'supplierId');uuid(addressId,'addressId');
 const own=await db.address.findFirst({
  where:{id:addressId,userId,deletedAt:null},select:{id:true}
 });
 if(!own)throw new ApiError(404,'NOT_FOUND','Address not found.');
 // City + explicit PIN membership are always required.
 // Postal-only areas are admin-approved manual coverage. If a polygon or
 // radius is configured, a spatially valid address point is ALSO mandatory.
 // All geometry is generated by SQL triggers from validated lat/lng.
 // This is eligibility PREVIEW, never an irrevocable checkout freight quote.
 const rows=await db.$queryRaw<Eligibility[]>(Prisma.sql`
   SELECT sa.id AS "areaId", ssa."minimumPaise" AS "minimumPaise",
     rate."baseFeePaise" AS "baseFeePaise",
     rate."handlingFeePaise" AS "handlingFeePaise",
     rate."freeAbovePaise" AS "freeAbovePaise"
   FROM "Address" address
   JOIN "City" city ON city.id=address."cityId" AND city.active=true
   JOIN "ServiceArea" sa ON sa."cityId"=city.id AND sa.active=true
   JOIN "SupplierServiceArea" ssa ON ssa."areaId"=sa.id AND ssa."supplierId"=${supplierId}::uuid
      AND ssa.active=true
   JOIN "Supplier" supplier ON supplier.id=ssa."supplierId"
      AND supplier.approval='APPROVED' AND supplier."suspendedAt" IS NULL
   JOIN "SupplierDeliveryRate" rate ON rate."supplierId"=ssa."supplierId"
      AND rate."areaId"=sa.id AND rate.active=true
      AND rate."effectiveFrom"<=NOW() AND
      (rate."effectiveTo" IS NULL OR rate."effectiveTo">NOW())
   WHERE address.id=${addressId}::uuid AND address."userId"=${userId}::uuid
     AND address."deletedAt" IS NULL
     AND address."postalCode"=ANY(sa."postalCodes")
     AND (
       (sa."geoBoundary" IS NOT NULL AND address."geoPoint" IS NOT NULL
        AND ST_Covers(sa."geoBoundary"::geometry,address."geoPoint"::geometry))
       OR
       (sa."geoBoundary" IS NULL AND sa."geoCenter" IS NOT NULL AND sa."radiusKm" IS NOT NULL
        AND address."geoPoint" IS NOT NULL
        AND ST_DWithin(sa."geoCenter",address."geoPoint",sa."radiusKm"::double precision*1000))
       OR
       (sa."geoBoundary" IS NULL AND sa."geoCenter" IS NULL AND sa."radiusKm" IS NULL)
     )
     AND rate."weightCapacityKg" IS NULL AND rate."volumeCapacityM3" IS NULL
    AND rate."perKmPaise"=0 AND rate."perTonneKmPaise"=0
     AND rate."perCubicMetreKmPaise"=0
     AND NOT EXISTS (
       SELECT 1 FROM "SupplierFreightBracket" bracket
       WHERE bracket."deliveryRateId"=rate.id AND bracket.active=true
     )
   ORDER BY (rate."baseFeePaise"+rate."handlingFeePaise") ASC,sa.id ASC,rate.id ASC
   LIMIT 1
 `);
 if(!rows.length)return {serviceable:false,reason:'NO_ACTIVE_COVERAGE_OR_RATE',previewOnly:true};
 const x=rows[0];
 return {
  serviceable:true,areaId:x.areaId,minimumOrderPaise:x.minimumPaise.toString(),
  standardDeliveryFeePaise:(x.baseFeePaise+x.handlingFeePaise).toString(),
  freeAbovePaise:x.freeAbovePaise?.toString()??null,
  previewOnly:true,
  message:'Final serviceability and freight must be rechecked during checkout.',
 };
}
