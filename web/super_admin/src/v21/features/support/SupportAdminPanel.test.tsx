// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {SupportAdminPanel} from './SupportAdminPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const caseId='11111111-1111-4111-a111-111111111111';
const returnId='22222222-2222-4222-a222-222222222222';
const reviewId='33333333-3333-4333-a333-333333333333';
const entry={id:caseId,publicNumber:'SUP-123',orderId:null,subject:'Wrong cement bag',priority:'NORMAL',status:'OPEN',createdAt:'2026-11-04T10:00:00Z',resolvedAt:null};
const returns=[{id:returnId,supplierOrderId:'44444444-4444-4444-a444-444444444444',reason:'Incorrect bag delivered',status:'REQUESTED',financialStatus:'NOT_REFUNDED',resolutionNote:null,items:[{orderItemId:'55555555-5555-4555-a555-555555555555',quantity:'1.000'}],createdAt:'2026-11-04T10:00:00Z'}];
const reviews=[{id:reviewId,supplierId:'66666666-6666-4666-a666-666666666666',supplierOrderId:'77777777-7777-4777-a777-777777777777',rating:2,comment:'Delivery needs improvement',status:'PENDING',createdAt:'2026-11-04T10:00:00Z'}];
function setup(){
 const get=vi.fn(async(path:string)=>{
  if(path.endsWith('/support/cases/'+caseId))return {data:{...entry,messages:[]},requestId:'detail'};
  if(path.endsWith('/support/cases'))return {data:[entry],requestId:'case'};
  if(path.endsWith('/returns'))return {data:returns,requestId:'returns'};
  if(path.endsWith('/reviews'))return {data:reviews,requestId:'reviews'};
  throw new Error(path);
 });
 const write=vi.fn(async(_method:string,_path:string,_body?:unknown)=>({data:{},requestId:'written'}));
 render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}><SupportAdminPanel/></V21ApiProvider>);
 return {get,write};
}
describe('A11 customer care',()=>{
 it('saves internal staff note without accidentally making it public',async()=>{
  const api=setup();await screen.findByText(/SUP-123/);
  fireEvent.click(screen.getByRole('button',{name:'Open conversation'}));
  await screen.findByText(/Wrong cement bag/);
  fireEvent.change(screen.getByLabelText('Reply or private note'),{target:{value:'Check driver handover proof with operator'}});
  fireEvent.click(screen.getByLabelText(/Internal note only/));
  fireEvent.click(screen.getByRole('button',{name:'Save internal note'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/support/cases/'+caseId+'/messages',{
   message:'Check driver handover proof with operator',internal:true
  }));
 });
 it('reviews a return but does not call a refund or payout endpoint',async()=>{
  const api=setup();await screen.findByText(/SUP-123/);
  fireEvent.click(screen.getByRole('tab',{name:/Return claims/}));
  await screen.findByText(/Incorrect bag delivered/);
  fireEvent.click(screen.getByRole('button',{name:'APPROVE'}));
  expect(screen.getByText(/NOT a refund, credit note/)).toBeTruthy();
  fireEvent.change(screen.getByLabelText(/Reason \/ customer-visible note/),{target:{value:'Verified quantity and condition with operations'}});
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/returns/'+returnId+'/review',{
   decision:'APPROVE',note:'Verified quantity and condition with operations'
  }));
  expect(api.write.mock.calls.every(call=>!String(call[1]).includes('/finance/'))).toBe(true);
 });
 it('publishes pending reviews only through the moderation endpoint',async()=>{
  const api=setup();await screen.findByText(/SUP-123/);
  fireEvent.click(screen.getByRole('tab',{name:/Supplier reviews/}));
  await screen.findByText('Delivery needs improvement');
  fireEvent.click(screen.getByRole('button',{name:'Publish review'}));
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/reviews/'+reviewId+'/moderate',{decision:'PUBLISH'}));
 });
});
