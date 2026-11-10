import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

/**
 * Checks that every supplier-mobile operation explicitly adopted by S00 exists
 * in the canonical V2.1 OpenAPI contract. This is NOT a client-implementation
 * test; the Flutter migration and live API verification begin in later PRs.
 *
 * @param {unknown} openapi
 * @param {unknown} manifest
 * @returns {string[]} actionable validation issues
 */
export function validateSupplierContract(openapi, manifest) {
  const issues = [];
  const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
  if (!object(openapi) || !object(openapi.paths)) {
    return ['OpenAPI document must contain a paths object'];
  }
  if (!object(manifest) || manifest.schemaVersion !== 1 || !Array.isArray(manifest.groups)) {
    return ['Supplier contract must contain schemaVersion: 1 and groups array'];
  }

  const usedGroups = new Set();
  const usedOperations = new Set();
  let total = 0;
  for (const [groupIndex, group] of manifest.groups.entries()) {
    if (!object(group) || typeof group.id !== 'string' || !/^[a-z][a-z0-9-]*$/.test(group.id)) {
      issues.push('groups[' + groupIndex + ']: invalid group id');
      continue;
    }
    if (usedGroups.has(group.id)) issues.push('duplicate group id: ' + group.id);
    usedGroups.add(group.id);
    if (!Array.isArray(group.operations) || group.operations.length === 0) {
      issues.push(group.id + ': operations must be a non-empty array');
      continue;
    }

    for (const [index, op] of group.operations.entries()) {
      const where = group.id + '.operations[' + index + ']';
      if (!object(op) || typeof op.method !== 'string' || typeof op.path !== 'string') {
        issues.push(where + ': expected {method, path} strings');
        continue;
      }
      if (!['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].includes(op.method)) {
        issues.push(where + ': unsupported HTTP method ' + op.method);
        continue;
      }
      if (!op.path.startsWith('/api/v2/') || /[?#]/.test(op.path)) {
        issues.push(where + ': expected canonical /api/v2/ path without query string');
        continue;
      }
      const key = op.method + ' ' + op.path;
      if (usedOperations.has(key)) issues.push('duplicate operation: ' + key);
      usedOperations.add(key);
      total++;
      if (!object(openapi.paths[op.path])) {
        issues.push('OpenAPI missing path: ' + key);
      } else if (!object(openapi.paths[op.path][op.method.toLowerCase()])) {
        issues.push('OpenAPI missing method: ' + key);
      }
    }
  }
  if (total === 0) issues.push('Supplier contract has no valid operations');
  return issues;
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const root = resolve(here, '../../..');
  const spec = JSON.parse(readFileSync(resolve(root, 'backend/v21/openapi.json'), 'utf8'));
  const matrix = JSON.parse(readFileSync(resolve(here, 'v21_supplier_contract.json'), 'utf8'));
  const problems = validateSupplierContract(spec, matrix);
  if (problems.length) {
    for (const problem of problems) console.error('FAIL: ' + problem);
    process.exitCode = 1;
    return;
  }
  const count = matrix.groups.reduce((n, group) => n + group.operations.length, 0);
  console.log('PASS: ' + count + ' supplier operations across ' + matrix.groups.length +
    ' groups match canonical V2.1 OpenAPI (' + spec.info?.version + ')');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error('FAIL: unable to check supplier V2.1 API contract: ' + error.message);
    process.exitCode = 1;
  }
}
