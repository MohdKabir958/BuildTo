import {ApiError} from './errors';

// Payment-provider calls happen ONLY outside PostgreSQL transactions.
export interface GatewayOrder {
 id:string;amount:bigint;currency:'INR';receipt:string;
}
export interface PaymentGateway {
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
