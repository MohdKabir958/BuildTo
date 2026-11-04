import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';
const STATUSES=['PLACED','CONFIRMED','PARTIALLY_FULFILLED','PARTIALLY_CANCELLED','FULFILLED','CANCELLED','CLOSED'] as const;
type Status=typeof STATUSES[number];

async function authorize(db:PrismaClient,actor:string){
 const access=await requireAdminPermission(db,actor,'ADMIN_READ');
 // Audit-only and catalogue administrators may not browse all customer orders.
 if(!['OWNER','OPERATIONS','SUPPORT','FINANCE'].includes(access.role))
  throw new ApiError(403,'ORDER_READ_DENIED','Order oversight is not available for this role.');
 return access;
}
const invalid=(what:string)=>{throw new ApiError(400,'INVALID_QUERY','Invalid '+what+'.');};
const number=(v:bigint)=>v.toString();
const orderBase=(x:{
 id:string;publicNumber:string;status:Status;currency:string;totalPaise:bigint;placedAt:Date;
})=>({
 id:x.id,publicNumber:x.publicNumber,status:x.status,currency:x.currency,
 totalPaise:number(x.totalPaise),placedAt:x.placedAt.toISOString()
});
export async function adminOrders(db:PrismaClient,actor:string,q:{limit?:number;cursor?:string;status?:string;number?:string}){
 await authorize(db,actor);
 const limit=q.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>50)invalid('limit');
 if(q.cursor!==undefined&&!isUuid(q.cursor))invalid('cursor');
 if(q.status!==undefined&&!STATUSES.includes(q.status as Status))invalid('status');
 if(q.number!==undefined&&(q.number.length<3||q.number.length>40||!/^[A-Za-z0-9-]+$/.test(q.number)))invalid('order number');
 const rows=await db.purchaseOrder.findMany({
  where:{
   ...(q.status?{status:q.status as Status}:{}),
   ...(q.number?{publicNumber:q.number}:{}),
  },
  orderBy:[{placedAt:'desc'},{id:'desc'}],
  ...(q.cursor?{cursor:{id:q.cursor},skip:1}:{}),
  take:limit+1,
  select:{
   id:true,publicNumber:true,status:true,currency:true,totalPaise:true,placedAt:true,
   supplierOrders:{select:{id:true,supplierId:true,status:true,
    supplier:{select:{displayName:true}}},orderBy:{id:'asc'},take:30}
  }
 });
 const visible=rows.slice(0,limit).map(x=>({...orderBase(x),
  supplierOrders:x.supplierOrders.map(s=>({
   id:s.id,supplierId:s.supplierId,supplierName:s.supplier.displayName,status:s.status
  }))
 }));
 return {asOf:new Date().toISOString(),items:visible,nextCursor:rows.length>limit?rows[limit-1].id:null,
  note:'Counts and supplier groups reflect current database state; never imply successful collection.'};
}
export async function adminOrderDetail(db:PrismaClient,actor:string,orderId:string){
 await authorize(db,actor);
 if(!isUuid(orderId))throw new ApiError(404,'NOT_FOUND','Order not found.');
 const row=await db.purchaseOrder.findUnique({where:{id:orderId},select:{
  id:true,publicNumber:true,status:true,currency:true,totalPaise:true,subtotalPaise:true,
  discountPaise:true,taxPaise:true,deliveryPaise:true,placedAt:true,
  supplierOrders:{orderBy:{createdAt:'asc'},take:100,select:{
   id:true,supplierId:true,status:true,totalPaise:true,subtotalPaise:true,deliveryPaise:true,
   supplier:{select:{displayName:true}},
   items:{orderBy:{id:'asc'},take:100,select:{
    id:true,skuSnapshot:true,nameSnapshot:true,quantity:true,unitCode:true,unitPrice:true,
    taxRateBps:true,lineTotalPaise:true
   }},
   shipments:{orderBy:{createdAt:'asc'},take:100,select:{
    id:true,shipmentNumber:true,status:true,createdAt:true,deliveredAt:true,handoverMethod:true,
    exceptionApprovedAt:true
   }}
  }},
  payments:{orderBy:{createdAt:'desc'},take:100,select:{
   id:true,status:true,provider:true,paymentMethod:true,amountPaise:true,capturedPaise:true,
   currency:true,verifiedAt:true,createdAt:true
  }}
 }});
 if(!row)throw new ApiError(404,'NOT_FOUND','Order not found.');
 return {...orderBase(row),
  subtotalPaise:number(row.subtotalPaise),taxPaise:number(row.taxPaise),
  deliveryPaise:number(row.deliveryPaise),discountPaise:number(row.discountPaise),
  supplierOrders:row.supplierOrders.map(s=>({
   id:s.id,supplierId:s.supplierId,supplierName:s.supplier.displayName,status:s.status,
   totalPaise:number(s.totalPaise),subtotalPaise:number(s.subtotalPaise),deliveryPaise:number(s.deliveryPaise),
   items:s.items.map(i=>({
    id:i.id,sku:i.skuSnapshot,name:i.nameSnapshot,quantity:i.quantity.toString(),unitCode:i.unitCode,
    unitPrice:i.unitPrice.toString(),taxRateBps:i.taxRateBps,lineTotalPaise:number(i.lineTotalPaise)
   })),
   shipments:s.shipments.map(sh=>({
    id:sh.id,number:sh.shipmentNumber,status:sh.status,createdAt:sh.createdAt.toISOString(),
    deliveredAt:sh.deliveredAt?.toISOString()??null,handoverMethod:sh.handoverMethod,
    exceptionApproved:sh.exceptionApprovedAt!==null
   }))
  })),
  payments:row.payments.map(p=>({
   id:p.id,status:p.status,provider:p.provider,paymentMethod:p.paymentMethod,
   amountPaise:number(p.amountPaise),capturedPaise:number(p.capturedPaise),currency:p.currency,
   verifiedAt:p.verifiedAt?.toISOString()??null,createdAt:p.createdAt.toISOString()
  })),
  privacy:'Customer address and contact, provider references, OTPs, evidence and bank details intentionally omitted.',
  executionAllowed:false
 };
}
