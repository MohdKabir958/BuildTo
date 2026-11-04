import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Landmark,RefreshCw,ShieldCheck} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Refund={id:string;orderId:string;returnRequestId:string|null;status:string;currency:'INR';amountPaise:string;
 providerRefundId:string|null;customerBankCredit:'NOT_VERIFIED';createdAt:string};
type Beneficiary={id:string;supplierId:string;supplierName:string;maskedBankAccount:string|null;
 active:boolean;holderName:string|null;ifsc:string|null;registeredById:string|null;approvedById:string|null;bankStatementVerifiedByApi:false};
type Page<T>={items:T[];nextCursor:string|null};
type Payout={id:string;settlementId:string;supplierId:string;status:string;amountPaise:string;currency:'INR';
 providerPayoutId:string|null;maskedBankAccount:string|null;payoutExecutionByBuildtoApi:false;payoutStatusMeaning:string};
type Report={payouts:{id:string;bankStatementAttested:boolean}[];missingBankAttestation:number;
 bankStatementAPIReconciled:false;payoutExecutionEnabledByApi:false};
type Kind='requestRefund'|'approveRefund'|'reconcileRefund'|'registerBeneficiary'|'approveBeneficiary'|'reservePayout'|'reconcilePayout'|'attestPayout';
type Action={kind:Kind;id:string;description:string};
const field='w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm';
const endpoint='/api/v2/admin/finance/';
function money(pa:string){
 if(!/^(0|[1-9]\d*)$/.test(pa))return '—';
 const value=BigInt(pa);
 return '₹'+(value/100n).toLocaleString('en-IN')+'.'+(value%100n).toString().padStart(2,'0');
}
function msg(error:unknown){
 if(error instanceof V21ApiError){
  if(error.status===403)return 'Independent finance approval required. The reviewer cannot be the requester or related supplier staff.';
  if(error.status===409)return 'Bank, return or payment evidence does not match. Refresh and investigate; no success is assumed.';
  return error.message;
 }
 return 'Financial request could not be confirmed. Check records before retrying.';
}
function ensureEvidence(action:Action,a:string,b:string){
 const first=a.trim(),second=b.trim();
 switch(action.kind){
 case 'requestRefund': return /^[0-9a-f-]{36}$/i.test(action.id);
 case 'approveRefund': case 'approveBeneficiary':return true;
 case 'reconcileRefund':return /^rfnd_[A-Za-z0-9]{8,60}$/.test(first);
 case 'registerBeneficiary':return /^fa_[A-Za-z0-9]{8,60}$/.test(first)&&/^fav_[A-Za-z0-9]{8,60}$/.test(second);
 case 'reservePayout':return /^[0-9a-f-]{36}$/i.test(first);
 case 'reconcilePayout':return /^pout_[A-Za-z0-9]{8,60}$/.test(first);
 case 'attestPayout':return /^[A-Za-z0-9][A-Za-z0-9_./:-]{11,119}$/.test(first)&&/^[A-Za-z0-9_-]{8,60}$/.test(second);
 }
}
const key=()=>crypto.randomUUID();

