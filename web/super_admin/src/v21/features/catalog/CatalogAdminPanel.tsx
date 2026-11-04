import {useCallback,useEffect,useState} from 'react';
import type {FormEvent} from 'react';
import {Layers3,PackageCheck,RefreshCw} from 'lucide-react';
import {useV21Api} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';

type Page<T>={items:T[];nextCursor:string|null};
type Category={id:string;name:string;slug:string;active:boolean;parentId:string|null;displayOrder:number};
type Brand={id:string;name:string;slug:string};
type Product={id:string;code:string;name:string;categoryId:string;categoryName:string;categoryActive:boolean;brandId:string|null;brandName:string|null;active:boolean;hsnCode:string|null};
type Listing={id:string;supplierId:string;productId:string;sku:string;unitCode:string;unitPrice:string;taxRateBps:number;status:string;active:boolean;version:number;minOrderQty:string};
type Unit={code:string;name:string};
type Tab='categories'|'brands'|'products'|'listings';
const LABELS:Record<Tab,string>={categories:'Categories',brands:'Brands',products:'Master products',listings:'Pending listings'};
const err=(e:unknown)=>e instanceof V21ApiError?
 e.status===409?'Another change conflicts with this catalog record. Reload and verify current data.':
 e.status===403?'You do not have catalog approval permission.':e.message:
 'Catalog request failed; check the connection and retry.';
const fieldClass='w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm';

