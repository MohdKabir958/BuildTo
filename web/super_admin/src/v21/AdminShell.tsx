import {useEffect,useMemo,useState} from 'react';
import {
  ArrowRight, Building2, CircleHelp, Command, ExternalLink, LockKeyhole,
  LogOut, Menu, RefreshCw, ShieldCheck, X,
} from 'lucide-react';
import type {Section,SectionId} from './navigation';
import {FEATURE_ORDER,SECTIONS} from './navigation';
import {fetchPublicRelease,validateApiOrigin} from './publicRelease';
import type {PublicRelease} from './publicRelease';
import {canViewSection} from './auth/roles';
import {TeamPanel} from './features/team/TeamPanel';
import {SupplierPanel} from './features/suppliers/SupplierPanel';
import type {VerifiedAdminSession} from './auth/adminSession';

type Connection={state:'unconfigured'|'checking'|'connected'|'failed';release?:PublicRelease};
type Props={apiBaseUrl?:string;administrator?:VerifiedAdminSession;onSignOut?:()=>void};
const groupNames=['Marketplace','Operations','Administration'] as const;
const byId=(id:SectionId):Section=>SECTIONS.find(s=>s.id===id)!;

export function AdminShell({apiBaseUrl,administrator,onSignOut}:Props) {
  const [active,setActive]=useState<SectionId>('overview');
  const [mobileOpen,setMobileOpen]=useState(false);
  const origin=apiBaseUrl??import.meta.env.VITE_API_BASE_URL??'';
  const [connection,setConnection]=useState<Connection>({state:origin?'checking':'unconfigured'});
  const [refresh,setRefresh]=useState(0);
  const current=useMemo(()=>byId(active),[active]);
  const visibleSections=useMemo(()=>SECTIONS.filter(s=>!administrator||canViewSection(administrator.role,s.id)),[administrator]);

  useEffect(()=>{
    if(!origin){setConnection({state:'unconfigured'});return;}
    const controller=new AbortController();
    setConnection({state:'checking'});
    fetchPublicRelease(origin,controller.signal)
      .then(release=>{if(!controller.signal.aborted)setConnection({state:'connected',release});})
      .catch(()=>{if(!controller.signal.aborted)setConnection({state:'failed'});});
    return ()=>controller.abort();
  },[origin,refresh]);

  useEffect(()=>{
    if(!mobileOpen)return;
    const onKey=(event:KeyboardEvent)=>{if(event.key==='Escape')setMobileOpen(false);};
    document.addEventListener('keydown',onKey);
    return ()=>document.removeEventListener('keydown',onKey);
  },[mobileOpen]);

  const navigate=(section:SectionId)=>{
    setActive(section);setMobileOpen(false);
  };
  const statusText={
    unconfigured:'API origin not configured',
    checking:'Checking API…',
    connected:'V2.1 staging API verified',
    failed:'API unavailable or safety check failed',
  }[connection.state];

  const sidebar=(
    <>
      <div className="flex items-center gap-3 border-b border-white/10 px-6 py-7">
        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-amber-400 text-2xl font-black text-slate-950" aria-hidden="true">B</div>
        <div>
          <p className="text-xl font-black leading-none tracking-tight text-white">BuildTo</p>
          <p className="mt-1 text-xs font-semibold tracking-wide text-slate-300">ADMIN CONSOLE</p>
        </div>
      </div>
      <nav aria-label="Admin sections" className="flex-1 overflow-y-auto px-3 py-5">
        {groupNames.map(group=>(
          <div key={group} className="mb-7">
            <p className="px-3 pb-3 text-[10px] font-bold uppercase tracking-[0.19em] text-slate-400">{group}</p>
            <div className="space-y-1">
              {visibleSections.filter(section=>section.group===group).map(section=>{
                const Icon=section.icon;
                return <button
                  key={section.id}
                  type="button"
                  onClick={()=>navigate(section.id)}
                  aria-current={active===section.id?'page':undefined}
                  className={`flex min-h-[44px] w-full items-center gap-3 rounded-xl px-3 text-left text-sm font-semibold transition-colors ${active===section.id?'bg-white text-slate-900 shadow-sm':'text-slate-300 hover:bg-white/10 hover:text-white'}`}>
                  <Icon size={18} aria-hidden="true"/>
                  <span>{section.label}</span>
                </button>;
              })}
            </div>
          </div>
        ))}
      </nav>
      <div className="border-t border-white/10 px-5 py-5">
        <div className="flex gap-3 rounded-xl bg-white/10 p-3">
          <LockKeyhole className="mt-0.5 shrink-0 text-amber-300" size={18} aria-hidden="true"/>
          <div>
            <p className="text-xs font-bold text-white">{administrator?'Verified admin session':'Staging preview only'}</p>
            <p className="mt-1 text-xs leading-relaxed text-slate-300">{administrator?administrator.displayName+' · '+administrator.role+' · Permissions enforced by the server.':'Clerk sign-in is required before any private module is enabled. Preview loads no private data.'}</p>
          </div>
        </div>
      </div>
    </>
  );

  return <div className="min-h-screen bg-[#F5F7FB] text-[#172D49]">
    <div className="flex min-h-screen">
      <aside aria-label="Desktop navigation" className="sticky top-0 hidden h-screen w-[258px] shrink-0 flex-col bg-[#102B4D] lg:flex">{sidebar}</aside>
      {mobileOpen&&<div className="fixed inset-0 z-40 lg:hidden">
        <div className="absolute inset-0 bg-[#10213D]/70" aria-hidden="true" onClick={()=>setMobileOpen(false)}/>
        <div role="dialog" aria-modal="true" aria-label="Mobile navigation" className="absolute inset-y-0 left-0 flex w-[min(85vw,300px)] flex-col bg-[#102B4D] shadow-2xl">
          <button type="button" className="absolute right-3 top-3 z-10 flex h-9 w-9 items-center justify-center rounded-full text-white hover:bg-white/10" aria-label="Close navigation" onClick={()=>setMobileOpen(false)}><X size={19}/></button>
          {sidebar}
        </div>
      </div>}
      <div className="min-w-0 flex-1">
        <header className="sticky top-0 z-20 flex min-h-[80px] items-center justify-between border-b border-slate-200 bg-white/95 px-4 backdrop-blur sm:px-8">
          <div className="flex items-center gap-4">
            <button type="button" className="inline-flex h-11 w-11 items-center justify-center rounded-xl border border-slate-200 lg:hidden" aria-label="Open navigation" onClick={()=>setMobileOpen(true)}><Menu size={21}/></button>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-slate-500">BuildTo / Administration</p>
              <h1 className="mt-1 text-xl font-extrabold tracking-tight sm:text-2xl">{current.label}</h1>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {administrator&&<span className="hidden rounded-full border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-700 sm:inline-flex">{administrator.role}</span>}
            <span className="flex items-center gap-2 rounded-full border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-bold text-amber-800" title="Production is disabled"><span className="h-2 w-2 rounded-full bg-amber-500" aria-hidden="true"/>Staging</span>
            {administrator&&onSignOut&&<button type="button" onClick={onSignOut} className="inline-flex min-h-10 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50"><LogOut size={15}/>Sign out</button>}
          </div>
        </header>
        <main id="main-content" className="mx-auto max-w-[1250px] px-4 py-8 sm:px-8 sm:py-10">
          <div className="mb-7 flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-slate-500">{current.caption}</p>
            <div className="flex items-center gap-2">
              <span role="status" className={`rounded-full border px-3 py-1.5 text-xs font-semibold ${connection.state==='connected'?'border-emerald-200 bg-emerald-50 text-emerald-800':connection.state==='failed'?'border-rose-200 bg-rose-50 text-rose-700':'border-slate-200 bg-white text-slate-600'}`}>{statusText}</span>
              {origin&&<button type="button" aria-label="Recheck staging API" onClick={()=>setRefresh(n=>n+1)} className="flex h-9 w-9 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-600 hover:text-slate-950"><RefreshCw size={17}/></button>}
            </div>
          </div>
          {active==='overview'
            ? <Overview onNavigate={navigate} connection={connection} administrator={administrator} />
            : active==='suppliers'&&administrator&&['OWNER','OPERATIONS'].includes(administrator.role)
            ? <SupplierPanel currentAdminId={administrator.id}/>
            : active==='team'&&administrator?.role==='OWNER'
            ? <TeamPanel currentAdminId={administrator.id}/>
            : <ModulePlaceholder section={current} />}
        </main>
        <footer className="mx-auto flex max-w-[1250px] flex-wrap justify-between gap-3 px-4 pb-8 text-xs text-slate-500 sm:px-8">
          <span>BuildTo V2.1 · Administrator workspace</span>
          <span>{administrator?'Clerk identity verified; server permissions remain authoritative.':'Public preview only. No administrator data is loaded.'}</span>
        </footer>
      </div>
    </div>
  </div>;
}

