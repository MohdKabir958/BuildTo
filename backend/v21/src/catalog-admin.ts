import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,slug,requiredString,code,uuid,integer,boolean,
 exactDecimal,specification,requireNonemptyPatch} from './catalog-validation';
import {requireAdminPermission} from './permissions';
import {publishOutbox} from './outbox';

type Tx=Prisma.TransactionClient;
async function admin(tx:Tx,userId:string) {
  // Force a row lock so an in-flight revocation cannot overtake this mutation.
  await tx.$queryRaw(Prisma.sql`SELECT "userId" FROM "AdminMembership" WHERE "userId"=${userId}::uuid FOR SHARE`);
  await requireAdminPermission(tx,userId,'CATALOG_APPROVE');
}
async function audit(tx:Tx,actorUserId:string,entityType:string,entityId:string,action:string) {
  await tx.auditEvent.create({data:{actorUserId,actorRole:'ADMIN_CATALOG',action,entityType,entityId}});
  await publishOutbox(tx,{eventKey:'catalog:'+randomUUID(),aggregateType:entityType,
    aggregateId:entityId,eventType:action,payload:{entityId,entityType}});
}
const serial=<T>(db:PrismaClient,fn:(tx:Tx)=>Promise<T>)=>
 db.$transaction(fn,{isolationLevel:Prisma.TransactionIsolationLevel.Serializable,maxWait:5000,timeout:10000});

