import {useCallback,useEffect,useState} from 'react';
import {ClipboardList,RefreshCw,Search,ShieldCheck} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type SupplierOrderSummary={id:string;supplierId:string;supplierName:string;status:string};
type Order={id:string;publicNumber:string;status:string;currency:string;totalPaise:string;placedAt:string;
 supplierOrders:SupplierOrderSummary[]};
type OrderPage={asOf:string;items:Order[];nextCursor:string|null;note:string};
// The detail endpoint includes additional fields for supplier orders. Do not intersect two
// incompatible array element shapes: a dedicated detail type keeps render-time contracts sound.
type SupplierOrderDetail=SupplierOrderSummary&{
 totalPaise:string;
 items:{id:string;sku:string;name:string;quantity:string;unitCode:string;unitPrice:string;lineTotalPaise:string}[];
 shipments:{id:string;number:string;status:string;deliveredAt:string|null;handoverMethod:string|null;exceptionApproved:boolean}[];
};
type Detail=Omit<Order,'supplierOrders'>&{
 subtotalPaise:string;discountPaise:string;taxPaise:string;deliveryPaise:string;executionAllowed:false;
 privacy:string;payments:{id:string;status:string;paymentMethod:string;amountPaise:string;capturedPaise:string;verifiedAt:string|null;createdAt:string}[];
 supplierOrders:SupplierOrderDetail[];
};
const STATES=['ALL','PLACED','CONFIRMED','PARTIALLY_FULFILLED','PARTIALLY_CANCELLED','FULFILLED','CANCELLED','CLOSED'] as const;
const msg=(error:unknown)=>error instanceof V21ApiError?
 error.status===403?'Your admin role cannot browse platform orders.':error.status===404?'This order is unavailable.':
 error.message:'Failed to fetch orders. Refresh after checking your connection.';
const rupees=(paise:string)=>{
 if(!/^-?(0|[1-9]\d*)$/.test(paise))return '—';
 const n=BigInt(paise);const abs=n<0n?-n:n;
 return (n<0n?'-':'')+'₹'+(abs/100n).toLocaleString('en-IN')+'.'+(abs%100n).toString().padStart(2,'0');
};
const time=(value:string|null)=>value?new Date(value).toLocaleString():'—';