function Overview({onNavigate,connection,administrator}:{onNavigate:(id:SectionId)=>void;connection:Connection;administrator?:VerifiedAdminSession}){
  return <>
    <section className="relative overflow-hidden rounded-[26px] bg-[#102B4D] px-6 py-9 text-white shadow-lg sm:px-10 sm:py-11">
      <div className="pointer-events-none absolute -right-14 -top-24 h-64 w-64 rounded-full border-[40px] border-white/5" aria-hidden="true"/>
      <div className="relative max-w-2xl">
        <div className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-3 py-1 text-xs font-bold text-amber-200"><ShieldCheck size={15}/> BuildTo V2.1</div>
        <h2 className="mt-5 text-3xl font-extrabold tracking-tight sm:text-4xl">Built for better marketplace operations.</h2>
        <p className="mt-4 max-w-xl text-sm leading-7 text-slate-200">{administrator?'Your Clerk session and admin role are verified by the V2.1 API. Modules will appear as they pass business-workflow tests—without mock totals or unauthorized actions.':'Your construction-materials operations workspace is being connected to the V2.1 backend. Modules appear as they pass role and integration testing—without mock transactions or invented totals.'}</p>
      </div>
    </section>
    <section aria-labelledby="setup-title" className="mt-8">
      <div className="mb-4 flex items-center justify-between gap-2">
        <h3 id="setup-title" className="text-lg font-extrabold">Workspace modules</h3>
        <span className="text-xs font-medium text-slate-500">Implementation in progress</span>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {FEATURE_ORDER.filter(id=>!administrator||canViewSection(administrator.role,id)).map(id=>{
          const section=byId(id),Icon=section.icon;
          return <button type="button" key={id} onClick={()=>onNavigate(id)} className="group rounded-2xl border border-slate-200 bg-white p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-[#95AAC2] hover:shadow-md">
            <span className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-[#EAF1FA] text-[#174C86]"><Icon size={20}/></span>
            <h4 className="mt-6 text-base font-bold">{section.label}</h4>
            <p className="mt-2 min-h-[48px] text-xs leading-5 text-slate-500">{section.caption}</p>
            <span className="mt-4 flex items-center justify-between border-t border-slate-100 pt-3 text-xs font-bold text-[#174C86]">
              Integration {section.plannedPr}<ArrowRight size={16} className="transition group-hover:translate-x-0.5"/>
            </span>
          </button>;
        })}
      </div>
    </section>
    <section className="mt-8 grid gap-4 lg:grid-cols-2">
      <div className="rounded-2xl border border-slate-200 bg-white p-6">
        <div className="flex items-center gap-3"><Command size={20} className="text-[#174C86]"/><h3 className="font-bold">Backend release contract</h3></div>
        {connection.state==='connected'&&connection.release
          ? <div className="mt-5 space-y-2 text-sm"><p>API version: <strong>{connection.release.apiVersion}</strong></p><p>Release stage: <strong>{connection.release.releaseStage}</strong></p><p>Production readiness: <strong>disabled</strong></p><p>Automatic refund and payout execution: <strong>disabled</strong></p></div>
          : <p className="mt-4 text-sm leading-6 text-slate-500">No verified backend metadata loaded. Configure the exact public staging API origin to check its release flags; this panel never guesses readiness.</p>}
      </div>
      <div className="rounded-2xl border border-slate-200 bg-white p-6">
        <div className="flex items-center gap-3"><CircleHelp size={20} className="text-[#174C86]"/><h3 className="font-bold">{administrator?'Next milestone: typed API integration':'Next milestone: secure admin sign-in'}</h3></div>
        <p className="mt-4 text-sm leading-6 text-slate-500">{administrator?'A03 introduces the typed V2.1 request client and conflict handling. Business modules are not activated until their API permissions and tests are complete.':<>A02 connects Clerk to the database-backed <code className="rounded bg-slate-100 px-1 py-0.5 text-xs">/api/v2/admin/access</code> endpoint. Until then, this preview intentionally exposes no admin data, management buttons or financial actions.</>}</p>
      </div>
    </section>
  </>;
}

function ModulePlaceholder({section}:{section:Section}){
  const Icon=section.icon;
  return <section className="rounded-[24px] border border-slate-200 bg-white px-6 py-14 text-center shadow-sm sm:px-10">
    <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-[#EAF1FA] text-[#174C86]"><Icon size={29}/></div>
    <h2 className="mt-5 text-xl font-extrabold">{section.label}</h2>
    <p className="mx-auto mt-3 max-w-lg text-sm leading-7 text-slate-600">{section.caption}. This module is not connected yet; no fabricated data or unauthorized API calls are shown.</p>
    <span className="mt-6 inline-flex items-center gap-2 rounded-full border border-slate-200 bg-slate-50 px-4 py-2 text-xs font-bold text-slate-600"><Building2 size={15}/> Scheduled for {section.plannedPr}</span>
    <a href="https://buildto-v21-staging.onrender.com/ready" target="_blank" rel="noreferrer" className="mx-auto mt-7 flex w-fit items-center gap-1 text-sm font-semibold text-[#174C86] underline-offset-4 hover:underline">Staging API readiness <ExternalLink size={14}/></a>
  </section>;
}
