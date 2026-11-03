'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {expectedBaselineChecksum,assertV21BaselineApplied}=require('../dist/baseline.js');
test('requires a completed official baseline migration with exact checksum',async()=>{
 const checksum=expectedBaselineChecksum();
 assert.match(checksum,/^[a-f0-9]{64}$/);
 await assert.doesNotReject(assertV21BaselineApplied({$queryRaw:async()=>[{checksum}]}));
 await assert.rejects(assertV21BaselineApplied({$queryRaw:async()=>[]}),/CHECKSUM_MISMATCH/);
 await assert.rejects(assertV21BaselineApplied({$queryRaw:async()=>[{checksum:'0'.repeat(64)}]}),/CHECKSUM_MISMATCH/);
 await assert.rejects(assertV21BaselineApplied({$queryRaw:async()=>{throw new Error('postgresql://secret');}}),e=>e.message.includes('LEDGER_REQUIRED')&&!e.message.includes('secret'));
});
