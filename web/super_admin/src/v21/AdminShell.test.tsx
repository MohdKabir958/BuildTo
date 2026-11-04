// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {AdminShell} from './AdminShell';
import {fetchPublicRelease,validateApiOrigin} from './publicRelease';

afterEach(()=>{cleanup();vi.unstubAllGlobals();vi.restoreAllMocks();});

describe('BuildTo A01 admin shell',()=>{
  it('shows real empty-state foundation, without legacy requests or invented KPIs',()=>{
    const fetch=vi.fn();vi.stubGlobal('fetch',fetch);
    render(<AdminShell apiBaseUrl=""/>);
    expect(screen.getByRole('heading',{name:'Built for better marketplace operations.'})).toBeTruthy();
    expect(screen.getByText('API origin not configured')).toBeTruthy();
    expect(screen.getByRole('button',{name:'Suppliers'})).toBeTruthy();
    expect(screen.queryByText(/restaurant|rider|grozo|₹[0-9]/i)).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button',{name:'Catalog'}));
    expect(screen.getByText(/This module is not connected yet/)).toBeTruthy();
    expect(fetch).not.toHaveBeenCalled();
  });

  it('uses only public V2.1 system metadata and never sends bearer credentials',async()=>{
    const fetch=vi.fn(async()=>new Response(JSON.stringify({data:{
      apiVersion:'v2',releaseStage:'unreleased-staging-candidate',productionReady:false,
      automaticRefundExecution:false,automaticPayoutExecution:false,
    }}),{status:200,headers:{'Content-Type':'application/json'}}));
    vi.stubGlobal('fetch',fetch);
    render(<AdminShell apiBaseUrl="https://buildto-v21-staging.onrender.com"/>);
    await waitFor(()=>expect(screen.getByText('V2.1 staging API verified')).toBeTruthy());
    expect(fetch).toHaveBeenCalledWith('https://buildto-v21-staging.onrender.com/api/v2/system',
      expect.objectContaining({credentials:'omit',method:'GET'}));
    const sent=fetch.mock.calls[0][1] as RequestInit;
    expect(sent.headers).not.toHaveProperty('Authorization');
    expect(screen.getByText('disabled')).toBeTruthy();
  });

  it('opens and closes mobile navigation with Escape',()=>{
    render(<AdminShell apiBaseUrl=""/>);
    fireEvent.click(screen.getByRole('button',{name:'Open navigation'}));
    expect(screen.getByRole('dialog',{name:'Mobile navigation'})).toBeTruthy();
    fireEvent.keyDown(document,{key:'Escape'});
    expect(screen.queryByRole('dialog',{name:'Mobile navigation'})).toBeNull();
  });
});

describe('BuildTo public API origin contract',()=>{
  it('rejects arbitrary origins and paths',()=>{
    expect(()=>validateApiOrigin('http://other.example')).toThrow();
    expect(()=>validateApiOrigin('https://buildto.example/path')).toThrow();
    expect(()=>validateApiOrigin('https://user:pass@buildto.example')).toThrow();
    expect(validateApiOrigin('http://localhost:3000')).toBe('http://localhost:3000');
  });
  it('fails closed on production-ready or automatic money execution',async()=>{
    vi.stubGlobal('fetch',vi.fn(async()=>new Response(JSON.stringify({data:{
      apiVersion:'v2',releaseStage:'production',productionReady:true,
      automaticRefundExecution:true,automaticPayoutExecution:true,
    }}),{status:200})));
    await expect(fetchPublicRelease('https://buildto.example')).rejects.toThrow(/safety contract/);
  });
});
