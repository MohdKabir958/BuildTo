import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';
import {serializable} from './transaction';

const STATES=['DRAFT','PENDING','UNDER_REVIEW','APPROVED','REJECTED','SUSPENDED'] as const;
type State=typeof STATES[number];
const GST=['REGULAR','COMPOSITION','UNREGISTERED','EXEMPT'] as const;
const no=(code:string,message:string,status=400):never=>{throw new ApiError(status,code,message);};
const obj=(x:unknown):Record<string,unknown>=>
 x&&typeof x==='object'&&!Array.isArray(x)?x as Record<string,unknown>:no('INVALID_INPUT','JSON object required.');
const only=(x:Record<string,unknown>,keys:string[])=>{
 if(Object.keys(x).some(k=>!keys.includes(k)))no('INVALID_INPUT','Unexpected input field.');
};
const text=(x:unknown,name:string,min=1,max=250):string=>{
 if(typeof x!=='string'||x.trim().length<min||x.trim().length>max||/[\x00-\x1f\x7f]/.test(x))
  return no('INVALID_INPUT','Invalid '+name+'.');
 return x.trim();
};
const uuid=(id:string)=>isUuid(id)?id:no('NOT_FOUND','Supplier not found.',404);
const reason=(x:unknown)=>text(x,'audit reason',8,400);
const iso=(x:Date|null)=>x?.toISOString()??null;
const summary=(s:{
 id:string;slug:string;legalName:string;displayName:string;approval:State;gstRegistration:string;
 gstin:string|null;verifiedAt:Date|null;suspendedAt:Date|null;createdAt:Date;
})=>({id:s.id,slug:s.slug,legalName:s.legalName,displayName:s.displayName,approval:s.approval,
 gstRegistration:s.gstRegistration,gstin:s.gstin,verifiedAt:iso(s.verifiedAt),
 suspendedAt:iso(s.suspendedAt),createdAt:s.createdAt.toISOString()});
