import {useCallback,useEffect,useMemo,useState} from 'react';
import type {FormEvent} from 'react';
import {
 AlertCircle,ArrowRight,Building2,CheckCircle2,ClipboardCheck,Clock3,
 Download,FileCheck2,FileClock2,FileWarning,Mail,RefreshCw,Search,
 ShieldAlert,ShieldCheck,Store,UserRound,X,
} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Approval='DRAFT'|'PENDING'|'UNDER_REVIEW'|'APPROVED'|'REJECTED'|'SUSPENDED';
type Supplier={
 id:string;slug:string;displayName:string;legalName:string;approval:Approval;
 gstRegistration:string;gstin:string|null;verifiedAt:string|null;suspendedAt:string|null;createdAt:string;
};
type Doc={
 id:string;documentType:string;status:string;reviewNote:string|null;downloadPath?:string;
 mimeType:string;sizeBytes:string;digestAvailable:boolean;expiresAt:string|null;createdAt:string;
};
type Detail=Supplier&{
 contactEmail:string|null;contactPhone:string|null;businessType:string|null;
 billingAddress:unknown;owners:{userId:string;active:boolean;displayName:string;email:string|null}[];
 documents:Doc[];
};
type Page={items:Supplier[];nextCursor:string|null};
type Review={type:'supplier'|'document';decision:string;documentId?:string;reason:string};
type Issue={heading:string;description:string;code?:string;requestId?:string};

const STATUSES:readonly Approval[]=['PENDING','UNDER_REVIEW','APPROVED','REJECTED','SUSPENDED'];
const labels=(value:string)=>value.replace(/_/g,' ').toLowerCase().replace(/(^|\s)\S/g,match=>match.toUpperCase());
const date=(value:string|null)=>value?new Date(value).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'}):'—';
const allowed=(value:Approval):readonly string[]=>({
 DRAFT:[],PENDING:['UNDER_REVIEW','APPROVED','REJECTED'],
 UNDER_REVIEW:['APPROVED','REJECTED'],REJECTED:['UNDER_REVIEW'],
 APPROVED:['SUSPENDED'],SUSPENDED:['UNDER_REVIEW'],
})[value];

const requirements=(supplier:Detail)=>[
 {type:'BUSINESS_REGISTRATION',label:'Business registration certificate'},
 ...(['REGULAR','COMPOSITION'].includes(supplier.gstRegistration)
   ?[{type:'GST_CERTIFICATE',label:'GST registration certificate'}]:[]),
];
function evidenceState(supplier:Detail,type:string) {
 const docs=supplier.documents.filter(document=>document.documentType===type);
 const verified=docs.some(doc=>doc.status==='VERIFIED'&&doc.digestAvailable&&
  (!doc.expiresAt||new Date(doc.expiresAt).getTime()>Date.now()));
 if(verified)return 'VERIFIED' as const;
 if(docs.some(doc=>['UPLOADED','PENDING','REVIEWED'].includes(doc.status)))
  return 'UNDER_REVIEW' as const;
 if(docs.some(doc=>doc.status==='REJECTED'))return 'REJECTED' as const;
 return 'MISSING' as const;
}
function approvalReadiness(detail:Detail) {
 const required=requirements(detail);
 const incomplete=required.filter(req=>evidenceState(detail,req.type)!=='VERIFIED');
 return {ready:incomplete.length===0,required,incomplete};
}
function issueFrom(error:unknown):Issue {
 if(error instanceof V21ApiError) {
  const detail=error.code==='VERIFIED_DOCUMENTS_REQUIRED'
   ?{heading:'Approval blocked — documents are not verified',
     description:'Review the evidence checklist below. The supplier must upload the required certificates, and an independent administrator must verify each one before approval.'}
   :error.code==='INDEPENDENT_SUPPLIER_REVIEW_REQUIRED'
   ?{heading:'Independent review required',
     description:'You are linked to this supplier. Another authorized administrator must review its documents and application.'}
   :error.code==='ILLEGAL_TRANSITION'
   ?{heading:'Supplier status changed',
     description:'The requested approval decision is no longer valid. Refresh the supplier details and select an available action.'}
   :error.status===403
   ?{heading:'Review permission required',
     description:'Your administrator role is not authorized for this action.'}
   :error.status===409
   ?{heading:'This review cannot be completed yet',
     description:'The supplier status or required evidence has changed. Refresh the checklist and resolve the outstanding requirements.'}
   :error.status===404
   ?{heading:'Supplier record unavailable',description:'This supplier or document no longer exists or is not available to this administrator.'}
   :{heading:'Could not complete the request',
     description:error.message||'Check your connection and try again.'};
  return {...detail,code:error.code,requestId:error.requestId};
 }
 return {heading:'Unable to load the information',
  description:'Check the staging API connection and retry. Your review was not recorded.'};
}
function Status({state}:{state:string}){
 return <span className="splyzo-status" data-state={state}>
  <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full bg-current"/>
  {state==='MISSING'?'Not attached':labels(state)}
 </span>;
}
function Alert({issue,onDismiss}:{issue:Issue;onDismiss?:()=>void}) {
 return <div role="alert" className="splyzo-action-alert flex flex-wrap items-start gap-3" aria-live="assertive">
  <AlertCircle size={21} className="mt-0.5 shrink-0"/>
  <div className="min-w-0 flex-1">
   <p className="font-extrabold">{issue.heading}</p>
   <p className="mt-1 text-sm font-medium">{issue.description}</p>
   {(issue.code||issue.requestId)&&<p className="mt-2 text-[11px] font-semibold opacity-80">
    {issue.code&&'Error: '+issue.code}{issue.code&&issue.requestId?' · ':''}
    {issue.requestId&&'Request ID: '+issue.requestId}
   </p>}
  </div>
  {onDismiss&&<button type="button" onClick={onDismiss} aria-label="Dismiss error" className="p-1"><X size={17}/></button>}
 </div>;
}

