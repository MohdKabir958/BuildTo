// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {FinanceOperationsPanel} from './FinanceOperationsPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const sup='11111111-1111-4111-a111-111111111111';
const receipt='22222222-2222-4222-a222-222222222222';
const settlement='33333333-3333-4333-a333-333333333333';
const order='44444444-4444-4444-a444-444444444444';
const history={orders:[{supplierOrderId:order,totalPaise:'156700',platformFeePaise:'10000',codVerifiedPaise:'0',fundingType:'RAZORPAY_CAPTURE_VERIFIED',disputed:false,allocatedToActiveSettlement:false}],
 settlements:[{id:settlement,settlementKey:'SETTLE-2026-01',status:'ON_HOLD',payablePaise:'146700',grossPaise:'156700',commissionPaise:'10000',
 createdAt:'2026-11-04T10:00:00Z',periodStart:'2026-11-01T00:00:00Z',periodEnd:'2026-11-04T00:00:00Z',approvedById:null,payoutState:'NOT_DISBURSED',lines:[{supplierOrderId:order,netPaise:'146700'}]}],
 bankingReconciled:false};
function setup(){
 const get=vi.fn(async(path:string)=>{
  if(path.includes('/finance/suppliers?'))return {data:{items:[{id:sup,displayName:'Cement Supplier',approval:'APPROVED',suspended:false}],nextCursor:null},requestId:'choices'};
  if(path.includes('/finance/cod?'))return {data:{items:[{id:receipt,receiptNumber:'COD-123',supplierId:sup,supplierOrderId:order,collectedPaise:'156700',currency:'INR',status:'RECORDED',receivedAt:'2026-11-04T10:00:00Z'}],nextCursor:null},requestId:'cod'};
  if(path.includes('/finance/suppliers/'+sup))return {data:history,requestId:'history'};
  throw new Error(path);
 });
 const write=vi.fn(async (_method:string,_path:string,_body?:unknown)=>({data:{},requestId:'updated'}));
 render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}><FinanceOperationsPanel/></V21ApiProvider>);
 return {get,write};
}
describe('A12 finance review UI',()=>{
 it('labels ON_HOLD settlement as undistributed and demands independent statement reference',async()=>{
  setup();
  await screen.findByText('Finance review desk');
  fireEvent.change(screen.getByLabelText('Supplier'),{target:{value:sup}});
  await screen.findByText(/SETTLE-2026-01/);
  expect(screen.getByText(/NOT_DISBURSED/)).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Attest bank evidence'}));
  expect(screen.getByRole('dialog',{name:'Confirm financial review'})).toBeTruthy();
  expect(screen.getByRole('button',{name:'Confirm reviewed action'}).hasAttribute('disabled')).toBe(true);
 });
 it('independently verifies supplier-held COD with external evidence, never a bank transfer',async()=>{
  const api=setup();await screen.findByText('Finance review desk');
  fireEvent.click(screen.getByRole('tab',{name:'COD receipts'}));
  await screen.findByText(/COD-123/);
  fireEvent.click(screen.getByRole('button',{name:'Verify evidence'}));
  fireEvent.change(screen.getByLabelText('Independent COD evidence reference'),{target:{value:'EXTERNAL-RECEIPT-2026'}});
  fireEvent.click(screen.getByRole('button',{name:'Confirm reviewed action'}));
  await waitFor(()=>expect(api.write).toHaveBeenCalledWith('POST','/api/v2/admin/finance/cod/'+receipt+'/review',{
   decision:'VERIFY',externalReference:'EXTERNAL-RECEIPT-2026'
  }));
  expect(api.write.mock.calls.every(call=>!String(call[1]).includes('/payout-intent'))).toBe(true);
 });
});
