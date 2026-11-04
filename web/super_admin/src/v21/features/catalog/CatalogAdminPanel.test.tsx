// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {CatalogAdminPanel} from './CatalogAdminPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
const category={id:'11111111-1111-4111-a111-111111111111',name:'Cement',slug:'cement',active:false,parentId:null,displayOrder:0};
const listing={id:'22222222-2222-4222-a222-222222222222',sku:'CEM-100',
 supplierId:'33333333-3333-4333-a333-333333333333',productId:'44444444-4444-4444-a444-444444444444',
 unitCode:'BAG',unitPrice:'435.0000',taxRateBps:1800,status:'PENDING',active:false,version:7,minOrderQty:'1.000'};
afterEach(()=>{cleanup();vi.restoreAllMocks();});
function setup(){
 const get=vi.fn(async(path:string)=>{
  if(path.includes('/categories'))return {data:{items:[category],nextCursor:null},requestId:'cats'};
  if(path.includes('/brands'))return {data:{items:[],nextCursor:null},requestId:'brands'};
  if(path.includes('/products'))return {data:{items:[],nextCursor:null},requestId:'products'};
  if(path.includes('/listings/pending'))return {data:[listing],requestId:'listings'};
  if(path.includes('/catalog/units'))return {data:[{code:'BAG',name:'Bag'}],requestId:'units'};
  throw new Error(path);
 });
 const write=vi.fn(async()=>({data:{},requestId:'saved'}));
 render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}><CatalogAdminPanel/></V21ApiProvider>);
 return {get,write};
}
describe('A07 master catalog UI',()=>{
 it('renders inactive category and requires confirmation to activate',async()=>{
  const {write}=setup();
  await screen.findByText('Cement');
  fireEvent.click(screen.getByRole('button',{name:'Activate'}));
  expect(screen.getByRole('dialog',{name:'Confirm catalog change'})).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(write).toHaveBeenCalledWith('PATCH',
   '/api/v2/admin/catalog/categories/'+category.id,{active:true}));
 });
 it('moderates a supplier listing with expected optimistic version and exact price',async()=>{
  const {write}=setup();
  await screen.findByText('Cement');
  fireEvent.click(screen.getByRole('tab',{name:/Pending listings/}));
  expect(screen.getByText('INR 435.0000 / BAG')).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Approve'}));
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(write).toHaveBeenCalledWith('POST',
   '/api/v2/admin/catalog/listings/'+listing.id+'/review',{decision:'APPROVE',expectedVersion:7}));
 });
 it('shows request failure instead of inventing empty successful data',async()=>{
  const api={get:vi.fn(async()=>{throw new Error('offline');}),write:vi.fn()};
  render(<V21ApiProvider client={api as unknown as V21ApiClient}><CatalogAdminPanel/></V21ApiProvider>);
  expect(await screen.findByRole('alert')).toBeTruthy();
 });
});
