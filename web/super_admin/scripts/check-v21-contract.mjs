#!/usr/bin/env node
// CI-only OpenAPI contract gate. Does not contact or mutate a database.
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const api=JSON.parse(readFileSync(resolve('../../backend/v21/openapi.json'),'utf8'));
const present=api.paths??{};
const expected={
 '/health':['get'], '/ready':['get'], '/api/v2/system':['get'],
 '/api/v2/me':['get'], '/api/v2/admin/access':['get'],
 '/api/v2/admin/team':['get','post'],
 '/api/v2/admin/team/{userId}':['patch'],
 '/api/v2/admin/team/{userId}/revoke':['post'],
 '/api/v2/admin/suppliers':['get'],
 '/api/v2/admin/suppliers/{supplierId}':['get'],
 '/api/v2/admin/suppliers/{supplierId}/review':['post'],
 '/api/v2/supplier-applications':['post'],
 '/api/v2/admin/catalog/listings/pending':['get'],
 '/api/v2/admin/catalog/listings/{listingId}/review':['post'],
 '/api/v2/admin/delivery/cities':['post'],
 '/api/v2/admin/promotions':['get','post'],
 '/api/v2/admin/support/cases':['get'],
 '/api/v2/admin/returns':['get'],
 '/api/v2/admin/reviews':['get'],
 '/api/v2/admin/finance/refunds':['get'],
 '/api/v2/admin/finance/payouts':['get'],
};
for(const [route,methods] of Object.entries(expected)){
 for(const method of methods)assert.ok(present[route]?.[method],`Missing V2.1 ${method.toUpperCase()} ${route}`);
}
// These are *planned* additions, not secretly inherited from Grozo.
for(const missing of [
 '/api/v2/admin/overview',
 '/api/v2/admin/orders',
 '/api/v2/admin/audit',
])assert.ok(!Object.hasOwn(present,missing),`New endpoint ${missing} exists: update A00 map before implementing a client`);
assert.ok(Object.keys(present).length>=119,'Unexpected V2.1 contract shrinkage');
console.log('PASS: BuildTo admin A00 current API/gap matrix remains accurate; no database touched.');
