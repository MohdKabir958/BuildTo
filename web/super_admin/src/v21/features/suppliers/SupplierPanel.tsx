import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Building2,ClipboardCheck,RefreshCw,ShieldAlert} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Approval='DRAFT'|'PENDING'|'UNDER_REVIEW'|'APPROVED'|'REJECTED'|'SUSPENDED';
type Supplier={
 id:string;slug:string;displayName:string;legalName:string;approval:Approval;
 gstRegistration:string;gstin:string|null;verifiedAt:string|null;suspendedAt:string|null;createdAt:string;
};
type Doc={
 id:string;documentType:string;status:string;reviewNote:string|null;
 mimeType:string;sizeBytes:string;digestAvailable:boolean;expiresAt:string|null;createdAt:string;
};
type Detail=Supplier&{
 contactEmail:string|null;contactPhone:string|null;businessType:string|null;
 billingAddress:unknown;owners:{userId:string;active:boolean;displayName:string;email:string|null}[];
 documents:Doc[];
};
type Page={items:Supplier[];nextCursor:string|null};
type Review={type:'supplier'|'document';decision:string;documentId?:string;reason:string};

const STATUSES:readonly Approval[]=['PENDING','UNDER_REVIEW','APPROVED','REJECTED','SUSPENDED'];
const message=(error:unknown)=>error instanceof V21ApiError
 ?error.status===403?'You do not have supplier review permission.':error.status===409?'Supplier evidence or approval state has changed. Refresh and check the required verification.':
  error.status===404?'The supplier record could not be found.':error.message
 :'The request failed. Check your network and retry.';
const allowed=(value:Approval):readonly string[]=>({
 DRAFT:[],PENDING:['UNDER_REVIEW','APPROVED','REJECTED'],
 UNDER_REVIEW:['APPROVED','REJECTED'],REJECTED:['UNDER_REVIEW'],
 APPROVED:['SUSPENDED'],SUSPENDED:['UNDER_REVIEW']
})[value];
const date=(value:string|null)=>value?new Date(value).toLocaleString():'—';

