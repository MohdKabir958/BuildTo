import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {MapPin,TicketPercent} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type City={id:string;code:string;name:string;stateCode:string;active:boolean};
type Zone={id:string;cityId:string;name:string;postalCodes:string[];active:boolean;centerLat:string|null;centerLng:string|null;radiusKm:string|null};
type Promo={id:string;code:string|null;title:string;type:string;startsAt:string;endsAt:string;active:boolean;amountPaise:string|null;percentageBps:number|null};
const cls='w-full rounded-lg border border-slate-300 bg-white p-2 text-sm';
const msg=(e:unknown)=>e instanceof V21ApiError?
 e.status===403?'Operations permission is required.':e.status===409?'A linked area or business state prevents this change. Resolve dependencies first.':e.message:
 'Could not load delivery configuration.';
export function DeliveryAdminPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<'cities'|'zones'|'promotions'>('cities');
 const [cities,setCities]=useState<City[]>([]);
 const [areas,setAreas]=useState<Zone[]>([]);
 const [promos,setPromos]=useState<Promo[]>([]);
 const [selectedCity,setSelectedCity]=useState('');
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [name,setName]=useState('');
 const [code,setCode]=useState('');
 const [state,setState]=useState('TG');
 const [pins,setPins]=useState('');
 const [promoType,setPromoType]=useState<'PERCENTAGE'|'FIXED_PAISE'|'FREE_DELIVERY'>('FREE_DELIVERY');
 const [promoValue,setPromoValue]=useState('');
 const [start,setStart]=useState('');
 const [end,setEnd]=useState('');
 const [confirm,setConfirm]=useState<{type:'city'|'area'|'promo';id:string;active:boolean;name:string}|null>(null);
 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [c,p]=await Promise.all([
    api.get<City[]>('/api/v2/admin/delivery/cities',signal),
    api.get<Promo[]>('/api/v2/admin/promotions',signal)
   ]);
   if(!Array.isArray(c.data)||!Array.isArray(p.data))throw new Error('Invalid delivery config response');
   if(!signal?.aborted){setCities(c.data);setPromos(p.data);}
  }catch(e){if(!signal?.aborted)setError(msg(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 const loadAreas=useCallback(async(cityId:string,signal?:AbortSignal)=>{
  if(!cityId){setAreas([]);return;}
  try{
   const response=await api.get<Zone[]>('/api/v2/admin/delivery/areas?cityId='+encodeURIComponent(cityId),signal);
   if(!Array.isArray(response.data))throw new Error('Invalid delivery area response');
   if(!signal?.aborted)setAreas(response.data);
  }catch(e){if(!signal?.aborted)setError(msg(e));}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);
 useEffect(()=>{const c=new AbortController();void loadAreas(selectedCity,c.signal);return ()=>c.abort();},[selectedCity,loadAreas]);
 async function save(fn:()=>Promise<unknown>,noticeText:string){
  if(busy)return;setBusy(true);setError('');setNotice('');
  try{await fn();await load();if(selectedCity)await loadAreas(selectedCity);setNotice(noticeText);}
  catch(e){setError(msg(e));}finally{setBusy(false);}
 }
 function addCity(e:FormEvent<HTMLFormElement>){
  e.preventDefault();
  void save(async()=>{await api.write('POST','/api/v2/admin/delivery/cities',{code:code.trim().toUpperCase(),name:name.trim(),stateCode:state.trim().toUpperCase()});setCode('');setName('');},'City created inactive. Activate before adding delivery zones.');
 }
 function addArea(e:FormEvent<HTMLFormElement>){
  e.preventDefault();
  const postalCodes=pins.split(/[,\s]+/).map(s=>s.trim()).filter(Boolean);
  if(!postalCodes.length||new Set(postalCodes).size!==postalCodes.length||postalCodes.some(x=>!/^[1-9]\d{5}$/.test(x))){setError('Enter unique six-digit Indian PIN codes.');return;}
  void save(async()=>{await api.write('POST','/api/v2/admin/delivery/areas',{cityId:selectedCity,name:name.trim(),postalCodes});setName('');setPins('');},'Delivery area created inactive; enable when ready.');
 }
 function addPromo(e:FormEvent<HTMLFormElement>){
  e.preventDefault();
  const startIso=new Date(start).toISOString(),endIso=new Date(end).toISOString();
  const body={
   code:code.trim().toUpperCase(),title:name.trim(),type:promoType,
   startsAt:startIso,endsAt:endIso,
   ...(promoType==='PERCENTAGE'?{percentageBps:Number(promoValue)}:{}),
   ...(promoType==='FIXED_PAISE'?{amountPaise:promoValue.trim()}:{}),
  };
  void save(async()=>{await api.write('POST','/api/v2/admin/promotions',body);setName('');setCode('');setPromoValue('');},'Promotion created inactive; it cannot grant an unchecked discount.');
 }
 function applyChange(){
  if(!confirm)return;
  const c=confirm;setConfirm(null);
  const path=c.type==='city'?'/api/v2/admin/delivery/cities/':c.type==='area'?'/api/v2/admin/delivery/areas/':'/api/v2/admin/promotions/';
  void save(()=>api.write('PATCH',path+encodeURIComponent(c.id),{active:!c.active}),c.name+' status updated.');
 }
 return <div className="space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
  <div className="flex gap-3"><MapPin size={22} className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Delivery areas and promotions</h2><p className="text-sm text-slate-500">Only configured active cities and PIN zones are eligible for supplier delivery. Supplier-specific fees stay with suppliers.</p></div></div>
  <div className="flex flex-wrap gap-2" role="tablist" aria-label="Delivery configuration">
   {(['cities','zones','promotions'] as const).map(t=><button type="button" role="tab" aria-selected={tab===t} key={t} onClick={()=>{setTab(t);setName('');setCode('');setError('');}} className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===t?'bg-[#174C86] text-white':'border')}>{t==='cities'?'Cities':t==='zones'?'PIN zones':'Promotions'}</button>)}
  </div>
  {error&&<p role="alert" className="rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
  {notice&&<p role="status" className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
  {loading?<p role="status">Loading configuration…</p>:<>
   {tab==='cities'&&<>
    <form onSubmit={addCity} className="grid gap-3 rounded-xl bg-slate-50 p-4 sm:grid-cols-4">
     <label className="text-xs font-bold">City name<input required maxLength={120} value={name} onChange={e=>setName(e.target.value)} className={cls+' mt-1'}/></label>
     <label className="text-xs font-bold">Unique code<input required pattern="[A-Za-z0-9_-]{2,32}" value={code} onChange={e=>setCode(e.target.value)} className={cls+' mt-1'}/></label>
     <label className="text-xs font-bold">State code<input required pattern="[A-Za-z]{2}" maxLength={2} value={state} onChange={e=>setState(e.target.value)} className={cls+' mt-1'}/></label>
     <button disabled={busy} type="submit" className="self-end rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Add city</button>
    </form>
    <ul className="divide-y">{cities.map(c=><li key={c.id} className="flex flex-wrap items-center justify-between gap-3 py-4 text-sm"><span><b>{c.name}</b> · {c.code} · {c.stateCode}</span><span>{c.active?'Active':'Inactive'} <button type="button" onClick={()=>setConfirm({type:'city',id:c.id,active:c.active,name:c.name})} className="ml-3 rounded-lg border px-3 py-2 font-bold">{c.active?'Deactivate':'Activate'}</button></span></li>)}</ul>
   </>}
   {tab==='zones'&&<>
    <label className="block text-sm font-bold">City<select className={cls+' mt-2'} value={selectedCity} onChange={e=>setSelectedCity(e.target.value)}><option value="">Choose a city</option>{cities.map(c=><option key={c.id} value={c.id}>{c.name} {c.active?'(active)':'(inactive)'}</option>)}</select></label>
    {selectedCity&&<form onSubmit={addArea} className="grid gap-3 rounded-xl bg-slate-50 p-4 sm:grid-cols-3">
     <label className="text-xs font-bold">Zone name<input required value={name} onChange={e=>setName(e.target.value)} className={cls+' mt-1'} maxLength={150}/></label>
     <label className="text-xs font-bold">PIN codes (comma separated)<input required value={pins} onChange={e=>setPins(e.target.value)} placeholder="500001,500002" className={cls+' mt-1'}/></label>
     <button disabled={busy} className="self-end rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Add inactive zone</button>
    </form>}
    {areas.map(a=><div key={a.id} className="flex flex-wrap items-center justify-between gap-3 border-b py-4 text-sm"><div><b>{a.name}</b><p className="text-xs text-slate-500">PIN {a.postalCodes.join(', ')}{a.radiusKm?' · Radius '+a.radiusKm+' km':''}</p></div><div>{a.active?'Active':'Inactive'} <button type="button" className="ml-3 rounded-lg border px-3 py-2 font-semibold" onClick={()=>setConfirm({type:'area',id:a.id,active:a.active,name:a.name})}>{a.active?'Deactivate':'Activate'}</button></div></div>)}
    {selectedCity&&areas.length===0&&<p className="text-sm text-slate-500">No configured zones for this city yet.</p>}
   </>}
   {tab==='promotions'&&<>
    <div className="flex items-center gap-2"><TicketPercent size={18}/><p className="text-sm">Promotions remain inactive until explicitly approved. Money amounts are exact paise strings.</p></div>
    <form onSubmit={addPromo} className="grid gap-3 rounded-xl bg-slate-50 p-4 sm:grid-cols-3">
     <label className="text-xs font-bold">Code<input required value={code} onChange={e=>setCode(e.target.value)} pattern="[a-zA-Z0-9_-]{3,60}" className={cls+' mt-1'}/></label>
     <label className="text-xs font-bold">Title<input required value={name} onChange={e=>setName(e.target.value)} className={cls+' mt-1'}/></label>
     <label className="text-xs font-bold">Type<select value={promoType} onChange={e=>setPromoType(e.target.value as typeof promoType)} className={cls+' mt-1'}><option value="FREE_DELIVERY">Free delivery</option><option value="FIXED_PAISE">Fixed paise</option><option value="PERCENTAGE">Percentage (basis points)</option></select></label>
     {promoType!=='FREE_DELIVERY'&&<label className="text-xs font-bold">{promoType==='PERCENTAGE'?'Percentage BPS':'Amount in paise'}<input required inputMode="numeric" pattern="[0-9]+" value={promoValue} onChange={e=>setPromoValue(e.target.value)} className={cls+' mt-1'}/></label>}
     <label className="text-xs font-bold">Start (local time)<input required type="datetime-local" value={start} onChange={e=>setStart(e.target.value)} className={cls+' mt-1'}/></label>
     <label className="text-xs font-bold">End (local time)<input required type="datetime-local" value={end} onChange={e=>setEnd(e.target.value)} className={cls+' mt-1'}/></label>
     <button disabled={busy} className="self-end rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Create inactive promotion</button>
    </form>
    <ul className="divide-y">{promos.map(p=><li key={p.id} className="flex flex-wrap items-center justify-between gap-3 py-4 text-sm"><div><b>{p.title}</b> · {p.code}<p className="text-xs text-slate-500">{p.type} · {p.startsAt.slice(0,10)} – {p.endsAt.slice(0,10)} · {p.active?'Active':'Inactive'}</p></div><button type="button" className="rounded-lg border px-3 py-2 font-semibold" onClick={()=>setConfirm({type:'promo',id:p.id,active:p.active,name:p.title})}>{p.active?'Deactivate':'Activate'}</button></li>)}</ul>
   </>}
  </>}
  {confirm&&<div role="dialog" aria-label="Confirm delivery configuration change" aria-modal="true" className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4"><div className="w-full max-w-sm rounded-xl bg-white p-6 shadow-lg"><h3 className="text-lg font-bold">Confirm change</h3><p className="my-4 text-sm">Update {confirm.name}? A change can affect customer delivery eligibility or discounts.</p><div className="flex gap-3"><button disabled={busy} onClick={applyChange} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white">Confirm</button><button onClick={()=>setConfirm(null)} className="rounded-lg border px-4 py-2 text-sm font-semibold">Cancel</button></div></div></div>}
 </div>;
}
