export type PublicRelease={
  apiVersion:'v2';
  releaseStage:string;
  productionReady:false;
  automaticRefundExecution:false;
  automaticPayoutExecution:false;
};

export function validateApiOrigin(baseUrl:string):string {
  let url:URL;
  try {url=new URL(baseUrl);} catch {throw new Error('Invalid API origin');}
  const local=url.hostname==='localhost'||url.hostname==='127.0.0.1';
  if((url.protocol!=='https:' && !(local&&url.protocol==='http:'))
    || url.username || url.password || url.search || url.hash
    || url.pathname!=='/' || !url.hostname)throw new Error('API origin must be exact HTTPS or local development origin');
  return url.origin;
}

/** Public metadata only; no Clerk session, credentials or admin data is sent. */
export async function fetchPublicRelease(baseUrl:string,signal?:AbortSignal):Promise<PublicRelease> {
  const origin=validateApiOrigin(baseUrl);
  const response=await fetch(origin+'/api/v2/system',{
    method:'GET',credentials:'omit',headers:{Accept:'application/json'},signal,
  });
  if(!response.ok)throw new Error('API is not responding');
  const raw:unknown=await response.json();
  if(!raw||typeof raw!=='object'||Array.isArray(raw))throw new Error('Unexpected API response');
  const data=(raw as {data?:unknown}).data;
  if(!data||typeof data!=='object'||Array.isArray(data))throw new Error('Unexpected API contract');
  const d=data as Record<string,unknown>;
  if(d.apiVersion!=='v2'||typeof d.releaseStage!=='string'
    || d.productionReady!==false
    || d.automaticRefundExecution!==false
    || d.automaticPayoutExecution!==false)
    throw new Error('API failed staging safety contract');
  return {
    apiVersion:'v2',releaseStage:d.releaseStage,productionReady:false,
    automaticRefundExecution:false,automaticPayoutExecution:false,
  };
}
