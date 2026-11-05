import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Landmark,RefreshCw,ShieldCheck} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Candidate={id:string;supplierId:string;supplierOrderId:string;status:string;createdAt:string;supplierTotalPaise:string;
 creditNote:null|{id:string;kind:string;status:string;totalPaise:string;originalInvoiceLinked:boolean};fullRefundEligible:false;eligibilityNote:string};
type Refund={id:string;orderId:string;returnRequestId:string|null;amountPaise:string;status:string;providerRefundId:string|null;
 approvalAt:string|null;providerCompletedAt:string|null;customerBankCredit:'NOT_VERIFIED';createdAt:string;reason:string};
type Beneficiary={id:string;supplierId:string;maskedBankAccount:string|null;active:boolean;validated:boolean;independentlyApproved:boolean;createdAt:string};
type Payout={id:string;settlementId:string;supplierId:string;amountPaise:string;status:string;providerPayoutId:string|null;
 externalReferenceId:string;maskedBankAccount:string|null;settlementStatus:string;payoutStatusMeaning:string};
type Report={payouts:{id:string;supplierId:string;status:string;amountPaise:string;providerPayoutId:string|null;bankStatementAttested:boolean}[];
 missingBankAttestation:number;bankStatementAPIReconciled:false;payoutExecutionEnabledByApi:false};
type Supplier={id:string;displayName:string;approval:string;suspended:boolean};
type Settlement={id:string;settlementKey:string;status:string;payablePaise:string};
type SupplierFinance={orders:unknown[];settlements:Settlement[]};
type Action={type:'refundRequest'|'refundApprove'|'refundReconcile'|'bankRegister'|'bankApprove'|'payoutIntent'|'payoutReconcile'|'bankAttest';
 id:string;label:string;providerRef:string;secondRef:string;selectedBank:string};
const errors=(e:unknown)=>e instanceof V21ApiError?
 e.status===403?'A different authorized FINANCE reviewer is required for this action.':
 e.status===409?'Evidence or state changed. Refresh; independent verification requirements still apply.':
 e.status===503?'Required provider GET-only verification is unavailable. No money was sent.':e.message:
 'The financial workflow could not be completed. No success is assumed.';
