import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {AlertCircle,ArrowRight,Building2,CheckCircle2,ClipboardCheck,FileCheck2,FileWarning,RefreshCw,Search,ShieldAlert,ShieldCheck,XCircle} from 'lucide-react';
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
 reviewPolicy?:{stagingTestWithoutDocuments:boolean};
};
type Page={items:Supplier[];nextCursor:string|null};
type Review={type:'supplier'|'document';decision:string;documentId?:string;reason:string};

const STATUSES:readonly Approval[]=['PENDING','UNDER_REVIEW','APPROVED','REJECTED','SUSPENDED'];
export const supplierReviewMessage=(error:unknown):string=>{
 if(!(error instanceof V21ApiError)) return 'The request failed. Check your connection and retry.';
 switch(error.code){
  case 'VERIFIED_DOCUMENTS_REQUIRED':
   return 'Approval blocked: independently verified business registration evidence is required, plus a verified GST certificate for a GST-registered business. Open the Evidence checklist below and review each uploaded document first.';
  case 'INDEPENDENT_SUPPLIER_REVIEW_REQUIRED':
   return 'You cannot approve a business that you belong to. Another authorized administrator must review this application.';
  case 'INCOMPLETE_APPLICATION':
   return 'Approval blocked: the supplier must provide a verified contact email and billing address.';
  case 'OWNER_REQUIRED':
   return 'Approval blocked: this business needs an active owner record before it can be approved.';
  case 'ILLEGAL_TRANSITION':
   return 'This review action is no longer allowed. Refresh the supplier record to see its current status.';
  case 'DOCUMENT_LOCKED':
   return 'This application cannot accept document changes in its current state.';
 }
 if(error.status===403)return 'Your administrator role cannot perform this action.';
 if(error.status===404)return 'This supplier or document is no longer available. Refresh the page.';
 if(error.status===409)return error.message || 'This supplier changed. Refresh and try again.';
 return error.message;
};
const message=supplierReviewMessage;
const statusLabel=(value:string)=>value.replace(/_/g,' ').toLowerCase().replace(/\b\w/g,c=>c.toUpperCase());
const statusColor=(value:string)=>value==='APPROVED'||value==='VERIFIED'
 ?'border-emerald-200 bg-emerald-50 text-emerald-800'
 :value==='PENDING'||value==='UNDER_REVIEW'||value==='UPLOADED'
 ?'border-amber-200 bg-amber-50 text-amber-800'
 :value==='REJECTED'||value==='SUSPENDED'
 ?'border-rose-200 bg-rose-50 text-rose-800'
 :'border-slate-200 bg-slate-100 text-slate-700';
const requiredEvidence=(detail:Detail):{type:string;label:string;verified:boolean;uploaded:boolean}[]=>{
 const requirements=[
  {type:'BUSINESS_REGISTRATION',label:'Business registration certificate'},
  ...(['REGULAR','COMPOSITION'].includes(detail.gstRegistration)
   ?[{type:'GST_CERTIFICATE',label:'GST registration certificate'}]:[]),
 ];
 return requirements.map(entry=>{
  const matches=detail.documents.filter(d=>d.documentType===entry.type);
  return {...entry,uploaded:matches.length>0,verified:matches.some(d=>
   d.status==='VERIFIED'&&d.digestAvailable&&(!d.expiresAt||new Date(d.expiresAt)>new Date()))};
 });
};
const allowed=(value:Approval):readonly string[]=>({
 DRAFT:[],PENDING:['UNDER_REVIEW','APPROVED','REJECTED'],
 UNDER_REVIEW:['APPROVED','REJECTED'],REJECTED:['UNDER_REVIEW'],
 APPROVED:['SUSPENDED'],SUSPENDED:['UNDER_REVIEW']
})[value];
const date=(value:string|null)=>value?new Date(value).toLocaleString():'—';

