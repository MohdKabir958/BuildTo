import assert from 'node:assert/strict';
import { stringifyApiDto, parseApiDto } from '../api/json-safe.mjs';

const money = 90071992547409931234n;
const dto = { orderId: 'BT-42', totalPaise: money, lines: [{ subtotalPaise: 340n }], count: 2, empty: null };
const output = stringifyApiDto(dto);
assert.equal(output.includes('"totalPaise":"90071992547409931234"'), true);
assert.equal(parseApiDto(output).totalPaise, money.toString());
assert.equal(parseApiDto(output).lines[0].subtotalPaise, '340');
assert.equal(parseApiDto(output).count, 2);
assert.equal(parseApiDto(output).empty, null);
console.log('PASS: BigInt amounts safely serialized as strings without precision loss');
