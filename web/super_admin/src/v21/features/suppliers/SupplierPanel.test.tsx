// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {SupplierPanel} from './SupplierPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';

const supplier='22222222-2222-4222-a222-222222222222';
const owner='11111111-1111-4111-a111-111111111111';
const reviewer='33333333-3333-4333-a333-333333333333';
const row={id:supplier,slug:'example',displayName:'Example Cement',legalName:'Example Cement Ltd',approval:'PENDING',
 gstRegistration:'UNREGISTERED',gstin:null,verifiedAt:null,suspendedAt:null,createdAt:'2026-11-04T01:00:00Z'};
const document={id:'44444444-4444-4444-a444-444444444444',documentType:'BUSINESS_REGISTRATION',status:'UPLOADED',
 reviewNote:null,mimeType:'application/pdf',sizeBytes:'3210',digestAvailable:true,expiresAt:null,createdAt:'2026-11-04T01:00:00Z'};
const detail={...row,contactEmail:'contact@example.test',contactPhone:null,businessType:null,billingAddress:{line1:'Office'},
 owners:[{userId:owner,displayName:'Supplier Owner',email:'owner@example.test',active:false}],documents:[document]};
afterEach(()=>{cleanup();vi.restoreAllMocks();});
function setup(myId=reviewer){
 const api={
  get:vi.fn(async(path:string)=>path.includes(supplier)?{data:detail,requestId:'detail'}:
   {data:{items:[row],nextCursor:null},requestId:'list'}),
  write:vi.fn(async()=>({data:{},requestId:'saved'}))
 };
 render(<V21ApiProvider client={api as unknown as V21ApiClient}><SupplierPanel currentAdminId={myId}/></V21ApiProvider>);
 return api;
}
describe('A06 supplier approval UI',()=>{
 it('shows real queue, private evidence review instructions and audit reason before actions',async()=>{
  const api=setup();
  await screen.findByText('Example Cement');
  expect(api.get).toHaveBeenCalledWith('/api/v2/admin/suppliers?limit=25&status=PENDING',expect.anything());
  fireEvent.click(screen.getByRole('button',{name:'View details'}));
  await screen.findByText('Evidence checklist');
  expect(screen.getByText(/Download and inspect each document/i)).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Verify'}));
  expect(screen.getByRole('button',{name:'Confirm reviewed decision'}).hasAttribute('disabled')).toBe(true);
  fireEvent.change(screen.getByLabelText(/Mandatory audit reason/),{target:{value:'Business identity checked via approved offline review'}});
  fireEvent.click(screen.getByRole('button',{name:'Confirm reviewed decision'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST',
   '/api/v2/admin/suppliers/'+supplier+'/documents/'+document.id+'/review',{
    decision:'VERIFIED',reason:'Business identity checked via approved offline review'
   }));
 });
 it('prevents supplier members from accessing review controls',async()=>{
  setup(owner);
  await screen.findByText('Example Cement');
  fireEvent.click(screen.getByRole('button',{name:'View details'}));
  await screen.findByText('Evidence checklist');
  expect(screen.getByText('You are a member of this supplier. Independent review is required.')).toBeTruthy();
  expect(screen.queryByRole('button',{name:'Verify'})).toBeNull();
  expect(screen.queryByRole('button',{name:'APPROVED'})).toBeNull();
 });
 it('filters by current application status without fake counters',async()=>{
  const api=setup();
  await screen.findByText('Example Cement');
  fireEvent.change(screen.getByLabelText('Approval status'),{target:{value:'REJECTED'}});
  await waitFor(()=>expect(api.get).toHaveBeenCalledWith(
   '/api/v2/admin/suppliers?limit=25&status=REJECTED',expect.anything()));
 });
});
