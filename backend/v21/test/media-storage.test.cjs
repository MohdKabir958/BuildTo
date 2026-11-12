'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const express=require('express');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrivateS3MediaStore,privateS3MediaStore}=require('../dist/media-s3');
const {registerPublicImages}=require('../dist/media');

test('private S3 adapter uses immutable keys and returns bytes without public ACLs',async()=>{
 const calls=[];
 const client={send:async command=>{calls.push(command);return {Body:{transformToByteArray:async()=>Buffer.from('private')}};}};
 const store=new PrivateS3MediaStore(client,'private-media');const key=randomUUID();
 await store.put(key,Buffer.from('private'));
 assert.equal(calls[0].input.IfNoneMatch,'*');assert.equal(calls[0].input.ACL,undefined);
 assert.equal(calls[0].input.Bucket,'private-media');
 assert.equal((await store.get(key)).toString(),'private');await store.remove(key);
 await assert.rejects(store.get('../secret'),/INVALID_STORAGE_KEY/);
 assert.equal(calls.length,3);
});
test('S3 configuration rejects partial credentials and insecure endpoints',()=>{
 assert.equal(privateS3MediaStore({}),undefined);
 assert.throws(()=>privateS3MediaStore({BUILDTO_V21_MEDIA_S3_BUCKET:'private'}),/CONFIG_INCOMPLETE/);
 const env={BUILDTO_V21_MEDIA_S3_ENDPOINT:'http://storage.example',BUILDTO_V21_MEDIA_S3_REGION:'us-east-2',BUILDTO_V21_MEDIA_S3_BUCKET:'private',BUILDTO_V21_MEDIA_S3_ACCESS_KEY_ID:'test',BUILDTO_V21_MEDIA_S3_SECRET_ACCESS_KEY:'test'};
 assert.throws(()=>privateS3MediaStore(env),/ENDPOINT_INVALID/);
});
test('media route falls through to supplier product photos without exposing private evidence',async()=>{
 const app=express();let query;
 registerPublicImages(app,{mediaAsset:{findFirst:async input=>{query=input;return null;}}});
 app.get('/api/v2/catalog/images/:imageId',(_req,res)=>res.type('png').send('supplier-photo'));
 const res=await request(app).get('/api/v2/catalog/images/'+randomUUID());
 assert.equal(res.status,200);assert.equal(res.body.toString(),'supplier-photo');
 assert.equal(query.where.purpose,'CATALOG_IMAGE');assert.equal(query.where.product.active,true);
});
