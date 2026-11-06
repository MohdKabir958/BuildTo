import {ApiError} from './errors';

// Payment-provider calls happen ONLY outside PostgreSQL transactions.
export interface GatewayOrder {
 id:string;amount:bigint;currency:'INR';receipt:string;
}
export interface GatewayRefund {
 id:string;paymentId:string;amount:bigint;currency:'INR';
 status:'processed'|'pending'|'failed';
}
export interface GatewayPaymentInspection {
 status:'NO_ACTIVE_PAYMENT'|'ACTIVE_PAYMENT'|'CAPTURED';
}
export interface PaymentGateway {
 inspectOrderPayments?(orderId:string):Promise<GatewayPaymentInspection>;
 lookupRefund?(refundId:string):Promise<GatewayRefund>;
 readonly publicKey:string;
 createOrder(input:{amount:bigint;receipt:string}):Promise<GatewayOrder>;
 lookupOrderByReceipt?(receipt:string):Promise<GatewayOrder|null>;
}
export class RazorpayGateway implements PaymentGateway {
 constructor(
  public readonly publicKey:string,
  private readonly secretKey:string
 ) {
  if(!/^rzp_(test|live)_[A-Za-z0-9]+$/.test(publicKey)||!secretKey)
   throw new Error('V21_RAZORPAY_CONFIG_INVALID');
 }
 async createOrder(input:{amount:bigint;receipt:string}):Promise<GatewayOrder> {
  if(input.amount<100n||input.amount>100000000000n||
     !/^[A-Za-z0-9_-]{8,40}$/.test(input.receipt))
   throw new ApiError(422,'PAYMENT_AMOUNT_UNSUPPORTED','Payment cannot be initialized for this amount.');
  let response:globalThis.Response;
  try {
   response=await fetch('https://api.razorpay.com/v1/orders',{
    method:'POST',
    headers:{
     Authorization:'Basic '+Buffer.from(this.publicKey+':'+this.secretKey).toString('base64'),
     'Content-Type':'application/json'
    },
    body:JSON.stringify({
     amount:Number(input.amount),currency:'INR',receipt:input.receipt
    }),
    signal:AbortSignal.timeout(7000)
   });
  } catch {
   // Treat timeout as UNKNOWN; never blindly repeat a create request.
   throw new ApiError(503,'PAYMENT_PROVIDER_UNAVAILABLE','Payment provider could not be reached.');
  }
  if(!response.ok)
   throw new ApiError(503,'PAYMENT_PROVIDER_UNAVAILABLE','Payment provider rejected order initialization.');
  let body:unknown;
  try {body=await response.json();}catch{
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Payment provider returned an invalid response.');
  }
  if(!body||typeof body!=='object'||Array.isArray(body))
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid payment provider response.');
  const x=body as Record<string,unknown>;
  if(typeof x.id!=='string'||!/^order_[A-Za-z0-9]{8,60}$/.test(x.id)||
    x.currency!=='INR'||x.receipt!==input.receipt||
    typeof x.amount!=='number'||!Number.isSafeInteger(x.amount)||
    BigInt(x.amount)!==input.amount)
   throw new ApiError(503,'PAYMENT_PROVIDER_MISMATCH','Payment provider order details did not match.');
  return {id:x.id,amount:input.amount,currency:'INR',receipt:input.receipt};
 }
 /**
  * Read-only Razorpay refund reconciliation. This class does NOT issue refunds.
  * No arbitrary host URL or response status becomes a financial success.
  */
 async lookupRefund(refundId:string):Promise<GatewayRefund>{
  if(!/^rfnd_[A-Za-z0-9]{8,60}$/.test(refundId))
   throw new ApiError(400,'INVALID_PROVIDER_REFUND_ID','Invalid Razorpay refund reference.');
  let response:globalThis.Response;
  try{
   response=await fetch('https://api.razorpay.com/v1/refunds/'+
    encodeURIComponent(refundId),{
     headers:{Authorization:'Basic '+
      Buffer.from(this.publicKey+':'+this.secretKey).toString('base64')},
     signal:AbortSignal.timeout(7000)
   });
  }catch{
   throw new ApiError(503,'REFUND_PROVIDER_UNAVAILABLE','Refund provider verification is unavailable.');
  }
  if(!response.ok)
   throw new ApiError(503,'REFUND_PROVIDER_UNAVAILABLE','Refund provider verification failed.');
  let payload:unknown;
  try{payload=await response.json();}catch{
   throw new ApiError(503,'REFUND_PROVIDER_INVALID','Invalid refund provider response.');
  }
  if(!payload||typeof payload!=='object'||Array.isArray(payload))
   throw new ApiError(503,'REFUND_PROVIDER_INVALID','Invalid refund response structure.');
  const p=payload as Record<string,unknown>;
  if(p.id!==refundId||typeof p.payment_id!=='string'||
   !/^pay_[A-Za-z0-9]{8,60}$/.test(p.payment_id)||
   p.currency!=='INR'||typeof p.amount!=='number'||
   !Number.isSafeInteger(p.amount)||p.amount<=0||
   !['processed','pending','failed'].includes(String(p.status)))
   throw new ApiError(503,'REFUND_PROVIDER_INVALID','Invalid amount or identity in refund evidence.');
  return {id:refundId,paymentId:p.payment_id,
   amount:BigInt(p.amount),currency:'INR',
   status:p.status as GatewayRefund['status']};
 }
 /**
  * Read-only inspection of payments for one Razorpay Order.
  * A payment.failed event only reports one try, NOT the whole order.
  */
 async inspectOrderPayments(orderId:string):Promise<GatewayPaymentInspection>{
  if(!/^order_[A-Za-z0-9]{8,60}$/.test(orderId))
   throw new ApiError(400,'INVALID_PROVIDER_ORDER','Invalid gateway order ID.');
  let response:globalThis.Response;
  try {
   response=await fetch('https://api.razorpay.com/v1/orders/'+
    encodeURIComponent(orderId)+'/payments?count=100',{
    headers:{Authorization:'Basic '+
     Buffer.from(this.publicKey+':'+this.secretKey).toString('base64')},
    signal:AbortSignal.timeout(7000)
   });
  }catch{
   throw new ApiError(503,'PAYMENT_RECONCILIATION_UNAVAILABLE','Provider payment lookup unavailable.');
  }
  if(!response.ok)
   throw new ApiError(503,'PAYMENT_RECONCILIATION_UNAVAILABLE','Provider payment lookup failed.');
  let body:unknown;
  try{body=await response.json();}catch{
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider payments response.');
  }
  if(!body||typeof body!=='object'||Array.isArray(body))
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider payments response.');
  const {items,count}=body as {items?:unknown;count?:unknown};
  if(!Array.isArray(items)||!Number.isSafeInteger(count)||typeof count!=='number'||
     count<0||count!==items.length||count>=100)
   throw new ApiError(503,'PAYMENT_RECONCILIATION_INCOMPLETE','Complete provider payment history required.');
  let active=false,captured=false;
  for(const item of items){
   if(!item||typeof item!=='object'||Array.isArray(item))
    throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider payment row.');
   const p=item as Record<string,unknown>;
   if(p.order_id!==orderId||typeof p.status!=='string')
    throw new ApiError(503,'PAYMENT_PROVIDER_MISMATCH','Provider payment does not belong to order.');
   if(['captured','refunded'].includes(p.status))captured=true;
   else if(p.status!=='failed')active=true;
  }
  return {status:captured?'CAPTURED':active?'ACTIVE_PAYMENT':'NO_ACTIVE_PAYMENT'};
 }
 // Lookup is read-only. It is used to reconcile an UNKNOWN create outcome;
 // never blindly issue another POST after a timeout or missing response.
 async lookupOrderByReceipt(receipt:string):Promise<GatewayOrder|null>{
  if(!/^[A-Za-z0-9_-]{8,40}$/.test(receipt))
   throw new ApiError(400,'BAD_GATEWAY_RECEIPT','Invalid gateway receipt.');
  let response:globalThis.Response;
  try{
   response=await fetch('https://api.razorpay.com/v1/orders?receipt='+
    encodeURIComponent(receipt)+'&count=10',{
     headers:{Authorization:'Basic '+
      Buffer.from(this.publicKey+':'+this.secretKey).toString('base64')},
     signal:AbortSignal.timeout(7000)
    });
  }catch{
   throw new ApiError(503,'PAYMENT_RECONCILIATION_UNAVAILABLE','Provider lookup unavailable.');
  }
  if(!response.ok)
   throw new ApiError(503,'PAYMENT_RECONCILIATION_UNAVAILABLE','Provider lookup unavailable.');
  let payload:unknown;
  try{payload=await response.json();}catch{
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider lookup.');
  }
  if(!payload||typeof payload!=='object'||Array.isArray(payload))
   throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider lookup.');
  const items=(payload as {items?:unknown}).items;
  if(!Array.isArray(items))throw new ApiError(503,'PAYMENT_PROVIDER_INVALID_RESPONSE','Invalid provider lookup.');
  const matched=items.filter(x=>x&&typeof x==='object'&&x.receipt===receipt);
  if(matched.length===0)return null;
  if(matched.length!==1)throw new ApiError(503,'PAYMENT_PROVIDER_MISMATCH','Duplicate provider receipts need review.');
  const x=matched[0];
  if(typeof x.id!=='string'||!/^order_[A-Za-z0-9]{8,60}$/.test(x.id)||
    !Number.isSafeInteger(x.amount)||x.amount<100||x.currency!=='INR')
   throw new ApiError(503,'PAYMENT_PROVIDER_MISMATCH','Provider receipt record invalid.');
  return {id:x.id,amount:BigInt(x.amount),currency:'INR',receipt};
 }
}
