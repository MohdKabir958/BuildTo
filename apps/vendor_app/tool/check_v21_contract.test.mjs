import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateSupplierContract } from './check_v21_contract.mjs';

const path = '/api/v2/suppliers/{supplierId}/orders';
const spec = { paths: { [path]: { get: { summary: 'Orders' } } } };
const entry = { method: 'GET', path };
const matrix = () => ({
  schemaVersion: 1,
  groups: [{ id: 'orders', operations: [{ ...entry }] }],
});

test('accepts a canonical supplier operation', () => {
  assert.deepEqual(validateSupplierContract(spec, matrix()), []);
});

test('fails closed when a route disappears', () => {
  assert.match(validateSupplierContract({ paths: {} }, matrix()).join('\n'), /OpenAPI missing path/);
});

test('fails closed when the HTTP verb changes', () => {
  const modified = matrix();
  modified.groups[0].operations[0].method = 'POST';
  assert.match(validateSupplierContract(spec, modified).join('\n'), /OpenAPI missing method/);
});

test('rejects duplicate operations and duplicate groups', () => {
  const modified = matrix();
  modified.groups[0].operations.push({ ...entry });
  modified.groups.push({ id: 'orders', operations: [{ ...entry }] });
  const errors = validateSupplierContract(spec, modified).join('\n');
  assert.match(errors, /duplicate operation/);
  assert.match(errors, /duplicate group id/);
});

test('rejects legacy API routes and query-string route keys', () => {
  const modified = matrix();
  modified.groups[0].operations[0].path = '/api/v1/partner/orders';
  assert.match(validateSupplierContract(spec, modified).join('\n'), /canonical \/api\/v2\//);
  modified.groups[0].operations[0].path = path + '?limit=50';
  assert.match(validateSupplierContract(spec, modified).join('\n'), /without query string/);
});

test('rejects invalid or empty manifests', () => {
  assert.match(validateSupplierContract(spec, { groups: [] }).join('\n'), /schemaVersion/);
  const modified = matrix();
  modified.groups[0].operations = [];
  assert.match(validateSupplierContract(spec, modified).join('\n'), /non-empty array/);
});

test('rejects malformed OpenAPI', () => {
  assert.match(validateSupplierContract({ paths: null }, matrix()).join('\n'), /paths object/);
});