export function RefundPayoutPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<'refunds'|'beneficiaries'|'payouts'>('refunds');
 const [refunds,setRefunds]=useState<Refund[]>([]);
 const [beneficiaries,setBeneficiaries]=useState<Beneficiary[]>([]);
 const [cursor,setCursor]=useState<string|null>(null);
 const [payouts,setPayouts]=useState<Payout[]>([]);
 const [report,setReport]=useState<Report|null>(null);
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [action,setAction]=useState<Action|null>(null);
 const [a,setA]=useState('');
 const [b,setB]=useState('');
 const [returnId,setReturnId]=useState('');
 const [supplierId,setSupplierId]=useState('');
 const [settlementId,setSettlementId]=useState('');
 const open=(kind:Kind,id:string,description:string)=>{setA('');setB('');setAction({kind,id,description});setError('');setNotice('');};
 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [r,ben,p,rep]=await Promise.all([
    api.get<Refund[]>(endpoint+'refunds',signal),
    api.get<Page<Beneficiary>>(endpoint+'beneficiaries?limit=25',signal),
    api.get<Payout[]>(endpoint+'payouts',signal),
    api.get<Report>(endpoint+'payouts-reconciliation',signal)
   ]);
   if(!Array.isArray(r.data)||!Array.isArray(ben.data.items)||!Array.isArray(p.data)||!Array.isArray(rep.data.payouts))
    throw new Error('Unrecognized finance response');
   if(!signal?.aborted){setRefunds(r.data);setBeneficiaries(ben.data.items);setCursor(ben.data.nextCursor);
    setPayouts(p.data);setReport(rep.data);}
  }catch(e){if(!signal?.aborted)setError(msg(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);
 async function nextBeneficiaries(){
  if(!cursor||busy)return;setBusy(true);
  try{const page=await api.get<Page<Beneficiary>>(endpoint+'beneficiaries?limit=25&cursor='+encodeURIComponent(cursor));
   if(!Array.isArray(page.data.items))throw new Error('Invalid beneficiary page');
   setBeneficiaries(x=>[...x,...page.data.items]);setCursor(page.data.nextCursor);
  }catch(e){setError(msg(e));}finally{setBusy(false);}
 }
 async function confirm(event:FormEvent<HTMLFormElement>){
  event.preventDefault();
  if(!action||busy||!ensureEvidence(action,a,b))return;
  setBusy(true);setError('');setNotice('');
  try{
   const id=encodeURIComponent(action.id);
   switch(action.kind){
   case 'requestRefund':
    await api.write('POST',endpoint+'refunds/requests/'+id,{}, {idempotencyKey:key()});break;
   case 'approveRefund':
    await api.write('POST',endpoint+'refunds/'+id+'/approve',{});break;
   case 'reconcileRefund':
    await api.write('POST',endpoint+'refunds/'+id+'/reconcile',{providerRefundId:a.trim()});break;
   case 'registerBeneficiary':
    await api.write('POST',endpoint+'suppliers/'+id+'/beneficiaries',{fundAccountId:a.trim(),validationId:b.trim()});break;
   case 'approveBeneficiary':
    await api.write('POST',endpoint+'beneficiaries/'+id+'/approve',{});break;
   case 'reservePayout':
    await api.write('POST',endpoint+'settlements/'+id+'/payout-intent',{payoutAccountId:a.trim()},{idempotencyKey:key()});break;
   case 'reconcilePayout':
    await api.write('POST',endpoint+'payouts/'+id+'/reconcile',{providerPayoutId:a.trim()});break;
   case 'attestPayout':
    await api.write('POST',endpoint+'payouts/'+id+'/bank-attest',{bankStatementReference:a.trim(),providerUtr:b.trim()});break;
   }
   setAction(null);
   setNotice('Request processed by the server. Review the refreshed state; no bank transfer was initiated by BuildTo.');
   await load();
  }catch(e){setError(msg(e));}
  finally{setBusy(false);}
 }
 const attested=new Set((report?.payouts??[]).filter(x=>x.bankStatementAttested).map(x=>x.id));
 return <div className="space-y-5">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap items-start justify-between gap-3">
    <div className="flex items-center gap-3"><Landmark size={22} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Refunds, beneficiaries and payout evidence</h2>
     <p className="mt-1 text-sm text-slate-500">Separate reviewer controls; external provider evidence only.</p></div></div>
    <button type="button" disabled={loading||busy} onClick={()=>void load()} className="rounded-lg border px-3 py-2 text-sm font-bold disabled:opacity-50"><RefreshCw size={16} className="mr-1 inline"/>Refresh</button>
   </div>
   <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-950" role="note"><ShieldCheck size={17} className="mr-2 inline"/>
    BuildTo does not execute a Razorpay refund or a RazorpayX payout from this screen.
    Provider processed does not prove customer bank credit; independent bank statement verification is manual.
   </p>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-800">{error}</p>}
   {notice&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-900">{notice}</p>}
   <div role="tablist" aria-label="Refunds and payouts" className="mt-5 flex flex-wrap gap-2">
    {(['refunds','beneficiaries','payouts'] as const).map(k=><button key={k} type="button" role="tab" aria-selected={tab===k} onClick={()=>{setTab(k);setAction(null);}}
      className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===k?'bg-[#174C86] text-white':'border text-slate-700')}>{k==='refunds'?'Refund requests':k==='beneficiaries'?'Bank beneficiaries':'Payout intents'}</button>)}
   </div>
   {loading?<p role="status" className="mt-6 text-sm">Loading server-authoritative finance records…</p>:<>
    {tab==='refunds'&&<section className="mt-5 space-y-3">
     <div className="rounded-xl border p-4"><p className="text-sm font-semibold">Request a full refund only after a received return, issued supplier credit note and verified online payment.</p>
      <form onSubmit={e=>{e.preventDefault();if(returnId.trim())open('requestRefund',returnId.trim(),'Reserve refund request (no provider POST)');}} className="mt-3 flex flex-wrap gap-2">
       <label className="min-w-[220px] flex-1 text-xs font-bold">Received return UUID<input value={returnId} onChange={e=>setReturnId(e.target.value)} className={field+' mt-1'} required/></label>
       <button className="self-end rounded-lg border px-4 py-2 text-sm font-bold" type="submit">Review refund request</button>
      </form></div>
     {refunds.length===0?<p className="py-4 text-sm text-slate-500">No outstanding financial refund requests.</p>:refunds.map(r=><article key={r.id} className="rounded-xl border border-slate-200 p-4">
      <div className="flex flex-wrap justify-between gap-2 text-sm"><b>{money(r.amountPaise)} · {r.status}</b><span className="text-xs text-slate-500">Bank credit: NOT VERIFIED</span></div>
      <p className="mt-2 break-all text-xs text-slate-500">Refund {r.id} · Return {r.returnRequestId||'—'}</p>
      <div className="mt-3 flex flex-wrap gap-2">{r.status==='REQUESTED'&&<button className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>open('approveRefund',r.id,'Independent approval of requested refund')}>Approve independently</button>}
       {['APPROVED','PROCESSING'].includes(r.status)&&<button className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>open('reconcileRefund',r.id,'Look up a manually initiated Razorpay refund')}>Reconcile provider status</button>}</div>
     </article>)}
    </section>}
    {tab==='beneficiaries'&&<section className="mt-5 space-y-3">
     <form onSubmit={e=>{e.preventDefault();open('registerBeneficiary',supplierId.trim(),'Validate externally registered supplier beneficiary');}} className="rounded-xl border p-4">
      <label className="text-xs font-bold">Approved supplier UUID<input className={field+' mt-1'} value={supplierId} onChange={e=>setSupplierId(e.target.value)} required/></label>
      <button className="mt-3 rounded-lg border px-4 py-2 text-sm font-bold">Review beneficiary registration</button>
      <p className="mt-2 text-xs text-slate-500">Only RazorpayX fund-account and validation IDs. Never paste bank account numbers.</p>
     </form>
     {beneficiaries.length===0?<p className="py-4 text-sm text-slate-500">No beneficiary records.</p>:beneficiaries.map(b=><article key={b.id} className="flex flex-wrap justify-between gap-3 rounded-xl border p-4">
      <div><b className="text-sm">{b.supplierName} · {b.maskedBankAccount||'No masked account'}</b>
       <p className="mt-1 text-xs text-slate-500">{b.holderName} · {b.ifsc} · {b.active?'Verified active':'Pending independent review'}</p></div>
      {!b.active&&<button className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>open('approveBeneficiary',b.id,'Second finance administrator revalidates beneficiary with provider')}>Approve bank beneficiary</button>}
     </article>)}
     {cursor&&<button disabled={busy} type="button" onClick={()=>void nextBeneficiaries()} className="rounded-lg border px-3 py-2 text-xs font-bold">Load more beneficiaries</button>}
    </section>}
    {tab==='payouts'&&<section className="mt-5 space-y-3">
     <p className="rounded-xl bg-slate-50 p-3 text-xs font-semibold">Payout execution via BuildTo API: DISABLED · Missing independent bank attestations: {report?.missingBankAttestation??'—'}</p>
     <form className="rounded-xl border p-4" onSubmit={e=>{e.preventDefault();open('reservePayout',settlementId.trim(),'Reserve payout intent only (no transfer)');}}>
      <label className="text-xs font-bold">Approved settlement UUID<input className={field+' mt-1'} value={settlementId} onChange={e=>setSettlementId(e.target.value)} required/></label>
      <button className="mt-3 rounded-lg border px-3 py-2 text-sm font-bold">Review payout intent</button>
     </form>
     {payouts.length===0?<p className="py-4 text-sm text-slate-500">No payout intents awaiting review.</p>:payouts.map(p=><article key={p.id} className="rounded-xl border p-4">
      <div className="flex flex-wrap justify-between gap-2"><b className="text-sm">{money(p.amountPaise)} · {p.status}</b><span className="text-xs text-slate-500">{p.maskedBankAccount||'Masked account unavailable'}</span></div>
      <p className="mt-2 text-xs text-slate-500">{p.payoutStatusMeaning} · {attested.has(p.id)?'Bank debit human-attested':'Bank debit NOT attested'}</p>
      <div className="mt-3 flex flex-wrap gap-2">{['PENDING','PROCESSING'].includes(p.status)&&<button onClick={()=>open('reconcilePayout',p.id,'Read-only RazorpayX payout lookup')} className="rounded-lg border px-3 py-2 text-xs font-bold">Reconcile provider</button>}
       {p.status==='SUCCEEDED'&&!attested.has(p.id)&&<button onClick={()=>open('attestPayout',p.id,'Third finance reviewer confirms statement debit against provider UTR')} className="rounded-lg border px-3 py-2 text-xs font-bold">Attest bank debit</button>}
      </div>
     </article>)}
    </section>}
   </>}
  </section>
  {action&&<section aria-label="Confirm finance evidence" role="dialog" aria-modal="true" className="rounded-2xl border-2 border-[#174C86] bg-white p-6 shadow-lg">
   <h3 className="font-extrabold">Confirm finance evidence</h3><p className="mt-2 text-sm text-slate-600">{action.description}</p>
   <p className="mt-2 break-all text-xs text-slate-500">Record: {action.id}</p>
   <form onSubmit={e=>void confirm(e)} className="mt-4 space-y-3">
    {action.kind==='registerBeneficiary'&&<><label className="block text-xs font-bold">RazorpayX fund account ID<input className={field+' mt-1'} value={a} onChange={e=>setA(e.target.value)}/></label>
     <label className="block text-xs font-bold">RazorpayX validation ID<input className={field+' mt-1'} value={b} onChange={e=>setB(e.target.value)}/></label></>}
    {action.kind==='reconcileRefund'&&<label className="block text-xs font-bold">Provider refund ID<input className={field+' mt-1'} value={a} onChange={e=>setA(e.target.value)} placeholder="rfnd_…"/></label>}
    {action.kind==='reconcilePayout'&&<label className="block text-xs font-bold">Provider payout ID<input className={field+' mt-1'} value={a} onChange={e=>setA(e.target.value)} placeholder="pout_…"/></label>}
    {action.kind==='reservePayout'&&<label className="block text-xs font-bold">Approved beneficiary UUID<input className={field+' mt-1'} value={a} onChange={e=>setA(e.target.value)}/></label>}
    {action.kind==='attestPayout'&&<><label className="block text-xs font-bold">Independent bank statement reference<input className={field+' mt-1'} value={a} onChange={e=>setA(e.target.value)}/></label>
     <label className="block text-xs font-bold">Provider-confirmed UTR<input className={field+' mt-1'} value={b} onChange={e=>setB(e.target.value)}/></label></>}
    <div className="flex gap-2"><button type="button" disabled={busy} className="rounded-lg border px-4 py-2 text-sm" onClick={()=>setAction(null)}>Cancel</button>
     <button type="submit" disabled={busy||!ensureEvidence(action,a,b)} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-40">Confirm reviewed action</button></div>
   </form>
  </section>}
 </div>;
}
