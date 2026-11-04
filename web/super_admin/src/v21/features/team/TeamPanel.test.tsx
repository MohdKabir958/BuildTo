// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {TeamPanel} from './TeamPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';

const ownerId='11111111-1111-4111-a111-111111111111';
const staffId='22222222-2222-4222-a222-222222222222';
const items=[
 {userId:ownerId,displayName:'Platform Owner',email:'owner@example.test',role:'OWNER',active:true,createdAt:'2026-11-04T01:00:00Z',revokedAt:null},
 {userId:staffId,displayName:'Catalog Operator',email:'catalog@example.test',role:'CATALOG',active:true,createdAt:'2026-11-04T01:00:00Z',revokedAt:null},
];
const page={data:{items,nextCursor:null},requestId:'req-team'};
afterEach(()=>{cleanup();vi.restoreAllMocks();});
function setup(){
 const api={get:vi.fn(async()=>page),write:vi.fn(async()=>({data:{},requestId:'req-save'}))};
 const ui=render(<V21ApiProvider client={api as unknown as V21ApiClient}><TeamPanel currentAdminId={ownerId}/></V21ApiProvider>);
 return {api,...ui};
}
describe('A04 team management UI',()=>{
 it('loads real team entries and prevents self-management controls',async()=>{
   const {api}=setup();
   await screen.findByText('Platform Owner');
   expect(screen.getByText('Catalog Operator')).toBeTruthy();
   expect(screen.queryByRole('button',{name:'Revoke Platform Owner'})).toBeNull();
   expect(screen.getByRole('button',{name:'Revoke Catalog Operator'})).toBeTruthy();
   expect(api.get).toHaveBeenCalledWith('/api/v2/admin/team?limit=25',expect.anything());
 });
 it('grants only a verified existing Clerk user and records an audit reason',async()=>{
   const {api}=setup();await screen.findByText('Catalog Operator');
   fireEvent.change(screen.getByLabelText('Verified Clerk email'),{target:{value:'new@example.test'}});
   fireEvent.change(screen.getByLabelText('Reason for grant'),{target:{value:'Verified catalog operator for BuildTo'}});
   fireEvent.click(screen.getByRole('button',{name:'Grant access'}));
   await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/team',{
     email:'new@example.test',role:'CATALOG',reason:'Verified catalog operator for BuildTo',
   }));
 });
 it('requires reason before revoking and allows cancellation',async()=>{
   const {api}=setup();await screen.findByText('Catalog Operator');
   fireEvent.click(screen.getByRole('button',{name:'Revoke Catalog Operator'}));
   expect(screen.getByRole('button',{name:'Confirm change'}).hasAttribute('disabled')).toBe(true);
   fireEvent.change(screen.getByLabelText('Audit reason'),{target:{value:'No longer on the approved team'}});
   fireEvent.click(screen.getByRole('button',{name:'Confirm change'}));
   await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/team/'+staffId+'/revoke',{
     reason:'No longer on the approved team',
   }));
 });
});