export function AdminOrdersPanel(){
 const api=useV21Api();
 const [status,setStatus]=useState<string>('ALL');
 const [number,setNumber]=useState('');
 const [search,setSearch]=useState('');
 const [items,setItems]=useState<Order[]>([]);
 const [cursor,setCursor]=useState<string|null>(null);
 const [loading,setLoading]=useState(true);
 const [detailId,setDetailId]=useState('');
 const [detail,setDetail]=useState<Detail|null>(null);
 const [detailLoading,setDetailLoading]=useState(false);
 const [error,setError]=useState('');
 const load=useCallback(async(reset:boolean,next?:string,signal?:AbortSignal)=>{
  setLoading(true);setError('');
  const q=new URLSearchParams({limit:'25'});
  if(status!=='ALL')q.set('status',status);
  if(search)q.set('number',search);
  if(next)q.set('cursor',next);
  try{
   const response=await api.get<OrderPage>('/api/v2/admin/orders?'+q,signal);
   if(!Array.isArray(response.data.items)||!(response.data.nextCursor===null||typeof response.data.nextCursor==='string'))
    throw new Error('Invalid order list response');
   if(!signal?.aborted){setItems(old=>reset?response.data.items:[...old,...response.data.items]);setCursor(response.data.nextCursor);}
  }catch(e){if(!signal?.aborted)setError(msg(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api,status,search]);
 useEffect(()=>{const c=new AbortController();setDetailId('');setDetail(null);void load(true,undefined,c.signal);return ()=>c.abort();},[load]);
 useEffect(()=>{
  if(!detailId)return;
  const c=new AbortController();setDetailLoading(true);setDetail(null);
  api.get<Detail>('/api/v2/admin/orders/'+encodeURIComponent(detailId),c.signal).then(x=>{
   if(!c.signal.aborted){if(!Array.isArray(x.data.supplierOrders)||!Array.isArray(x.data.payments))throw new Error('Invalid order detail');setDetail(x.data);}
  }).catch(e=>{if(!c.signal.aborted)setError(msg(e));}).finally(()=>{if(!c.signal.aborted)setDetailLoading(false);});
  return ()=>c.abort();
 },[api,detailId]);
 return <div className="space-y-5">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap items-center justify-between gap-3"><div className="flex items-center gap-3"><ClipboardList size={23} className="text-[#174C86]"/><div>
    <h2 className="text-lg font-extrabold">Platform orders</h2><p className="text-sm text-slate-500">Read-only, cross-supplier oversight. Customer contacts, shipping addresses and provider secrets stay hidden.</p>
   </div></div><button type="button" onClick={()=>void load(true)} disabled={loading} className="rounded-lg border px-4 py-2 text-sm font-bold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button></div>
   <div className="mt-5 grid gap-3 sm:grid-cols-3">
    <label className="text-sm font-bold">Order status<select value={status} onChange={e=>setStatus(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm">{STATES.map(x=><option key={x} value={x}>{x.replace(/_/g,' ')}</option>)}</select></label>
    <form className="sm:col-span-2" onSubmit={e=>{e.preventDefault();setSearch(number.trim());}}>
     <label htmlFor="order-number" className="block text-sm font-bold">Exact public order number</label>
     <div className="mt-1 flex gap-2"><input id="order-number" value={number} onChange={e=>setNumber(e.target.value)} className="min-w-0 flex-1 rounded-lg border border-slate-300 p-2 text-sm" placeholder="Order reference" maxLength={40}/>
      <button type="submit" className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white"><Search size={16} className="mr-1 inline"/>Find</button>
      <button type="button" className="rounded-lg border px-3 py-2 text-sm" onClick={()=>{setNumber('');setSearch('');}}>Clear</button></div>
    </form>
   </div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
   {loading&&items.length===0?<p role="status" className="mt-5 text-sm">Loading orders…</p>:
    <div className="mt-6 overflow-x-auto"><table className="w-full min-w-[650px] text-left text-sm"><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="pb-3">Order</th><th>Placed</th><th>State</th><th>Amount (not payment confirmation)</th><th className="text-right">Details</th></tr></thead><tbody>
     {items.map(o=><tr key={o.id} className="border-b border-slate-100"><td className="py-4 font-bold">{o.publicNumber}<p className="text-xs font-normal text-slate-500">{o.supplierOrders.length} supplier group(s) shown</p></td>
      <td>{time(o.placedAt)}</td><td>{o.status.replace(/_/g,' ')}</td><td className="font-semibold">{rupees(o.totalPaise)}</td>
      <td className="text-right"><button className="rounded-lg border px-3 py-2 font-bold" type="button" onClick={()=>setDetailId(o.id)}>Inspect</button></td>
     </tr>)}</tbody></table>
     {items.length===0&&!loading&&<p className="py-7 text-sm text-slate-500">No orders match the current filters.</p>}
     {cursor&&<button type="button" disabled={loading} onClick={()=>void load(false,cursor)} className="mt-3 rounded-lg border px-4 py-2 text-sm font-bold disabled:opacity-50">Load older orders</button>}
    </div>}
  </section>
  {detailId&&<section aria-label="Order detail" className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex justify-between gap-3"><h3 className="text-lg font-extrabold">Order details</h3><button type="button" className="text-sm font-semibold text-[#174C86]" onClick={()=>{setDetailId('');setDetail(null);}}>Close</button></div>
   {detailLoading?<p role="status" className="mt-4">Loading order record…</p>:detail&&<>
    <div className="mt-4 flex flex-wrap gap-4 text-sm"><p><b>{detail.publicNumber}</b> · {detail.status}</p><p>Quoted total: <b>{rupees(detail.totalPaise)}</b></p></div>
    <p className="mt-3 flex items-center gap-2 rounded-lg bg-slate-50 p-3 text-xs text-slate-600"><ShieldCheck size={16}/>Totals are order commitments, not bank deposits. No order modification or impersonation is available.</p>
    <h4 className="mt-6 font-bold">Payment attempts and captured funds</h4>
    {detail.payments.length===0?<p className="mt-2 text-sm text-slate-500">No payment attempts recorded.</p>:
     <div className="mt-3 space-y-3">{detail.payments.map(p=><div key={p.id} className="rounded-xl border border-slate-200 p-4 text-sm"><b>{p.paymentMethod} · {p.status}</b>
      <p className="mt-1 text-xs text-slate-600">Attempted {rupees(p.amountPaise)} · Captured {rupees(p.capturedPaise)} · Verified {time(p.verifiedAt)}</p></div>)}</div>}
    <h4 className="mt-6 font-bold">Supplier fulfillment</h4>
    {detail.supplierOrders.map(s=><article key={s.id} className="mt-3 rounded-xl border border-slate-200 p-4">
     <div className="flex justify-between gap-2 text-sm"><b>{s.supplierName}</b><span>{s.status.replace(/_/g,' ')}</span></div>
     <p className="mt-1 text-xs text-slate-500">Supplier order amount: {rupees(s.totalPaise)}</p>
     <ul className="mt-3 divide-y">{s.items.map(item=><li key={item.id} className="py-2 text-sm"><span className="font-semibold">{item.name}</span><span className="ml-2 text-slate-500">{item.quantity} {item.unitCode} · {rupees(item.lineTotalPaise)}</span></li>)}</ul>
     <h5 className="mt-3 text-sm font-bold">Shipments</h5>
     {s.shipments.length===0?<p className="text-xs text-slate-500">No shipment planned.</p>:s.shipments.map(sh=><p key={sh.id} className="mt-2 text-xs text-slate-600">{sh.number} · {sh.status} · Delivered {time(sh.deliveredAt)}{sh.exceptionApproved?' · independently approved exception':''}</p>)}
    </article>)}
   </>}
  </section>}
 </div>;
}
