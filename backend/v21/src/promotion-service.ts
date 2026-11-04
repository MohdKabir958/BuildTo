import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission} from './permissions';
import {record,requiredString,integer,paise,uuid} from './catalog-validation';
import {boundedPaise} from './rfq-validation';

type Tx=Prisma.TransactionClient;
const promotionSelect={
 id:true,code:true,title:true,type:true,amountPaise:true,percentageBps:true,
 capPaise:true,minCartPaise:true,perUserLimit:true,globalLimit:true,
 startsAt:true,endsAt:true,active:true
} as const;
function promoDTO(p:any){
 return {id:p.id,code:p.code,title:p.title,type:p.type,
  amountPaise:p.amountPaise?.toString()??null,percentageBps:p.percentageBps,
  capPaise:p.capPaise?.toString()??null,minCartPaise:p.minCartPaise?.toString()??null,
  perUserLimit:p.perUserLimit,globalLimit:p.globalLimit,
  startsAt:p.startsAt.toISOString(),endsAt:p.endsAt.toISOString(),active:p.active};
}
function parseDate(x:unknown,name:string){
 if(typeof x!=='string'||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?Z$/.test(x))
  throw new ApiError(400,'INVALID_DATE','Invalid UTC date for '+name+'.');
 const d=new Date(x);
 if(Number.isNaN(d.getTime()))throw new ApiError(400,'INVALID_DATE','Invalid date.');
 return d;
}
function promoInput(payload:unknown) {
 const o=record(payload,['code','title','type','amountPaise','percentageBps',
  'capPaise','minCartPaise','perUserLimit','globalLimit','startsAt','endsAt']);
 const code=requiredString(o.code,'code',60).toUpperCase();
 if(!/^[A-Z0-9][A-Z0-9_-]{2,59}$/.test(code))
  throw new ApiError(400,'INVALID_PROMOTION_CODE','Promotion code must use letters, numbers, underscores or dashes.');
 const title=requiredString(o.title,'title',160);
 if(!['PERCENTAGE','FIXED_PAISE','FREE_DELIVERY'].includes(String(o.type)))
  throw new ApiError(400,'INVALID_PROMOTION_TYPE','Unsupported promotion type.');
 const type=o.type as 'PERCENTAGE'|'FIXED_PAISE'|'FREE_DELIVERY';
 const amountPaise=o.amountPaise===null||o.amountPaise===undefined?null:boundedPaise(paise(o.amountPaise,'amountPaise'));
 const percentageBps=o.percentageBps===undefined||o.percentageBps===null?null:integer(o.percentageBps,'percentageBps',1,10000);
 const capPaise=o.capPaise===undefined||o.capPaise===null?null:boundedPaise(paise(o.capPaise,'capPaise'));
 if(type==='PERCENTAGE'&&(!percentageBps||amountPaise!==null))
  throw new ApiError(400,'INVALID_PROMOTION_VALUE','Percentage promotion requires basis points and no fixed amount.');
 if(type==='FIXED_PAISE'&&(!amountPaise||amountPaise<=0n||percentageBps!==null||capPaise!==null))
  throw new ApiError(400,'INVALID_PROMOTION_VALUE','Fixed promotion requires a positive amount only.');
 if(type==='FREE_DELIVERY'&&(amountPaise!==null||percentageBps!==null||capPaise!==null))
  throw new ApiError(400,'INVALID_PROMOTION_VALUE','Free delivery cannot specify a monetary amount.');
 const startsAt=parseDate(o.startsAt,'startsAt'),endsAt=parseDate(o.endsAt,'endsAt');
 if(endsAt<=startsAt||endsAt.getTime()<=Date.now()||
    endsAt.getTime()-startsAt.getTime()>366*86400000)
  throw new ApiError(400,'INVALID_PROMOTION_WINDOW','Promotion needs a future expiry and a window no longer than one year.');
 return {code,title,type,amountPaise,percentageBps,capPaise,
  minCartPaise:o.minCartPaise===undefined||o.minCartPaise===null?null:boundedPaise(paise(o.minCartPaise,'minCartPaise')),
  perUserLimit:o.perUserLimit===undefined||o.perUserLimit===null?null:integer(o.perUserLimit,'perUserLimit',1,1000),
  globalLimit:o.globalLimit===undefined||o.globalLimit===null?null:integer(o.globalLimit,'globalLimit',1,1000000),
  startsAt,endsAt,active:false};
}
async function admin(tx:Tx,actorId:string) {
 await tx.$queryRaw(Prisma.sql`SELECT "userId" FROM "AdminMembership" WHERE "userId"=${actorId}::uuid FOR SHARE`);
 await requireAdminPermission(tx,actorId,'PROMOTION_MANAGE');
}
export async function listPromotions(db:PrismaClient,actorId:string) {
 await requireAdminPermission(db,actorId,'PROMOTION_MANAGE');
 const items=await db.promotion.findMany({select:promotionSelect,
  orderBy:{startsAt:'desc'},take:100});
 return items.map(promoDTO);
}
export async function createPromotion(db:PrismaClient,actorId:string,payload:unknown) {
 const data=promoInput(payload);
 return serializable(db,async tx=>{
  await admin(tx,actorId);
  const created=await tx.promotion.create({data,select:promotionSelect});
  await tx.auditEvent.create({data:{actorUserId:actorId,actorRole:'ADMIN_PROMOTION',
   action:'PROMOTION_CREATED',entityType:'Promotion',entityId:created.id}});
  return promoDTO(created);
 });
}
export async function setPromotionActive(db:PrismaClient,actorId:string,promotionId:string,payload:unknown) {
 uuid(promotionId,'promotionId');
 const o=record(payload,['active']);
 if(typeof o.active!=='boolean')throw new ApiError(400,'INVALID_ACTIVE','active must be boolean.');
 const active=o.active as boolean;
 return serializable(db,async tx=>{
  await admin(tx,actorId);
  const promotion=await tx.promotion.findUnique({where:{id:promotionId},select:promotionSelect});
  if(!promotion)throw new ApiError(404,'NOT_FOUND','Promotion not found.');
  if(active&&promotion.endsAt<=new Date())
   throw new ApiError(409,'PROMOTION_EXPIRED','Expired promotion cannot be activated.');
  const updated=await tx.promotion.update({where:{id:promotionId},
   data:{active},select:promotionSelect});
  await tx.auditEvent.create({data:{actorUserId:actorId,actorRole:'ADMIN_PROMOTION',
   action:active?'PROMOTION_ACTIVATED':'PROMOTION_DEACTIVATED',
   entityType:'Promotion',entityId:promotionId}});
  return promoDTO(updated);
 });
}
type ActivePromotion=Prisma.PromotionGetPayload<{select:typeof promotionSelect}>;
export function computeDiscount(p:ActivePromotion,subtotalPaise:bigint,deliveryPaise:bigint):bigint {
 boundedPaise(subtotalPaise);boundedPaise(deliveryPaise);
 if(p.minCartPaise!==null&&subtotalPaise<p.minCartPaise)
  throw new ApiError(422,'PROMOTION_MINIMUM_NOT_MET','Order subtotal is below the promotion minimum.');
 if(p.type==='FREE_DELIVERY')return deliveryPaise;
 if(p.type==='FIXED_PAISE')return subtotalPaise<(p.amountPaise??0n)?subtotalPaise:p.amountPaise!;
 const percent=BigInt(p.percentageBps??0);
 let amount=(subtotalPaise*percent+5000n)/10000n;
 if(p.capPaise!==null&&amount>p.capPaise)amount=p.capPaise;
 return amount>subtotalPaise?subtotalPaise:amount;
}
async function findActivePromo(tx:Tx,code:string,now:Date) {
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "Promotion" WHERE code=${code} AND active=true
    AND "startsAt"<=${now} AND "endsAt">${now}
  FOR UPDATE
 `);
 if(!rows[0])throw new ApiError(422,'PROMOTION_UNAVAILABLE','Promotion is unavailable or expired.');
 return tx.promotion.findUniqueOrThrow({where:{id:rows[0].id},select:promotionSelect});
}
// Called INSIDE PR 08's authoritative checkout transaction, never with a
// customer-supplied subtotal. Lock the promo row to serialize use-limit checks.
export async function recordOrderPromotion(tx:Tx,args:{
 code:string;customerId:string;orderId:string;now?:Date
}) {
 uuid(args.customerId,'customerId');uuid(args.orderId,'orderId');
 const code=requiredString(args.code,'code',60).toUpperCase();
 if(!/^[A-Z0-9][A-Z0-9_-]{2,59}$/.test(code))
  throw new ApiError(400,'INVALID_PROMOTION_CODE','Invalid promotion code.');
 const order=await tx.purchaseOrder.findFirst({where:{id:args.orderId,customerId:args.customerId},
  select:{id:true,subtotalPaise:true,deliveryPaise:true,discountPaise:true}});
 if(!order)throw new ApiError(404,'ORDER_NOT_FOUND','Customer order does not exist.');
 // An already committed discount remains replayable after its expiry/deactivation.
 // A new redemption must still lock the currently active promotion.
 const existing=await tx.promotionRedemption.findUnique({where:{orderId:args.orderId},
  select:{customerId:true,promotionId:true,amountPaise:true,promotion:{select:{code:true}}}});
 if(existing){
  if(existing.customerId===args.customerId&&existing.promotion.code===code)
   return {amountPaise:existing.amountPaise.toString(),replayed:true};
  throw new ApiError(409,'PROMOTION_ALREADY_USED','An order can apply only one promotion.');
 }
 const now=args.now??new Date();
 const promotion=await findActivePromo(tx,code,now);
 const [globalUsed,customerUsed]=await Promise.all([
  tx.promotionRedemption.count({where:{promotionId:promotion.id}}),
  tx.promotionRedemption.count({where:{promotionId:promotion.id,customerId:args.customerId}})
 ]);
 if(promotion.globalLimit!==null&&globalUsed>=promotion.globalLimit)
  throw new ApiError(409,'PROMOTION_LIMIT_REACHED','Promotion usage limit reached.');
 if(promotion.perUserLimit!==null&&customerUsed>=promotion.perUserLimit)
  throw new ApiError(409,'PROMOTION_USER_LIMIT','Promotion already used the maximum times.');
 const amount=computeDiscount(promotion,order.subtotalPaise,order.deliveryPaise);
 if(amount<=0n||order.discountPaise!==amount)
  throw new ApiError(409,'PROMOTION_TOTAL_MISMATCH','Order discount must match its server-calculated promotion.');
 await tx.promotionRedemption.create({data:{promotionId:promotion.id,
  customerId:args.customerId,orderId:args.orderId,amountPaise:amount}});
 return {amountPaise:amount.toString(),replayed:false};
}
