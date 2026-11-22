import {useCallback,useEffect,useState} from 'react';
import {Activity,ArrowRight,Boxes,CheckCircle2,ClipboardList,RefreshCw,ShieldAlert,Wallet} from 'lucide-react';
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
export function DashboardPanel({onNavigate}:{onNavigate?:(section:'suppliers'|'catalog'|'support'|'orders'|'finance')=>void}={}){
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
  <div className="relative overflow-hidden rounded-[25px] bg-gradient-to-r from-[#102b4d] via-[#143b68] to-[#1b4d7d] p-7 text-white shadow-lg sm:p-9">
   <div className="pointer-events-none absolute -right-16 -top-20 h-72 w-72 rounded-full border-[45px] border-white/5" aria-hidden="true"/>
   <div className="relative flex flex-wrap items-start justify-between gap-4">
    <div className="max-w-2xl">
     <p className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[11px] font-extrabold uppercase tracking-[.15em] text-amber-200">
      <Activity size={14}/>Splyzo · Operations
     </p>
     <h2 className="mt-5 text-3xl font-black tracking-tight">Marketplace overview</h2>
     <p className="mt-3 max-w-xl text-sm leading-6 text-slate-200">
      Your construction-materials marketplace at a glance. All numbers below come from the live staging database—never estimates or sample revenue.
     </p>
    </div>
    <button type="button" disabled={loading} onClick={()=>void load()}
     className="inline-flex min-h-[44px] items-center gap-2 rounded-xl border border-white/30 bg-white/10 px-4 py-2 text-sm font-bold transition hover:bg-white/20 disabled:opacity-50">
     <RefreshCw size={16} className={loading?'animate-spin':''}/>Refresh snapshot
    </button>
   </div>
  </div>
  {error&&<p role="alert" className="rounded-lg border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</p>}
  {loading?<p role="status" className="rounded-lg border bg-white p-6 text-sm">Reading live dashboard data…</p>:data&&<>
   <p className="text-xs text-slate-500" role="status">Snapshot requested: {new Date(data.asOf).toLocaleString()} · Past 7 days begins {new Date(data.windowStart7d).toLocaleString()}</p>
   <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
    {metrics.map((metric,index)=>{const Icon=metric.icon;return <section key={metric.label} className="splyzo-surface group relative overflow-hidden p-5">
     <span aria-hidden="true" className={'absolute left-0 top-5 h-11 w-[3px] rounded-r '+(index===1||index===2?'bg-orange-400':'bg-[#2e6496]')}/>
     <div className="flex items-center justify-between"><span className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#eef4fb] text-[#1b5286]"><Icon size={19}/></span><span className="text-[10px] font-extrabold uppercase tracking-[.14em] text-slate-400">Live data</span></div>
     <p className="mt-4 text-xs font-bold text-slate-600">{metric.label}</p>
     <p className="mt-2 text-3xl font-black tabular-nums tracking-tight text-[#172e4d]">{metric.value.toLocaleString('en-IN')}</p>
     <p className="mt-2 text-xs leading-5 text-slate-500">{metric.note}</p>
    </section>;})}
   </div>
   <section className="splyzo-surface p-6">
    <div className="flex flex-wrap items-center justify-between gap-3">
     <div><p className="splyzo-eyebrow">Prioritize your work</p><h3 className="mt-1 text-lg font-extrabold">Queues that need attention</h3></div>
     <p className="text-xs text-slate-500">Read-only counts · Actions require verified roles</p>
    </div>
    <div className="mt-5 grid gap-3 lg:grid-cols-3">
     {([
      {section:'suppliers' as const,count:data.pendingSuppliers,label:'Supplier applications',description:'Review business documents and approval'},
      {section:'catalog' as const,count:data.pendingListings,label:'Catalog listings',description:'Review materials submitted by sellers'},
      {section:'support' as const,count:data.openSupportCases,label:'Customer cases',description:'Investigate open customer support requests'},
     ]).map(row=><div key={row.section} className="flex flex-col justify-between rounded-2xl border border-[#e0e9f4] bg-[#f7f9fd] p-5">
      <div className="flex items-start justify-between gap-2">
       <div><p className="text-sm font-extrabold text-[#152f4f]">{row.label}</p><p className="mt-1 text-xs leading-5 text-slate-500">{row.description}</p></div>
       <span className="rounded-xl bg-white px-3 py-1.5 text-xl font-black tabular-nums text-[#173c65]">{row.count}</span>
      </div>
      <div className="mt-5">{onNavigate?<button type="button" onClick={()=>onNavigate(row.section)} className="splyzo-secondary flex w-full items-center justify-between text-xs">
       Open {row.label.toLowerCase()}<ArrowRight size={16}/>
      </button>:<p className="flex items-center gap-2 text-xs font-semibold text-slate-500"><CheckCircle2 size={14}/>Available to authorized administrators</p>}</div>
     </div>)}
    </div>
   </section>
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
