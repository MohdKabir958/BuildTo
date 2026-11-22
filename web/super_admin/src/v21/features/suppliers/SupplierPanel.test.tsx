// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {SupplierPanel} from './SupplierPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import {V21ApiError} from '../../lib/apiClient';
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
function setup(myId=reviewer,options?:{documents?:typeof document[];writeError?:V21ApiError}){
 const api={
  get:vi.fn(async(path:string)=>path.includes(supplier)?{data:{...detail,documents:options?.documents??detail.documents},requestId:'detail'}:
   {data:{items:[row],nextCursor:null},requestId:'list'}),
  write:vi.fn(async()=>{if(options?.writeError)throw options.writeError;return {data:{},requestId:'saved'};})
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
 it('clearly explains missing documents and disables approval until verified',async()=>{
  setup();
  await screen.findByText('Example Cement');
  fireEvent.click(screen.getByRole('button',{name:'View details'}));
  await screen.findByText('Evidence checklist');
  expect(screen.getByText(/Approval blocked — 1 requirement outstanding/i)).toBeTruthy();
  const approve=screen.getByRole('button',{name:'Approved'});
  expect(approve.hasAttribute('disabled')).toBe(true);
  expect(screen.getByText(/Approval is disabled until all required evidence is verified/)).toBeTruthy();
 });
 it('explains backend 409 at the decision action and preserves request ID',async()=>{
  const api=setup(reviewer,{
   documents:[{...document,status:'VERIFIED'}],
   writeError:new V21ApiError(409,'VERIFIED_DOCUMENTS_REQUIRED',
    'Current independently verified business evidence required.','req-example-409'),
  });
  await screen.findByText('Example Cement');
  fireEvent.click(screen.getByRole('button',{name:'View details'}));
  await screen.findByText('Evidence checklist');
  const approve=screen.getByRole('button',{name:'Approved'});
  expect(approve.hasAttribute('disabled')).toBe(false);
  fireEvent.click(approve);
  fireEvent.change(screen.getByLabelText(/Mandatory audit reason/),
   {target:{value:'Company documents verified against source records'}});
  fireEvent.click(screen.getByRole('button',{name:'Confirm reviewed decision'}));
  expect(await screen.findByText('Approval blocked — documents are not verified')).toBeTruthy();
  expect(screen.getByText(/Request ID: req-example-409/)).toBeTruthy();
  expect(api.write).toHaveBeenCalledTimes(1);
 });
 it('filters by current application status without fake counters',async()=>{
  const api=setup();
  await screen.findByText('Example Cement');
  fireEvent.change(screen.getByLabelText('Approval status'),{target:{value:'REJECTED'}});
  await waitFor(()=>expect(api.get).toHaveBeenCalledWith(
   '/api/v2/admin/suppliers?limit=25&status=REJECTED',expect.anything()));
 });
});
