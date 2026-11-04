import {validateApiOrigin} from '../publicRelease';

export type Method='GET'|'POST'|'PUT'|'PATCH'|'DELETE';
export interface V21Response<T>{data:T;requestId:string}
export type TokenGetter=()=>Promise<string|null>;
export type RequestOptions={
 method?:Method;
 body?:unknown;
 idempotencyKey?:string;
 signal?:AbortSignal;
 timeoutMs?:number;
};

export class V21ApiError extends Error {
 constructor(readonly status:number,readonly code:string,message:string,readonly requestId:string='') {
   super(message);this.name='V21ApiError';
 }
}
const isObject=(value:unknown):value is Record<string,unknown>=>
 typeof value==='object'&&value!==null&&!Array.isArray(value);

export class V21ApiClient {
 private readonly origin:string;
 constructor(baseUrl:string,private readonly getToken:TokenGetter){
   this.origin=validateApiOrigin(baseUrl);
 }
 async request<T>(path:string,{method='GET',body,idempotencyKey,signal,timeoutMs=15000}:RequestOptions={}):Promise<V21Response<T>>{
   // Only exact V2.1 API paths; never permit user-controlled cross-origin tokens.
   if(!path.startsWith('/api/v2/')||path.startsWith('//')||path.includes('#'))
     throw new V21ApiError(0,'INVALID_API_PATH','Only BuildTo V2.1 API paths are allowed');
   const url=new URL(path,this.origin);
   if(url.origin!==this.origin)throw new V21ApiError(0,'INVALID_API_PATH','Cross-origin requests are not allowed');
   if(!['GET','POST','PUT','PATCH','DELETE'].includes(method))
     throw new V21ApiError(0,'INVALID_METHOD','Unsupported API method');
   if(method==='GET'&&body!==undefined)
     throw new V21ApiError(0,'INVALID_BODY','GET cannot send a request body');
   if(idempotencyKey!==undefined){
     if(method==='GET'||!/^[-_A-Za-z0-9]{8,128}$/.test(idempotencyKey))
       throw new V21ApiError(0,'INVALID_IDEMPOTENCY_KEY','Invalid write idempotency key');
   }
   if(!Number.isFinite(timeoutMs)||timeoutMs<1000||timeoutMs>30000)
     throw new V21ApiError(0,'INVALID_TIMEOUT','Invalid API timeout');
   let token:string|null;
   try{token=await this.getToken();}catch{throw new V21ApiError(401,'SESSION_UNAVAILABLE','Clerk session could not be read');}
   if(typeof token!=='string'||token.length===0||token.length>8192||/\s/.test(token))
     throw new V21ApiError(401,'INVALID_SESSION','Sign in with Clerk to continue');
   const controller=new AbortController();
   let timedOut=false;
   const abort=()=>controller.abort();
   if(signal?.aborted)controller.abort();
   else signal?.addEventListener('abort',abort,{once:true});
   const timer=window.setTimeout(()=>{timedOut=true;controller.abort();},timeoutMs);
   try{
     const headers:Record<string,string>={Authorization:'Bearer '+token,Accept:'application/json'};
     if(body!==undefined)headers['Content-Type']='application/json';
     if(idempotencyKey)headers['Idempotency-Key']=idempotencyKey;
     let response:Response;
     try{
       response=await fetch(url.toString(),{
         method,headers,body:body===undefined?undefined:JSON.stringify(body),
         credentials:'omit',cache:'no-store',signal:controller.signal,
       });
     }catch{
       if(timedOut)throw new V21ApiError(0,'TIMEOUT','The API request timed out');
       if(signal?.aborted)throw new V21ApiError(0,'ABORTED','The request was cancelled');
       throw new V21ApiError(0,'NETWORK','Cannot reach the BuildTo API');
     }
     let raw:unknown;
     try{raw=await response.json();}catch{
       throw new V21ApiError(response.status,'INVALID_RESPONSE','The API returned an invalid response');
     }
     if(!isObject(raw))throw new V21ApiError(response.status,'INVALID_RESPONSE','The API returned an invalid response');
     const requestId=typeof raw.requestId==='string'&&raw.requestId.length<=140?raw.requestId:'';
     if(!response.ok){
       const error=isObject(raw.error)?raw.error:{};
       const code=typeof error.code==='string'&&/^[A-Z][A-Z0-9_]{0,70}$/.test(error.code)?error.code:'REQUEST_FAILED';
       const message=typeof error.message==='string'?error.message.slice(0,200):'Request could not be completed';
       throw new V21ApiError(response.status,code,message,requestId);
     }
     if(!Object.prototype.hasOwnProperty.call(raw,'data'))
       throw new V21ApiError(response.status,'INVALID_RESPONSE','Missing API data',requestId);
     return {data:raw.data as T,requestId};
   }finally{
     window.clearTimeout(timer);
     signal?.removeEventListener('abort',abort);
   }
 }
 get<T>(path:string,signal?:AbortSignal):Promise<V21Response<T>>{
   return this.request<T>(path,{method:'GET',signal});
 }
 write<T>(method:Exclude<Method,'GET'>,path:string,body?:unknown,options:Omit<RequestOptions,'body'|'method'>={}):Promise<V21Response<T>>{
   return this.request<T>(path,{...options,method,body});
 }
}
