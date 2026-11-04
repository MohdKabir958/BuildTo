import {ApiError} from './errors';

export interface PayoutFundAccount {
 id:string;active:boolean;accountType:'bank_account';holder:string;
 ifsc:string;last4:string;
}
export interface PayoutValidation {
 id:string;fundAccountId:string;status:'completed';registeredName:string;
 accountStatus:'active'|'valid';
}
export interface PayoutProviderRecord {
 id:string;fundAccountId:string;amount:bigint;currency:'INR';
 referenceId:string;purpose:'payout';status:string;utr:string|null;
}
export interface PayoutEvidenceGateway {
 fetchFundAccount(id:string):Promise<PayoutFundAccount>;
 fetchValidation(id:string):Promise<PayoutValidation>;
 fetchPayout(id:string):Promise<PayoutProviderRecord>;
}
/** RazorpayX ONLY, read-only GET methods; no payout/validation POST capability. */
export class RazorpayXPayoutEvidence implements PayoutEvidenceGateway {
 constructor(private readonly keyId:string,private readonly secret:string){
  if(!/^rzp_(?:test|live)_[A-Za-z0-9]+$/.test(keyId)||!secret)
   throw new Error('V21_RAZORPAYX_CONFIG_INVALID');
 }
 private async get(endpoint:string):Promise<Record<string,unknown>>{
  let response:globalThis.Response;
  try{
   response=await fetch('https://api.razorpay.com/v1/'+endpoint,{
    method:'GET',headers:{Authorization:'Basic '+
     Buffer.from(this.keyId+':'+this.secret).toString('base64')},
    signal:AbortSignal.timeout(7000)
   });
  }catch{
   throw new ApiError(503,'PAYOUT_EVIDENCE_UNAVAILABLE','Independent provider verification unavailable.');
  }
  if(!response.ok)throw new ApiError(503,'PAYOUT_EVIDENCE_UNAVAILABLE','Provider verification failed.');
  let body:unknown;
  try{body=await response.json();}catch{
   throw new ApiError(503,'PAYOUT_EVIDENCE_INVALID','Provider returned invalid evidence.');
  }
  if(!body||typeof body!=='object'||Array.isArray(body))
   throw new ApiError(503,'PAYOUT_EVIDENCE_INVALID','Provider data invalid.');
  return body as Record<string,unknown>;
 }
 async fetchFundAccount(id:string):Promise<PayoutFundAccount>{
  if(!/^fa_[A-Za-z0-9]{8,60}$/.test(id))
   throw new ApiError(400,'PAYOUT_BENEFICIARY_ID_INVALID','Invalid fund-account ID.');
  const r=await this.get('fund_accounts/'+encodeURIComponent(id));
  const bank=r.bank_account;
  if(r.id!==id||r.active!==true||r.account_type!=='bank_account'||
   !bank||typeof bank!=='object'||Array.isArray(bank))
   throw new ApiError(409,'PAYOUT_BENEFICIARY_UNVERIFIED','Provider account is inactive or not bank type.');
  const b=bank as Record<string,unknown>;
  if(typeof b.account_number!=='string'||!/^[0-9]{5,35}$/.test(b.account_number)||
   typeof b.ifsc!=='string'||!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(b.ifsc)||
   typeof b.name!=='string'||b.name.trim().length<3||b.name.length>160)
   throw new ApiError(409,'PAYOUT_BENEFICIARY_UNVERIFIED','Provider bank identity is invalid.');
  // Never return, persist, log, or audit the full bank account number.
  return {id,active:true,accountType:'bank_account',
   holder:b.name.trim(),ifsc:b.ifsc,last4:b.account_number.slice(-4)};
 }
 async fetchValidation(id:string):Promise<PayoutValidation>{
  if(!/^fav_[A-Za-z0-9]{8,60}$/.test(id))
   throw new ApiError(400,'PAYOUT_VALIDATION_ID_INVALID','Invalid validation ID.');
  const r=await this.get('fund_accounts/validations/'+encodeURIComponent(id));
  const a=r.fund_account;
  const x=r.validation_results??r.results;
  if(r.id!==id||r.status!=='completed'||!a||typeof a!=='object'||
   Array.isArray(a)||!x||typeof x!=='object'||Array.isArray(x))
   throw new ApiError(409,'PAYOUT_VALIDATION_UNCONFIRMED','Bank-account validation is incomplete.');
  const acct=a as Record<string,unknown>,results=x as Record<string,unknown>;
  if(typeof acct.id!=='string'||!/^fa_[A-Za-z0-9]{8,60}$/.test(acct.id)||
   !['active','valid'].includes(String(results.account_status))||
   typeof results.registered_name!=='string'||results.registered_name.trim().length<3)
   throw new ApiError(409,'PAYOUT_VALIDATION_UNCONFIRMED','Beneficiary bank validation did not confirm validity.');
  return {id,fundAccountId:acct.id,status:'completed',
   registeredName:results.registered_name.trim(),
   accountStatus:results.account_status as 'active'|'valid'};
 }
 async fetchPayout(id:string):Promise<PayoutProviderRecord>{
  if(!/^pout_[A-Za-z0-9]{8,60}$/.test(id))
   throw new ApiError(400,'PAYOUT_PROVIDER_ID_INVALID','Invalid provider payout ID.');
  const r=await this.get('payouts/'+encodeURIComponent(id));
  if(r.id!==id||r.entity!=='payout'||
   typeof r.fund_account_id!=='string'||
   !/^fa_[A-Za-z0-9]{8,60}$/.test(r.fund_account_id)||
   typeof r.amount!=='number'||!Number.isSafeInteger(r.amount)||r.amount<=0||
   r.currency!=='INR'||r.purpose!=='payout'||
   typeof r.reference_id!=='string'||!/^BT[A-F0-9]{32}$/.test(r.reference_id)||
   !['queued','pending','processing','processed','reversed','failed',
    'rejected','cancelled'].includes(String(r.status))||
   !(r.utr===null||r.utr===undefined||typeof r.utr==='string'))
   throw new ApiError(409,'PAYOUT_PROVIDER_EVIDENCE_MISMATCH','Provider payout identity or status is invalid.');
  return {id,fundAccountId:r.fund_account_id,amount:BigInt(r.amount),
   currency:'INR',purpose:'payout',referenceId:r.reference_id,
   status:r.status as string,utr:typeof r.utr==='string'?r.utr:null};
 }
}
