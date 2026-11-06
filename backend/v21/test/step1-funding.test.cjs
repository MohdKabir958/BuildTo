'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {verifiedCapturedPayment,verifiedFulfillmentPayment}=require('../dist/payment-funding.js');
const total=15000n;
const capture={
 provider:'RAZORPAY',paymentMethod:'UPI',status:'CAPTURED',
 amountPaise:total,capturedPaise:total,verifiedAt:new Date(),
 providerPayRef:'pay_valid123456789'
};
const failed={
 provider:'RAZORPAY',paymentMethod:'UPI',status:'FAILED',
 amountPaise:total,capturedPaise:0n,verifiedAt:null,providerPayRef:null
};
test('retries: prior failed attempts never poison verified captured payment',()=>{
 assert.equal(verifiedCapturedPayment([failed,capture],total),capture);
 assert.equal(verifiedFulfillmentPayment([failed,capture],total),capture);
 assert.equal(verifiedCapturedPayment([capture,failed,failed],total),capture);
});
test('two captures, wrong amount or unreconciled active attempt block funding',()=>{
 assert.equal(verifiedCapturedPayment([capture,{...capture}],total),null);
 assert.equal(verifiedCapturedPayment([{...capture,capturedPaise:1n}],total),null);
 assert.equal(verifiedCapturedPayment([{...capture,verifiedAt:null}],total),null);
 assert.equal(verifiedCapturedPayment([capture,{...failed,status:'PENDING'}],total),null);
 assert.equal(verifiedFulfillmentPayment([capture,{...failed,status:'AUTHORIZED'}],total),null);
});
test('COD after verified cancelled attempt is fundable, not a Razorpay refund',()=>{
 const cod={provider:'MANUAL',paymentMethod:'COD',status:'PENDING',
  amountPaise:total,capturedPaise:0n,verifiedAt:null,providerPayRef:null};
 const cancelled={...failed,status:'CANCELLED'};
 assert.equal(verifiedFulfillmentPayment([cancelled,cod],total),cod);
 assert.equal(verifiedCapturedPayment([cancelled,cod],total),null);
 assert.equal(verifiedFulfillmentPayment([capture,cod],total),null);
});
