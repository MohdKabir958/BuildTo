import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,uuid,exactDecimal,requiredString} from './catalog-validation';
import {feePaise} from './delivery-validation';
import {requireSupplierPermission} from './permissions';
import {serializable} from './transaction';
import {boundedPaise} from './rfq-validation';

export function calculateFreight(rate:{baseFeePaise:bigint;handlingFeePaise:bigint;perKmPaise:bigint;perTonneKmPaise:bigint;perCubicMetreKmPaise:bigint;weightCapacityKg:Prisma.Decimal|null;volumeCapacityM3:Prisma.Decimal|null},distance:Prisma.Decimal,weight:Prisma.Decimal|null,volume:Prisma.Decimal|null){
 if(rate.perTonneKmPaise>0n&&!weight||rate.weightCapacityKg&&!weight||rate.perCubicMetreKmPaise>0n&&!volume||rate.volumeCapacityM3&&!volume)throw new ApiError(422,'FREIGHT_DIMENSIONS_REQUIRED','Verified product conversions are required for this tariff.');
 if(weight&&!rate.weightCapacityKg||volume&&!rate.volumeCapacityM3)throw new ApiError(422,'FREIGHT_CAPACITY_REQUIRED','Configure vehicle capacity for the measured load.');
 const trips=Prisma.Decimal.max(1,weight&&rate.weightCapacityKg?weight.div(rate.weightCapacityKg).ceil():1,volume&&rate.volumeCapacityM3?volume.div(rate.volumeCapacityM3).ceil():1);
 if(trips.gt(100))throw new ApiError(422,'FREIGHT_TRIP_LIMIT','Load requires an individually negotiated freight quote.');
 const amount=new Prisma.Decimal((rate.baseFeePaise+rate.handlingFeePaise).toString()).mul(trips)
  .plus(distance.mul(rate.perKmPaise.toString()).mul(trips))
  .plus(distance.mul(weight??0).div(1000).mul(rate.perTonneKmPaise.toString()))
  .plus(distance.mul(volume??0).mul(rate.perCubicMetreKmPaise.toString()));
 return {trips:trips.toNumber(),amountPaise:boundedPaise(BigInt(amount.toDecimalPlaces(0,Prisma.Decimal.ROUND_HALF_UP).toFixed(0))).toString()};
}
export async function configureFreightRate(db:PrismaClient,actor:string,supplierId:string,areaId:string,body:unknown){
 uuid(supplierId,'supplierId');uuid(areaId,'areaId');
 const o=record(body,['baseFeePaise','handlingFeePaise','perKmPaise','perTonneKmPaise','perCubicMetreKmPaise','weightCapacityKg','volumeCapacityM3','vehicleClass']);
 const data={baseFeePaise:feePaise(o.baseFeePaise,'baseFeePaise'),handlingFeePaise:feePaise(o.handlingFeePaise,'handlingFeePaise'),
  perKmPaise:feePaise(o.perKmPaise??'0','perKmPaise'),perTonneKmPaise:feePaise(o.perTonneKmPaise??'0','perTonneKmPaise'),perCubicMetreKmPaise:feePaise(o.perCubicMetreKmPaise??'0','perCubicMetreKmPaise'),
  weightCapacityKg:o.weightCapacityKg==null?null:exactDecimal(o.weightCapacityKg,'weightCapacityKg',9,3,true),
  volumeCapacityM3:o.volumeCapacityM3==null?null:exactDecimal(o.volumeCapacityM3,'volumeCapacityM3',9,3,true),
  vehicleClass:requiredString(o.vehicleClass,'vehicleClass',70)};
 if(data.perTonneKmPaise>0n&&!data.weightCapacityKg||data.perCubicMetreKmPaise>0n&&!data.volumeCapacityM3)throw new ApiError(400,'FREIGHT_CAPACITY_REQUIRED','Weight and volume tariffs require matching capacities.');
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,actor,supplierId,'DELIVERY_MANAGE');
  await tx.$queryRaw(Prisma.sql`SELECT "supplierId" FROM "SupplierServiceArea" WHERE "supplierId"=${supplierId}::uuid AND "areaId"=${areaId}::uuid FOR UPDATE`);
  const coverage=await tx.supplierServiceArea.findFirst({where:{supplierId,areaId,active:true,area:{active:true,city:{active:true}}}});
  if(!coverage)throw new ApiError(409,'COVERAGE_NOT_ACTIVE','Enable approved delivery coverage first.');
  await tx.$executeRaw(Prisma.sql`UPDATE "SupplierDeliveryRate" SET active=false,"effectiveTo"=GREATEST(NOW(),"effectiveFrom"+INTERVAL '1 millisecond') WHERE "supplierId"=${supplierId}::uuid AND "areaId"=${areaId}::uuid AND active=true`);
  const row=await tx.supplierDeliveryRate.create({data:{...data,supplierId,areaId,active:true}});
  await tx.auditEvent.create({data:{actorUserId:actor,actorRole:'SUPPLIER_DELIVERY',entityType:'SupplierDeliveryRate',entityId:row.id,action:'FREIGHT_RATE_CONFIGURED'}});
  return {id:row.id,vehicleClass:row.vehicleClass,quoteRequired:true};
 });
}
export async function rfqFreightSnapshot(tx:Prisma.TransactionClient,supplierId:string,rfqId:string,input:unknown):Promise<Prisma.InputJsonObject>{
 const o=record(input,['rateId','roadDistanceKm','distanceEvidence']);
 const rateId=uuid(o.rateId,'rateId'),distance=exactDecimal(o.roadDistanceKm,'roadDistanceKm',5,3,true);
 if(distance.gt(5000))throw new ApiError(400,'FREIGHT_DISTANCE_INVALID','Road distance exceeds supported limit.');
 const evidence=requiredString(o.distanceEvidence,'distanceEvidence',300);
 if(evidence.length<8)throw new ApiError(400,'DISTANCE_EVIDENCE_REQUIRED','Record how road distance was verified.');
 const rate=await tx.supplierDeliveryRate.findFirst({where:{id:rateId,supplierId,active:true,effectiveFrom:{lte:new Date()},OR:[{effectiveTo:null},{effectiveTo:{gt:new Date()}}],area:{active:true,city:{active:true}}},include:{freightBrackets:{where:{active:true}},area:true}});
 const rfq=await tx.rfq.findUnique({where:{id:rfqId},include:{items:{include:{product:{include:{conversions:true}}}}}});
 if(!rate||!rfq)throw new ApiError(404,'NOT_FOUND','Freight tariff unavailable.');
 const site=rfq.siteSnapshot as {postalCode?:string;city?:string};
 const city=await tx.city.findUniqueOrThrow({where:{id:rate.area.cityId}});
 if(!site.postalCode||!rate.area.postalCodes.includes(site.postalCode)||site.city?.trim().toLowerCase()!==city.name.trim().toLowerCase())throw new ApiError(422,'FREIGHT_LOCATION_MISMATCH','Tariff must cover the RFQ delivery location.');
 // Polygon/radius coverage requires precise geocoded points; a city/PIN RFQ is insufficient.
 if(rate.area.centerLat!==null||rate.area.radiusKm!==null)throw new ApiError(422,'FREIGHT_PRECISE_LOCATION_REQUIRED','Use a verified location-specific freight agreement for radius areas.');
 const spatial=await tx.$queryRaw<{present:boolean}[]>(Prisma.sql`SELECT ("geoBoundary" IS NOT NULL) AS present FROM "ServiceArea" WHERE id=${rate.areaId}::uuid`);
 if(spatial[0]?.present)throw new ApiError(422,'FREIGHT_PRECISE_LOCATION_REQUIRED','Use a location-specific freight agreement for polygon areas.');
 if(rate.freightBrackets.some(b=>!['MASS','VOLUME'].includes(b.dimension)))throw new ApiError(422,'FREIGHT_BRACKET_UNSUPPORTED','Use a weight or volume freight bracket.');
 const needWeight=rate.perTonneKmPaise>0n||rate.weightCapacityKg!==null||rate.freightBrackets.some(b=>b.dimension==='MASS'||b.perTonneKmPaise>0n);
 const needVolume=rate.perCubicMetreKmPaise>0n||rate.volumeCapacityM3!==null||rate.freightBrackets.some(b=>b.dimension==='VOLUME'||b.perCubicMetreKmPaise>0n);
 const load=(target:'KG'|'CUM')=>rfq.items.reduce((sum,item)=>{
  const factor=item.unitCode===target?new Prisma.Decimal(1):item.product?.conversions.find(c=>c.fromUnit===item.unitCode&&c.toUnit===target)?.multiplier;
  if(!factor)throw new ApiError(422,'FREIGHT_DIMENSIONS_REQUIRED','Catalog needs a verified conversion from each sale unit to '+target+'.');
  return sum.plus(item.quantity.mul(factor));
 },new Prisma.Decimal(0));
 const weight=needWeight?load('KG'):null,volume=needVolume?load('CUM'):null;
 const combined={...rate};const bracketIds:string[]=[];
 for(const dimension of ['MASS','VOLUME'] as const){
  const brackets=rate.freightBrackets.filter(b=>b.dimension===dimension);
  if(!brackets.length)continue;
  const value=dimension==='MASS'?weight:volume;
  const matches=brackets.filter(b=>value&&value.gte(b.minQuantity)&&(!b.maxQuantity||value.lt(b.maxQuantity)));
  if(matches.length!==1)throw new ApiError(422,'FREIGHT_BRACKET_UNAVAILABLE','Load must match exactly one configured freight bracket.');
  const b=matches[0];bracketIds.push(b.id);
  combined.baseFeePaise+=b.fixedFeePaise;combined.perKmPaise+=b.perKmPaise;combined.perTonneKmPaise+=b.perTonneKmPaise;combined.perCubicMetreKmPaise+=b.perCubicMetreKmPaise;
 }
 const priced=calculateFreight(combined,distance,weight,volume);
 return {version:1,rateId,bracketIds,roadDistanceKm:distance.toString(),distanceEvidence:evidence,distanceSource:'SUPPLIER_ATTESTED',weightKg:weight?.toString()??null,volumeM3:volume?.toString()??null,vehicleClass:rate.vehicleClass,weightCapacityKg:rate.weightCapacityKg?.toString()??null,volumeCapacityM3:rate.volumeCapacityM3?.toString()??null,
 baseFeePaise:combined.baseFeePaise.toString(),handlingFeePaise:combined.handlingFeePaise.toString(),perKmPaise:combined.perKmPaise.toString(),perTonneKmPaise:combined.perTonneKmPaise.toString(),perCubicMetreKmPaise:combined.perCubicMetreKmPaise.toString(),...priced};
}