export async function createCategory(db:PrismaClient,actor:string,input:unknown) {
 const o=record(input,['slug','name','parentId','displayOrder']);
 const values={
   slug:slug(o.slug,'slug',140),
   name:requiredString(o.name,'name',160),
   parentId:o.parentId===undefined||o.parentId===null?null:uuid(o.parentId,'parentId'),
   displayOrder:o.displayOrder===undefined?0:integer(o.displayOrder,'displayOrder',0,1000000),
 };
 return serial(db,async tx=>{
   await admin(tx,actor);
   if(values.parentId){
     const parent=await tx.category.findUnique({where:{id:values.parentId},select:{id:true,active:true}});
     if(!parent||!parent.active)throw new ApiError(422,'PARENT_CATEGORY_UNAVAILABLE','Parent category must be active.');
   }
   const created=await tx.category.create({data:{...values,active:false},select:{
     id:true,parentId:true,name:true,slug:true,displayOrder:true,active:true
   }});
   await audit(tx,actor,'Category',created.id,'CATALOG_CATEGORY_CREATED');
   return created;
 });
}
export async function updateCategory(db:PrismaClient,actor:string,id:string,input:unknown) {
 uuid(id,'categoryId');
 const o=record(input,['name','displayOrder','active']);
 requireNonemptyPatch(o);
 const data:{
   name?:string;displayOrder?:number;active?:boolean
 }={};
 if(o.name!==undefined)data.name=requiredString(o.name,'name',160);
 if(o.displayOrder!==undefined)data.displayOrder=integer(o.displayOrder,'displayOrder',0,1000000);
 if(o.active!==undefined)data.active=boolean(o.active,'active');
 return serial(db,async tx=>{
   await admin(tx,actor);
   const cat=await tx.category.findUnique({where:{id},select:{id:true,active:true,parentId:true}});
   if(!cat)throw new ApiError(404,'NOT_FOUND','Resource not found.');
   if(data.active===false && cat.active){
     const [products,children]=await Promise.all([
       tx.product.count({where:{categoryId:id,active:true}}),
       tx.category.count({where:{parentId:id,active:true}})
     ]);
     if(products||children)throw new ApiError(409,'CATEGORY_IN_USE','Deactivate products and child categories first.');
   }
   if(data.active===true && cat.parentId) {
     const parent=await tx.category.findUnique({where:{id:cat.parentId},select:{active:true}});
     if(!parent?.active)throw new ApiError(409,'PARENT_CATEGORY_INACTIVE','Activate the parent category first.');
   }
   const updated=await tx.category.update({where:{id},data,select:{
     id:true,name:true,slug:true,parentId:true,active:true,displayOrder:true
   }});
   await audit(tx,actor,'Category',id,'CATALOG_CATEGORY_UPDATED');
   return updated;
 });
}
export async function createBrand(db:PrismaClient,actor:string,input:unknown) {
 const o=record(input,['slug','name']);
 const data={slug:slug(o.slug,'slug',160),name:requiredString(o.name,'name',160)};
 return serial(db,async tx=>{
   await admin(tx,actor);
   const row=await tx.brand.create({data,select:{id:true,slug:true,name:true}});
   await audit(tx,actor,'Brand',row.id,'CATALOG_BRAND_CREATED');
   return row;
 });
}
function hsn(input:unknown) {
 if(input===null)return null;
 if(typeof input!=='string'||!/^[0-9]{4,12}$/.test(input))
  throw new ApiError(400,'INVALID_HSN','HSN must contain 4–12 digits.');
 return input;
}
export async function createProduct(db:PrismaClient,actor:string,input:unknown) {
 const o=record(input,['code','name','categoryId','brandId','description','hsnCode','specification']);
 const data={
   code:code(o.code,'code',80),name:requiredString(o.name,'name',240),
   categoryId:uuid(o.categoryId,'categoryId'),
   brandId:o.brandId===undefined||o.brandId===null?null:uuid(o.brandId,'brandId'),
   description:o.description===undefined||o.description===null?null:requiredString(o.description,'description',4000),
   hsnCode:o.hsnCode===undefined?null:hsn(o.hsnCode),
   specification:o.specification===undefined?{}:specification(o.specification),
   active:false,
 };
 return serial(db,async tx=>{
   await admin(tx,actor);
   const category=await tx.category.findUnique({where:{id:data.categoryId},select:{active:true}});
   if(!category?.active)throw new ApiError(422,'CATEGORY_INACTIVE','Choose an active category.');
   if(data.brandId && !(await tx.brand.findUnique({where:{id:data.brandId},select:{id:true}})))
     throw new ApiError(422,'BRAND_NOT_FOUND','Brand does not exist.');
   const row=await tx.product.create({data,select:{
     id:true,code:true,name:true,categoryId:true,brandId:true,active:true,hsnCode:true
   }});
   await audit(tx,actor,'Product',row.id,'CATALOG_PRODUCT_CREATED');
   return row;
 });
}
export async function updateProduct(db:PrismaClient,actor:string,id:string,input:unknown) {
 uuid(id,'productId');
 const o=record(input,['name','description','hsnCode','specification','active']);
 requireNonemptyPatch(o);
 const data:{
   name?:string;description?:string|null;hsnCode?:string|null;
   specification?:Prisma.InputJsonObject;active?:boolean
 }={};
 if(o.name!==undefined)data.name=requiredString(o.name,'name',240);
 if(o.description!==undefined)data.description=o.description===null?null:requiredString(o.description,'description',4000);
 if(o.hsnCode!==undefined)data.hsnCode=hsn(o.hsnCode);
 if(o.specification!==undefined)data.specification=specification(o.specification);
 if(o.active!==undefined)data.active=boolean(o.active,'active');
 return serial(db,async tx=>{
   await admin(tx,actor);
   const previous=await tx.product.findUnique({where:{id},select:{id:true,category:{select:{active:true}}}});
   if(!previous)throw new ApiError(404,'NOT_FOUND','Resource not found.');
   if(data.active===true && !previous.category.active)
     throw new ApiError(409,'CATEGORY_INACTIVE','Category must be active.');
   const row=await tx.product.update({where:{id},data,select:{
     id:true,code:true,name:true,active:true,categoryId:true,brandId:true,hsnCode:true
   }});
   await audit(tx,actor,'Product',row.id,'CATALOG_PRODUCT_UPDATED');
   return row;
 });
}
export async function addProductConversion(db:PrismaClient,actor:string,id:string,input:unknown) {
 uuid(id,'productId');
 const o=record(input,['fromUnit','toUnit','multiplier']);
 const fromUnit=code(o.fromUnit,'fromUnit',20);
 const toUnit=code(o.toUnit,'toUnit',20);
 if(fromUnit===toUnit)throw new ApiError(400,'INVALID_CONVERSION','Use different units.');
 const multiplier=exactDecimal(o.multiplier,'multiplier',15,9,true);
 return serial(db,async tx=>{
   await admin(tx,actor);
   if(!await tx.product.findUnique({where:{id},select:{id:true}}))
     throw new ApiError(404,'NOT_FOUND','Product not found.');
   const units=await tx.unitOfMeasure.findMany({where:{code:{in:[fromUnit,toUnit]},active:true},select:{code:true}});
   if(units.length!==2)throw new ApiError(422,'UNIT_UNAVAILABLE','Both units must be active.');
   const row=await tx.productUnitConversion.create({data:{productId:id,fromUnit,toUnit,multiplier},
     select:{id:true,productId:true,fromUnit:true,toUnit:true,multiplier:true}});
   await audit(tx,actor,'ProductUnitConversion',row.id,'CATALOG_CONVERSION_CREATED');
   return {...row,multiplier:row.multiplier.toString()};
 });
}
