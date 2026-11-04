/**
 * BuildTo V2.1 browser API client.
 *
 * Kept alongside the legacy UI until migration PRs replace its Grozo API calls.
 * Authentication always comes from the active Clerk session; never localStorage.
 * No request automatically retries a mutation or exposes raw provider errors.
 */
export type AdminRole = 'OWNER' | 'OPERATIONS' | 'CATALOG' | 'FINANCE' | 'SUPPORT' | 'AUDITOR';

export interface AdminIdentity {
  id: string;
  displayName: string;
  adminRole: AdminRole | null;
  suppliers: Array<{ supplierId: string; role: string }>;
}

export interface ApiEnvelope<T> {
  data: T;
  requestId: string;
}

type HttpMethod = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
type TokenProvider = () => Promise<string | null>;

export interface V21ClientOptions {
  baseUrl: string;
  getToken: TokenProvider;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}

export interface V21RequestOptions {
  method?: HttpMethod;
  body?: unknown;
  signal?: AbortSignal;
  idempotencyKey?: string;
  headers?: HeadersInit;
}

export class V21ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly requestId: string | null = null,
  ) {
    super(message);
    this.name = 'V21ApiError';
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function apiOrigin(baseUrl: string): string {
  let url: URL;
  try { url = new URL(baseUrl); }
  catch { throw new Error('V21_API_ORIGIN_INVALID'); }
  const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
  if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) ||
      url.username || url.password || url.hash || url.search ||
      (url.pathname !== '/' && url.pathname !== '')) {
    throw new Error('V21_API_ORIGIN_INVALID');
  }
  return url.origin;
}

function apiPath(path: string, origin: string): string {
  if (!path.startsWith('/api/v2/') || path.includes('\\') ||
      /[\u0000-\u001f\u007f]/.test(path) || /(?:^|\/)\.{1,2}(?:\/|\?|#|$)/.test(path)) {
    throw new Error('V21_API_PATH_INVALID');
  }
  const resolved = new URL(path, origin);
  if (resolved.origin !== origin || !resolved.pathname.startsWith('/api/v2/')) {
    throw new Error('V21_API_PATH_INVALID');
  }
  return resolved.pathname + resolved.search;
}

export function createV21AdminApi(options: V21ClientOptions) {
  const origin = apiOrigin(options.baseUrl);
  const transport = options.fetchImpl ?? fetch;
  const timeoutMs = options.timeoutMs ?? 15_000;
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 120_000)
    throw new Error('V21_API_TIMEOUT_INVALID');

  async function request<T>(path: string, opts: V21RequestOptions = {}): Promise<ApiEnvelope<T>> {
    const target = origin + apiPath(path, origin);
    const method = opts.method ?? 'GET';
    if (method === 'GET' && opts.body !== undefined)
      throw new Error('V21_GET_BODY_FORBIDDEN');

    const headers = new Headers(opts.headers);
    if (headers.has('Authorization'))
      throw new Error('V21_AUTH_HEADER_OWNED_BY_CLERK');
    if (opts.idempotencyKey && !/^[A-Za-z0-9:_-]{8,180}$/.test(opts.idempotencyKey))
      throw new Error('V21_INVALID_IDEMPOTENCY_KEY');

    let token: string | null;
    try { token = await options.getToken(); }
    catch { throw new V21ApiError(401, 'INVALID_SESSION', 'Clerk session unavailable.'); }
    if (!token || /\s/.test(token))
      throw new V21ApiError(401, 'INVALID_SESSION', 'Sign in with Clerk to continue.');

    headers.set('Authorization', 'Bearer ' + token);
    headers.set('Accept', 'application/json');
    if (opts.body !== undefined) headers.set('Content-Type', 'application/json');
    if (opts.idempotencyKey) headers.set('Idempotency-Key', opts.idempotencyKey);

    const aborter = new AbortController();
    const abort = () => aborter.abort();
    if (opts.signal?.aborted) abort();
    opts.signal?.addEventListener('abort', abort, { once: true });
    const timeout = setTimeout(abort, timeoutMs);
    try {
      const response = await transport(target, {
        method,
        headers,
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
        signal: aborter.signal,
        credentials: 'omit',
        redirect: 'error',
      });
      const payload: unknown = await response.json().catch(() => null);
      const requestId = object(payload) && typeof payload.requestId === 'string'
        ? payload.requestId : null;

      if (!response.ok) {
        const details = object(payload) && object(payload.error) ? payload.error : null;
        const code = details && typeof details.code === 'string'
          ? details.code.slice(0, 100) : 'REQUEST_FAILED';
        const message = details && typeof details.message === 'string'
          ? details.message.slice(0, 240) : 'Request failed. Try again.';
        throw new V21ApiError(response.status, code, message, requestId);
      }
      if (!object(payload) || !('data' in payload) || typeof payload.requestId !== 'string') {
        throw new V21ApiError(502, 'INVALID_API_RESPONSE', 'Unexpected server response.');
      }
      return payload as unknown as ApiEnvelope<T>;
    } catch (error) {
      if (error instanceof V21ApiError) throw error;
      if (aborter.signal.aborted)
        throw new V21ApiError(0, 'REQUEST_ABORTED', 'Request cancelled or timed out.');
      throw new V21ApiError(0, 'NETWORK_UNAVAILABLE', 'Unable to reach BuildTo API.');
    } finally {
      clearTimeout(timeout);
      opts.signal?.removeEventListener('abort', abort);
    }
  }

  return {
    request,
    getMe: () => request<AdminIdentity>('/api/v2/me'),
    getAdminAccess: () => request<{ role: AdminRole }>('/api/v2/admin/access'),
  };
}
