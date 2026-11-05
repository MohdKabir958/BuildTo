// @vitest-environment jsdom
import {afterEach,describe,expect,it,vi} from 'vitest';
import {AdminAccessError,fetchAdminSession} from './adminSession';
import {canViewSection} from './roles';

const userId='d993d319-47a2-4905-b99c-86b2e42b11e5';
const response=(data:unknown,status=200)=>new Response(JSON.stringify({data}),{status,headers:{'Content-Type':'application/json'}});
afterEach(()=>{vi.unstubAllGlobals();vi.restoreAllMocks();localStorage.clear();});
describe('A02: Clerk token and server-authoritative role gate',()=>{
  it('checks me and admin access using an in-memory bearer token, never persistent storage',async()=>{
    const fetch=vi.fn(async (url:string,_init?:RequestInit)=>url.endsWith('/me')
      ?response({id:userId,displayName:'BuildTo Operator',adminRole:'CATALOG',suppliers:[]})
      :response({role:'CATALOG'}));
    vi.stubGlobal('fetch',fetch);
    const session=await fetchAdminSession('https://buildto-v21-staging.onrender.com','valid-session-token');
    expect(session).toEqual({id:userId,displayName:'BuildTo Operator',role:'CATALOG'});
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls.map(x=>x[0])).toEqual([
      'https://buildto-v21-staging.onrender.com/api/v2/me',
      'https://buildto-v21-staging.onrender.com/api/v2/admin/access',
    ]);
    for(const call of fetch.mock.calls){
      expect(call[1]).toMatchObject({credentials:'omit',cache:'no-store',headers:{
        Authorization:'Bearer valid-session-token',Accept:'application/json',
      }});
    }
    expect(localStorage.length).toBe(0);
  });
  it('rejects unprovisioned Clerk accounts without granting roles',async()=>{
    const fetch=vi.fn(async(url:string)=>url.endsWith('/me')
      ?response({id:userId,displayName:'Applicant',adminRole:null})
      :response({role:'OWNER'}));
    vi.stubGlobal('fetch',fetch);
    await expect(fetchAdminSession('https://buildto.example','token')).rejects.toMatchObject({status:403});
    expect(fetch).toHaveBeenCalledTimes(1);
  });
  it('rejects a revoked administrator even if /me has a stale role',async()=>{
    vi.stubGlobal('fetch',vi.fn(async(url:string)=>url.endsWith('/me')
      ?response({id:userId,displayName:'Applicant',adminRole:'OWNER'})
      :response({error:{code:'ADMIN_NOT_PROVISIONED'}},403)));
    await expect(fetchAdminSession('https://buildto.example','token')).rejects.toMatchObject({status:403});
  });
  it('fails closed on inconsistent admin roles and missing tokens',async()=>{
    const fetch=vi.fn(async(url:string)=>url.endsWith('/me')
      ?response({id:userId,displayName:'Applicant',adminRole:'FINANCE'})
      :response({role:'OWNER'}));
    vi.stubGlobal('fetch',fetch);
    await expect(fetchAdminSession('https://buildto.example','token')).rejects.toBeInstanceOf(AdminAccessError);
    await expect(fetchAdminSession('https://buildto.example','')).rejects.toMatchObject({status:401});
    expect(fetch).toHaveBeenCalledTimes(2);
  });
  it('shows only entitled placeholder modules, including strict AUDITOR read-only role',()=>{
    expect(canViewSection('CATALOG','catalog')).toBe(true);
    expect(canViewSection('CATALOG','finance')).toBe(false);
    expect(canViewSection('AUDITOR','audit')).toBe(true);
    expect(canViewSection('AUDITOR','team')).toBe(false);
    expect(canViewSection('SUPPORT','finance')).toBe(false);
    expect(canViewSection('OWNER','team')).toBe(true);
  });
});
