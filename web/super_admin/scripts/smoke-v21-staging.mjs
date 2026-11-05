#!/usr/bin/env node
// A15 operator-invoked, read-only staging smoke. No tokens, writes or migrations.
const origin=process.env.BUILDTO_V21_STAGING_API_ORIGIN||'https://buildto-v21-staging.onrender.com';
if(origin!=='https://buildto-v21-staging.onrender.com')throw new Error('Unapproved staging origin');
async function get(path){
 const response=await fetch(origin+path,{method:'GET',headers:{Accept:'application/json'},
   cache:'no-store',signal:AbortSignal.timeout(30000)});
 let json;try{json=await response.json();}catch{throw new Error(path+' did not return JSON');}
 return{status:response.status,json};
}
const health=await get('/health');
if(health.status!==200||health.json.status!=='ok')throw new Error('Health probe failed');
const ready=await get('/ready');
if(ready.status!==200||ready.json.ready!==true)throw new Error('Migration/database readiness failed');
const system=await get('/api/v2/system');
const data=system.json.data;
if(system.status!==200||data?.apiVersion!=='v2'||data.productionReady!==false||
  data.automaticRefundExecution!==false||data.automaticPayoutExecution!==false)
 throw new Error('Unsafe or incomplete V2.1 release flags');
const denied=await get('/api/v2/admin/access');
if(denied.status!==401)throw new Error('Unauthenticated admin access was not denied');
console.log('PASS: staging health/ready, v2 release restrictions and 401 admin access.');
console.log('This does not validate authenticated A04–A14 routes or frontend CORS/Clerk callback.');