const money=(paise:string)=>{
 if(!/^(0|[1-9]\d*)$/.test(paise))return '—';
 const n=BigInt(paise);
 return '₹'+(n/100n).toLocaleString('en-IN')+'.'+(n%100n).toString().padStart(2,'0');
};
const cls='w-full rounded-lg border border-slate-300 bg-white p-2 text-sm';
export function RefundPayoutPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<'refunds'|'payouts'|'beneficiaries'>('refunds');
 const [refunds,setRefunds]=useState<Refund[]>([]);
 const [candidates,setCandidates]=useState<Candidate[]>([]);
 const [candidateCursor,setCandidateCursor]=useState<string|null>(null);
 const [payouts,setPayouts]=useState<Payout[]>([]);
 const [report,setReport]=useState<Report|null>(null);
 const [suppliers,setSuppliers]=useState<Supplier[]>([]);
 const [supplier,setSupplier]=useState('');
 const [banks,setBanks]=useState<Beneficiary[]>([]);
 const [settlements,setSettlements]=useState<Settlement[]>([]);
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [action,setAction]=useState<Action|null>(null);
 const [selectedBank,setSelectedBank]=useState('');
 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [r,c,p,reportResponse,s]=await Promise.all([
    api.get<Refund[]>('/api/v2/admin/finance/refunds',signal),
    api.get<{items:Candidate[];nextCursor:string|null}>('/api/v2/admin/finance/refund-candidates?limit=25',signal),
    api.get<Payout[]>('/api/v2/admin/finance/payouts',signal),
    api.get<Report>('/api/v2/admin/finance/payouts-reconciliation',signal),
    api.get<{items:Supplier[];nextCursor:string|null}>('/api/v2/admin/finance/suppliers?limit=50',signal)
   ]);
   if(!Array.isArray(r.data)||!Array.isArray(c.data.items)||!Array.isArray(p.data)||!Array.isArray(reportResponse.data.payouts)||!Array.isArray(s.data.items))
    throw new Error('Invalid financial data');
   if(!signal?.aborted){
    setRefunds(r.data);setCandidates(c.data.items);setCandidateCursor(c.data.nextCursor);
    setPayouts(p.data);setReport(reportResponse.data);setSuppliers(s.data.items);
   }
  }catch(e){if(!signal?.aborted)setError(errors(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 const loadSupplier=useCallback(async(id:string,signal?:AbortSignal)=>{
  if(!id){setBanks([]);setSettlements([]);return;}
  try{
   const [b,f]=await Promise.all([
    api.get<Beneficiary[]>('/api/v2/admin/finance/suppliers/'+encodeURIComponent(id)+'/beneficiaries',signal),
    api.get<SupplierFinance>('/api/v2/admin/finance/suppliers/'+encodeURIComponent(id),signal)
   ]);
   if(!Array.isArray(b.data)||!Array.isArray(f.data.settlements))throw new Error('Invalid supplier finance response');
   if(!signal?.aborted){setBanks(b.data);setSettlements(f.data.settlements);}
  }catch(e){if(!signal?.aborted)setError(errors(e));}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);
 useEffect(()=>{const c=new AbortController();void loadSupplier(supplier,c.signal);return ()=>c.abort();},[supplier,loadSupplier]);
 async function perform(event:FormEvent<HTMLFormElement>){
  event.preventDefault();if(!action||busy)return;
  const a=action;const ref=a.providerRef.trim(),secondary=a.secondRef.trim();
  let call:()=>Promise<unknown>;
  switch(a.type){
   case 'refundRequest':call=()=>api.write('POST','/api/v2/admin/finance/refunds/requests/'+a.id,{},{
    idempotencyKey:crypto.randomUUID()});break;
   case 'refundApprove':call=()=>api.write('POST','/api/v2/admin/finance/refunds/'+a.id+'/approve',{});break;
   case 'refundReconcile':call=()=>api.write('POST','/api/v2/admin/finance/refunds/'+a.id+'/reconcile',{providerRefundId:ref});break;
   case 'bankRegister':call=()=>api.write('POST','/api/v2/admin/finance/suppliers/'+a.id+'/beneficiaries',{
    fundAccountId:ref,validationId:secondary});break;
   case 'bankApprove':call=()=>api.write('POST','/api/v2/admin/finance/beneficiaries/'+a.id+'/approve',{});break;
   case 'payoutIntent':call=()=>api.write('POST','/api/v2/admin/finance/settlements/'+a.id+'/payout-intent',{
    payoutAccountId:a.selectedBank},{idempotencyKey:crypto.randomUUID()});break;
   case 'payoutReconcile':call=()=>api.write('POST','/api/v2/admin/finance/payouts/'+a.id+'/reconcile',{providerPayoutId:ref});break;
   case 'bankAttest':call=()=>api.write('POST','/api/v2/admin/finance/payouts/'+a.id+'/bank-attest',{
    bankStatementReference:ref,providerUtr:secondary});break;
  }
  setBusy(true);setError('');setNotice('');
  try{
   await call();setAction(null);await load();if(supplier)await loadSupplier(supplier);
   setNotice('Evidence review recorded. No outgoing provider payment request was made by BuildTo; independently verify the returned state.');
  }catch(e){setError(errors(e));}finally{setBusy(false);}
 }
 const prompts:Record<Action['type'],string>={
  refundRequest:'Reserve full refund request (provider POST disabled)',
  refundApprove:'Independent second finance approval (no refund POST)',
  refundReconcile:'Read-only Razorpay refund status reconciliation',
  bankRegister:'Register validated provider beneficiary reference (GET-only checks)',
  bankApprove:'Independent masked bank beneficiary approval',
  payoutIntent:'Reserve a payout intent — NOT a transfer',
  payoutReconcile:'GET-only RazorpayX payout reconciliation',
  bankAttest:'Independent bank statement/UTR manual attestation'
 };
 const requiresRef=action&&['refundReconcile','bankRegister','payoutReconcile','bankAttest'].includes(action.type);
 const requiresSecond=action&&['bankRegister','bankAttest'].includes(action.type);
 const valid=Boolean(action)&&(!requiresRef||action!.providerRef.trim().length>=8)&&(!requiresSecond||action!.secondRef.trim().length>=8)&&
  (action?.type!=='payoutIntent'||Boolean(action.selectedBank));
 return <div className="space-y-5">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex gap-3"><Landmark size={23} className="shrink-0 text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Refund and payout evidence</h2>
    <p className="mt-1 text-sm text-slate-500">Manual maker/checker flow. Provider lookup verifies status but does not send money.</p></div></div>
   <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
    <ShieldCheck size={16} className="mr-2 inline"/>Refund SUCCEEDED means provider processed, not customer bank credit.
    Payout SUCCEEDED means provider processed, not independently verified bank debit.
    BuildTo has no automatic refund or payout execution endpoint.
   </p>
   <div className="mt-5 flex flex-wrap items-center justify-between gap-3"><div className="flex flex-wrap gap-2" role="tablist" aria-label="Finance evidence sections">
    {(['refunds','payouts','beneficiaries'] as const).map(t=><button key={t} type="button" role="tab" aria-selected={tab===t} onClick={()=>{setTab(t);setAction(null);}}
      className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===t?'bg-[#174C86] text-white':'border')}>{t==='beneficiaries'?'Beneficiaries':t==='payouts'?'Payouts':'Refunds'}</button>)}</div>
    <button type="button" disabled={loading} onClick={()=>void load()} className="rounded-lg border px-3 py-2 text-sm font-semibold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button></div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
   {notice&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{notice}</p>}
   {loading?<p role="status" className="mt-5">Reading finance evidence…</p>:<>
    {tab==='refunds'&&<>
     <h3 className="mt-6 font-bold">Received returns — preliminary candidates</h3>
     <p className="mt-2 text-xs text-slate-500">Candidate list is NOT eligibility. Only full returned orders with valid credit note, verified Razorpay capture and no settlement may pass the backend.</p>
     <div className="mt-3 space-y-3">{candidates.map(c=><article key={c.id} className="flex flex-wrap justify-between gap-3 rounded-xl border p-4 text-sm">
      <div><b>Return {c.id.slice(0,8)}…</b> · {money(c.supplierTotalPaise)}
       <p className="mt-1 text-xs text-slate-500">Credit note: {c.creditNote?c.creditNote.status+' / '+c.creditNote.kind:'Not issued'} · Original invoice link {c.creditNote?.originalInvoiceLinked?'present':'missing'}</p></div>
      <button type="button" onClick={()=>setAction({type:'refundRequest',id:c.id,label:'Return '+c.id,providerRef:'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Request verified full refund</button>
     </article>)}{candidates.length===0&&<p className="text-sm text-slate-500">No received return candidates in this page.</p>}</div>
     {candidateCursor&&<p className="mt-2 text-xs text-slate-500">More candidates exist; page navigation will be added before large-volume operations.</p>}
     <h3 className="mt-6 font-bold">Refund requests and provider verification</h3>
     <div className="mt-3 space-y-3">{refunds.map(r=><article key={r.id} className="rounded-xl border p-4 text-sm"><div className="flex flex-wrap items-center justify-between gap-3"><div>
      <b>{r.status} · {money(r.amountPaise)}</b>
      <p className="mt-1 text-xs text-slate-500">Refund {r.id.slice(0,8)}… · Razorpay {r.providerRefundId||'not linked'}</p>
      <p className="mt-1 text-xs text-amber-900">Bank credit: NOT VERIFIED {r.providerCompletedAt?'· provider processed '+new Date(r.providerCompletedAt).toLocaleString():''}</p></div>
      <div className="flex gap-2">{r.status==='REQUESTED'&&<button type="button" onClick={()=>setAction({type:'refundApprove',id:r.id,label:'Refund '+r.id,providerRef:'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Second finance approval</button>}
       {['APPROVED','PROCESSING','SUCCEEDED'].includes(r.status)&&<button type="button" onClick={()=>setAction({type:'refundReconcile',id:r.id,label:'Refund '+r.id,providerRef:r.providerRefundId||'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Check provider status</button>}</div></div>
     </article>)}{refunds.length===0&&<p className="text-sm text-slate-500">No refund requests awaiting finance review.</p>}</div>
     <p className="mt-3 text-xs text-slate-500">Refund queue is bounded to 100 records. Do not infer total count from the visible page.</p>
    </>}
    {tab==='payouts'&&<>
     <div className="mt-5 rounded-xl bg-slate-50 p-4 text-sm">
      <b>{report?.missingBankAttestation??0}</b> provider-processed payouts in the latest report lack independent manual bank attestation.
      <p className="mt-1 text-xs text-slate-500">Bank statement API reconciliation: disabled. Automatic payout execution: disabled.</p>
     </div>
     <div className="mt-4 space-y-3">{payouts.map(p=><article key={p.id} className="rounded-xl border p-4 text-sm"><div className="flex flex-wrap justify-between gap-3"><div>
      <b>{p.status} · {money(p.amountPaise)}</b><p className="mt-1 text-xs text-slate-500">Supplier {p.supplierId.slice(0,8)}… · {p.maskedBankAccount||'No masked destination'} · {p.payoutStatusMeaning}</p>
      <p className="mt-1 text-xs text-slate-500">Provider payout: {p.providerPayoutId||'not linked'} · bank attested: {report?.payouts.find(x=>x.id===p.id)?.bankStatementAttested?'YES':'NO'}</p></div>
      <div className="flex flex-wrap gap-2">{['PENDING','PROCESSING'].includes(p.status)&&<button type="button" onClick={()=>setAction({type:'payoutReconcile',id:p.id,label:'Payout '+p.id,providerRef:p.providerPayoutId||'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">GET provider status</button>}
       {p.status==='SUCCEEDED'&&!report?.payouts.find(x=>x.id===p.id)?.bankStatementAttested&&<button type="button" onClick={()=>setAction({type:'bankAttest',id:p.id,label:'Payout '+p.id,providerRef:'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Independent bank attestation</button>}</div></div>
     </article>)}{payouts.length===0&&<p className="text-sm text-slate-500">No payout intents in the current review queue.</p>}</div>
     <p className="mt-3 text-xs text-slate-500">This queue shows up to 100 pending/processing/failed payouts; provider SUCCEEDED records may appear only in reconciliation report.</p>
    </>}
    {tab==='beneficiaries'&&<>
     <label className="mt-5 block text-sm font-bold">Supplier<select className={cls+' mt-2'} value={supplier} onChange={e=>setSupplier(e.target.value)}>
      <option value="">Select supplier</option>{suppliers.map(s=><option value={s.id} key={s.id}>{s.displayName} · {s.approval}</option>)}
     </select></label>
     {supplier&&<>
      <button type="button" onClick={()=>setAction({type:'bankRegister',id:supplier,label:'Validate bank beneficiary for selected supplier',providerRef:'',secondRef:'',selectedBank:''})} className="mt-4 rounded-lg border px-4 py-2 text-sm font-semibold">Register provider-validated beneficiary</button>
      <h3 className="mt-5 font-bold">Masked verified beneficiary records</h3>
      <div className="mt-3 space-y-3">{banks.map(b=><article key={b.id} className="flex flex-wrap justify-between gap-3 rounded-xl border p-4 text-sm"><div><b>{b.maskedBankAccount||'Masked bank destination not available'}</b>
       <p className="mt-1 text-xs text-slate-500">{b.active?'Active':'Inactive'} · provider validated: {b.validated?'yes':'no'} · separate reviewer approved: {b.independentlyApproved?'yes':'no'}</p></div>
       {!b.active&&<button type="button" onClick={()=>setAction({type:'bankApprove',id:b.id,label:'Beneficiary '+b.id,providerRef:'',secondRef:'',selectedBank:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Second reviewer approve</button>}
      </article>)}{banks.length===0&&<p className="text-sm text-slate-500">No approved provider fund account on record.</p>}</div>
      <h3 className="mt-6 font-bold">Create payout intent (not a transfer)</h3>
      <label className="mt-2 block text-sm font-semibold">Independently approved destination<select className={cls+' mt-1'} value={selectedBank} onChange={e=>setSelectedBank(e.target.value)}>
       <option value="">Select approved bank</option>{banks.filter(x=>x.active&&x.validated&&x.independentlyApproved).map(x=><option key={x.id} value={x.id}>{x.maskedBankAccount}</option>)}</select></label>
      {settlements.filter(x=>x.status==='APPROVED').map(s=><article key={s.id} className="mt-3 flex flex-wrap justify-between gap-3 rounded-xl border p-4 text-sm"><div><b>{s.settlementKey} · {money(s.payablePaise)}</b><p className="text-xs text-slate-500">APPROVED settlement, not disbursed</p></div>
       <button type="button" disabled={!selectedBank} onClick={()=>setAction({type:'payoutIntent',id:s.id,label:s.settlementKey,providerRef:'',secondRef:'',selectedBank})} className="rounded-lg border px-3 py-2 text-xs font-bold disabled:opacity-50">Reserve payout intent</button></article>)}
     </>}
    </>}
   </>}
  </section>
  {action&&<div role="dialog" aria-modal="true" aria-label="Confirm finance evidence decision" className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/70 p-4">
   <form className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl" onSubmit={e=>void perform(e)}>
    <h3 className="text-lg font-black">{prompts[action.type]}</h3>
    <p className="mt-2 break-all text-xs text-slate-500">{action.label}</p>
    <p className="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">This action requires current backend permission, independent review and exact provider evidence. No automatic outgoing money POST is permitted.</p>
    {requiresRef&&<label className="mt-4 block text-sm font-bold">{action.type==='refundReconcile'?'Razorpay refund ID (rfnd_...)':action.type==='bankRegister'?'RazorpayX fund account ID (fa_...)':action.type==='payoutReconcile'?'RazorpayX payout ID (pout_...)':'External bank statement reference'}
     <input className={cls+' mt-1'} value={action.providerRef} required minLength={8} maxLength={120} onChange={e=>setAction({...action,providerRef:e.target.value})}/></label>}
    {requiresSecond&&<label className="mt-4 block text-sm font-bold">{action.type==='bankRegister'?'Fund-account validation ID (fav_...)':'Provider-verified UTR'}
     <input className={cls+' mt-1'} required minLength={8} maxLength={100} value={action.secondRef} onChange={e=>setAction({...action,secondRef:e.target.value})}/></label>}
    <div className="mt-5 flex gap-3"><button type="submit" disabled={busy||!valid} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Confirm independent check</button>
     <button type="button" onClick={()=>setAction(null)} className="rounded-lg border px-4 py-2 text-sm">Cancel</button></div>
   </form>
  </div>}
 </div>;
}