export function SupplierPanel({currentAdminId}:{currentAdminId:string}){
 const api=useV21Api();
 const [status,setStatus]=useState<Approval|'ALL'>('PENDING');
 const [items,setItems]=useState<Supplier[]>([]);
 const [cursor,setCursor]=useState<string|null>(null);
 const [selectedId,setSelectedId]=useState('');
 const [detail,setDetail]=useState<Detail|null>(null);
 const [busy,setBusy]=useState(false);
 const [loading,setLoading]=useState(true);
 const [detailLoading,setDetailLoading]=useState(false);
 const [review,setReview]=useState<Review|null>(null);
 const [error,setError]=useState('');
 const [info,setInfo]=useState('');

 const load=useCallback(async(reset:boolean,next?:string,signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const query=new URLSearchParams({limit:'25'});
   if(status!=='ALL')query.set('status',status);
   if(next)query.set('cursor',next);
   const response=await api.get<Page>('/api/v2/admin/suppliers?'+query,signal);
   if(!Array.isArray(response.data.items)||!(response.data.nextCursor===null||typeof response.data.nextCursor==='string'))
    throw new Error('Invalid supplier list response');
   if(!signal?.aborted){
    setItems(old=>reset?response.data.items:[...old,...response.data.items]);
    setCursor(response.data.nextCursor);
   }
  }catch(e){if(!signal?.aborted)setError(message(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api,status]);
 const loadDetail=useCallback(async(id:string,signal?:AbortSignal)=>{
  setDetailLoading(true);setError('');
  try{
   const response=await api.get<Detail>('/api/v2/admin/suppliers/'+encodeURIComponent(id),signal);
   if(!Array.isArray(response.data.documents)||!Array.isArray(response.data.owners))
    throw new Error('Invalid supplier detail response');
   if(!signal?.aborted)setDetail(response.data);
  }catch(e){if(!signal?.aborted){setDetail(null);setError(message(e));}}
  finally{if(!signal?.aborted)setDetailLoading(false);}
 },[api]);
 useEffect(()=>{
  const controller=new AbortController();setSelectedId('');setDetail(null);setReview(null);
  void load(true,undefined,controller.signal);
  return ()=>controller.abort();
 },[load]);
 useEffect(()=>{
  if(!selectedId)return;
  const controller=new AbortController();
  void loadDetail(selectedId,controller.signal);
  return ()=>controller.abort();
 },[selectedId,loadDetail]);
 const self=false;
 async function submitReview(event:FormEvent<HTMLFormElement>){
  event.preventDefault();if(!detail||!review||busy||review.reason.trim().length<8)return;
  setBusy(true);setError('');setInfo('');
  try{
   const base='/api/v2/admin/suppliers/'+encodeURIComponent(detail.id);
   const path=review.type==='document'
    ?base+'/documents/'+encodeURIComponent(review.documentId||'')+'/review':base+'/review';
   await api.write('POST',path,{decision:review.decision,reason:review.reason.trim()});
   setReview(null);
   setInfo('Review saved with an audit reason. No payment or supplier data was changed.');
   await Promise.all([load(true),loadDetail(detail.id)]);
  }catch(e){setError(message(e));}
  finally{setBusy(false);}
 }
 return <div className="space-y-6">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap items-center justify-between gap-3">
    <div className="flex items-center gap-3"><Building2 className="text-[#174C86]" size={24}/><div>
     <h2 className="text-lg font-extrabold">Supplier verification</h2>
     <p className="text-sm text-slate-500">Approval requires human-verified business records and, where applicable, GST evidence.</p>
    </div></div>
    <button type="button" onClick={()=>void load(true)} disabled={loading} className="rounded-lg border px-3 py-2 text-sm font-semibold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button>
   </div>
   <div className="mt-5 flex flex-wrap items-center gap-3">
    <label htmlFor="supplier-state" className="text-sm font-semibold">Approval status</label>
    <select id="supplier-state" value={status} onChange={e=>setStatus(e.target.value as Approval|'ALL')} className="rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm">
     <option value="ALL">All suppliers</option>
     {STATUSES.map(s=><option value={s} key={s}>{s.replace(/_/g,' ')}</option>)}
    </select>
   </div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-800">{error}</p>}
   {info&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{info}</p>}
   {loading&&items.length===0?<p role="status" className="mt-6 text-sm text-slate-500">Loading supplier applications…</p>:
    <div className="mt-5 overflow-x-auto"><table className="w-full min-w-[540px] text-left text-sm">
     <thead><tr className="border-b text-xs uppercase text-slate-500"><th scope="col" className="pb-3">Supplier</th><th scope="col">GST</th><th scope="col">State</th><th scope="col" className="text-right">Review</th></tr></thead>
     <tbody>{items.map(s=><tr key={s.id} className="border-b border-slate-100">
      <td className="py-4"><span className="font-bold">{s.displayName}</span><span className="block text-xs text-slate-500">{s.legalName}</span></td>
      <td className="py-4">{s.gstRegistration}</td><td className="py-4">{s.approval.replace(/_/g,' ')}</td>
      <td className="py-4 text-right"><button type="button" className="rounded-lg border border-slate-300 px-3 py-2 font-semibold hover:bg-slate-50" onClick={()=>{setSelectedId(s.id);setReview(null);}}>View details</button></td>
     </tr>)}</tbody>
    </table>{items.length===0&&!loading&&<p className="py-8 text-sm text-slate-500">No suppliers match this approval status.</p>}
    {cursor&&<button type="button" disabled={loading} onClick={()=>void load(false,cursor)} className="mt-4 rounded-lg border px-4 py-2 text-sm font-semibold disabled:opacity-50">Load more</button>}
    </div>}
  </section>

  {selectedId&&<section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm" aria-label="Selected supplier details">
   {detailLoading&&!detail?<p role="status">Loading verified supplier details…</p>:detail&&<>
    <div className="flex items-start justify-between gap-3">
     <div><h3 className="text-lg font-extrabold">{detail.displayName}</h3><p className="text-sm text-slate-500">{detail.legalName} · {detail.slug}</p></div>
     <button type="button" onClick={()=>{setSelectedId('');setDetail(null);setReview(null);}} className="text-sm font-semibold text-[#174C86]">Close</button>
    </div>
    <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
     <div><dt className="text-slate-500">Approval</dt><dd className="font-bold">{detail.approval}</dd></div>
     <div><dt className="text-slate-500">GST registration</dt><dd className="font-bold">{detail.gstRegistration}</dd></div>
     <div><dt className="text-slate-500">GSTIN supplied</dt><dd className="font-bold">{detail.gstin||'Not registered'}</dd></div>
     <div><dt className="text-slate-500">Contact email</dt><dd className="font-bold">{detail.contactEmail||'Not provided'}</dd></div>
     <div><dt className="text-slate-500">Verified on</dt><dd>{date(detail.verifiedAt)}</dd></div>
     <div><dt className="text-slate-500">Suspended on</dt><dd>{date(detail.suspendedAt)}</dd></div>
    </dl>
    <div className="mt-6">
     <h4 className="mb-3 font-bold">Ownership</h4>
     {detail.owners.map(o=><p key={o.userId} className="text-sm">{o.displayName} · {o.email||'No verified email'} · {o.active?'Active':'Pending approval'}</p>)}
    </div>
    <div className="mt-6">
     <div className="flex items-center gap-2"><ClipboardCheck size={18}/><h4 className="font-bold">Evidence checklist</h4></div>
     <p className="mt-2 flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-xs text-amber-900"><ShieldAlert size={16} className="shrink-0"/>Evidence is private. Only metadata and document review decisions are available here; file preview/download is not implemented. Never mark a document verified without an independently approved way to inspect its actual contents.</p>
     {detail.documents.length===0?<p className="mt-3 text-sm text-slate-500">No documents attached yet. Approval is blocked until evidence is verified.</p>:
      <ul className="mt-3 space-y-3">{detail.documents.map(d=><li key={d.id} className="rounded-xl border border-slate-200 p-4">
       <div className="flex flex-wrap justify-between gap-3"><div>
        <p className="font-semibold">{d.documentType.replace(/_/g,' ')}</p>
        <p className="text-xs text-slate-500">{d.mimeType} · {d.sizeBytes} bytes · Digest {d.digestAvailable?'recorded':'missing'} · {d.status}</p>
        {d.expiresAt&&<p className="text-xs text-slate-500">Expires: {date(d.expiresAt)}</p>}
        {d.reviewNote&&<p className="mt-2 text-sm text-slate-600">Review note: {d.reviewNote}</p>}
       </div>
       {!self&&['UPLOADED','PENDING','REVIEWED'].includes(d.status)&&
        <div className="flex gap-2"><button type="button" onClick={()=>setReview({type:'document',decision:'VERIFIED',documentId:d.id,reason:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Verify</button>
         <button type="button" onClick={()=>setReview({type:'document',decision:'REJECTED',documentId:d.id,reason:''})} className="rounded-lg border border-rose-200 px-3 py-2 text-xs font-bold text-rose-700">Reject</button></div>}
       </div>
      </li>)}</ul>}
    </div>
    {self?<p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm text-amber-900">You are a member of this supplier. Independent review is required.</p>:
     <div className="mt-6 flex flex-wrap gap-2">
      {allowed(detail.approval).map(decision=><button type="button" key={decision} onClick={()=>setReview({type:'supplier',decision,reason:''})} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold hover:bg-slate-50">{decision.replace(/_/g,' ')}</button>)}
     </div>}
    {review&&<form onSubmit={e=>void submitReview(e)} className="mt-6 rounded-xl border border-[#B7C9DD] bg-[#F4F8FC] p-5">
     <p className="font-bold">{review.type==='supplier'?'Supplier':'Document'} decision: {review.decision}</p>
     <label htmlFor="review-reason" className="mt-4 block text-sm font-semibold">Mandatory audit reason (8–400 characters)</label>
     <textarea id="review-reason" value={review.reason} onChange={e=>setReview({...review,reason:e.target.value})} rows={3} maxLength={400} minLength={8} required className="mt-2 w-full rounded-lg border border-slate-300 p-3 text-sm"/>
     <div className="mt-3 flex gap-3"><button type="submit" disabled={busy||review.reason.trim().length<8} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Confirm reviewed decision</button>
      <button type="button" onClick={()=>setReview(null)} className="rounded-lg border px-4 py-2 text-sm font-semibold">Cancel</button></div>
    </form>}
   </>}
  </section>}
 </div>;
}