export function SupplierPanel({currentAdminId}:{currentAdminId:string}){
 const api=useV21Api();
 const [status,setStatus]=useState<Approval|'ALL'>('PENDING');
 const [search,setSearch]=useState('');
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
 const [downloading,setDownloading]=useState<string|null>(null);
 const [lastRequestId,setLastRequestId]=useState('');
 const evidence=detail?requiredEvidence(detail):[];
 const stagingTestApproval=detail?.reviewPolicy?.stagingTestWithoutDocuments===true;
 const approvalReady=(stagingTestApproval||evidence.every(e=>e.verified))&&Boolean(detail?.contactEmail)&&Boolean(detail?.billingAddress)&&Boolean(detail?.owners.length);
 const filteredItems=items.filter(s=>[s.displayName,s.legalName,s.slug].join(' ').toLowerCase().includes(search.trim().toLowerCase()));
 const download=async(doc:Doc)=>{
  if(!doc.downloadPath||downloading)return;
  setDownloading(doc.id);setError('');
  try{
   if(!/^\/api\/v2\/media\/[0-9a-f-]{36}\?format=base64$/.test(doc.downloadPath))throw new Error('Invalid document reference');
   const result=await api.get<{base64:string;mimeType:string}>(doc.downloadPath);
   if(!['application/pdf','image/png','image/jpeg'].includes(result.data.mimeType)||typeof result.data.base64!=='string'||result.data.base64.length>14000000)throw new Error('Invalid document');
   const bytes=Uint8Array.from(atob(result.data.base64),c=>c.charCodeAt(0));
   const url=URL.createObjectURL(new Blob([bytes],{type:result.data.mimeType}));
   const anchor=document.createElement('a');anchor.href=url;anchor.download='verification-document.'+(result.data.mimeType==='application/pdf'?'pdf':result.data.mimeType==='image/png'?'png':'jpg');
   anchor.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000);
  }catch(failure){setError(message(failure));}finally{setDownloading(null);}
 };

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
 const self=detail?.owners.some(owner=>owner.userId===currentAdminId) ?? false;
 async function submitReview(event:FormEvent<HTMLFormElement>){
  event.preventDefault();if(!detail||!review||busy||review.reason.trim().length<8)return;
  setBusy(true);setError('');setInfo('');setLastRequestId('');
  try{
   const base='/api/v2/admin/suppliers/'+encodeURIComponent(detail.id);
   const path=review.type==='document'
    ?base+'/documents/'+encodeURIComponent(review.documentId||'')+'/review':base+'/review';
   await api.write('POST',path,{decision:review.decision,reason:review.reason.trim()});
   setReview(null);
   setInfo(stagingTestApproval&&review.type==='supplier'&&review.decision==='APPROVED'
    ?'Test approval saved on staging without document verification. This supplier is NOT KYC-verified. The exception is recorded in the audit log.'
    :'Review saved with an audit reason. No payment or supplier data was changed.');
   await Promise.all([load(true),loadDetail(detail.id)]);
  }catch(e){setError(message(e));if(e instanceof V21ApiError)setLastRequestId(e.requestId);}
  finally{setBusy(false);}
 }
 return <div className={selectedId?'grid items-start gap-6 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]':'space-y-6'}>
  <section className="v21-surface overflow-hidden rounded-[24px] border border-slate-200 bg-white shadow-sm">
   <div className="flex flex-wrap items-start justify-between gap-4 bg-gradient-to-br from-[#f6f9ff] via-white to-white px-6 py-7 sm:px-8">
    <div className="flex items-start gap-4">
     <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-[#e7effe] text-[#123a75]"><Building2 size={23}/></div>
     <div>
      <div className="mb-1 flex items-center gap-2"><span className="text-[11px] font-extrabold uppercase tracking-[0.12em] text-[#5275aa]">Marketplace / Compliance</span></div>
      <h2 className="text-2xl font-extrabold tracking-tight text-[#142e53]">Supplier verification</h2>
      <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-600">Review business credentials and document evidence before enabling marketplace access. Every decision is independently audited.</p>
     </div>
    </div>
    <button type="button" onClick={()=>void load(true)} disabled={loading} className="v21-outline-button"><RefreshCw size={16} className={loading?'animate-spin':''}/> Refresh queue</button>
   </div>
   <div className="grid gap-3 border-y border-slate-100 bg-white px-6 py-4 sm:grid-cols-3 sm:px-8">
    <div className="rounded-xl bg-[#f5f8fc] p-4"><p className="text-xs font-semibold text-slate-500">Applications loaded</p><p className="mt-1 text-2xl font-extrabold text-[#173860]">{items.length}</p></div>
    <div className="rounded-xl bg-amber-50 p-4"><p className="text-xs font-semibold text-amber-800">Awaiting review in this page</p><p className="mt-1 text-2xl font-extrabold text-amber-900">{items.filter(s=>s.approval==='PENDING'||s.approval==='UNDER_REVIEW').length}</p></div>
    <div className="rounded-xl bg-emerald-50 p-4"><p className="text-xs font-semibold text-emerald-800">Approved in this page</p><p className="mt-1 text-2xl font-extrabold text-emerald-900">{items.filter(s=>s.approval==='APPROVED').length}</p></div>
   </div>
   <div className="px-6 pb-6 pt-5 sm:px-8">
   <div className="flex flex-wrap items-end gap-3">
    <div className="min-w-[200px] flex-1">
     <label htmlFor="supplier-search" className="mb-2 block text-xs font-semibold text-slate-600">Search applications</label>
     <div className="relative"><Search aria-hidden="true" size={17} className="pointer-events-none absolute left-3.5 top-3.5 text-slate-400"/><input id="supplier-search" value={search} onChange={e=>setSearch(e.target.value)} placeholder="Business name or supplier ID" className="v21-input pl-10"/></div>
    </div>
    <div className="min-w-[185px]">
     <label htmlFor="supplier-state" className="mb-2 block text-xs font-semibold text-slate-600">Approval status</label>
     <select id="supplier-state" value={status} onChange={e=>setStatus(e.target.value as Approval|'ALL')} className="v21-input">
      <option value="ALL">All suppliers</option>
      {STATUSES.map(v=><option value={v} key={v}>{statusLabel(v)}</option>)}
     </select>
    </div>
   </div>
   {error&&!selectedId&&<div role="alert" className="mt-4 flex items-start gap-3 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-900"><AlertCircle className="mt-0.5 shrink-0" size={19}/><div><strong className="block">Action could not be completed</strong><p className="mt-1 leading-6">{error}</p>{lastRequestId&&<p className="mt-2 text-xs text-rose-700">Support reference: {lastRequestId}</p>}</div></div>}
   {info&&!selectedId&&<div role="status" className="mt-4 flex items-start gap-3 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900"><CheckCircle2 size={18}/>{info}</div>}
   {loading&&items.length===0?<p role="status" className="mt-6 text-sm text-slate-500">Loading supplier applications…</p>:
    <div className="mt-5 overflow-x-auto rounded-2xl border border-slate-200"><table className="w-full min-w-[560px] text-left text-sm">
     <thead><tr className="border-b border-slate-200 bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500"><th scope="col" className="px-5 py-4">Supplier</th><th scope="col" className="px-4 py-4">GST</th><th scope="col" className="px-4 py-4">Status</th><th scope="col" className="px-5 py-4 text-right">Action</th></tr></thead>
     <tbody>{filteredItems.map(s=><tr key={s.id} className={`border-b border-slate-100 transition hover:bg-[#f5f8fd] ${selectedId===s.id?'bg-[#eff5ff]':''}`}>
      <td className="px-5 py-4"><div className="font-bold text-[#173251]">{s.displayName}</div><div className="mt-1 text-xs text-slate-500">{s.legalName}</div><div className="mt-1 font-mono text-[10px] text-slate-400">{s.slug}</div></td>
      <td className="px-4 py-4"><span className="text-xs font-semibold text-slate-700">{statusLabel(s.gstRegistration)}</span></td>
      <td className="px-4 py-4"><span className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${statusColor(s.approval)}`}>{statusLabel(s.approval)}</span></td>
      <td className="px-5 py-4 text-right"><button type="button" className="v21-outline-button ml-auto" onClick={()=>{setSelectedId(s.id);setReview(null);}}>View details <ArrowRight size={16}/></button></td>
     </tr>)}</tbody>
    </table>{filteredItems.length===0&&!loading&&<p className="px-5 py-8 text-sm text-slate-500">{search?'No suppliers match this search.':'No suppliers match this approval status.'}</p>}
    {cursor&&<button type="button" disabled={loading} onClick={()=>void load(false,cursor)} className="mt-4 rounded-lg border px-4 py-2 text-sm font-semibold disabled:opacity-50">Load more</button>}
    </div>}
   </div>
  </section>

  {selectedId&&<section className="v21-surface scroll-mt-28 rounded-[24px] border border-slate-200 bg-white p-6 shadow-sm sm:p-8 xl:sticky xl:top-[106px] xl:max-h-[calc(100vh-125px)] xl:overflow-y-auto" aria-label="Selected supplier details">
   {detailLoading&&!detail?<p role="status">Loading verified supplier details…</p>:detail&&<>
    <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-100 pb-6">
     <div className="flex items-start gap-3">
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-[#e9f1ff] text-[#123a75]"><Building2 size={23}/></div>
      <div><p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">Application review</p><h3 className="mt-1 text-xl font-extrabold tracking-tight text-[#142e53]">{detail.displayName}</h3><p className="mt-1 text-sm text-slate-500">{detail.legalName} · {detail.slug}</p></div>
     </div>
     <div className="flex items-center gap-3"><span className={`rounded-full border px-3 py-1 text-xs font-bold ${statusColor(detail.approval)}`}>{statusLabel(detail.approval)}</span><button type="button" onClick={()=>{setSelectedId('');setDetail(null);setReview(null);setError('');}} className="v21-outline-button"><XCircle size={16}/>Close</button></div>
    </div>
    {stagingTestApproval&&<div role="status" className="mt-6 flex gap-3 rounded-2xl border border-orange-300 bg-orange-50 p-5 text-sm text-orange-950">
     <ShieldAlert size={21} className="mt-0.5 shrink-0"/>
     <div><strong className="block">Staging testing mode is active</strong><p className="mt-1 leading-6">You can approve a test supplier without uploaded documents. This approval is NOT evidence of KYC verification. Admin permissions, independent review, required business details and an audit reason still apply. Production verification is unchanged.</p></div>
    </div>}
    <div className={`mt-6 rounded-2xl border p-5 ${stagingTestApproval?'border-orange-200 bg-[#fffaf1]':approvalReady?'border-emerald-200 bg-emerald-50':'border-amber-200 bg-[#fffbeb]'}`} aria-label="Approval readiness">
     <div className="flex items-start gap-3">
      {approvalReady?<ShieldCheck className="mt-0.5 shrink-0 text-emerald-700" size={22}/>:<ShieldAlert className="mt-0.5 shrink-0 text-amber-800" size={22}/>}
      <div className="flex-1">
       <h4 className="font-extrabold text-[#173251]">{stagingTestApproval?'Document requirement waived for staging test':approvalReady?'Documents ready for independent review':'Approval requirements not yet complete'}</h4>
       <p className="mt-1 text-sm leading-6 text-slate-700">{stagingTestApproval?'Documents are optional for this temporary staging test; missing documents are still shown below. Do not represent this approval as verified.':approvalReady?'The required evidence is recorded as verified. Review the uploaded files and audit reason before granting access.':'Approval cannot proceed until every required document is uploaded and independently verified. The applicant can add missing evidence in the supplier app.'}</p>
       <div className="mt-4 grid gap-2 sm:grid-cols-2">
        {evidence.map(item=><div key={item.type} className="flex items-start gap-2 rounded-xl border border-black/5 bg-white/80 px-3 py-3">
         {item.verified?<CheckCircle2 className="mt-0.5 shrink-0 text-emerald-700" size={18}/>:item.uploaded?<FileWarning className="mt-0.5 shrink-0 text-amber-700" size={18}/>:<XCircle className="mt-0.5 shrink-0 text-rose-700" size={18}/>}
         <div><p className="text-sm font-semibold text-slate-800">{item.label}</p><p className="mt-0.5 text-xs text-slate-600">{item.verified?'Verified':item.uploaded?'Uploaded — awaiting verification':'Not uploaded by supplier'}</p></div>
        </div>)}
       </div>
      </div>
     </div>
    </div>
    <h4 className="mt-7 text-sm font-extrabold uppercase tracking-wide text-slate-700">Business details</h4>
    <dl className="mt-4 grid gap-3 rounded-2xl border border-slate-100 bg-slate-50/70 p-5 text-sm sm:grid-cols-2">
     <div><dt className="text-slate-500">Approval</dt><dd className="font-bold">{detail.approval}</dd></div>
     <div><dt className="text-slate-500">GST registration</dt><dd className="font-bold">{detail.gstRegistration}</dd></div>
     <div><dt className="text-slate-500">GSTIN supplied</dt><dd className="font-bold">{detail.gstin||'Not registered'}</dd></div>
     <div><dt className="text-slate-500">Contact email</dt><dd className="mt-1 font-bold">{detail.contactEmail||'Not provided'}</dd></div>
     <div><dt className="text-slate-500">Phone number</dt><dd className="mt-1 font-bold">{detail.contactPhone||'Not provided'}</dd></div>
     <div><dt className="text-slate-500">Verified on</dt><dd>{date(detail.verifiedAt)}</dd></div>
     <div><dt className="text-slate-500">Suspended on</dt><dd>{date(detail.suspendedAt)}</dd></div>
    </dl>
    <div className="mt-6">
     <h4 className="mb-3 font-extrabold text-[#173251]">Business ownership</h4>
     {detail.owners.map(o=><p key={o.userId} className="text-sm">{o.displayName} · {o.email||'No verified email'} · {o.active?'Active':'Pending approval'}</p>)}
    </div>
    <div className="mt-6">
     <div className="flex items-center gap-2 text-[#173251]"><ClipboardCheck size={20}/><h4 className="text-lg font-extrabold">Evidence checklist</h4></div>
     <p className="mt-2 flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-xs text-amber-900"><ShieldAlert size={16} className="shrink-0"/>Evidence is private. Download and inspect each document before recording a review decision. Downloads require your current reviewer session.</p>
     {detail.documents.length===0?<div className="mt-3 flex items-start gap-3 rounded-xl border border-dashed border-amber-300 bg-amber-50 p-5 text-sm text-amber-950"><FileWarning size={21} className="shrink-0"/>No documents have been uploaded. Ask the supplier to add the required files in their registration application. Approval is blocked until an independent reviewer verifies them.</div> :
      <ul className="mt-3 space-y-3">{detail.documents.map(d=><li key={d.id} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
       <div className="flex flex-wrap justify-between gap-3"><div>
        <p className="flex items-center gap-2 font-bold text-[#173251]"><FileCheck2 size={18}/>{statusLabel(d.documentType)} <span className={`rounded-full border px-2 py-0.5 text-[11px] ${statusColor(d.status)}`}>{statusLabel(d.status)}</span></p>
        <p className="text-xs text-slate-500">{d.mimeType} · {d.sizeBytes} bytes · Digest {d.digestAvailable?'recorded':'missing'} · {d.status}</p>
        {!self&&d.downloadPath&&<button type="button" disabled={downloading!==null} onClick={()=>void download(d)} className="mt-2 rounded-lg border px-3 py-2 text-xs font-bold">{downloading===d.id?'Downloading…':'Download private document'}</button>}
        {d.expiresAt&&<p className="text-xs text-slate-500">Expires: {date(d.expiresAt)}</p>}
        {d.reviewNote&&<p className="mt-2 text-sm text-slate-600">Review note: {d.reviewNote}</p>}
       </div>
       {!self&&['UPLOADED','PENDING','REVIEWED'].includes(d.status)&&
        <div className="flex gap-2"><button type="button" onClick={()=>setReview({type:'document',decision:'VERIFIED',documentId:d.id,reason:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Verify</button>
         <button type="button" onClick={()=>setReview({type:'document',decision:'REJECTED',documentId:d.id,reason:''})} className="rounded-lg border border-rose-200 px-3 py-2 text-xs font-bold text-rose-700">Reject</button></div>}
       </div>
      </li>)}</ul>}
    </div>
    {self?<p className="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">You are a member of this supplier. Independent review is required.</p>:
     <div className="mt-7 rounded-2xl border border-slate-200 bg-[#f8fafd] p-5">
      <h4 className="font-extrabold text-[#173251]">Decision and next steps</h4>
      <p className="mt-1 text-sm text-slate-600">Choose a permitted transition. {stagingTestApproval?'Staging test approval skips only document verification.':'Approval requires independently verified evidence.'} A written audit reason is always mandatory.</p>
      <div className="mt-4 flex flex-wrap gap-2">
       {allowed(detail.approval).map(decision=>{
        const disabled=decision==='APPROVED'&&!approvalReady;
        return <button type="button" key={decision} disabled={disabled} title={disabled?'Verify all required evidence before approval':undefined}
         onClick={()=>{setError('');setReview({type:'supplier',decision,reason:''});}}
         className={`v21-outline-button ${decision==='APPROVED'?'border-emerald-300 text-emerald-800':''} disabled:cursor-not-allowed disabled:opacity-50`}>{decision==='APPROVED'&&stagingTestApproval?'Approve (test only)':statusLabel(decision)}</button>;
       })}
      </div>
      {!approvalReady&&allowed(detail.approval).includes('APPROVED')&&<p className="mt-3 flex items-center gap-2 text-xs font-semibold text-amber-800"><ShieldAlert size={15}/> Approve is disabled until all required evidence is verified.</p>}
     </div>}
    {error&&<div role="alert" className="mt-6 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-900"><div className="flex items-start gap-3"><AlertCircle size={19} className="mt-0.5 shrink-0"/><div><p className="font-extrabold">Review was not saved</p><p className="mt-1 leading-6">{error}</p>{lastRequestId&&<p className="mt-2 text-xs text-rose-700">Support reference: {lastRequestId}</p>}</div></div></div>}
    {info&&<div role="status" className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900"><CheckCircle2 size={18} className="mr-2 inline"/> {info}</div>}
    {review&&<form onSubmit={e=>void submitReview(e)} className="mt-6 rounded-2xl border border-[#b8ceee] bg-[#f4f8ff] p-6">
     <p className="font-extrabold text-[#163765]">{review.type==='supplier'?'Supplier':'Document'} decision: {statusLabel(review.decision)}</p>
     <p className="mt-2 text-sm text-slate-600">{review.type==='supplier'&&review.decision==='APPROVED'&&stagingTestApproval?'Staging testing mode: your approval will bypass document checks and be flagged as unverified in the audit log.':'This action will be recorded in the audit log. Verify the business evidence before confirming.'}</p>
     <label htmlFor="review-reason" className="mt-4 block text-sm font-semibold">Mandatory audit reason (8–400 characters)</label>
     <textarea id="review-reason" value={review.reason} onChange={e=>setReview({...review,reason:e.target.value})} rows={3} maxLength={400} minLength={8} required placeholder="Explain the evidence reviewed and the reason for this decision…" className="v21-input mt-2 min-h-[110px] w-full resize-y p-3 text-sm"/>
     <div className="mt-4 flex flex-wrap gap-3"><button type="submit" disabled={busy||review.reason.trim().length<8||(review.type==='supplier'&&review.decision==='APPROVED'&&!approvalReady)} className="v21-primary-button disabled:opacity-50">{busy?'Saving review…':'Confirm reviewed decision'}</button>
      <button type="button" onClick={()=>setReview(null)} className="v21-outline-button">Cancel</button></div>
    </form>}
   </>}
  </section>}
 </div>;
}
