import {validateApiOrigin} from '../publicRelease';

export const ADMIN_ROLES=['OWNER','OPERATIONS','CATALOG','FINANCE','SUPPORT','AUDITOR'] as const;
export type AdminRole=typeof ADMIN_ROLES[number];
export type VerifiedAdminSession={id:string;displayName:string;role:AdminRole};

export class AdminAccessError extends Error {
  constructor(readonly status:number,message:string){super(message);this.name='AdminAccessError';}
}
const isRole=(value:unknown):value is AdminRole=>ADMIN_ROLES.some(x=>x===value);
const isRecord=(value:unknown):value is Record<string,unknown>=>Boolean(value)&&typeof value==='object'&&!Array.isArray(value);
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Authenticated, read-only server session checks. Never caches or persists tokens. */
export async function fetchAdminSession(baseUrl:string,token:string,signal?:AbortSignal):Promise<VerifiedAdminSession> {
  if(typeof token!=='string'||!token||token.length>8192||/\s/.test(token))
    throw new AdminAccessError(401,'A valid Clerk session is required');
  const origin=validateApiOrigin(baseUrl);
  async function get(path:'/api/v2/me'|'/api/v2/admin/access'):Promise<Record<string,unknown>> {
    let response:Response;
    try {
      response=await fetch(origin+path,{
        method:'GET',credentials:'omit',cache:'no-store',signal,
        headers:{Authorization:'Bearer '+token,Accept:'application/json'},
      });
    }catch{
      if(signal?.aborted)throw new AdminAccessError(503,'Authorization check interrupted');
      throw new AdminAccessError(503,'Cannot reach the Splyzo staging API');
    }
    if(response.status===401)throw new AdminAccessError(401,'Your Clerk session was rejected');
    if(response.status===403)throw new AdminAccessError(403,'Administrator access has not been granted');
    if(!response.ok)throw new AdminAccessError(response.status,'Administrator verification is temporarily unavailable');
    let raw:unknown;
    try{raw=await response.json();}catch{throw new AdminAccessError(502,'Unexpected administrator API response');}
    if(!isRecord(raw)||!isRecord(raw.data))throw new AdminAccessError(502,'Unexpected administrator API response');
    return raw.data;
  }
  const me=await get('/api/v2/me');
  if(typeof me.id!=='string'||!uuid.test(me.id)||typeof me.displayName!=='string'||!me.displayName.trim()
    ||!isRole(me.adminRole))throw new AdminAccessError(403,'Administrator role is not active');
  const access=await get('/api/v2/admin/access');
  if(!isRole(access.role)||access.role!==me.adminRole)
    throw new AdminAccessError(403,'Administrator role verification failed');
  return {id:me.id,displayName:me.displayName.trim(),role:access.role};
}
