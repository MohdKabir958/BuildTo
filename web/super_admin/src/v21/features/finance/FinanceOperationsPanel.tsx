import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Banknote,Landmark,RefreshCw} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Choice={id:string;displayName:string;approval:string;suspended:boolean};
type Page<T>={items:T[];nextCursor:string|null};
type Order={supplierOrderId:string;totalPaise:string;platformFeePaise:string;codVerifiedPaise:string;fundingType:string;disputed:boolean;allocatedToActiveSettlement:boolean};
type Settlement={id:string;settlementKey:string;status:string;payablePaise:string;grossPaise:string;commissionPaise:string;createdAt:string;periodStart:string;periodEnd:string;payoutState:string;approvedById:string|null;lines:{supplierOrderId:string;netPaise:string}[]};
type SupplierFinance={orders:Order[];settlements:Settlement[];bankingReconciled:false};
type Receipt={id:string;receiptNumber:string;supplierId:string;supplierOrderId:string;collectedPaise:string;currency:string;status:string;receivedAt:string};
type Journal={id:string;referenceKey:string;eventType:string;postedAt:string|null;balanced:boolean;debitPaise:string;creditPaise:string;lines:{lineNumber:number;accountCode:string;currency:string;debitPaise:string;creditPaise:string;memo:string}[]};
type Action={kind:'approve'|'cancel'|'codVerify'|'codDispute'|'commission';id:string;label:string;reference:string};
const err=(x:unknown)=>x instanceof V21ApiError?
 x.status===403?'Independent finance authorization required. The maker, supplier staff and reviewer must be separate people.':
 x.status===409?'Finance evidence or approval state changed; reload and re-check invoices, capture, return and bank evidence.':x.message:
 'Finance request unavailable. No financial status has been changed in the UI.';
const money=(v:string)=>{
 if(!/^-?(0|[1-9]\d*)$/.test(v))return '—';
 const n=BigInt(v),abs=n<0n?-n:n;return (n<0n?'-':'')+'₹'+(abs/100n).toLocaleString('en-IN')+'.'+(abs%100n).toString().padStart(2,'0');
};
const field='w-full rounded-lg border border-slate-300 p-2 text-sm';

