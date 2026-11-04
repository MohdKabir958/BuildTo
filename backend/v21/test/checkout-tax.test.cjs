'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {splitOrderGst}=require('../dist/checkout-tax.js');
const gst=(gstin='36ABCDE1234F1Z1')=>({
 gstin,gstRegistration:'REGULAR',verifiedAt:new Date()
});
test('GST within a state splits CGST and SGST exactly to paise',()=>{
 const x=splitOrderGst(101n,gst(),'TG');
 assert.deepEqual(x,{cgstPaise:50n,sgstPaise:51n,utgstPaise:0n,igstPaise:0n,cessPaise:0n});
});
test('interstate construction supplies get IGST and no duplicate local tax',()=>{
 const x=splitOrderGst(3600n,gst('27ABCDE1234F1Z1'),'TG');
 assert.equal(x.igstPaise,3600n);
 assert.equal(x.cgstPaise+x.sgstPaise+x.utgstPaise,0n);
});
test('supported Union Territories without legislatures get UTGST',()=>{
 const x=splitOrderGst(200n,gst('04ABCDE1234F1Z1'),'CH');
 assert.equal(x.cgstPaise,100n);
 assert.equal(x.utgstPaise,100n);
 assert.equal(x.sgstPaise+x.igstPaise,0n);
});
test('taxable order requires a verified regular-GST supplier',()=>{
 assert.throws(()=>splitOrderGst(100n,{gstin:null,gstRegistration:'UNVERIFIED',verifiedAt:null},'TG'),
  e=>e.code==='GST_SUPPLIER_UNVERIFIED');
 assert.throws(()=>splitOrderGst(100n,{...gst(),verifiedAt:null},'TG'),
  e=>e.code==='GST_SUPPLIER_UNVERIFIED');
});
test('zero-tax and unknown state behavior are safe and explicit',()=>{
 assert.equal(splitOrderGst(0n,{gstin:null,gstRegistration:'UNREGISTERED',verifiedAt:null},'TG').igstPaise,0n);
 assert.throws(()=>splitOrderGst(50n,gst(),'XX'),e=>e.code==='GST_JURISDICTION_UNKNOWN');
});
