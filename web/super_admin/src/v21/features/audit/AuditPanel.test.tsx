// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {AuditPanel} from './AuditPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';

afterEach(()=>{cleanup();vi.restoreAllMocks();});
describe('A14 audit viewer',()=>{
  it('fetches only the redacted audit page, applies filters and paginates',async()=>{
    const first={items:[{id:'11111111-1111-4111-8111-111111111111',
      createdAt:'2026-11-04T12:00:00.000Z',actorRole:'ADMIN_OWNER',
      actorUserId:null,action:'ADMIN_ACCESS_GRANTED',entityType:'AdminMembership',
      entityId:'22222222-2222-4222-8222-222222222222'}],
      nextCursor:'11111111-1111-4111-8111-111111111111'};
    const api={get:vi.fn(async()=>({data:first,requestId:'req-audit'}))};
    render(<V21ApiProvider client={api as unknown as V21ApiClient}><AuditPanel/></V21ApiProvider>);
    await screen.findByText('ADMIN_ACCESS_GRANTED');
    expect(api.get).toHaveBeenCalledWith('/api/v2/admin/audit?limit=25',expect.anything());
    fireEvent.change(screen.getByLabelText('Entity type'),{target:{value:'AdminMembership'}});
    fireEvent.change(screen.getByLabelText('Action'),{target:{value:'ADMIN_ACCESS_GRANTED'}});
    fireEvent.click(screen.getByRole('button',{name:'Apply filters'}));
    await waitFor(()=>expect(api.get).toHaveBeenCalledWith(
      '/api/v2/admin/audit?limit=25&entityType=AdminMembership&action=ADMIN_ACCESS_GRANTED',expect.anything()
    ));
    fireEvent.click(screen.getByRole('button',{name:'Load older events'}));
    await waitFor(()=>expect(api.get).toHaveBeenCalledWith(
      '/api/v2/admin/audit?limit=25&entityType=AdminMembership&action=ADMIN_ACCESS_GRANTED&cursor=11111111-1111-4111-8111-111111111111',undefined
    ));
  });
  it('handles permission denial without fake data',async()=>{
    const api={get:vi.fn(async()=>{throw new Error('offline');})};
    render(<V21ApiProvider client={api as unknown as V21ApiClient}><AuditPanel/></V21ApiProvider>);
    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(screen.queryByText('ADMIN_ACCESS_GRANTED')).toBeNull();
  });
});
