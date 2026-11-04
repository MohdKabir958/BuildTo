import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Headphones,RefreshCw,ShieldAlert} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';
type Case={id:string;publicNumber:string;orderId:string|null;subject:string;priority:string;status:string;createdAt:string;resolvedAt:string|null};
type Message={id:string;authorId:string;body:string;internal:boolean;createdAt:string};
type CaseDetail=Case&{messages:Message[]};
type Return={id:string;supplierOrderId:string;reason:string;status:string;financialStatus:string;resolutionNote:string|null;items:{orderItemId:string;quantity:string}[];createdAt:string};
type Review={id:string;supplierId:string;supplierOrderId:string;rating:number;comment:string|null;status:string;createdAt:string};
type Tab='cases'|'returns'|'reviews';
type Pending={kind:Tab;id:string;decision:string;note:string};
const asDate=(s:string)=>new Date(s).toLocaleString();
const show=(e:unknown)=>e instanceof V21ApiError?
 e.status===403?'Support management permission is required.':e.status===409?'The item changed or cannot transition from its current state. Reload the queue.':e.message:
 'Support data is unavailable. Check the connection.';
export function SupportAdminPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<Tab>('cases');
 const [cases,setCases]=useState<Case[]>([]);
 const [returns,setReturns]=useState<Return[]>([]);
 const [reviews,setReviews]=useState<Review[]>([]);
 const [detailId,setDetailId]=useState('');
 const [detail,setDetail]=useState<CaseDetail|null>(null);
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [pending,setPending]=useState<Pending|null>(null);
 const [responseText,setResponseText]=useState('');
 const [internal,setInternal]=useState(false);
 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [a,b,c]=await Promise.all([
    api.get<Case[]>('/api/v2/admin/support/cases',signal),
    api.get<Return[]>('/api/v2/admin/returns',signal),
    api.get<Review[]>('/api/v2/admin/reviews',signal)
   ]);
   if(!Array.isArray(a.data)||!Array.isArray(b.data)||!Array.isArray(c.data))throw new Error('Invalid admin queues');
   if(!signal?.aborted){setCases(a.data);setReturns(b.data);setReviews(c.data);}
  }catch(e){if(!signal?.aborted)setError(show(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 const loadDetail=useCallback(async(id:string,signal?:AbortSignal)=>{
  try{
   const response=await api.get<CaseDetail>('/api/v2/admin/support/cases/'+encodeURIComponent(id),signal);
   if(!Array.isArray(response.data.messages))throw new Error('Invalid support detail');
   if(!signal?.aborted)setDetail(response.data);
  }catch(e){if(!signal?.aborted){setDetail(null);setError(show(e));}}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);
 useEffect(()=>{
  if(!detailId)return;
  const c=new AbortController();setDetail(null);void loadDetail(detailId,c.signal);
  return ()=>c.abort();
 },[detailId,loadDetail]);
 async function save(fn:()=>Promise<unknown>,success:string){
  if(busy)return;
  setBusy(true);setError('');setNotice('');
  try{
   await fn();setPending(null);setResponseText('');await load();
   if(detailId)await loadDetail(detailId);
   setNotice(success);
  }catch(e){setError(show(e));}
  finally{setBusy(false);}
 }
 function confirm(e:FormEvent<HTMLFormElement>){
  e.preventDefault();if(!pending)return;
  const p=pending;
  if(p.kind==='cases')void save(
   ()=>api.write('PATCH','/api/v2/admin/support/cases/'+encodeURIComponent(p.id),
    {status:p.decision,...(p.note.trim()?{note:p.note.trim()}:{})}),
   'Support case status updated. Resolution notes are public to the customer.');
  if(p.kind==='returns')void save(
   ()=>api.write('POST','/api/v2/admin/returns/'+encodeURIComponent(p.id)+'/review',
    {decision:p.decision,note:p.note.trim()}),
   'Return claim reviewed. This does not initiate a refund, credit note or restock.');
  if(p.kind==='reviews')void save(
   ()=>api.write('POST','/api/v2/admin/reviews/'+encodeURIComponent(p.id)+'/moderate',{decision:p.decision}),
   'Supplier review moderation completed.');
 }
 function sendMessage(e:FormEvent<HTMLFormElement>){
  e.preventDefault();if(!detailId||responseText.trim().length<2)return;
  void save(()=>api.write('POST','/api/v2/admin/support/cases/'+encodeURIComponent(detailId)+'/messages',
   {message:responseText.trim(),internal}),internal?'Private internal note saved.':'Customer-visible response saved.');
 }
 return <div className="space-y-5">
  <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap justify-between gap-3"><div className="flex items-center gap-3"><Headphones size={23} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Customer care and trust</h2>
    <p className="text-sm text-slate-500">Support cases, return decisions and independent supplier review moderation.</p></div></div><button disabled={loading} type="button" onClick={()=>void load()} className="rounded-lg border px-4 py-2 text-sm font-bold disabled:opacity-50"><RefreshCw size={16} className="mr-1 inline"/>Refresh</button></div>
   <div role="tablist" aria-label="Support queues" className="mt-5 flex flex-wrap gap-2">
    {(['cases','returns','reviews'] as const).map(t=><button type="button" role="tab" key={t} aria-selected={tab===t} onClick={()=>{setTab(t);setPending(null);setError('');}} className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===t?'bg-[#174C86] text-white':'border')}>{t==='cases'?'Support cases':t==='returns'?'Return claims':'Supplier reviews'} ({t==='cases'?cases.length:t==='returns'?returns.length:reviews.length})</button>)}
   </div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
   {notice&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
   {loading?<p role="status" className="mt-5 text-sm">Loading support queues…</p>:<>
    {tab==='cases'&&<div className="mt-4 space-y-3">{cases.map(c=><article key={c.id} className="rounded-xl border border-slate-200 p-4"><div className="flex flex-wrap justify-between gap-2">
     <div><b className="text-sm">{c.publicNumber} · {c.subject}</b><p className="mt-1 text-xs text-slate-500">{c.priority} · {c.status} · {asDate(c.createdAt)}</p></div>
     <button type="button" className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>{setDetailId(c.id);setPending(null);}}>Open conversation</button>
    </div></article>)}{cases.length===0&&<p className="py-5 text-sm text-slate-500">No open support cases.</p>}</div>}
    {tab==='returns'&&<div className="mt-4 space-y-3">{returns.map(r=><article key={r.id} className="rounded-xl border border-slate-200 p-4">
     <div className="flex flex-wrap justify-between gap-3"><div><b className="text-sm">Return {r.id.slice(0,8)}… · {r.status}</b><p className="mt-2 text-sm">{r.reason}</p><p className="mt-1 text-xs text-slate-500">Units: {r.items.map(i=>i.quantity).join(', ')} · {r.financialStatus}</p></div>
      <div className="flex flex-wrap gap-2">{['REQUESTED','UNDER_REVIEW'].includes(r.status)&&(['REVIEW','APPROVE','REJECT'] as const).map(decision=><button key={decision} type="button" className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>setPending({kind:'returns',id:r.id,decision,note:''})}>{decision}</button>)}</div>
     </div></article>)}{returns.length===0&&<p className="py-5 text-sm text-slate-500">No return claims awaiting support.</p>}</div>}
    {tab==='reviews'&&<div className="mt-4 space-y-3">{reviews.map(r=><article key={r.id} className="rounded-xl border border-slate-200 p-4">
     <p className="text-sm font-bold">{r.rating} / 5 · Supplier {r.supplierId.slice(0,8)}…</p>
     <p className="mt-2 whitespace-pre-wrap text-sm">{r.comment||'No written comment.'}</p>
     <div className="mt-3 flex flex-wrap gap-2">{(['PUBLISH','REJECT'] as const).map(decision=><button type="button" key={decision} onClick={()=>setPending({kind:'reviews',id:r.id,decision,note:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">{decision==='PUBLISH'?'Publish review':'Reject review'}</button>)}</div>
    </article>)}{reviews.length===0&&<p className="py-5 text-sm text-slate-500">No pending customer reviews.</p>}</div>}
   </>}
   <p className="mt-4 text-xs text-slate-500">These existing queues show up to 100 entries each. Queue totals displayed here are visible-item counts, not platform-wide totals.</p>
  </div>
  {detailId&&tab==='cases'&&<section aria-label="Support conversation" className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex justify-between gap-2"><h3 className="font-extrabold">{detail?.publicNumber||'Loading conversation…'}</h3><button type="button" className="text-sm font-bold text-[#174C86]" onClick={()=>{setDetailId('');setDetail(null);}}>Close</button></div>
   {detail&&<>
    <h4 className="mt-3 text-sm font-bold">{detail.subject} · {detail.status}</h4>
    <div className="mt-4 max-h-96 space-y-3 overflow-y-auto">{detail.messages.map(m=><article key={m.id} className={'rounded-xl border p-4 text-sm '+(m.internal?'border-amber-300 bg-amber-50':'border-slate-200 bg-slate-50')}>
     <p className="text-xs font-bold">{m.internal?'INTERNAL — not visible to customer':'Public conversation'} · {asDate(m.createdAt)}</p><p className="mt-2 whitespace-pre-wrap">{m.body}</p>
    </article>)}</div>
    {detail.status!=='CLOSED'&&<>
     <form className="mt-5 space-y-3" onSubmit={sendMessage}><label htmlFor="support-message" className="block text-sm font-bold">Reply or private note</label>
      <textarea id="support-message" rows={3} maxLength={3000} minLength={2} required value={responseText} onChange={e=>setResponseText(e.target.value)} className="w-full rounded-lg border p-3 text-sm"/>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={internal} onChange={e=>setInternal(e.target.checked)}/>Internal note only (never shown to the customer)</label>
      <button type="submit" disabled={busy||responseText.trim().length<2} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Save {internal?'internal note':'public reply'}</button></form>
     <div className="mt-4 flex flex-wrap gap-2">{(['ASSIGNED','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED'] as const).filter(s=>s!==detail.status).map(status=><button type="button" key={status} onClick={()=>setPending({kind:'cases',id:detail.id,decision:status,note:''})} className="rounded-lg border px-3 py-2 text-xs font-semibold">{status.replace(/_/g,' ')}</button>)}</div>
    </>}
   </>}
  </section>}
  {pending&&<div role="dialog" aria-modal="true" aria-label="Confirm support decision" className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4">
   <form onSubmit={confirm} className="w-full max-w-lg rounded-xl bg-white p-6 shadow-xl">
    <div className="flex items-center gap-2"><ShieldAlert size={18} className="text-[#174C86]"/><h3 className="font-extrabold">Confirm {pending.decision}</h3></div>
    <p className="mt-3 text-sm text-slate-600">{pending.kind==='returns'?'Return approval is NOT a refund, credit note, payment or stock adjustment.':pending.kind==='reviews'?'Review moderation is recorded and independent of the supplier.':'A resolution note is customer-visible; internal notes belong in the conversation.'}</p>
    {pending.kind!=='reviews'&&<label className="mt-4 block text-sm font-semibold">Reason / customer-visible note
     <textarea value={pending.note} onChange={e=>setPending({...pending,note:e.target.value})} rows={3} minLength={pending.kind==='returns'?12:8} maxLength={pending.kind==='returns'?500:3000}
      required={pending.kind==='returns'||['RESOLVED','CLOSED'].includes(pending.decision)} className="mt-2 w-full rounded-lg border border-slate-300 p-3 text-sm"/>
    </label>}
    <div className="mt-4 flex gap-3"><button type="submit" disabled={busy||(pending.kind==='returns'&&pending.note.trim().length<12)||(['RESOLVED','CLOSED'].includes(pending.decision)&&pending.note.trim().length<8)} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Confirm</button>
     <button type="button" onClick={()=>setPending(null)} className="rounded-lg border px-4 py-2 text-sm">Cancel</button></div>
   </form>
  </div>}
 </div>;
}