export function SupplierPanel({currentAdminId}:{currentAdminId:string}) {
 const api=useV21Api();
 const [status,setStatus]=useState<Approval|'ALL'>('PENDING');
 const [items,setItems]=useState<Supplier[]>([]);
 const [cursor,setCursor]=useState<string|null>(null);
 const [selectedId,setSelectedId]=useState('');
 const [detail,setDetail]=useState<Detail|null>(null);
 const [search,setSearch]=useState('');
 const [busy,setBusy]=useState(false);
 const [loading,setLoading]=useState(true);
 const [detailLoading,setDetailLoading]=useState(false);
 const [review,setReview]=useState<Review|null>(null);
 const [error,setError]=useState<Issue|null>(null);
 const [actionError,setActionError]=useState<Issue|null>(null);
 const [info,setInfo]=useState('');
 const [downloading,setDownloading]=useState<string|null>(null);

 const filtered=useMemo(()=>items.filter(s=>
  (s.displayName+' '+s.legalName+' '+s.slug).toLowerCase().includes(search.trim().toLowerCase())),[items,search]);
 const self=detail?.owners.some(owner=>owner.userId===currentAdminId)??false;
 const readiness=detail?approvalReadiness(detail):null;
 const canApprove=Boolean(readiness?.ready&&!self);

 const load=useCallback(async(reset:boolean,next?:string,signal?:AbortSignal)=>{
  setLoading(true);setError(null);
  try{
   const query=new URLSearchParams({limit:'25'});
   if(status!=='ALL')query.set('status',status);
   if(next)query.set('cursor',next);
   const response=await api.get<Page>('/api/v2/admin/suppliers?'+query,signal);
   if(!Array.isArray(response.data.items)||
      !(response.data.nextCursor===null||typeof response.data.nextCursor==='string'))
    throw new Error('Invalid supplier list response');
   if(!signal?.aborted){
    setItems(old=>reset?response.data.items:[...old,...response.data.items]);
    setCursor(response.data.nextCursor);
   }
  }catch(failure){if(!signal?.aborted)setError(issueFrom(failure));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api,status]);
 const loadDetail=useCallback(async(id:string,signal?:AbortSignal)=>{
  setDetailLoading(true);
  try{
   const response=await api.get<Detail>('/api/v2/admin/suppliers/'+encodeURIComponent(id),signal);
   if(!Array.isArray(response.data.documents)||!Array.isArray(response.data.owners))
    throw new Error('Invalid supplier detail response');
   if(!signal?.aborted)setDetail(response.data);
  }catch(failure){
   if(!signal?.aborted){setDetail(null);setError(issueFrom(failure));}
  }finally{if(!signal?.aborted)setDetailLoading(false);}
 },[api]);
 useEffect(()=>{
  const controller=new AbortController();
  setSelectedId('');setDetail(null);setReview(null);setActionError(null);
  void load(true,undefined,controller.signal);
  return ()=>controller.abort();
 },[load]);
 useEffect(()=>{
  if(!selectedId)return;
  const controller=new AbortController();
  void loadDetail(selectedId,controller.signal);
  return ()=>controller.abort();
 },[selectedId,loadDetail]);

 function choose(id:string) {
  setSelectedId(id);setReview(null);setActionError(null);setInfo('');
 }
 function close() {
  setSelectedId('');setDetail(null);setReview(null);setActionError(null);
 }
 function startReview(type:'supplier'|'document',decision:string,documentId?:string) {
  setReview({type,decision,documentId,reason:''});
  setActionError(null);setInfo('');
 }
 async function download(doc:Doc) {
  if(!doc.downloadPath||downloading)return;
  setDownloading(doc.id);setActionError(null);
  try{
   if(!/^\/api\/v2\/media\/[0-9a-f-]{36}\?format=base64$/.test(doc.downloadPath))throw new Error('Invalid document reference');
   const result=await api.get<{base64:string;mimeType:string}>(doc.downloadPath);
   if(!['application/pdf','image/png','image/jpeg'].includes(result.data.mimeType)||
      typeof result.data.base64!=='string'||result.data.base64.length>14000000)throw new Error('Invalid document');
   const bytes=Uint8Array.from(atob(result.data.base64),c=>c.charCodeAt(0));
   const url=URL.createObjectURL(new Blob([bytes],{type:result.data.mimeType}));
   const anchor=document.createElement('a');anchor.href=url;
   anchor.download='verification-document.'+(result.data.mimeType==='application/pdf'?'pdf':result.data.mimeType==='image/png'?'png':'jpg');
   anchor.click();
   window.setTimeout(()=>URL.revokeObjectURL(url),1000);
  }catch(failure){setActionError(issueFrom(failure));}
  finally{setDownloading(null);}
 }
 async function submitReview(event:FormEvent<HTMLFormElement>) {
  event.preventDefault();
  if(!detail||!review||busy||review.reason.trim().length<8)return;
  if(review.type==='supplier'&&review.decision==='APPROVED'&&!canApprove) {
   setActionError({heading:'Approval blocked — documents are not verified',
    description:'All required certificates need independent verification first. See the checklist above.'});
   return;
  }
  setBusy(true);setActionError(null);setInfo('');
  try{
   const base='/api/v2/admin/suppliers/'+encodeURIComponent(detail.id);
   const path=review.type==='document'
    ?base+'/documents/'+encodeURIComponent(review.documentId||'')+'/review'
    :base+'/review';
   await api.write('POST',path,{decision:review.decision,reason:review.reason.trim()});
   setReview(null);
   setInfo('Decision saved successfully. The audit reason is recorded and the supplier details have been refreshed.');
   await Promise.all([load(true),loadDetail(detail.id)]);
  }catch(failure){setActionError(issueFrom(failure));}
  finally{setBusy(false);}
 }

 return <div className="space-y-6">
  <section className="splyzo-surface overflow-hidden">
   <div className="border-b border-slate-100 bg-gradient-to-r from-[#f3f7fd] via-white to-white p-6 sm:p-7">
    <div className="flex flex-wrap items-start justify-between gap-4">
     <div className="flex items-start gap-4">
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-[#113964] text-white shadow-sm">
       <Store size={23}/>
      </div>
      <div>
       <p className="splyzo-eyebrow">Trust & compliance / Supplier onboarding</p>
       <h2 className="mt-1 text-2xl font-extrabold text-[#142d4a]">Supplier verification</h2>
       <p className="mt-1 max-w-2xl text-sm leading-6 text-slate-600">
        Review applications, verify supporting documents and make audited decisions.
        Every approval requires independent evidence verification.
       </p>
      </div>
     </div>
     <button type="button" className="splyzo-secondary inline-flex items-center gap-2"
      onClick={()=>{setActionError(null);void load(true);if(selectedId)void loadDetail(selectedId);}} disabled={loading}>
      <RefreshCw size={16} className={loading?'animate-spin':''}/>Refresh queue
     </button>
    </div>
    <div className="mt-6 grid gap-3 sm:grid-cols-3">
     <div className="rounded-2xl border border-[#dfe8f3] bg-white p-4">
      <p className="splyzo-eyebrow">Loaded applications</p>
      <p className="mt-1 text-2xl font-extrabold tabular-nums text-[#16395e]">{items.length}</p>
      <p className="mt-1 text-xs text-slate-500">Current loaded results, not an all-time total</p>
     </div>
     <div className="rounded-2xl border border-[#f1e1c4] bg-[#fffbf3] p-4">
      <p className="splyzo-eyebrow">Awaiting review</p>
      <p className="mt-1 text-2xl font-extrabold tabular-nums text-[#a66a25]">{items.filter(x=>['PENDING','UNDER_REVIEW'].includes(x.approval)).length}</p>
      <p className="mt-1 text-xs text-slate-500">In the current loaded results</p>
     </div>
     <div className="rounded-2xl border border-[#dbe5f4] bg-[#f6f9fd] p-4">
      <p className="splyzo-eyebrow">Review policy</p>
      <p className="mt-1 flex items-center gap-2 text-sm font-extrabold text-[#183e6a]"><ShieldCheck size={18}/>Independent approval</p>
      <p className="mt-2 text-xs text-slate-500">Signed-in admin and valid evidence required</p>
     </div>
    </div>
   </div>
   <div className="p-5 sm:p-6">
    <div className="flex flex-wrap items-end gap-3">
     <label className="min-w-[180px] flex-1 text-xs font-bold text-slate-600" htmlFor="supplier-state">
      Approval status
      <select id="supplier-state" value={status} onChange={event=>{setStatus(event.target.value as Approval|'ALL');setSearch('');}}
       className="splyzo-select mt-2 w-full text-sm">
       <option value="ALL">All suppliers</option>
       {STATUSES.map(value=><option value={value} key={value}>{labels(value)}</option>)}
      </select>
     </label>
     <label className="min-w-[220px] flex-[2] text-xs font-bold text-slate-600" htmlFor="supplier-search">
      Search loaded suppliers
      <span className="relative mt-2 block">
       <Search size={17} className="pointer-events-none absolute left-3 top-3.5 text-slate-400"/>
       <input id="supplier-search" type="search" value={search} onChange={e=>setSearch(e.target.value)}
        placeholder="Name or business identifier" className="splyzo-input w-full pl-10 text-sm"/>
      </span>
     </label>
     <div className="pb-2 text-xs font-semibold text-slate-500">{filtered.length} shown</div>
    </div>
    {error&&<div className="mt-4"><Alert issue={error} onDismiss={()=>setError(null)}/></div>}
    {info&&<div role="status" className="mt-4 flex items-start gap-3 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-900">
     <CheckCircle2 size={19} className="shrink-0"/>{info}
    </div>}
    {loading&&items.length===0?<div role="status" className="py-12 text-center text-sm text-slate-600">Loading supplier applications…</div>:
     <div className="mt-5 overflow-x-auto rounded-xl border border-[#e2e9f2]">
      <table className="w-full min-w-[650px] text-left text-sm">
       <thead><tr><th scope="col">Business</th><th scope="col">GST</th><th scope="col">Submitted</th><th scope="col">Status</th><th scope="col" className="text-right">Review</th></tr></thead>
       <tbody>{filtered.map(s=><tr key={s.id} className={selectedId===s.id?'bg-[#f0f6ff]':''}>
        <td>
         <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#e8f0f9] text-sm font-extrabold text-[#1d5284]">{s.displayName.slice(0,2).toUpperCase()}</span>
          <span className="min-w-0"><span className="block font-extrabold text-[#172e4c]">{s.displayName}</span><span className="block max-w-[270px] truncate text-xs text-slate-500">{s.legalName}</span></span>
         </div>
        </td>
        <td className="text-xs font-semibold">{s.gstRegistration==='UNREGISTERED'?'Not registered':labels(s.gstRegistration)}</td>
        <td className="text-xs font-medium text-slate-500">{date(s.createdAt)}</td>
        <td><Status state={s.approval}/></td>
        <td className="text-right"><button type="button" onClick={()=>choose(s.id)} className="splyzo-secondary inline-flex items-center gap-2 text-xs">
          View details <ArrowRight size={15}/>
         </button></td>
       </tr>)}</tbody>
      </table>
      {filtered.length===0&&!loading&&<div className="py-12 text-center">
       <Search size={24} className="mx-auto text-slate-400"/>
       <p className="mt-3 font-bold text-slate-700">{search?'No matching loaded suppliers':'No suppliers match this approval status.'}</p>
       <p className="mt-1 text-xs text-slate-500">{search?'Clear the search or change the approval filter.':'Try another status to browse the queue.'}</p>
      </div>}
     </div>}
    {cursor&&<div className="mt-4 flex justify-center"><button type="button" className="splyzo-secondary" disabled={loading} onClick={()=>void load(false,cursor)}>Load more suppliers</button></div>}
   </div>
  </section>

  {selectedId&&<section aria-label="Selected supplier details" className="splyzo-surface overflow-hidden">
   {detailLoading&&!detail?<div role="status" className="p-8 text-sm text-slate-500">Loading verified supplier details…</div>:detail&&<>
    <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[#e5ecf5] bg-[#f8fafd] px-6 py-6 sm:px-8">
     <div className="flex items-start gap-3">
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-[#143d69] text-white"><Building2 size={23}/></div>
      <div>
       <p className="splyzo-eyebrow">Application review / {detail.slug}</p>
       <h3 className="mt-1 text-xl font-extrabold text-[#122d4c]">{detail.displayName}</h3>
       <p className="mt-1 text-sm text-slate-500">{detail.legalName}</p>
       <div className="mt-3"><Status state={detail.approval}/></div>
      </div>
     </div>
     <button type="button" onClick={close} className="splyzo-secondary inline-flex items-center gap-2 text-sm"><X size={16}/>Close</button>
    </header>
    <div className="grid gap-7 p-5 sm:p-8 xl:grid-cols-[minmax(0,.9fr)_minmax(0,1.1fr)]">
     <div className="space-y-6">
      <section aria-label="Business information" className="rounded-2xl border border-[#e3eaf3] bg-white p-5">
       <p className="splyzo-eyebrow">01 / Business identity</p>
       <h4 className="mt-1 text-base font-extrabold">Registered information</h4>
       <dl className="mt-5 grid gap-x-5 gap-y-4 text-sm sm:grid-cols-2">
        <div><dt className="text-xs font-semibold text-slate-500">GST registration</dt><dd className="mt-1 font-extrabold">{labels(detail.gstRegistration)}</dd></div>
        <div><dt className="text-xs font-semibold text-slate-500">GSTIN supplied</dt><dd className="mt-1 break-all font-extrabold">{detail.gstin||'Not registered'}</dd></div>
        <div><dt className="text-xs font-semibold text-slate-500">Contact email</dt><dd className="mt-1 break-all font-bold">{detail.contactEmail||'Not provided'}</dd></div>
        <div><dt className="text-xs font-semibold text-slate-500">Contact phone</dt><dd className="mt-1 font-bold">{detail.contactPhone||'Not provided'}</dd></div>
        <div><dt className="text-xs font-semibold text-slate-500">Submitted on</dt><dd className="mt-1 font-bold">{date(detail.createdAt)}</dd></div>
        <div><dt className="text-xs font-semibold text-slate-500">Verified on</dt><dd className="mt-1 font-bold">{date(detail.verifiedAt)}</dd></div>
       </dl>
       <div className="mt-5 border-t border-slate-100 pt-4">
        <p className="flex items-center gap-2 text-sm font-extrabold"><UserRound size={17} className="text-[#2a5b87]"/>Business ownership</p>
        {detail.owners.length===0?<p className="mt-2 text-sm text-slate-500">No owner recorded.</p>:
         detail.owners.map(owner=><div key={owner.userId} className="mt-3 flex items-start gap-3 rounded-xl bg-[#f5f8fc] p-3 text-sm">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#dce9f7] text-[#1b4b78]"><UserRound size={17}/></span>
          <div className="min-w-0"><p className="font-bold">{owner.displayName}</p><p className="break-all text-xs text-slate-600">{owner.email||'No verified email'}</p><p className="mt-1 text-xs text-slate-500">{owner.active?'Active owner':'Awaiting access'}</p></div>
         </div>)}
       </div>
      </section>
      <section aria-label="Approval readiness" className="rounded-2xl border border-[#e3eaf3] bg-white p-5">
       <p className="splyzo-eyebrow">02 / Approval readiness</p>
       <h4 className="mt-1 text-base font-extrabold">Verification progress</h4>
       <p className="mt-2 text-sm text-slate-500">{readiness?.ready?'Every required document is independently verified.':'Approval is blocked until every required certificate is verified.'}</p>
       <div className="mt-5 space-y-3">
        {readiness?.required.map(req=>{
         const state=evidenceState(detail,req.type);
         return <div key={req.type} className="flex items-start justify-between gap-2 rounded-xl border border-[#e7edf5] bg-[#f9fbfe] p-3">
          <span className="flex min-w-0 items-center gap-2 text-sm font-bold">{state==='VERIFIED'?<CheckCircle2 size={19} className="shrink-0 text-emerald-600"/>:state==='MISSING'?<FileWarning size={19} className="shrink-0 text-amber-600"/>:<FileClock2 size={19} className="shrink-0 text-[#2a5b87]"/>}{req.label}</span>
          <Status state={state}/>
         </div>;
        })}
       </div>
       {readiness&&!readiness.ready&&<div className="splyzo-note mt-4" data-tone="warning">
        <p className="flex gap-2 text-sm font-extrabold text-[#92541b]"><ShieldAlert size={19} className="shrink-0"/>Approval blocked — {readiness.incomplete.length} requirement{readiness.incomplete.length===1?'':'s'} outstanding</p>
        <p className="mt-2 text-xs leading-6 text-[#805c2c]">The supplier must upload missing documents in their app. Uploaded documents must then be downloaded, inspected and marked verified by an independent reviewer.</p>
        {detail.contactEmail&&<a className="mt-3 inline-flex items-center gap-2 text-xs font-extrabold text-[#174C86] underline-offset-4 hover:underline" href={'mailto:'+encodeURIComponent(detail.contactEmail)+'?subject='+encodeURIComponent('Splyzo supplier verification documents')+'&body='+encodeURIComponent('Hello, please upload the required verification documents from your Splyzo Supplier app. This is needed before we can approve your application.')}>
         <Mail size={15}/>Draft an email to supplier
        </a>}
       </div>}
       {readiness?.ready&&<div role="status" className="splyzo-note mt-4 flex items-center gap-3 text-sm font-semibold text-emerald-800"><CheckCircle2 size={20}/>Required evidence is verified. You may proceed with an independent approval decision.</div>}
      </section>
     </div>
     <div className="space-y-6">
      <section aria-label="Document evidence" className="rounded-2xl border border-[#e3eaf3] bg-white p-5">
       <div className="flex items-start gap-3">
        <span className="rounded-xl bg-[#e7eff9] p-2.5 text-[#1c5384]"><ClipboardCheck size={20}/></span>
        <div><p className="splyzo-eyebrow">03 / Document evidence</p><h4 className="mt-1 text-base font-extrabold">Evidence checklist</h4></div>
       </div>
       <p className="mt-4 flex items-start gap-2 rounded-xl border border-[#d7e5f2] bg-[#f3f7fc] p-4 text-xs leading-6 text-[#355573]">
        <ShieldAlert size={18} className="mt-0.5 shrink-0"/>
        Evidence is private. Download and inspect each document before recording a review decision. Downloads require your current reviewer session.
       </p>
       {detail.documents.length===0?<div className="mt-4 rounded-xl border border-dashed border-[#e9c79e] bg-[#fffaf1] p-6 text-center">
        <FileWarning size={26} className="mx-auto text-[#bd7e31]"/>
        <h5 className="mt-3 font-extrabold text-[#80511d]">No documents attached yet</h5>
        <p className="mt-2 text-sm leading-6 text-[#966f3e]">The supplier needs to upload a business registration certificate{['REGULAR','COMPOSITION'].includes(detail.gstRegistration)?' and GST certificate':''} in the supplier app before review.</p>
       </div>:
        <ul className="mt-4 space-y-3">{detail.documents.map(doc=><li key={doc.id} className="rounded-2xl border border-[#e1e9f3] bg-white p-4">
         <div className="flex flex-wrap justify-between gap-3">
          <div className="flex min-w-0 flex-1 gap-3">
           <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-[#eef4fb] text-[#215583]"><FileCheck2 size={20}/></span>
           <div className="min-w-0">
            <p className="text-sm font-extrabold">{labels(doc.documentType)}</p>
            <p className="mt-1 text-xs text-slate-500">{doc.mimeType} · {(Number(doc.sizeBytes)/1024).toFixed(1)} KB · SHA-256 {doc.digestAvailable?'recorded':'missing'}</p>
            <div className="mt-2"><Status state={doc.status}/></div>
           </div>
          </div>
          {!self&&doc.downloadPath&&<button type="button" className="splyzo-secondary inline-flex items-center gap-2 text-xs" disabled={downloading!==null} onClick={()=>void download(doc)}>
           <Download size={15}/>{downloading===doc.id?'Downloading…':'Download private document'}
          </button>}
         </div>
         {doc.expiresAt&&<p className="mt-2 text-xs text-slate-500">Expires: {date(doc.expiresAt)}</p>}
         {doc.reviewNote&&<p className="mt-3 rounded-lg bg-slate-50 p-3 text-xs text-slate-600">Review note: {doc.reviewNote}</p>}
         {!self&&['UPLOADED','PENDING','REVIEWED'].includes(doc.status)&&<div className="mt-4 flex flex-wrap gap-2 border-t border-slate-100 pt-3">
          <button type="button" className="splyzo-secondary text-xs" onClick={()=>startReview('document','VERIFIED',doc.id)}>Verify</button>
          <button type="button" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-2 text-xs font-extrabold text-rose-700 hover:bg-rose-100" onClick={()=>startReview('document','REJECTED',doc.id)}>Reject</button>
         </div>}
        </li>)}</ul>}
      </section>
      <section aria-label="Application decision" className="rounded-2xl border border-[#e3eaf3] bg-white p-5">
       <p className="splyzo-eyebrow">04 / Decision</p>
       <h4 className="mt-1 text-base font-extrabold">Application actions</h4>
       {self?<p className="splyzo-note mt-4 text-sm font-semibold text-amber-900">
        You are a member of this supplier. Independent review is required.
       </p>:
        <div className="mt-4 flex flex-wrap gap-2">
         {allowed(detail.approval).map(decision=><button type="button" key={decision}
          disabled={busy||(decision==='APPROVED'&&!canApprove)}
          title={decision==='APPROVED'&&!canApprove?'Verify every required document before approval':undefined}
          onClick={()=>startReview('supplier',decision)}
          className={decision==='APPROVED'?'splyzo-primary':decision==='REJECTED'||decision==='SUSPENDED'?'rounded-xl border border-rose-200 bg-rose-50 px-4 py-2 text-sm font-extrabold text-rose-800':'splyzo-secondary'}>
          {labels(decision)}
         </button>)}
        </div>}
       {!self&&readiness&&!readiness.ready&&allowed(detail.approval).includes('APPROVED')&&
        <p className="mt-3 flex items-start gap-2 text-xs leading-5 text-[#916224]"><Clock3 size={15} className="mt-0.5 shrink-0"/>Approval is disabled until all required evidence is verified.</p>}
       {actionError&&<div className="mt-4"><Alert issue={actionError} onDismiss={()=>setActionError(null)}/></div>}
       {review&&<form onSubmit={e=>void submitReview(e)} className="mt-5 rounded-2xl border border-[#bacfe5] bg-[#f4f8fe] p-5">
        <p className="text-sm font-extrabold">{review.type==='supplier'?'Supplier':'Document'} decision: {labels(review.decision)}</p>
        <p className="mt-2 text-xs leading-5 text-slate-600">This is an audited action. Explain what you checked or why the application should change state.</p>
        <label htmlFor="review-reason" className="mt-4 block text-xs font-extrabold">Mandatory audit reason (8–400 characters)</label>
        <textarea id="review-reason" value={review.reason} onChange={event=>setReview({...review,reason:event.target.value})} rows={4}
         maxLength={400} minLength={8} required className="mt-2 w-full rounded-xl border border-slate-300 bg-white p-3 text-sm"
         placeholder="Example: Documents independently checked and match business details…"/>
        <p className="mt-1 text-right text-[11px] text-slate-500">{review.reason.trim().length}/400 characters</p>
        <div className="mt-3 flex flex-wrap gap-3">
         <button type="submit" className="splyzo-primary" disabled={busy||review.reason.trim().length<8}>
          {busy?'Recording decision…':'Confirm reviewed decision'}
         </button>
         <button type="button" className="splyzo-secondary" onClick={()=>{setReview(null);setActionError(null);}}>Cancel</button>
        </div>
       </form>}
       {allowed(detail.approval).length===0&&!self&&<p className="mt-4 text-sm text-slate-500">No further actions are available for this approval state.</p>}
      </section>
     </div>
    </div>
   </>}
  </section>}
 </div>;
}
