import {useState} from 'react';
import {FinanceOperationsPanel} from './FinanceOperationsPanel';
import {RefundPayoutPanel} from './RefundPayoutPanel';

export function FinanceWorkspace(){
 const [view,setView]=useState<'settlements'|'money'>('settlements');
 return <div className="space-y-5">
  <nav aria-label="Finance sections" className="flex flex-wrap gap-2">
   <button type="button" aria-current={view==='settlements'?'page':undefined}
    className={view==='settlements'?'rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white':'rounded-lg border px-4 py-2 text-sm font-bold'}
    onClick={()=>setView('settlements')}>Settlements, COD and journals</button>
   <button type="button" aria-current={view==='money'?'page':undefined}
    className={view==='money'?'rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white':'rounded-lg border px-4 py-2 text-sm font-bold'}
    onClick={()=>setView('money')}>Refunds, payouts and beneficiaries</button>
  </nav>
  {view==='settlements'?<FinanceOperationsPanel/>:<RefundPayoutPanel/>}
 </div>;
}
