import {useCallback,useEffect,useState} from 'react';
import {Activity,Boxes,ClipboardList,RefreshCw,ShieldAlert,Wallet} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';
type Counts={
 asOf:string;windowStart7d:string;
 supplierCount:number;pendingSuppliers:number;activeSuppliers:number;pendingListings:number;
 totalOrders:number;ordersPlacedLast7d:number;pendingSupplierOrders:number;
 openSupportCases:number;unresolvedReturnClaims:number;deliveryExceptionsApproved:number;
 failedShipments:number;financialActionCounts:{pendingRefunds:number;pendingPayouts:number};
 financeEvidence:null|{verifiedGatewayCaptureEvidencePaise:string;verifiedCaptureCount:number;currency:string;bankCreditVerified:false;netRevenueCalculated:false};
};
const show=(e:unknown)=>e instanceof V21ApiError?
 e.status===403?'Your account is not authorized to view marketplace statistics.':e.message:
 'The dashboard is unavailable. No cached totals are displayed.';
function exactRupees(paise:string) {
 if(!/^(0|[1-9]\d*)$/.test(paise))return 'Unavailable';
 const whole=BigInt(paise)/100n,fraction=(BigInt(paise)%100n).toString().padStart(2,'0');
 return '₹'+whole.toLocaleString('en-IN')+'.'+fraction;
}
export function DashboardPanel(){
 const api=useV21Api();
 const [data,setData]=useState<Counts|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState('');
 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const result=await api.get<Counts>('/api/v2/admin/overview',signal);
   if(typeof result.data.totalOrders!=='number'||!result.data.asOf||typeof result.data.pendingSuppliers!=='number')throw new Error('Invalid statistics');
   if(!signal?.aborted)setData(result.data);
  }catch(e){if(!signal?.aborted){setError(show(e));setData(null);}}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 useEffect(()=>{const controller=new AbortController();void load(controller.signal);return ()=>controller.abort();},[load]);
 const metrics=data?[
  {label:'Suppliers registered',value:data.supplierCount,note:data.activeSuppliers+' approved',icon:Boxes},
  {label:'Pending supplier review',value:data.pendingSuppliers,note:'Pending and under review',icon:ShieldAlert},
  {label:'Pending catalog listings',value:data.pendingListings,note:'All pending records',icon:ClipboardList},
  {label:'Purchase orders',value:data.totalOrders,note:data.ordersPlacedLast7d+' placed in previous 7 days',icon:Activity},
  {label:'Supplier orders awaiting acceptance',value:data.pendingSupplierOrders,note:'All suppliers',icon:ClipboardList},
  {label:'Open customer support cases',value:data.openSupportCases,note:'Includes waiting on customer',icon:ShieldAlert},
  {label:'Unresolved return claims',value:data.unresolvedReturnClaims,note:'Not refunds or credits',icon:Boxes},
  {label:'Failed shipments',value:data.failedShipments,note:'Exception approvals: '+data.deliveryExceptionsApproved,icon:Activity},
 ]:[];
 return <div className="space-y-6">
  <div className="rounded-2xl bg-[#102B4D] p-7 text-white">
   <div className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-amber-300">BuildTo · Operations</p><h2 className="mt-2 text-2xl font-black">Marketplace overview</h2><p className="mt-2 text-sm text-slate-300">Live, read-only PostgreSQL counts. No mock revenue or optimistic totals.</p></div>
    <button type="button" disabled={loading} onClick={()=>void load()} className="rounded-lg border border-white/30 px-4 py-2 text-sm font-bold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button></div>
  </div>
  {error&&<p role="alert" className="rounded-lg border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</p>}
  {loading?<p role="status" className="rounded-lg border bg-white p-6 text-sm">Reading live dashboard data…</p>:data&&<>
   <p className="text-xs text-slate-500" role="status">Snapshot requested: {new Date(data.asOf).toLocaleString()} · Past 7 days begins {new Date(data.windowStart7d).toLocaleString()}</p>
   <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
    {metrics.map(metric=>{const Icon=metric.icon;return <section key={metric.label} className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
     <Icon size={19} className="text-[#174C86]"/><p className="mt-4 text-xs font-semibold text-slate-500">{metric.label}</p>
     <p className="mt-2 text-3xl font-black tabular-nums">{metric.value.toLocaleString('en-IN')}</p><p className="mt-2 text-xs text-slate-500">{metric.note}</p></section>;})}
   </div>
   <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
    <div className="flex items-center gap-2"><Wallet size={20} className="text-[#174C86]"/><h3 className="font-extrabold">Financial operations</h3></div>
    <div className="mt-4 grid gap-4 sm:grid-cols-2">
     <p className="rounded-xl bg-slate-50 p-4 text-sm"><strong>{data.financialActionCounts.pendingRefunds}</strong> refunds requiring finance attention</p>
     <p className="rounded-xl bg-slate-50 p-4 text-sm"><strong>{data.financialActionCounts.pendingPayouts}</strong> payout intents requiring review</p>
    </div>
    {data.financeEvidence?<div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4">
     <p className="font-bold">{exactRupees(data.financeEvidence.verifiedGatewayCaptureEvidencePaise)}</p>
     <p className="mt-1 text-xs text-amber-900">Verified Razorpay capture evidence across {data.financeEvidence.verifiedCaptureCount} attempts. This is NOT net revenue, cleared bank balance, COD receipts or approved supplier payout.</p>
    </div>:<p className="mt-4 text-sm text-slate-500">Gateway capture totals are visible only to authorized Finance/OWNER roles.</p>}
   </section>
  </>}
 </div>;
}
