// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {RefundPayoutPanel} from './RefundPayoutPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const refundId='11111111-1111-4111-a111-111111111111';
const beneficiaryId='22222222-2222-4222-a222-222222222222';
function setup(){
 const get=vi.fn(async (path:string)=>{
  if(path.endsWith('/refunds'))return {data:[{id:refundId,orderId:'ord',returnRequestId:'return',status:'REQUESTED',
   currency:'INR',amountPaise:'135000',providerRefundId:null,customerBankCredit:'NOT_VERIFIED',createdAt:'2026-11-04T12:00:00Z'}],requestId:'ref'};
  if(path.includes('/beneficiaries?'))return {data:{items:[{id:beneficiaryId,supplierId:'sup',supplierName:'Cement Supplier',
   maskedBankAccount:'****1234',active:false,holderName:'Seller',ifsc:'ABCD0001111',registeredById:'person',approvedById:null,
   bankStatementVerifiedByApi:false}],nextCursor:null},requestId:'ben'};
  if(path.endsWith('/payouts'))return {data:[],requestId:'payouts'};
  if(path.endsWith('/payouts-reconciliation'))return {data:{payouts:[],missingBankAttestation:0,bankStatementAPIReconciled:false,payoutExecutionEnabledByApi:false},requestId:'report'};
  throw new Error(path);
 });
 const write=vi.fn(async (_method:string,_path:string,_body?:unknown,_options?:unknown)=>({data:{},requestId:'write'}));
 render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}><RefundPayoutPanel/></V21ApiProvider>);
 return {get,write};
}
describe('A13 independent financial review',()=>{
 it('approves a refund through existing API and never sends provider money POST',async()=>{
  const api=setup();await screen.findByText(/₹1,350.00/);
  expect(screen.getByText(/does not execute a Razorpay refund/)).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Approve independently'}));
  fireEvent.click(screen.getByRole('button',{name:'Confirm reviewed action'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/finance/refunds/'+refundId+'/approve',{}));
  expect(api.write.mock.calls.every(c=>!c[1].includes('payouts/execute'))).toBe(true);
 });
 it('requires a second reviewer for masked beneficiary approval',async()=>{
  const api=setup();await screen.findByText(/₹1,350.00/);
  fireEvent.click(screen.getByRole('tab',{name:'Bank beneficiaries'}));
  await screen.findByText(/Cement Supplier/);
  expect(screen.getByText(/1234/)).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Approve bank beneficiary'}));
  fireEvent.click(screen.getByRole('button',{name:'Confirm reviewed action'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/finance/beneficiaries/'+beneficiaryId+'/approve',{}));
 });
 it('requires a provider refund ID before lookup',async()=>{
  const api=setup();await screen.findByText(/₹1,350.00/);
  fireEvent.click(screen.getByRole('button',{name:'Approve independently'}));
  expect(api.write).not.toHaveBeenCalled();
 });
});