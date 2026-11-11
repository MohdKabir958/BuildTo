'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {commissionPaise}=require('../dist/commission-policy.js');
test('commission is charged only on discounted tax-exclusive materials, with paise rounding',()=>{
 assert.equal(commissionPaise(10000n,2000n,500),400n);
 assert.equal(commissionPaise(101n,0n,500),5n);
 assert.equal(commissionPaise(1n,0n,5000),1n);
 assert.equal(commissionPaise(10000n,0n,0),0n);
 assert.throws(()=>commissionPaise(100n,101n,500),/INVALID_COMMISSION_INPUT/);
 assert.throws(()=>commissionPaise(100n,0n,5001),/INVALID_COMMISSION_INPUT/);
});
