'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {serializable}=require('../dist/transaction.js');
const failure=code=>Object.assign(new Error('database conflict'),{code});

test('serializable DB transactions retry P2034 twice and then succeed',async()=>{
 let attempts=0;
 const result=await serializable({$transaction:async cb=>{
  attempts++;
  if(attempts<3)throw failure('P2034');
  return cb({attempts});
 }},async tx=>tx.attempts);
 assert.equal(result,3);
 assert.equal(attempts,3);
});
test('other database errors are not retried or swallowed',async()=>{
 let attempts=0;
 await assert.rejects(serializable({$transaction:async()=>{
  attempts++;throw failure('P2002');
 }},async()=>null),e=>e.code==='P2002');
 assert.equal(attempts,1);
});
test('repeated serialization failures abort after a fixed bound',async()=>{
 let attempts=0;
 await assert.rejects(serializable({$transaction:async()=>{
  attempts++;throw failure('P2034');
 }},async()=>null),e=>e.code==='P2034');
 assert.equal(attempts,5);
});

test('wrapped Postgres serialization and deadlocks retry with exact SQLSTATE',async()=>{
 for(const sqlstate of ['40001','40P01']){
  let attempts=0;
  const result=await serializable({$transaction:async cb=>{
   attempts++;
   if(attempts===1)throw Object.assign(new Error('raw SQL failed'),{
    code:'P2010',meta:{code:sqlstate}});
   return cb({attempts});
  }},async tx=>tx.attempts);
  assert.equal(result,2);
 }
});
test('P2010 constraint failures never retry as deadlocks',async()=>{
 let attempts=0;
 await assert.rejects(serializable({$transaction:async()=>{
  attempts++;
  throw Object.assign(new Error('constraint'),{code:'P2010',meta:{code:'23514'}});
 }},async()=>null),e=>e.meta.code==='23514');
 assert.equal(attempts,1);
});