export function FinanceOperationsPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<'settlements'|'cod'|'journals'>('settlements');
 const [suppliers,setSuppliers]=useState<Choice[]>([]);
 const [supplierCursor,setSupplierCursor]=useState<string|null>(null);
 const [supplierId,setSupplierId]=useState('');
 const [finance,setFinance]=useState<SupplierFinance|null>(null);
 const [receipts,setReceipts]=useState<Receipt[]>([]);
 const [codCursor,setCodCursor]=useState<string|null>(null);
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [settlementKey,setSettlementKey]=useState('');
 const [start,setStart]=useState('');
 const [end,setEnd]=useState('');
 const [selected,setSelected]=useState<string[]>([]);
 const [action,setAction]=useState<Action|null>(null);
 const [journalId,setJournalId]=useState('');
 const [journal,setJournal]=useState<Journal|null>(null);

 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [choice,cod]=await Promise.all([
    api.get<Page<Choice>>('/api/v2/admin/finance/suppliers?limit=25',signal),
    api.get<Page<Receipt>>('/api/v2/admin/finance/cod?limit=25&status=RECORDED',signal)
   ]);
   if(!Array.isArray(choice.data.items)||!Array.isArray(cod.data.items))throw new Error('Invalid finance response');
   if(!signal?.aborted){
    setSuppliers(choice.data.items);setSupplierCursor(choice.data.nextCursor);
    setReceipts(cod.data.items);setCodCursor(cod.data.nextCursor);
   }
  }catch(e){if(!signal?.aborted)setError(err(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 const loadFinance=useCallback(async(id:string,signal?:AbortSignal)=>{
  if(!id){setFinance(null);return;}
  setError('');
  try{
   const response=await api.get<SupplierFinance>('/api/v2/admin/finance/suppliers/'+encodeURIComponent(id),signal);
   if(!Array.isArray(response.data.orders)||!Array.isArray(response.data.settlements))throw new Error('Invalid supplier statement');
   if(!signal?.aborted)setFinance(response.data);
  }catch(e){if(!signal?.aborted){setFinance(null);setError(err(e));}}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);
 useEffect(()=>{const c=new AbortController();setSelected([]);void loadFinance(supplierId,c.signal);return ()=>c.abort();},[supplierId,loadFinance]);
 async function save(fn:()=>Promise<unknown>,success:string){
  if(busy)return;
  setBusy(true);setError('');setNotice('');
  try{
   await fn();setAction(null);setSelected([]);await load();
   if(supplierId)await loadFinance(supplierId);
   setNotice(success);
  }catch(e){setError(err(e));}
  finally{setBusy(false);}
 }
 async function moreSuppliers(){
  if(!supplierCursor||busy)return;setBusy(true);
  try{const x=await api.get<Page<Choice>>('/api/v2/admin/finance/suppliers?limit=25&cursor='+encodeURIComponent(supplierCursor));
   setSuppliers(old=>[...old,...x.data.items]);setSupplierCursor(x.data.nextCursor);
  }catch(e){setError(err(e));}finally{setBusy(false);}
 }
 async function moreCod(){
  if(!codCursor||busy)return;setBusy(true);
  try{const x=await api.get<Page<Receipt>>('/api/v2/admin/finance/cod?limit=25&status=RECORDED&cursor='+encodeURIComponent(codCursor));
   setReceipts(old=>[...old,...x.data.items]);setCodCursor(x.data.nextCursor);
  }catch(e){setError(err(e));}finally{setBusy(false);}
 }
 function draft(e:FormEvent<HTMLFormElement>){
  e.preventDefault();
  if(!supplierId||!selected.length||!start||!end||settlementKey.trim().length<8){setError('Choose a supplier, eligible supplier orders and a valid settlement period/key.');return;}
  const periodStart=new Date(start).toISOString(),periodEnd=new Date(end).toISOString();
  if(new Date(periodStart)>=new Date(periodEnd)){setError('End time must be after start time.');return;}
  // A draft remains ON_HOLD. Backend validates capture, invoice, handover, returns and commission atomically.
  void save(()=>api.write('POST','/api/v2/admin/finance/settlements/drafts',{
   supplierId,settlementKey:settlementKey.trim(),supplierOrderIds:selected,periodStart,periodEnd
  },{idempotencyKey:crypto.randomUUID()}),'ON_HOLD settlement proposal created. Independent bank-statement attestation is still required.');
 }
 function confirm(e:FormEvent<HTMLFormElement>){
  e.preventDefault();if(!action)return;
  const c=action;
  if(c.kind==='approve')void save(()=>api.write('POST','/api/v2/admin/finance/settlements/'+c.id+'/approve',
   {bankStatementReference:c.reference.trim()}),'Independent bank-statement attestation recorded; no payout transfer executed.');
  if(c.kind==='cancel')void save(()=>api.write('POST','/api/v2/admin/finance/settlements/'+c.id+'/cancel',
   {reason:c.reference.trim()}),'Held settlement draft cancelled; captured funds remain unchanged.');
  if(c.kind==='codVerify')void save(()=>api.write('POST','/api/v2/admin/finance/cod/'+c.id+'/review',
   {decision:'VERIFY',externalReference:c.reference.trim()}),'Supplier-held COD receipt independently verified and memorandum posted. Platform bank credit NOT established.');
  if(c.kind==='codDispute')void save(()=>api.write('POST','/api/v2/admin/finance/cod/'+c.id+'/review',
   {decision:'DISPUTE'}),'COD receipt marked disputed; no cash transfer.');
  if(c.kind==='commission')void save(()=>api.write('POST','/api/v2/admin/finance/cod-commissions/'+c.id+'/recognize',{}),
   'Verified supplier-held COD commission receivable recognized, not bank cash.');
 }
 async function lookUp(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setError('');setJournal(null);
  try{const r=await api.get<Journal>('/api/v2/admin/finance/journals/'+encodeURIComponent(journalId.trim()));
   if(!Array.isArray(r.data.lines))throw new Error('Malformed journal');
   setJournal(r.data);
  }catch(e){setError(err(e));}
 }
 const eligible=finance?.orders.filter(x=>x.fundingType==='RAZORPAY_CAPTURE_VERIFIED'&&!x.disputed&&!x.allocatedToActiveSettlement)??[];
 return <div className="space-y-5">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap items-center justify-between gap-3"><div className="flex items-center gap-3"><Landmark size={23} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Finance review desk</h2><p className="mt-1 text-sm text-slate-500">Audit-backed maker/checker settlement evidence, supplier-held COD and balanced journals.</p></div></div>
    <button type="button" disabled={loading} onClick={()=>void load()} className="rounded-lg border px-3 py-2 text-sm font-semibold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button></div>
   <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">Captured gateway payments are NOT verified bank deposits. Approved settlement is NOT a bank payout. COD is held by the supplier until independently confirmed. This screen never sends funds.</p>
   <div className="mt-5 flex flex-wrap gap-2" role="tablist" aria-label="Finance review">
    {(['settlements','cod','journals'] as const).map(t=><button type="button" role="tab" key={t} aria-selected={tab===t} onClick={()=>{setTab(t);setError('');setAction(null);}} className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===t?'bg-[#174C86] text-white':'border')}>{t==='cod'?'COD receipts':t==='journals'?'Ledger journals':'Settlements'}</button>)}
   </div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
   {notice&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
   {loading?<p role="status" className="mt-5">Loading finance evidence…</p>:<>
    {tab==='settlements'&&<>
     <label className="mt-5 block text-sm font-bold">Supplier<select value={supplierId} onChange={e=>setSupplierId(e.target.value)} className={field+' mt-2'}><option value="">Choose supplier</option>{suppliers.map(s=><option key={s.id} value={s.id}>{s.displayName} · {s.approval}{s.suspended?' (suspended)':''}</option>)}</select></label>
     {supplierCursor&&<button type="button" disabled={busy} onClick={()=>void moreSuppliers()} className="mt-2 rounded-lg border px-3 py-2 text-xs font-semibold">Load more suppliers</button>}
     {supplierId&&finance&&<>
      <div className="mt-5 grid gap-4 sm:grid-cols-2"><section className="rounded-xl bg-slate-50 p-4"><p className="text-xs font-bold text-slate-600">Delivered supplier orders</p><p className="mt-1 text-2xl font-black">{finance.orders.length}</p><p className="text-xs text-slate-500">Only the latest 100 records from the supplier finance endpoint</p></section>
       <section className="rounded-xl bg-slate-50 p-4"><p className="text-xs font-bold text-slate-600">Settlements on record</p><p className="mt-1 text-2xl font-black">{finance.settlements.length}</p><p className="text-xs text-slate-500">Payout status never implies bank statement reconciliation</p></section></div>
      <form onSubmit={draft} className="mt-5 space-y-4 rounded-xl border border-slate-200 p-4">
       <h3 className="font-extrabold">Prepare ON_HOLD settlement draft</h3>
       <p className="text-xs text-slate-500">Only capture-evidenced, undisputed and currently unallocated delivered orders appear. The backend performs additional invoice, stock and verified handover eligibility checks.</p>
       {eligible.length===0?<p className="text-sm text-slate-500">No candidate orders for a new online-funded settlement.</p>:<div className="max-h-52 space-y-2 overflow-y-auto">{eligible.map(o=><label key={o.supplierOrderId} className="flex items-center justify-between gap-3 border-b pb-2 text-sm">
        <span className="flex items-center gap-2"><input type="checkbox" checked={selected.includes(o.supplierOrderId)} onChange={e=>setSelected(old=>e.target.checked?[...old,o.supplierOrderId]:old.filter(id=>id!==o.supplierOrderId))}/>Order {o.supplierOrderId.slice(0,8)}…</span>
        <span>{money(o.totalPaise)} · fee {money(o.platformFeePaise)}</span></label>)}</div>}
       <div className="grid gap-3 sm:grid-cols-3"><label className="text-xs font-bold">Settlement reference<input className={field+' mt-1'} maxLength={100} minLength={8} value={settlementKey} required onChange={e=>setSettlementKey(e.target.value)}/></label>
        <label className="text-xs font-bold">Period start (local)<input required type="datetime-local" className={field+' mt-1'} value={start} onChange={e=>setStart(e.target.value)}/></label>
        <label className="text-xs font-bold">Period end (local)<input required type="datetime-local" className={field+' mt-1'} value={end} onChange={e=>setEnd(e.target.value)}/></label></div>
       <button type="submit" disabled={busy||!selected.length} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Create on-hold proposal</button>
      </form>
      <h3 className="mt-6 font-extrabold">Existing settlement proposals</h3>
      {finance.settlements.map(s=><article key={s.id} className="mt-3 rounded-xl border border-slate-200 p-4"><div className="flex flex-wrap justify-between gap-3"><div>
       <b className="text-sm">{s.settlementKey} · {s.status}</b><p className="mt-1 text-xs text-slate-500">Payable {money(s.payablePaise)} · {s.payoutState}</p>
       <p className="mt-1 text-xs text-slate-500">Order line(s): {s.lines.length} · {s.periodStart.slice(0,10)} to {s.periodEnd.slice(0,10)}</p>
      </div>{s.status==='ON_HOLD'&&<div className="flex gap-2">
       <button type="button" onClick={()=>setAction({kind:'approve',id:s.id,label:s.settlementKey,reference:''})} className="rounded-lg border px-3 py-2 text-xs font-bold">Attest bank evidence</button>
       <button type="button" onClick={()=>setAction({kind:'cancel',id:s.id,label:s.settlementKey,reference:''})} className="rounded-lg border border-rose-200 px-3 py-2 text-xs font-bold text-rose-700">Cancel draft</button>
      </div>}</div></article>)}
     </>}
    </>}
    {tab==='cod'&&<>
     <div className="mt-5 flex items-center gap-2"><Banknote size={18}/><p className="text-sm font-semibold">Recorded, supplier-held COD receipts awaiting independent finance verification</p></div>
     <div className="mt-3 space-y-3">{receipts.map(c=><article key={c.id} className="flex flex-wrap justify-between gap-3 rounded-xl border p-4">
      <div><b className="text-sm">{c.receiptNumber} · {money(c.collectedPaise)}</b><p className="mt-1 text-xs text-slate-500">Supplier {c.supplierId.slice(0,8)}… · Recorded {new Date(c.receivedAt).toLocaleString()} · {c.status}</p></div>
      <div className="flex gap-2"><button type="button" onClick={()=>setAction({kind:'codVerify',id:c.id,label:c.receiptNumber,reference:''})} className="rounded-lg border px-3 py-2 text-xs font-semibold">Verify evidence</button>
       <button type="button" onClick={()=>setAction({kind:'codDispute',id:c.id,label:c.receiptNumber,reference:''})} className="rounded-lg border border-rose-200 px-3 py-2 text-xs font-semibold text-rose-700">Dispute</button></div>
     </article>)}{receipts.length===0&&<p className="text-sm text-slate-500">No recorded COD receipts in the queue.</p>}</div>
     {codCursor&&<button type="button" onClick={()=>void moreCod()} disabled={busy} className="mt-3 rounded-lg border px-4 py-2 text-sm">Load more receipts</button>}
    </>}
    {tab==='journals'&&<>
     <form className="mt-5 flex items-end gap-3" onSubmit={lookUp}><label htmlFor="journal-ref" className="flex-1 text-sm font-bold">Immutable journal ID<input id="journal-ref" value={journalId} required onChange={e=>setJournalId(e.target.value)} className={field+' mt-2'}/></label><button className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white">Read journal</button></form>
     {journal&&<div className="mt-5 rounded-xl border p-4"><h3 className="font-extrabold">{journal.referenceKey} · {journal.eventType}</h3>
      <p className="mt-2 text-sm">Posted {journal.postedAt||'not posted'} · <b>{journal.balanced?'Balanced':'NOT BALANCED'}</b> · Debit {money(journal.debitPaise)} / Credit {money(journal.creditPaise)}</p>
      <ul className="mt-3 divide-y">{journal.lines.map(line=><li key={line.lineNumber} className="flex flex-wrap justify-between gap-3 py-3 text-xs"><span>{line.lineNumber}. {line.accountCode}</span><span>Dr {money(line.debitPaise)} / Cr {money(line.creditPaise)}</span></li>)}</ul>
     </div>}
    </>}
   </>}
  </section>
  {action&&<div role="dialog" aria-modal="true" aria-label="Confirm financial review" className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/70 p-4">
   <form onSubmit={confirm} className="w-full max-w-lg rounded-xl bg-white p-6 shadow-xl"><h3 className="text-lg font-black">Confirm financial review</h3><p className="mt-3 text-sm text-slate-700">{action.label} · {action.kind}. A separate authorized finance reviewer is required for independent attestations. This UI does not execute a bank transfer.</p>
    {(action.kind==='approve'||action.kind==='cancel'||action.kind==='codVerify')&&<label className="mt-4 block text-sm font-bold">{action.kind==='approve'?'External bank statement reference':action.kind==='cancel'?'Audit reason':'Independent COD evidence reference'}
     <input value={action.reference} onChange={e=>setAction({...action,reference:e.target.value})} required minLength={action.kind==='codVerify'?8:12} maxLength={120} className={field+' mt-2'} autoFocus/></label>}
    <div className="mt-5 flex gap-3"><button type="submit" disabled={busy||((action.kind==='approve'||action.kind==='cancel'||action.kind==='codVerify')&&action.reference.trim().length<(action.kind==='codVerify'?8:12))} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Confirm reviewed action</button><button type="button" className="rounded-lg border px-4 py-2 text-sm" onClick={()=>setAction(null)}>Cancel</button></div>
   </form>
  </div>}
 </div>;
}
