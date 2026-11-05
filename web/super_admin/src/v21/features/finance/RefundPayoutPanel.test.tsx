// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {RefundPayoutPanel} from './RefundPayoutPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';

const refund='11111111-1111-4111-8111-111111111111';
const supplier='22222222-2222-4222-8222-222222222222';
function setup(){
  const get=vi.fn(async(path:string)=>{
    if(path==='/api/v2/admin/finance/refunds')return {data:[{
      id:refund,orderId:'44444444-4444-4444-8444-444444444444',
      returnRequestId:null,amountPaise:'120000',status:'REQUESTED',providerRefundId:null,
      approvalAt:null,providerCompletedAt:null,customerBankCredit:'NOT_VERIFIED',
      createdAt:'2026-11-04T10:00:00Z',reason:'Verified full return'
    }],requestId:'refund-queue'};
    if(path.includes('/finance/refund-candidates?'))return {data:{items:[],nextCursor:null},requestId:'candidates'};
    if(path==='/api/v2/admin/finance/payouts')return {data:[],requestId:'payouts'};
    if(path==='/api/v2/admin/finance/payouts-reconciliation')return {data:{
      payouts:[],missingBankAttestation:0,bankStatementAPIReconciled:false,payoutExecutionEnabledByApi:false
    },requestId:'report'};
    if(path.includes('/finance/suppliers?'))return {data:{items:[
      {id:supplier,displayName:'Building Supplies',approval:'APPROVED',suspended:false}
    ],nextCursor:null},requestId:'suppliers'};
    if(path.endsWith('/beneficiaries'))return {data:[],requestId:'bank'};
    if(path.endsWith('/finance/suppliers/'+supplier))return {data:{orders:[],settlements:[]},requestId:'settlements'};
    throw new Error('Unexpected endpoint '+path);
  });
  const write=vi.fn(async(_method:string,_path:string,_body?:unknown)=>({data:{},requestId:'decision'}));
  render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}>
    <RefundPayoutPanel/>
  </V21ApiProvider>);
  return {get,write};
}
afterEach(()=>{cleanup();vi.restoreAllMocks();});
describe('A13 financial review',()=>{
  it('requires independent refund approval and does not issue a provider payment',async()=>{
    const api=setup();
    await screen.findByText(/Refund 11111111/);
    expect(screen.getByText(/Refund SUCCEEDED means provider processed/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button',{name:'Second finance approval'}));
    const confirm=screen.getByRole('button',{name:'Confirm independent check'});
    fireEvent.click(confirm);
    await waitFor(()=>expect(api.write).toHaveBeenCalledWith(
      'POST','/api/v2/admin/finance/refunds/'+refund+'/approve',{}
    ));
    expect(api.write.mock.calls.every(call=>!String(call[1]).includes('payment-attempt'))).toBe(true);
  });
  it('does not allow payout intent without a validated independent bank account',async()=>{
    setup();await screen.findByText(/Refund 11111111/);
    fireEvent.click(screen.getByRole('tab',{name:'Beneficiaries'}));
    fireEvent.change(screen.getByLabelText('Supplier'),{target:{value:supplier}});
    await screen.findByText('No approved provider fund account on record.');
    expect(screen.queryByRole('button',{name:'Reserve payout intent'})).toBeNull();
  });
});
