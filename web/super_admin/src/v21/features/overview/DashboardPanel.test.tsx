// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,render,screen} from '@testing-library/react';
import {DashboardPanel} from './DashboardPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const data={asOf:'2026-11-04T10:00:00.000Z',windowStart7d:'2026-10-28T10:00:00.000Z',
 supplierCount:13,pendingSuppliers:2,activeSuppliers:10,pendingListings:5,
 totalOrders:42,ordersPlacedLast7d:9,pendingSupplierOrders:4,
 openSupportCases:6,unresolvedReturnClaims:3,deliveryExceptionsApproved:1,failedShipments:2,
 financialActionCounts:{pendingRefunds:1,pendingPayouts:2},financeEvidence:null};
describe('A09 live dashboard',()=>{
 it('renders database figures and hides restricted financial evidence when not supplied',async()=>{
  const api={get:vi.fn(async()=>({data,requestId:'dashboard'}))};
  render(<V21ApiProvider client={api as unknown as V21ApiClient}><DashboardPanel/></V21ApiProvider>);
  await screen.findByText('Marketplace overview');
  expect(await screen.findByText('13')).toBeTruthy();
  expect(screen.getByText('9 placed in previous 7 days')).toBeTruthy();
  expect(screen.getByText(/Gateway capture totals are visible only/)).toBeTruthy();
  expect(api.get).toHaveBeenCalledWith('/api/v2/admin/overview',expect.anything());
 });
 it('presents provider capture as evidence, never bank credit or net revenue',async()=>{
  const api={get:vi.fn(async()=>({data:{...data,financeEvidence:{
   verifiedGatewayCaptureEvidencePaise:'12345',verifiedCaptureCount:1,currency:'INR',bankCreditVerified:false,netRevenueCalculated:false
  }},requestId:'dashboard'}))};
  render(<V21ApiProvider client={api as unknown as V21ApiClient}><DashboardPanel/></V21ApiProvider>);
  expect(await screen.findByText('₹123.45')).toBeTruthy();
  expect(screen.getByText(/NOT net revenue/)).toBeTruthy();
 });
 it('shows a real error rather than invented zero totals on API failure',async()=>{
  const api={get:vi.fn(async()=>{throw new Error('offline');})};
  render(<V21ApiProvider client={api as unknown as V21ApiClient}><DashboardPanel/></V21ApiProvider>);
  await screen.findByRole('alert');
  expect(screen.queryByText('42')).toBeNull();
 });
});
