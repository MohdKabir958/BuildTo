// @vitest-environment jsdom
import {afterEach,describe,expect,it,vi} from 'vitest';
import {V21ApiClient,V21ApiError} from './apiClient';
import {formatPaise,formatDecimalQuantity,withExpectedVersion} from './precision';

const ORIGIN='https://buildto-v21-staging.onrender.com';
const reply=(data:unknown,status=200,requestId='req-001')=>new Response(JSON.stringify(data),{
 status,headers:{'Content-Type':'application/json'},
});
afterEach(()=>{vi.unstubAllGlobals();vi.restoreAllMocks();localStorage.clear();});

describe('A03 typed admin API client',()=>{
 it('uses Bearer token exclusively from Clerk callback, returns requestId and preserves DTO',async()=>{
   const getToken=vi.fn(async()=> 'clerk-session-123');
   const fetch=vi.fn(async(_url:string,_opts?:RequestInit)=>reply({data:{value:'42'},requestId:'req-verified'}));
   vi.stubGlobal('fetch',fetch);
   const api=new V21ApiClient(ORIGIN,getToken);
   const result=await api.get<{value:string}>('/api/v2/admin/access');
   expect(result).toEqual({data:{value:'42'},requestId:'req-verified'});
   expect(getToken).toHaveBeenCalledTimes(1);
   expect(fetch).toHaveBeenCalledWith(ORIGIN+'/api/v2/admin/access',expect.objectContaining({
     method:'GET',credentials:'omit',cache:'no-store',headers:expect.objectContaining({Authorization:'Bearer clerk-session-123'}),
   }));
   expect(localStorage.length).toBe(0);
 });
 it('rejects external paths before requesting or reading tokens',async()=>{
   const getToken=vi.fn(async()=> 'secret');
   const api=new V21ApiClient(ORIGIN,getToken);
   await expect(api.get('https://evil.example/steal')).rejects.toMatchObject({code:'INVALID_API_PATH'});
   await expect(api.get('//evil.example/steal')).rejects.toMatchObject({code:'INVALID_API_PATH'});
   await expect(api.get('/api/v1/admin/team')).rejects.toMatchObject({code:'INVALID_API_PATH'});
   expect(getToken).not.toHaveBeenCalled();
 });
 it('fails closed on missing sessions before any outgoing request',async()=>{
   const fetch=vi.fn();vi.stubGlobal('fetch',fetch);
   const api=new V21ApiClient(ORIGIN,async()=>null);
   await expect(api.get('/api/v2/admin/access')).rejects.toMatchObject({status:401,code:'INVALID_SESSION'});
   expect(fetch).not.toHaveBeenCalled();
 });
 it.each([401,403,404,409,422,429])('exposes stable backend error status %i without automatic retries',async status=>{
   const fetch=vi.fn(async()=>reply({error:{code:'PERMISSION_DENIED',message:'Not permitted'},requestId:'req-audit'},status));
   vi.stubGlobal('fetch',fetch);
   const api=new V21ApiClient(ORIGIN,async()=> 'token');
   await expect(api.write('POST','/api/v2/admin/finance/settlements/drafts',{supplierId:'x'}, {idempotencyKey:'request123456789'}))
     .rejects.toMatchObject({status,code:'PERMISSION_DENIED',message:'Not permitted',requestId:'req-audit'});
   expect(fetch).toHaveBeenCalledTimes(1);
 });
 it('sends stable idempotency and exact version body on one mutation',async()=>{
   const fetch=vi.fn(async(_url:string,_opts?:RequestInit)=>reply({data:{updated:true},requestId:'req-ok'}));
   vi.stubGlobal('fetch',fetch);
   const api=new V21ApiClient(ORIGIN,async()=> 'token');
   const body=withExpectedVersion({status:'APPROVED'},7);
   await api.write('POST','/api/v2/admin/catalog/listings/123/review',body,{idempotencyKey:'unique-intent-001'});
   expect(fetch.mock.calls[0][1]).toMatchObject({
     method:'POST',headers:expect.objectContaining({'Idempotency-Key':'unique-intent-001','Content-Type':'application/json'}),
     body:JSON.stringify({status:'APPROVED',expectedVersion:7}),
   });
 });
 it('rejects wrong-keyed writes and GET bodies instead of sending them',async()=>{
   const fetch=vi.fn();vi.stubGlobal('fetch',fetch);
   const api=new V21ApiClient(ORIGIN,async()=> 'token');
   await expect(api.request('/api/v2/admin/access',{method:'GET',body:{x:1}})).rejects.toMatchObject({code:'INVALID_BODY'});
   await expect(api.write('POST','/api/v2/admin/promotions',{}, {idempotencyKey:'bad'})).rejects.toMatchObject({code:'INVALID_IDEMPOTENCY_KEY'});
   expect(fetch).not.toHaveBeenCalled();
 });
 it('reports a network error without leaking bearer token in message',async()=>{
   vi.stubGlobal('fetch',vi.fn(async()=>{throw new TypeError('failed');}));
   const api=new V21ApiClient(ORIGIN,async()=> 'very-secret-clerk-token');
   await expect(api.get('/api/v2/admin/access')).rejects.toMatchObject({code:'NETWORK'});
 });
});

describe('A03 exact financial presentation',()=>{
 it('formats large and negative paise precisely',()=>{
   expect(formatPaise('12345678')).toBe('₹1,23,456.78');
   expect(formatPaise('-5')).toBe('-₹0.05');
   expect(formatPaise('0')).toBe('₹0.00');
   expect(formatPaise('9223372036854775807')).toMatch(/^₹/);
 });
 it('preserves decimal quantities rather than converting to floats',()=>{
   expect(formatDecimalQuantity('0.125','tonne')).toBe('0.125 tonne');
   expect(formatDecimalQuantity('1.000')).toBe('1.000');
   expect(()=>formatDecimalQuantity('1e3')).toThrow();
   expect(()=>formatPaise('10.2')).toThrow();
   expect(()=>withExpectedVersion({},-1)).toThrow();
 });
});