export function CatalogAdminPanel(){
 const api=useV21Api();
 const [tab,setTab]=useState<Tab>('categories');
 const [categories,setCategories]=useState<Category[]>([]);
 const [brands,setBrands]=useState<Brand[]>([]);
 const [products,setProducts]=useState<Product[]>([]);
 const [listings,setListings]=useState<Listing[]>([]);
 const [units,setUnits]=useState<Unit[]>([]);
 const [page,setPage]=useState<Record<'categories'|'brands'|'products',string|null>>({categories:null,brands:null,products:null});
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [notice,setNotice]=useState('');
 const [newName,setNewName]=useState('');
 const [newSlug,setNewSlug]=useState('');
 const [productCode,setProductCode]=useState('');
 const [categoryId,setCategoryId]=useState('');
 const [brandId,setBrandId]=useState('');
 const [hsnCode,setHsnCode]=useState('');
 const [conversionProduct,setConversionProduct]=useState('');
 const [fromUnit,setFromUnit]=useState('');
 const [toUnit,setToUnit]=useState('');
 const [multiplier,setMultiplier]=useState('1');
 const [confirm,setConfirm]=useState<{kind:'category'|'product'|'listing';id:string;name:string;active?:boolean;version?:number;decision?:'APPROVE'|'REJECT'}|null>(null);

 const load=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{
   const [cat,brandsRes,productRes,list,unitRes]=await Promise.all([
    api.get<Page<Category>>('/api/v2/admin/catalog/categories?limit=50',signal),
    api.get<Page<Brand>>('/api/v2/admin/catalog/brands?limit=50',signal),
    api.get<Page<Product>>('/api/v2/admin/catalog/products?limit=50',signal),
    api.get<Listing[]>('/api/v2/admin/catalog/listings/pending',signal),
    api.get<Unit[]>('/api/v2/catalog/units',signal)
   ]);
   if(!Array.isArray(cat.data.items)||!Array.isArray(brandsRes.data.items)||!Array.isArray(productRes.data.items)||
      !Array.isArray(list.data)||!Array.isArray(unitRes.data))throw new Error('Invalid V2.1 catalog response');
   if(!signal?.aborted){
    setCategories(cat.data.items);setBrands(brandsRes.data.items);setProducts(productRes.data.items);
    setListings(list.data);setUnits(unitRes.data);
    setPage({categories:cat.data.nextCursor,brands:brandsRes.data.nextCursor,products:productRes.data.nextCursor});
   }
  }catch(e){if(!signal?.aborted)setError(err(e));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 useEffect(()=>{const c=new AbortController();void load(c.signal);return ()=>c.abort();},[load]);

 async function more(kind:'categories'|'brands'|'products'){
  if(!page[kind]||busy)return;
  setBusy(true);setError('');
  try{
   const next=await api.get<Page<Category|Brand|Product>>('/api/v2/admin/catalog/'+kind+'?limit=50&cursor='+encodeURIComponent(page[kind]!));
   if(!Array.isArray(next.data.items))throw new Error('Invalid page');
   if(kind==='categories')setCategories(prev=>[...prev,...next.data.items as Category[]]);
   if(kind==='brands')setBrands(prev=>[...prev,...next.data.items as Brand[]]);
   if(kind==='products')setProducts(prev=>[...prev,...next.data.items as Product[]]);
   setPage(p=>({...p,[kind]:next.data.nextCursor}));
  }catch(e){setError(err(e));}finally{setBusy(false);}
 }
 async function write(action:()=>Promise<unknown>,message:string){
  setBusy(true);setError('');setNotice('');
  try{await action();await load();setNotice(message);}catch(e){setError(err(e));}
  finally{setBusy(false);}
 }
 function create(event:FormEvent<HTMLFormElement>){
  event.preventDefault();
  if(tab==='categories')void write(async()=>{await api.write('POST','/api/v2/admin/catalog/categories',{name:newName.trim(),slug:newSlug.trim(),displayOrder:0});setNewName('');setNewSlug('');},'Inactive category created; publish it explicitly.');
  if(tab==='brands')void write(async()=>{await api.write('POST','/api/v2/admin/catalog/brands',{name:newName.trim(),slug:newSlug.trim()});setNewName('');setNewSlug('');},'Brand created.');
  if(tab==='products')void write(async()=>{await api.write('POST','/api/v2/admin/catalog/products',{
   name:newName.trim(),code:productCode.trim(),categoryId,brandId:brandId||null,
   ...(hsnCode.trim()?{hsnCode:hsnCode.trim()}:{})
  });setNewName('');setProductCode('');setHsnCode('');},'Inactive master product created; publish it explicitly.');
 }
 function conversion(event:FormEvent<HTMLFormElement>){
  event.preventDefault();
  void write(()=>api.write('POST','/api/v2/admin/catalog/products/'+encodeURIComponent(conversionProduct)+'/conversions',{
   fromUnit,toUnit,multiplier
  }),'Product unit conversion saved as an exact decimal.');
 }
 function commitConfirm(){
  if(!confirm)return;
  const pending=confirm;setConfirm(null);
  if(pending.kind==='category')
   void write(()=>api.write('PATCH','/api/v2/admin/catalog/categories/'+encodeURIComponent(pending.id),{active:!pending.active}),
    'Category status updated.');
  if(pending.kind==='product')
   void write(()=>api.write('PATCH','/api/v2/admin/catalog/products/'+encodeURIComponent(pending.id),{active:!pending.active}),
    'Product status updated.');
  if(pending.kind==='listing')
   void write(()=>api.write('POST','/api/v2/admin/catalog/listings/'+encodeURIComponent(pending.id)+'/review',{
    decision:pending.decision,expectedVersion:pending.version
   }),'Supplier listing reviewed using its current version.');
 }
 const table='w-full min-w-[550px] text-left text-sm';
 return <div className="space-y-6">
  <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex flex-wrap justify-between gap-3"><div className="flex items-center gap-3">
    <Layers3 className="text-[#174C86]"/><div><h2 className="text-lg font-extrabold">Construction materials catalog</h2>
     <p className="text-sm text-slate-500">Master data and independent supplier-listing approvals; amounts and quantities stay exact.</p></div>
   </div><button type="button" disabled={loading} onClick={()=>void load()} className="rounded-lg border px-3 py-2 text-sm font-semibold disabled:opacity-50"><RefreshCw size={16} className="mr-2 inline"/>Refresh</button></div>
   <div className="mt-5 flex flex-wrap gap-2" role="tablist" aria-label="Catalog modules">
    {(Object.keys(LABELS) as Tab[]).map(t=><button type="button" key={t} role="tab" aria-selected={tab===t}
     className={'rounded-lg px-4 py-2 text-sm font-bold '+(tab===t?'bg-[#174C86] text-white':'border border-slate-200 text-slate-700')}
     onClick={()=>{setTab(t);setConfirm(null);}}>{LABELS[t]}{t==='listings'?' ('+listings.length+')':''}</button>)}
   </div>
   {error&&<p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
   {notice&&<p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
   {loading?<p role="status" className="mt-5 text-sm text-slate-500">Loading catalog…</p>:
   <>
    {tab!=='listings'&&<form onSubmit={create} className="mt-5 flex flex-wrap items-end gap-3 rounded-xl bg-slate-50 p-4">
     <label className="min-w-[180px] flex-1 text-xs font-bold">Name<input className={fieldClass+' mt-1'} value={newName} onChange={e=>setNewName(e.target.value)} required maxLength={240}/></label>
     {tab!=='products'?
      <label className="min-w-[160px] flex-1 text-xs font-bold">Slug<input className={fieldClass+' mt-1'} value={newSlug} onChange={e=>setNewSlug(e.target.value)} required maxLength={140} pattern="[a-z0-9]+(-[a-z0-9]+)*"/></label>:
      <>
       <label className="min-w-[120px] flex-1 text-xs font-bold">Product code<input className={fieldClass+' mt-1'} value={productCode} onChange={e=>setProductCode(e.target.value)} required maxLength={80}/></label>
       <label className="min-w-[160px] flex-1 text-xs font-bold">Active category<select required className={fieldClass+' mt-1'} value={categoryId} onChange={e=>setCategoryId(e.target.value)}><option value="">Choose</option>{categories.filter(c=>c.active).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
       <label className="min-w-[120px] flex-1 text-xs font-bold">Brand (optional)<select className={fieldClass+' mt-1'} value={brandId} onChange={e=>setBrandId(e.target.value)}><option value="">Unbranded</option>{brands.map(b=><option key={b.id} value={b.id}>{b.name}</option>)}</select></label>
       <label className="min-w-[100px] flex-1 text-xs font-bold">HSN (optional)<input className={fieldClass+' mt-1'} value={hsnCode} onChange={e=>setHsnCode(e.target.value)} pattern="[0-9]{4,12}"/></label>
      </>}
     <button type="submit" disabled={busy} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Create {tab==='products'?'product':tab.slice(0,-1)}</button>
    </form>}
    <div className="mt-5 overflow-x-auto">
     {tab==='categories'&&<table className={table}><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="pb-2">Category</th><th>Slug</th><th>Status</th><th className="text-right">Action</th></tr></thead><tbody>
      {categories.map(c=><tr key={c.id} className="border-b border-slate-100"><td className="py-3 font-semibold">{c.name}</td><td>{c.slug}</td><td>{c.active?'Active':'Inactive'}</td><td className="text-right"><button type="button" onClick={()=>setConfirm({kind:'category',id:c.id,name:c.name,active:c.active})} className="rounded-lg border px-3 py-2 text-xs font-semibold">{c.active?'Deactivate':'Activate'}</button></td></tr>)}</tbody></table>}
     {tab==='brands'&&<table className={table}><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="pb-2">Brand</th><th>Slug</th></tr></thead><tbody>
      {brands.map(b=><tr key={b.id} className="border-b border-slate-100"><td className="py-3 font-semibold">{b.name}</td><td>{b.slug}</td></tr>)}</tbody></table>}
     {tab==='products'&&<table className={table}><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="pb-2">Master product</th><th>Category / brand</th><th>Status</th><th className="text-right">Action</th></tr></thead><tbody>
      {products.map(p=><tr key={p.id} className="border-b border-slate-100"><td className="py-3"><b>{p.name}</b><span className="block text-xs text-slate-500">{p.code} · HSN {p.hsnCode||'not set'}</span></td><td>{p.categoryName} / {p.brandName||'Unbranded'}</td><td>{p.active?'Published':'Inactive'}</td><td className="text-right"><button type="button" onClick={()=>setConfirm({kind:'product',id:p.id,name:p.name,active:p.active})} className="rounded-lg border px-3 py-2 text-xs font-semibold">{p.active?'Deactivate':'Publish'}</button></td></tr>)}</tbody></table>}
     {tab==='listings'&&<table className={table}><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="pb-2">Listing</th><th>Exact unit price</th><th>Version</th><th className="text-right">Moderation</th></tr></thead><tbody>
      {listings.map(l=><tr key={l.id} className="border-b border-slate-100"><td className="py-3"><b>{l.sku}</b><span className="block text-xs text-slate-500">Supplier {l.supplierId.slice(0,8)}… · {l.unitCode}</span></td><td>INR {l.unitPrice} / {l.unitCode}</td><td>{l.version}</td><td className="space-x-2 text-right">{(['APPROVE','REJECT'] as const).map(decision=><button type="button" key={decision} className="rounded-lg border px-3 py-2 text-xs font-bold" onClick={()=>setConfirm({kind:'listing',id:l.id,name:l.sku,version:l.version,decision})}>{decision==='APPROVE'?'Approve':'Reject'}</button>)}</td></tr>)}</tbody></table>}
     {((tab==='categories'&&categories.length===0)||(tab==='brands'&&brands.length===0)||(tab==='products'&&products.length===0)||(tab==='listings'&&listings.length===0))&&
      <p className="py-6 text-sm text-slate-500">No entries in this section.</p>}
    </div>
    {tab!=='listings'&&page[tab]&&<button type="button" onClick={()=>void more(tab)} disabled={busy} className="mt-3 rounded-lg border px-4 py-2 text-sm font-semibold disabled:opacity-50">Load more {tab}</button>}
   </>}
  </section>
  {tab==='products'&&<form onSubmit={conversion} className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
   <div className="flex items-center gap-2"><PackageCheck size={18}/><h3 className="font-bold">Exact product unit conversion</h3></div>
   <p className="mt-2 text-xs text-slate-500">Conversion applies to a selected master product; never use approximate floating-point money or units.</p>
   <div className="mt-4 grid gap-3 sm:grid-cols-4">
    <label className="text-xs font-bold">Product<select className={fieldClass+' mt-1'} required value={conversionProduct} onChange={e=>setConversionProduct(e.target.value)}><option value="">Choose</option>{products.map(p=><option value={p.id} key={p.id}>{p.name}</option>)}</select></label>
    <label className="text-xs font-bold">From<select className={fieldClass+' mt-1'} required value={fromUnit} onChange={e=>setFromUnit(e.target.value)}><option value="">Choose</option>{units.map(u=><option value={u.code} key={u.code}>{u.name} ({u.code})</option>)}</select></label>
    <label className="text-xs font-bold">To<select className={fieldClass+' mt-1'} required value={toUnit} onChange={e=>setToUnit(e.target.value)}><option value="">Choose</option>{units.map(u=><option value={u.code} key={u.code}>{u.name} ({u.code})</option>)}</select></label>
    <label className="text-xs font-bold">Exact multiplier<input className={fieldClass+' mt-1'} required pattern="[0-9]+(\.[0-9]{1,9})?" value={multiplier} onChange={e=>setMultiplier(e.target.value)}/></label>
   </div>
   <button type="submit" disabled={busy||!conversionProduct||!fromUnit||!toUnit||fromUnit===toUnit} className="mt-3 rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Add conversion</button>
  </form>}
  {confirm&&<div role="dialog" aria-modal="true" aria-label="Confirm catalog change" className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4">
   <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg"><h3 className="text-lg font-bold">Confirm catalog change</h3>
    <p className="mt-3 text-sm text-slate-600">Change {confirm.name}? This action affects marketplace catalog visibility and may be rejected if dependent records exist.</p>
    <div className="mt-5 flex gap-3"><button type="button" disabled={busy} onClick={commitConfirm} className="rounded-lg bg-[#174C86] px-4 py-2 text-sm font-bold text-white">Confirm</button>
     <button type="button" onClick={()=>setConfirm(null)} className="rounded-lg border px-4 py-2 text-sm font-semibold">Cancel</button></div>
   </div>
  </div>}
 </div>;
}
