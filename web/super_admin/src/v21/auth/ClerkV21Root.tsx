import {useEffect,useState} from 'react';
import {ClerkProvider,ClerkLoaded,ClerkLoading,ClerkFailed,SignIn,UserButton,useAuth} from '@clerk/react';
import {LockKeyhole,RefreshCw,ShieldCheck} from 'lucide-react';
import {AdminShell} from '../AdminShell';
import {AdminAccessError,fetchAdminSession} from './adminSession';
import type {VerifiedAdminSession} from './adminSession';

type GateState={phase:'checking'|'allowed'|'denied';identity?:string;admin?:VerifiedAdminSession;error?:string};
const stagingOnly=(mode:string|undefined,key:string)=>mode==='clerk-test'&&key.startsWith('pk_test_');

function Frame({children}:{children:React.ReactNode}) {
  return <main className="flex min-h-screen items-center justify-center bg-[#F5F7FB] px-4 py-10 text-[#172D49]">
    <div className="w-full max-w-md rounded-[24px] border border-slate-200 bg-white p-7 shadow-xl sm:p-9">
      <div className="mb-7 flex items-center gap-3">
        <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-[#102B4D] text-2xl font-black text-amber-300" aria-hidden="true">B</span>
        <div><p className="text-lg font-extrabold">BuildTo</p><p className="text-xs font-medium text-slate-500">Secure administrator workspace</p></div>
      </div>
      {children}
    </div>
  </main>;
}

function ClerkV21Gate() {
  const {isLoaded,isSignedIn,userId,sessionId,getToken,signOut}=useAuth();
  const [retry,setRetry]=useState(0);
  const [state,setState]=useState<GateState>({phase:'checking'});
  const identity=userId&&sessionId?userId+':'+sessionId:'';
  const apiBaseUrl=import.meta.env.VITE_API_BASE_URL||'';

  useEffect(()=>{
    if(!isLoaded||!isSignedIn||!identity){setState({phase:'checking'});return;}
    const controller=new AbortController();
    const timer=window.setTimeout(()=>controller.abort(),12000);
    setState({phase:'checking'});
    (async()=>{
      try {
        if(!apiBaseUrl)throw new AdminAccessError(503,'Backend API origin has not been configured');
        const token=await getToken();
        if(!token)throw new AdminAccessError(401,'Clerk session token is missing');
        const admin=await fetchAdminSession(apiBaseUrl,token,controller.signal);
        if(!controller.signal.aborted)setState({phase:'allowed',identity,admin});
      }catch(error){
        if(controller.signal.aborted)return;
        const message=error instanceof AdminAccessError && error.status===403
          ?'Your Clerk account is not an active BuildTo administrator. Ask the owner to grant access.'
          :error instanceof AdminAccessError && error.status===401
          ?'Clerk could not authorize this session. Sign out and sign in again.'
          :'Cannot verify admin access. Check the API connection and retry.';
        setState({phase:'denied',identity,error:message});
      }finally{window.clearTimeout(timer);}
    })();
    return ()=>{controller.abort();window.clearTimeout(timer);};
  },[isLoaded,isSignedIn,identity,getToken,apiBaseUrl,retry]);

  if(!isLoaded)return <Frame><p role="status" className="text-sm">Loading Clerk authentication…</p></Frame>;
  if(!isSignedIn)return <Frame>
    <div className="mb-5"><h1 className="text-2xl font-extrabold">Admin sign in</h1><p className="mt-2 text-sm leading-6 text-slate-600">Use your approved BuildTo Clerk account. Signing up does not grant administrator access.</p></div>
    <SignIn routing="hash" appearance={{variables:{colorPrimary:'#123E6A',borderRadius:'12px'},elements:{rootBox:'w-full',card:'shadow-none border-0',cardBox:'shadow-none'}}}/>
  </Frame>;
  if(state.phase==='allowed'&&state.identity===identity&&state.admin)
    return <><AdminShell apiBaseUrl={apiBaseUrl} administrator={state.admin} onSignOut={()=>{void signOut();}}/><div className="fixed bottom-4 right-4 z-30 rounded-full bg-white p-1 shadow-lg"><UserButton/></div></>;
  return <Frame>
    <ShieldCheck size={32} className="text-[#174C86]" aria-hidden="true"/>
    <h1 className="mt-4 text-xl font-extrabold">Verifying admin access</h1>
    <p role={state.phase==='denied'?'alert':'status'} className="mt-3 text-sm leading-6 text-slate-600">
      {state.phase==='denied'&&state.identity===identity?state.error:'Checking your Clerk identity and active database role…'}
    </p>
    {state.phase==='denied'&&state.identity===identity&&<button type="button" className="mt-6 mr-3 inline-flex min-h-11 items-center gap-2 rounded-xl bg-[#102B4D] px-5 text-sm font-semibold text-white" onClick={()=>setRetry(n=>n+1)}><RefreshCw size={16}/>Retry</button>}
    <button type="button" className="mt-6 inline-flex min-h-11 items-center gap-2 rounded-xl border border-slate-300 px-5 text-sm font-semibold" onClick={()=>{void signOut();}}><LockKeyhole size={16}/>Sign out</button>
  </Frame>;
}

export function ClerkV21Root() {
  const key=import.meta.env.VITE_CLERK_PUBLISHABLE_KEY||'';
  if(!stagingOnly(import.meta.env.VITE_AUTH_MODE,key)){
    return <Frame><h1 className="text-xl font-bold">Staging authentication not configured</h1><p className="mt-3 text-sm text-slate-600">BuildTo Admin V2.1 requires a Clerk development publishable key and clerk-test mode. No legacy passcode fallback is permitted.</p></Frame>;
  }
  return <ClerkProvider publishableKey={key} afterSignOutUrl="/">
    <ClerkLoading><Frame><p role="status" className="text-sm">Loading secure sign-in…</p></Frame></ClerkLoading>
    <ClerkFailed><Frame><p role="alert" className="text-sm">Clerk authentication could not load. Check the allowed staging origin.</p></Frame></ClerkFailed>
    <ClerkLoaded><ClerkV21Gate/></ClerkLoaded>
  </ClerkProvider>;
}
