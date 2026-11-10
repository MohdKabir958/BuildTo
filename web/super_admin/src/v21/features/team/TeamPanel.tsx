import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {ShieldCheck,UsersRound} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';
import type {AdminRole} from '../../auth/adminSession';
import {ADMIN_ROLES} from '../../auth/adminSession';

type TeamMember={
 userId:string;displayName:string;email:string|null;role:AdminRole;active:boolean;
 createdAt:string;revokedAt:string|null;
};
type TeamPage={items:TeamMember[];nextCursor:string|null};
type Action={kind:'role'|'revoke';member:TeamMember;role:AdminRole;reason:string};
const errorText=(e:unknown)=>e instanceof V21ApiError
 ?e.status===409?'The change conflicted with another administrator or the last-owner safeguard. Reload the team and retry.':
  e.status===403?'Only an active OWNER can manage administrator access.':
  e.status===404?'That verified user or admin membership was not found.':
  e.message:'The request failed. Check your connection and retry.';

export function TeamPanel({currentAdminId}:{currentAdminId:string}){
 const api=useV21Api();
 const [items,setItems]=useState<TeamMember[]>([]);
 const [cursor,setCursor]=useState<string|null>(null);
 const [loading,setLoading]=useState(true);
 const [saving,setSaving]=useState(false);
 const [error,setError]=useState('');
 const [success,setSuccess]=useState('');
 const [email,setEmail]=useState('');
 const [role,setRole]=useState<AdminRole>('CATALOG');
 const [reason,setReason]=useState('');
 const [action,setAction]=useState<Action|null>(null);

 const load=useCallback(async(reset:boolean,next?:string,signal?:AbortSignal)=>{
   setLoading(true);setError('');
   try {
     const query='/api/v2/admin/team?limit=25'+(next?'&cursor='+encodeURIComponent(next):'');
     const response=await api.get<TeamPage>(query,signal);
     if(!Array.isArray(response.data.items)||!(
       typeof response.data.nextCursor==='string'||response.data.nextCursor===null))
       throw new Error('Invalid admin team response');
     setItems(existing=>reset?response.data.items:[...existing,...response.data.items]);
     setCursor(response.data.nextCursor);
   }catch(e){
     if(!signal?.aborted)setError(errorText(e));
   }finally{if(!signal?.aborted)setLoading(false);}
 },[api]);

 useEffect(()=>{
   const controller=new AbortController();
   void load(true,undefined,controller.signal);
   return ()=>controller.abort();
 },[load]);

 async function grant(event:FormEvent<HTMLFormElement>){
   event.preventDefault();setSaving(true);setError('');setSuccess('');
   try{
     await api.write<TeamMember>('POST','/api/v2/admin/team',{email:email.trim(),role,reason:reason.trim()});
     setEmail('');setReason('');setRole('CATALOG');
     await load(true);
     setSuccess('Access granted to the existing verified Clerk account.');
   }catch(e){setError(errorText(e));}
   finally{setSaving(false);}
 }
 async function completeAction(event:FormEvent<HTMLFormElement>){
   event.preventDefault();
   if(!action)return;
   setSaving(true);setError('');setSuccess('');
   try{
     if(action.kind==='role')
       await api.write('PATCH','/api/v2/admin/team/'+encodeURIComponent(action.member.userId),
         {role:action.role,reason:action.reason.trim()});
     else
       await api.write('POST','/api/v2/admin/team/'+encodeURIComponent(action.member.userId)+'/revoke',
         {reason:action.reason.trim()});
     setAction(null);await load(true);
     setSuccess('Administrator access updated. The change has been audited.');
   }catch(e){setError(errorText(e));}
   finally{setSaving(false);}
 }

 return <div className="space-y-6">
   <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
     <div className="flex items-center gap-3"><UsersRound size={22} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Administrator team</h2><p className="mt-1 text-sm text-slate-500">Only verified Clerk accounts can be granted access. All changes are audited.</p></div></div>
     <div className="mt-5 overflow-x-auto">
       <table className="w-full min-w-[620px] text-left text-sm">
         <thead><tr className="border-b border-slate-200 text-xs uppercase tracking-wide text-slate-500"><th scope="col" className="pb-3">Administrator</th><th scope="col" className="pb-3">Role</th><th scope="col" className="pb-3">Status</th><th scope="col" className="pb-3 text-right">Actions</th></tr></thead>
         <tbody>
           {items.map(member=><tr className="border-b border-slate-100" key={member.userId}>
             <td className="py-4 pr-4"><span className="font-bold">{member.displayName}</span><span className="mt-1 block text-xs text-slate-500">{member.email||'No verified email'}</span>{member.userId===currentAdminId&&<span className="mt-1 block text-xs text-[#174C86]">You</span>}</td>
             <td className="py-4 pr-4"><span className="rounded-lg bg-slate-100 px-2.5 py-1 text-xs font-semibold">{member.role}</span></td>
             <td className="py-4 pr-4"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${member.active?'bg-emerald-50 text-emerald-700':'bg-slate-100 text-slate-500'}`}>{member.active?'Active':'Revoked'}</span></td>
             <td className="py-4 text-right">
               {member.active&&member.userId!==currentAdminId&&<div className="flex justify-end gap-2"><button type="button" onClick={()=>setAction({kind:'role',member,role:member.role,reason:''})} className="rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold hover:bg-slate-50" aria-label={'Change role for '+member.displayName}>Change role</button><button type="button" onClick={()=>setAction({kind:'revoke',member,role:member.role,reason:''})} className="rounded-lg border border-rose-200 px-3 py-2 text-xs font-semibold text-rose-700 hover:bg-rose-50" aria-label={'Revoke '+member.displayName}>Revoke</button></div>}
             </td>
           </tr>)}
         </tbody>
       </table>
       {!loading&&items.length===0&&<p className="py-10 text-center text-sm text-slate-500">No administrator membership records were returned.</p>}
       {loading&&<p role="status" className="py-5 text-sm text-slate-500">Loading team records…</p>}
     </div>
     {cursor&&<button type="button" disabled={loading} onClick={()=>void load(false,cursor)} className="mt-4 rounded-lg border border-slate-200 px-4 py-2 text-sm font-semibold disabled:opacity-50">Load more</button>}
   </section>

   {action&&<section aria-label="Confirm administrator change" className="rounded-2xl border border-amber-200 bg-amber-50 p-6">
     <h3 className="font-extrabold">{action.kind==='revoke'?'Revoke administrator access':'Change administrator role'}</h3>
     <p className="mt-2 text-sm text-slate-700">{action.member.displayName} ({action.member.email||'No email'}). {action.kind==='revoke'?'Access will end on the next authenticated request.':'Role changes take effect on the next authenticated request.'}</p>
     <form className="mt-4 max-w-xl space-y-4" onSubmit={e=>{void completeAction(e);}}>
       {action.kind==='role'&&<label className="block text-sm font-semibold">New role<select className="mt-2 block w-full rounded-lg border border-slate-300 bg-white p-3" value={action.role} onChange={e=>setAction({...action,role:e.target.value as AdminRole})}>{ADMIN_ROLES.map(value=><option key={value} value={value}>{value}</option>)}</select></label>}
       <label className="block text-sm font-semibold">Audit reason<textarea required minLength={8} maxLength={400} className="mt-2 block w-full rounded-lg border border-slate-300 p-3" value={action.reason} onChange={e=>setAction({...action,reason:e.target.value})}/></label>
       <div className="flex flex-wrap gap-3"><button disabled={saving||action.reason.trim().length<8} type="submit" className="rounded-xl bg-[#102B4D] px-5 py-3 text-sm font-bold text-white disabled:opacity-50">{saving?'Saving…':'Confirm change'}</button><button type="button" onClick={()=>setAction(null)} className="rounded-xl border border-slate-300 px-5 py-3 text-sm font-semibold">Cancel</button></div>
     </form>
   </section>}

   <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
     <div className="flex items-center gap-3"><ShieldCheck size={22} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Grant administrator access</h2><p className="mt-1 text-sm text-slate-500">The person must have a verified primary email in the current Clerk instance and an active Splyzo user profile.</p></div></div>
     <form onSubmit={e=>{void grant(e);}} className="mt-5 grid gap-4 md:grid-cols-2">
       <label className="text-sm font-semibold">Verified Clerk email<input type="email" required maxLength={320} value={email} onChange={e=>setEmail(e.target.value)} placeholder="operator@example.com" className="mt-2 block w-full rounded-lg border border-slate-300 p-3"/></label>
       <label className="text-sm font-semibold">Admin role<select value={role} onChange={e=>setRole(e.target.value as AdminRole)} className="mt-2 block w-full rounded-lg border border-slate-300 bg-white p-3">{ADMIN_ROLES.map(value=><option key={value} value={value}>{value}</option>)}</select></label>
       <label className="text-sm font-semibold md:col-span-2">Reason for grant<textarea value={reason} onChange={e=>setReason(e.target.value)} required minLength={8} maxLength={400} className="mt-2 block min-h-20 w-full rounded-lg border border-slate-300 p-3" placeholder="Why this person requires access"/></label>
       <button type="submit" disabled={saving||!email||reason.trim().length<8} className="w-fit rounded-xl bg-[#102B4D] px-5 py-3 text-sm font-bold text-white disabled:opacity-50">{saving?'Saving…':'Grant access'}</button>
     </form>
   </section>
   {error&&<p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">{error}</p>}
   {success&&<p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">{success}</p>}
 </div>;
}
