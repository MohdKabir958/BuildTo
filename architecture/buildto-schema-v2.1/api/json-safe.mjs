/**
 * Serialization boundary for API response DTOs only.
 * Encode paise BigInts and exact decimal values as JSON strings, never JS Number.
 * Keep PII/secret filtering in each endpoint's explicit allowlisted DTO, BEFORE serializing.
 * Do not globally patch BigInt.prototype.toJSON.
 */
export function stringifyApiDto(dto) {
  return JSON.stringify(dto, (_key, value) =>
    typeof value === 'bigint' ? value.toString() : value
  );
}

export function parseApiDto(json) {
  return JSON.parse(json);
}
