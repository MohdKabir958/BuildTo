// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {DeliveryAdminPanel} from './DeliveryAdminPanel';
import {V21ApiProvider} from '../../lib/ApiProvider';
import type {V21ApiClient} from '../../lib/apiClient';
afterEach(()=>{cleanup();vi.restoreAllMocks();});
const city={id:'11111111-1111-4111-a111-111111111111',code:'HYD',name:'Hyderabad',stateCode:'TG',active:false};
const area={id:'22222222-2222-4222-a222-222222222222',cityId:city.id,name:'Old town',postalCodes:['500001'],active:false,centerLat:null,centerLng:null,radiusKm:null};
function setup(){
 const get=vi.fn(async(path:string)=>path.includes('/promotions')?{data:[],requestId:'promo'}:
  path.includes('/areas?')?{data:[area],requestId:'area'}:{data:[city],requestId:'city'});
 const write=vi.fn(async()=>({data:{},requestId:'changed'}));
 render(<V21ApiProvider client={{get,write} as unknown as V21ApiClient}><DeliveryAdminPanel/></V21ApiProvider>);
 return {get,write};
}
describe('A08 delivery and promotions UI',()=>{
 it('only activates a city after confirmation, preserving exact route',async()=>{
  const {write}=setup();
  await screen.findByText(/Hyderabad/);
  fireEvent.click(screen.getByRole('button',{name:'Activate'}));
  expect(screen.getByRole('dialog',{name:'Confirm delivery configuration change'})).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(write).toHaveBeenCalledWith('PATCH','/api/v2/admin/delivery/cities/'+city.id,{active:true}));
 });
 it('loads inactive PIN zones from admin API and sends exact area activation',async()=>{
  const {write,get}=setup();
  await screen.findByText(/Hyderabad/);
  fireEvent.click(screen.getByRole('tab',{name:'PIN zones'}));
  fireEvent.change(screen.getByLabelText('City'),{target:{value:city.id}});
  await screen.findByText('Old town');
  expect(get).toHaveBeenCalledWith('/api/v2/admin/delivery/areas?cityId='+city.id,expect.anything());
  fireEvent.click(screen.getByRole('button',{name:'Activate'}));
  fireEvent.click(screen.getByRole('button',{name:'Confirm'}));
  await waitFor(()=>expect(write).toHaveBeenCalledWith('PATCH','/api/v2/admin/delivery/areas/'+area.id,{active:true}));
 });
});
