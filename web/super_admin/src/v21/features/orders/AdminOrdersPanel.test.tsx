// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {AdminOrdersPanel} from './AdminOrdersPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const id='11111111-1111-4111-a111-111111111111';
const base={id,publicNumber:'BT-123',status:'PLACED',currency:'INR',totalPaise:'25000',placedAt:'2026-11-04T10:00:00Z',
 supplierOrders:[{id:'22222222-2222-4222-a222-222222222222',supplierId:'33333333-3333-4333-a333-333333333333',supplierName:'Cement House',status:'PENDING_ACCEPTANCE'}]};
const detail={...base,subtotalPaise:'24000',discountPaise:'0',taxPaise:'0',deliveryPaise:'1000',executionAllowed:false,
 privacy:'PII omitted',payments:[{id:'44444444-4444-4444-a444-444444444444',status:'PENDING',paymentMethod:'UPI',amountPaise:'25000',capturedPaise:'0',verifiedAt:null,createdAt:'2026-11-04T10:01:00Z'}],
 supplierOrders:[{...base.supplierOrders[0],totalPaise:'25000',
  items:[{id:'55555555-5555-4555-a555-555555555555',sku:'CEM-01',name:'Cement Bag',quantity:'5.000',unitCode:'BAG',unitPrice:'48.0000',lineTotalPaise:'24000'}],
  shipments:[]}]};
function setup(){
 const get=vi.fn(async(path:string)=>path.includes('/orders/'+id)?{data:detail,requestId:'detail'}:{data:{asOf:'2026-11-04T10:02:00Z',items:[base],nextCursor:null,note:'Live'},requestId:'list'});
 const api={get,write:vi.fn()};
 render(<V21ApiProvider client={api as unknown as V21ApiClient}><AdminOrdersPanel/></V21ApiProvider>);
 return api;
}
describe('A10 global read-only order oversight',()=>{
 it('reads exact order number, supplier split and pending payment status',async()=>{
  const api=setup();
  await screen.findByText('BT-123');
  fireEvent.click(screen.getByRole('button',{name:'Inspect'}));
  await screen.findByText('Cement House');
  expect(screen.getByText('Cement Bag')).toBeTruthy();
  expect(screen.getByText(/UPI · PENDING/)).toBeTruthy();
  expect(screen.getByText(/No order modification or impersonation/)).toBeTruthy();
  expect(api.get).toHaveBeenCalledWith('/api/v2/admin/orders/'+id,expect.anything());
  expect(api.write).not.toHaveBeenCalled();
 });
 it('filters order status and performs exact public-number search',async()=>{
  const api=setup();await screen.findByText('BT-123');
  fireEvent.change(screen.getByLabelText('Order status'),{target:{value:'CONFIRMED'}});
  await waitFor(()=>expect(api.get).toHaveBeenCalledWith('/api/v2/admin/orders?limit=25&status=CONFIRMED',expect.anything()));
  fireEvent.change(screen.getByLabelText('Exact public order number'),{target:{value:'BT-123'}});
  fireEvent.click(screen.getByRole('button',{name:'Find'}));
  await waitFor(()=>expect(api.get).toHaveBeenCalledWith('/api/v2/admin/orders?limit=25&status=CONFIRMED&number=BT-123',expect.anything()));
 });
});
