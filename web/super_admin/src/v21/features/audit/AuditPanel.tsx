import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {FileClock,RefreshCw} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type AuditRow={
  id:string;createdAt:string;actorRole:string|null;actorUserId:string|null;
  action:string;entityType:string;entityId:string;
};
type Page={items:AuditRow[];nextCursor:string|null};
const input='rounded-lg border border-slate-300 px-3 py-2 text-sm';
const message=(e:unknown)=>e instanceof V21ApiError
  ?e.status===403?'Only platform owners and auditors may inspect the audit trail.':e.message
  :'Audit history could not be loaded. No data was changed.';

export function AuditPanel(){
  const api=useV21Api();
  const [items,setItems]=useState<AuditRow[]>([]);
  const [cursor,setCursor]=useState<string|null>(null);
  const [entityType,setEntityType]=useState('');
  const [action,setAction]=useState('');
  const [applied,setApplied]=useState({entityType:'',action:''});
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState('');
  const load=useCallback(async(reset:boolean,next?:string,signal?:AbortSignal)=>{
    setLoading(true);setError('');
    const q=new URLSearchParams({limit:'25'});
    if(applied.entityType)q.set('entityType',applied.entityType);
    if(applied.action)q.set('action',applied.action);
    if(next)q.set('cursor',next);
    try{
      const response=await api.get<Page>('/api/v2/admin/audit?'+q.toString(),signal);
      if(!Array.isArray(response.data.items)||
        !(typeof response.data.nextCursor==='string'||response.data.nextCursor===null))
        throw new Error('Invalid audit API response.');
      if(!signal?.aborted){
        setItems(old=>reset?response.data.items:[...old,...response.data.items]);
        setCursor(response.data.nextCursor);
      }
    }catch(e){if(!signal?.aborted)setError(message(e));}
    finally{if(!signal?.aborted)setLoading(false);}
  },[api,applied]);
  useEffect(()=>{
    const c=new AbortController();
    void load(true,undefined,c.signal);
    return ()=>c.abort();
  },[load]);
  function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault();
    setApplied({entityType:entityType.trim(),action:action.trim()});
  }
  return <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
    <header className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex items-center gap-2"><FileClock aria-hidden="true" className="text-[#174C86]"/>
        <div><h2 className="text-lg font-extrabold">Audit trail</h2>
          <p className="mt-1 text-sm text-slate-500">Owner / auditor only. Read-only; private before/after snapshots and IP hashes are never sent to the browser.</p>
        </div>
      </div>
      <button type="button" aria-label="Refresh audit history" onClick={()=>void load(true)}
        className="inline-flex items-center gap-2 rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold"><RefreshCw size={16}/>Refresh</button>
    </header>
    <form onSubmit={submit} className="my-6 flex flex-wrap items-end gap-3">
      <label className="flex flex-col gap-1 text-xs font-semibold">Entity type
        <input className={input} maxLength={100} value={entityType} onChange={e=>setEntityType(e.target.value)} placeholder="e.g. Supplier" pattern="[A-Za-z][A-Za-z0-9_-]*"/>
      </label>
      <label className="flex flex-col gap-1 text-xs font-semibold">Action
        <input className={input} maxLength={120} value={action} onChange={e=>setAction(e.target.value)} placeholder="e.g. ADMIN_ACCESS_GRANTED" pattern="[A-Z][A-Z0-9_]*"/>
      </label>
      <button className="rounded-lg bg-[#174C86] px-4 py-2.5 text-sm font-semibold text-white" type="submit">Apply filters</button>
    </form>
    {error&&<p role="alert" className="mb-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-800">{error}</p>}
    {loading&&<p role="status" className="text-sm text-slate-500">Loading verified audit events…</p>}
    {!loading&&items.length===0&&<p className="py-12 text-center text-sm text-slate-500">No matching audit events.</p>}
    {items.length>0&&<div className="overflow-x-auto">
      <table className="min-w-[800px] w-full text-left text-sm">
        <thead><tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
          <th scope="col" className="py-3">Recorded</th><th scope="col">Action</th>
          <th scope="col">Entity</th><th scope="col">Actor</th></tr></thead>
        <tbody>{items.map(item=><tr key={item.id} className="border-b border-slate-100 align-top">
          <td className="py-3 pr-4 whitespace-nowrap">{new Date(item.createdAt).toLocaleString('en-IN')}</td>
          <td className="py-3 pr-4 font-semibold">{item.action}</td>
          <td className="py-3 pr-4">{item.entityType}<span className="block break-all font-mono text-xs text-slate-500">{item.entityId}</span></td>
          <td className="py-3">{item.actorRole||'System'}<span className="block break-all font-mono text-xs text-slate-500">{item.actorUserId||'No staff actor'}</span></td>
        </tr>)}</tbody>
      </table>
    </div>}
    {cursor&&<div className="mt-5 flex justify-center">
      <button type="button" disabled={loading} onClick={()=>void load(false,cursor)}
        className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold disabled:opacity-50">Load older events</button>
    </div>}
  </section>;
}