async function lockSupplier(tx:Prisma.TransactionClient,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql\`SELECT id FROM "Supplier" WHERE id=\${id}::uuid FOR UPDATE\`);
 if(rows.length===0)no('NOT_FOUND','Supplier not found.',404);
}
async function reviewer(tx:Prisma.TransactionClient,actor:string,id:string){
 await requireAdminPermission(tx,actor,'SUPPLIER_APPROVE');
 if(await tx.supplierMember.findUnique({where:{supplierId_userId:{supplierId:id,userId:actor}}}))
  no('SELF_REVIEW_DENIED','Supplier members cannot review their own business.',403);
}
async function audit(tx:Prisma.TransactionClient,actor:string,id:string,action:string,before:Prisma.InputJsonObject,after:Prisma.InputJsonObject){
 await tx.auditEvent.create({data:{
  actorUserId:actor,actorRole:'ADMIN_OPERATIONS',action,entityType:'Supplier',entityId:id,
  beforeState:before,afterState:after
 }});
}
export async function submitSupplierApplication(db:PrismaClient,actor:string,input:unknown){
 const d=obj(input);only(d,['slug','legalName','displayName','contactEmail','contactPhone','gstRegistration','gstin','billingAddress']);
 const slug=text(d.slug,'slug',3,100).toLowerCase();
 if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug))no('INVALID_SLUG','Slug must be lowercase, hyphen-delimited.');
 const legalName=text(d.legalName,'legal name',3,250);
 const displayName=text(d.displayName,'display name',3,200);
 const email=text(d.contactEmail,'email',6,320).toLowerCase();
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))no('INVALID_EMAIL','Contact email must be verified.');
 const phone=d.contactPhone==null?null:text(d.contactPhone,'phone',8,20);
 if(phone&&!/^\+[1-9]\d{7,14}$/.test(phone))no('INVALID_PHONE','Use E.164 contact phone.');
 if(typeof d.gstRegistration!=='string'||!GST.includes(d.gstRegistration as typeof GST[number]))
  no('INVALID_GST_REGISTRATION','Select a supported GST registration.');
 const gstRegistration=d.gstRegistration as typeof GST[number];
 const gstin=d.gstin==null?null:text(d.gstin,'GSTIN',15,15).toUpperCase();
 if(gstin&&!/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gstin))
  no('INVALID_GSTIN','Invalid GSTIN format.');
 if(['REGULAR','COMPOSITION'].includes(gstRegistration)&&!gstin)no('GSTIN_REQUIRED','GSTIN required for registered business.');
 if(['UNREGISTERED','EXEMPT'].includes(gstRegistration)&&gstin)no('INVALID_GSTIN','GSTIN not allowed for unregistered/exempt status.');
 const address=obj(d.billingAddress);only(address,['line1','line2','city','state','pinCode']);
 const billing={
  line1:text(address.line1,'address',5,250),city:text(address.city,'city',2,100),
  state:text(address.state,'state',2,100),pinCode:text(address.pinCode,'PIN',6,6),
  ...(address.line2?{line2:text(address.line2,'address line 2',1,250)}:{})
 };
 if(!/^[1-9]\d{5}$/.test(billing.pinCode))no('INVALID_PIN','Six-digit Indian PIN is required.');
 try {
  return await serializable(db,async tx=>{
   await tx.$queryRaw(Prisma.sql\`SELECT pg_advisory_xact_lock(hashtextextended(\${actor}, 54117)) IS NULL AS locked\`);
   const user=await tx.user.findUnique({where:{id:actor},select:{email:true,clerkUserId:true,status:true,deletedAt:true}});
   if(!user||user.status!=='ACTIVE'||!user.clerkUserId||user.deletedAt||user.email?.toLowerCase()!==email)
    no('VERIFIED_CONTACT_REQUIRED','Use the verified email on your synchronized Clerk account.',403);
   const open=await tx.supplierMember.findFirst({where:{
    userId:actor,role:'OWNER',supplier:{approval:{in:['PENDING','UNDER_REVIEW']}}
   }});
   if(open)no('APPLICATION_ALREADY_OPEN','Finish existing supplier application first.',409);
   const created=await tx.supplier.create({data:{
    slug,legalName,displayName,contactEmail:email,contactPhone:phone,gstRegistration,
    gstin,billingAddress:billing,approval:'PENDING',
    members:{create:{userId:actor,role:'OWNER',active:false}}
   },select:{id:true,slug:true,legalName:true,displayName:true,approval:true,gstRegistration:true,gstin:true,verifiedAt:true,suspendedAt:true,createdAt:true}});
   await tx.auditEvent.create({data:{
    actorUserId:actor,actorRole:'SUPPLIER_APPLICANT',action:'SUPPLIER_APPLICATION_SUBMITTED',
    entityType:'Supplier',entityId:created.id
   }});
   return summary(created);
  });
 }catch(e){
  if(e instanceof Prisma.PrismaClientKnownRequestError && e.code==='P2002')
   no('DUPLICATE_SUPPLIER','A supplier with this slug or GSTIN already exists.',409);
  throw e;
 }
}
export async function ownSupplierApplications(db:PrismaClient,actor:string){
 const rows=await db.supplier.findMany({where:{members:{some:{userId:actor,role:'OWNER'}}},
  orderBy:{createdAt:'desc'},take:50,
  select:{id:true,slug:true,legalName:true,displayName:true,approval:true,gstRegistration:true,gstin:true,verifiedAt:true,suspendedAt:true,createdAt:true}});
 return rows.map(summary);
}
export async function attachSupplierDocument(db:PrismaClient,actor:string,id:string,input:unknown){
 uuid(id);const d=obj(input);only(d,['mediaId','documentType']);
 const mediaId=text(d.mediaId,'media ID',36,36);
 if(!isUuid(mediaId))no('INVALID_MEDIA','Invalid evidence ID.');
 if(d.documentType!=='BUSINESS_REGISTRATION'&&d.documentType!=='GST_CERTIFICATE')
  no('INVALID_DOCUMENT_TYPE','Only business registration or GST evidence supported.');
 return serializable(db,async tx=>{
  await lockSupplier(tx,id);
  const member=await tx.supplierMember.findUnique({where:{supplierId_userId:{supplierId:id,userId:actor}}});
  if(!member||member.role!=='OWNER'||member.revokedAt)no('NOT_FOUND','Supplier not found.',404);
  const supplier=await tx.supplier.findUniqueOrThrow({where:{id},select:{approval:true}});
  if(!['PENDING','UNDER_REVIEW','REJECTED'].includes(supplier.approval))
   no('DOCUMENT_LOCKED','Cannot attach evidence after approval.',409);
  const media=await tx.mediaAsset.findUnique({where:{id:mediaId},select:{ownerUserId:true,sizeBytes:true,mimeType:true,sha256:true}});
  if(!media||media.ownerUserId!==actor||!media.sha256||media.sizeBytes>BigInt(10485760)||
   !['application/pdf','image/jpeg','image/png'].includes(media.mimeType))
   no('EVIDENCE_UNAVAILABLE','Use a verified private PDF/JPEG/PNG asset owned by your account.',403);
  if(await tx.supplierDocument.findFirst({where:{mediaId}}))
   no('EVIDENCE_ALREADY_LINKED','Evidence is already attached to an application.',409);
  const doc=await tx.supplierDocument.create({data:{
   supplierId:id,mediaId,documentType:d.documentType,status:'UPLOADED'
  },select:{id:true,documentType:true,status:true,createdAt:true}});
  await tx.auditEvent.create({data:{
   actorUserId:actor,actorRole:'SUPPLIER_APPLICANT',action:'SUPPLIER_DOCUMENT_ATTACHED',
   entityType:'SupplierDocument',entityId:doc.id
  }});
  return {id:doc.id,documentType:doc.documentType,status:doc.status,createdAt:doc.createdAt.toISOString()};
 });
}
export async function adminSupplierQueue(db:PrismaClient,actor:string,query:{status?:string;cursor?:string;limit?:number}){
 await requireAdminPermission(db,actor,'SUPPLIER_APPROVE');
 const limit=query.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>100)no('INVALID_LIMIT','Limit must be 1–100.');
 const status=query.status;
 if(status!==undefined&&!STATES.includes(status as State))no('INVALID_STATUS','Invalid supplier state.');
 const cursor=query.cursor?uuid(query.cursor):undefined;
 const rows=await db.supplier.findMany({where:{
  ...(status?{approval:status as State}:{}),...(cursor?{id:{gt:cursor}}:{})
 },orderBy:{id:'asc'},take:limit+1,select:{
  id:true,slug:true,legalName:true,displayName:true,approval:true,gstRegistration:true,gstin:true,verifiedAt:true,suspendedAt:true,createdAt:true
 }});
 return {items:rows.slice(0,limit).map(summary),nextCursor:rows.length>limit?rows[limit-1].id:null};
}
export async function adminSupplierDetail(db:PrismaClient,actor:string,id:string){
 uuid(id);await requireAdminPermission(db,actor,'SUPPLIER_APPROVE');
 const found=await db.supplier.findUnique({where:{id},select:{
  id:true,slug:true,legalName:true,displayName:true,approval:true,gstRegistration:true,gstin:true,verifiedAt:true,suspendedAt:true,createdAt:true,
  businessType:true,contactEmail:true,contactPhone:true,billingAddress:true,
  members:{where:{role:'OWNER'},select:{userId:true,active:true,user:{select:{displayName:true,email:true}}}},
  documents:{select:{id:true,documentType:true,status:true,reviewNote:true,expiresAt:true,createdAt:true,
   media:{select:{mimeType:true,sizeBytes:true,sha256:true}}},orderBy:{createdAt:'asc'}}
 }});
 if(!found)no('NOT_FOUND','Supplier not found.',404);
 const {members,documents,businessType,contactEmail,contactPhone,billingAddress,...base}=found;
 return {...summary(base),businessType,contactEmail,contactPhone,billingAddress,
  owners:members.map(x=>({userId:x.userId,active:x.active,displayName:x.user.displayName,email:x.user.email})),
  documents:documents.map(x=>({id:x.id,documentType:x.documentType,status:x.status,reviewNote:x.reviewNote,
   expiresAt:iso(x.expiresAt),createdAt:x.createdAt.toISOString(),
   mimeType:x.media.mimeType,sizeBytes:x.media.sizeBytes.toString(),digestAvailable:Boolean(x.media.sha256)}))
 };
}
export async function reviewSupplierDocument(db:PrismaClient,actor:string,id:string,documentId:string,input:unknown){
 uuid(id);uuid(documentId);const d=obj(input);only(d,['decision','reason']);
 if(d.decision!=='VERIFIED'&&d.decision!=='REJECTED')no('INVALID_DECISION','Choose VERIFIED or REJECTED.');
 const why=reason(d.reason);
 return serializable(db,async tx=>{
  await lockSupplier(tx,id);await reviewer(tx,actor,id);
  const supplier=await tx.supplier.findUniqueOrThrow({where:{id},select:{approval:true}});
  if(!['PENDING','UNDER_REVIEW','REJECTED'].includes(supplier.approval))
   no('DOCUMENT_LOCKED','Document review is closed.',409);
  const old=await tx.supplierDocument.findFirst({where:{id:documentId,supplierId:id}});
  if(!old)no('NOT_FOUND','Document not found.',404);
  if(!['UPLOADED','PENDING','REVIEWED'].includes(old.status))no('DOCUMENT_FINAL','Document has final decision.',409);
  const saved=await tx.supplierDocument.update({where:{id:documentId},data:{
   status:d.decision as 'VERIFIED'|'REJECTED',reviewNote:why,verifiedById:actor
  }});
  await audit(tx,actor,id,'SUPPLIER_DOCUMENT_REVIEWED',
   {documentId,status:old.status},{documentId,status:saved.status,reason:why});
  return {id:saved.id,status:saved.status,reviewNote:saved.reviewNote};
 });
}
export async function reviewSupplierApplication(db:PrismaClient,actor:string,id:string,input:unknown){
 uuid(id);const d=obj(input);only(d,['decision','reason']);
 const decision=d.decision;
 if(decision!=='UNDER_REVIEW'&&decision!=='APPROVED'&&decision!=='REJECTED'&&decision!=='SUSPENDED')
  no('INVALID_DECISION','Unsupported supplier transition.');
 const why=reason(d.reason);
 return serializable(db,async tx=>{
  await lockSupplier(tx,id);await reviewer(tx,actor,id);
  const old=await tx.supplier.findUniqueOrThrow({where:{id}});
  const transitions:Record<string,readonly State[]>={
   PENDING:['UNDER_REVIEW','APPROVED','REJECTED'],
   UNDER_REVIEW:['APPROVED','REJECTED'],
   REJECTED:['UNDER_REVIEW'],
   APPROVED:['SUSPENDED'],
   SUSPENDED:['UNDER_REVIEW']
  };
  if(!transitions[old.approval]?.includes(decision))
   no('ILLEGAL_TRANSITION','Supplier review transition is not permitted.',409);
  if(decision==='APPROVED'){
   if(!old.contactEmail||!old.billingAddress)
    no('INCOMPLETE_APPLICATION','Verified contact and billing address required.',409);
   const docRows=await tx.supplierDocument.findMany({where:{
    supplierId:id,status:'VERIFIED',OR:[{expiresAt:null},{expiresAt:{gt:new Date()}}]
   },select:{documentType:true}});
   const types=new Set(docRows.map(x=>x.documentType));
   if(!types.has('BUSINESS_REGISTRATION')||
      (['REGULAR','COMPOSITION'].includes(old.gstRegistration)&&(!old.gstin||!types.has('GST_CERTIFICATE'))))
    no('VERIFIED_EVIDENCE_REQUIRED','Verify current business and applicable GST documents before approval.',409);
   const ownerCount=await tx.supplierMember.count({where:{supplierId:id,role:'OWNER',revokedAt:null}});
   if(ownerCount<1)no('OWNER_REQUIRED','Supplier requires an owner.',409);
  }
  const saved=await tx.supplier.update({where:{id},data:{
   approval:decision,
   ...(decision==='APPROVED'?{verifiedAt:new Date(),suspendedAt:null}:{}),
   ...(decision==='SUSPENDED'?{suspendedAt:new Date()}:{}),
   ...(decision==='UNDER_REVIEW'?{suspendedAt:null}:{})
  },select:{
   id:true,slug:true,legalName:true,displayName:true,approval:true,gstRegistration:true,gstin:true,verifiedAt:true,suspendedAt:true,createdAt:true
  }});
  if(decision==='APPROVED')await tx.supplierMember.updateMany({where:{
   supplierId:id,role:'OWNER',revokedAt:null
  },data:{active:true}});
  await audit(tx,actor,id,'SUPPLIER_APPROVAL_CHANGED',
   {approval:old.approval},{approval:decision,reason:why});
  return summary(saved);
 });
}
