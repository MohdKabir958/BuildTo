import { describe, expect, it, vi } from 'vitest';
import { createV21AdminApi, V21ApiError } from './apiClient';

const origin = 'https://buildto-v21-staging.onrender.com';
const identity = {
  id: 'a0',
  displayName: 'Test Admin',
  adminRole: 'OWNER',
  suppliers: [],
};

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('BuildTo V2.1 admin API client', () => {
  it('requires HTTPS and an exact origin (except local development)', () => {
    for (const baseUrl of [
      'http://example.com',
      'https://example.com/foo',
      'https://example.com/?key=secret',
      'https://user:secret@example.com',
      'https://example.com/#token',
    ]) {
      expect(() => createV21AdminApi({ baseUrl, getToken: async () => 'token' }))
        .toThrow('V21_API_ORIGIN_INVALID');
    }
    expect(() => createV21AdminApi({
      baseUrl: 'http://localhost:3000',
      getToken: async () => 'token',
    })).not.toThrow();
  });

  it('uses the active Clerk token and reads existing V2.1 identity', async () => {
    const fetchMock = vi.fn(async () => json(200, { data: identity, requestId: 'r1' }));
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => 'clerk-session-token',
      fetchImpl: fetchMock as typeof fetch,
    });
    expect((await client.getMe()).data.adminRole).toBe('OWNER');
    const [url, request] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(origin + '/api/v2/me');
    const headers = new Headers(request.headers);
    expect(headers.get('Authorization')).toBe('Bearer clerk-session-token');
    expect(request.credentials).toBe('omit');
    expect(request.redirect).toBe('error');
  });

  it('never requests the backend without a signed-in Clerk session', async () => {
    const fetchMock = vi.fn();
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => null,
      fetchImpl: fetchMock as typeof fetch,
    });
    await expect(client.getAdminAccess()).rejects.toMatchObject({
      status: 401, code: 'INVALID_SESSION',
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('blocks legacy, off-origin and custom auth requests', async () => {
    const fetchMock = vi.fn();
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => 'token',
      fetchImpl: fetchMock as typeof fetch,
    });
    for (const path of ['/api/v1/admin/team', '//evil.com/api/v2/me', '/api/v2/../admin']) {
      await expect(client.request(path)).rejects.toThrow('V21_API_PATH_INVALID');
    }
    await expect(client.request('/api/v2/me', {
      headers: { Authorization: 'Bearer manual-secret' },
    })).rejects.toThrow('V21_AUTH_HEADER_OWNED_BY_CLERK');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('preserves structured permission errors without swallowing 403', async () => {
    const fetchMock = vi.fn(async () => json(403, {
      error: { code: 'ADMIN_NOT_PROVISIONED', message: 'Administrator access not granted.' },
      requestId: 'req-403',
    }));
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => 'token',
      fetchImpl: fetchMock as typeof fetch,
    });
    await expect(client.getAdminAccess()).rejects.toMatchObject({
      status: 403, code: 'ADMIN_NOT_PROVISIONED', requestId: 'req-403',
    } satisfies Partial<V21ApiError>);
  });

  it('sends idempotency keys for writes and never retries rejected mutations', async () => {
    const fetchMock = vi.fn(async () => json(409, {
      error: { code: 'VERSION_CONFLICT', message: 'Stale version.' },
      requestId: 'req-409',
    }));
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => 'token',
      fetchImpl: fetchMock as typeof fetch,
    });
    await expect(client.request('/api/v2/admin/catalog/products', {
      method: 'POST',
      idempotencyKey: 'create-product-0001',
      body: { name: 'Cement' },
    })).rejects.toMatchObject({ status: 409, code: 'VERSION_CONFLICT' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(new Headers(options.headers).get('Idempotency-Key')).toBe('create-product-0001');
    expect(JSON.parse(String(options.body))).toEqual({ name: 'Cement' });
  });

  it('rejects non-envelope responses instead of treating them as valid application data', async () => {
    const fetchMock = vi.fn(async () => json(200, { legacy: true }));
    const client = createV21AdminApi({
      baseUrl: origin, getToken: async () => 'token',
      fetchImpl: fetchMock as typeof fetch,
    });
    await expect(client.getMe()).rejects.toMatchObject({
      code: 'INVALID_API_RESPONSE',
    });
  });
});
