import { createHash } from 'node:crypto';

export function paiseString(value: bigint | string): string {
  const s = typeof value === 'bigint' ? value.toString() : value;
  if (typeof s !== 'string' || !/^-?(?:0|[1-9][0-9]*)$/.test(s)) {
    throw new Error('INVALID_PAISE_AMOUNT: use an exact decimal integer string or bigint.');
  }
  return s;
}
export function decimalString(value: string | {toString(): string}): string {
  const s = typeof value === 'string' ? value : value.toString();
  if (!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(s)) throw new Error('INVALID_DECIMAL_VALUE');
  return s;
}
export function utcTimestamp(date: Date): string {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) throw new Error('INVALID_TIMESTAMP');
  return date.toISOString();
}
export function parsePaise(input: unknown): bigint {
  if (typeof input !== 'string' || !/^(?:0|[1-9][0-9]*)$/.test(input)) throw new Error('PAISE_MUST_BE_DECIMAL_STRING');
  const n = BigInt(input);
  if (n > 9223372036854775807n) throw new Error('PAISE_EXCEEDS_POSTGRES_BIGINT');
  return n;
}
// Explicit DTO factories only. Never JSON.stringify Prisma rows, because they can contain secret fields.
export function publicMoneyDTO(input: {totalPaise: bigint, currency: 'INR'}): {totalPaise: string,currency:'INR'} {
  return {totalPaise:paiseString(input.totalPaise),currency:input.currency};
}
export function stableRequestHash(input: unknown): string {
  function canonical(value: unknown): string {
    if (value === null) return 'null';
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      if (typeof value === 'number' && !Number.isFinite(value)) throw new Error('INVALID_JSON_NUMBER');
      return JSON.stringify(value);
    }
    if (Array.isArray(value)) return '['+value.map(canonical).join(',')+']';
    if (typeof value === 'object') {
      if (Object.getPrototypeOf(value) !== Object.prototype) throw new Error('INVALID_JSON_OBJECT');
      const o=value as Record<string,unknown>;
      return '{'+Object.keys(o).sort().map(k=>JSON.stringify(k)+':'+canonical(o[k])).join(',')+'}';
    }
    throw new Error('INVALID_JSON_VALUE');
  }
  return createHash('sha256').update(canonical(input)).digest('hex');
}
export interface ApiErrorDTO {error:{code:string,message:string};requestId:string}
export function errorDTO(code:string,message:string,requestId:string):ApiErrorDTO {
  return {error:{code,message},requestId};
}
