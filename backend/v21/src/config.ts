import { URL } from 'node:url';

export type V21Environment = 'local' | 'staging';
export interface V21Config {
  environment: V21Environment;
  port: number;
  databaseUrl: string;
  corsOrigins: string[];
  proxyHops: number;
  redisRestUrl: string | null;
  redisRestToken: string | null;
  rateLimitHashKey: string | null;
}
const STAGING_HOST = 'ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech';
export function readConfig(env: NodeJS.ProcessEnv): V21Config {
  const environment = env.BUILDTO_V21_ENV;
  // PR 02 is NOT approved for production. Unknown environment is a startup error.
  if (environment !== 'local' && environment !== 'staging') {
    throw new Error('V21_ENV_NOT_ALLOWED: use local or approved staging until production cutover.');
  }
  let database: URL;
  try {
    database = new URL(env.DATABASE_URL || '');
    if (!['postgres:', 'postgresql:'].includes(database.protocol) || !database.pathname.slice(1)) throw new Error();
  } catch {
    throw new Error('V21_DATABASE_URL_INVALID: PostgreSQL connection required.');
  }
  if (environment === 'staging' && database.hostname !== STAGING_HOST) {
    throw new Error('V21_DATABASE_TARGET_DENIED: only the approved Buildto Neon staging host is allowed.');
  }
  if (environment === 'local' && !['localhost', '127.0.0.1', '::1', '[::1]'].includes(database.hostname)) {
    throw new Error('V21_DATABASE_TARGET_DENIED: local must use loopback database.');
  }
  const port = Number(env.PORT ?? '5100');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('V21_PORT_INVALID');
  const proxyHops = Number(env.BUILDTO_V21_TRUST_PROXY_HOPS ?? '0');
  if (!Number.isInteger(proxyHops) || proxyHops < 0 || proxyHops > 1) throw new Error('V21_PROXY_CONFIG_INVALID');
  const corsOrigins = (env.BUILDTO_V21_CORS_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean);
  if (corsOrigins.some(x => x === '*' || !/^https?:\/\//.test(x) || x.includes('*'))) {
    throw new Error('V21_CORS_ORIGIN_INVALID');
  }
  if (environment === 'staging' && (corsOrigins.length === 0 || corsOrigins.some(x => !x.startsWith('https://')))) {
    throw new Error('V21_CORS_REQUIRED: staging needs explicit HTTPS origins.');
  }
  const redisRestUrl = env.BUILDTO_V21_REDIS_REST_URL?.trim() || null;
  const redisRestToken = env.BUILDTO_V21_REDIS_REST_TOKEN?.trim() || null;
  const rateLimitHashKey = env.BUILDTO_V21_RATE_LIMIT_HMAC_KEY?.trim() || null;
  if (environment === 'staging' && (!redisRestUrl || !redisRestToken || !rateLimitHashKey || rateLimitHashKey.length < 32)) {
    throw new Error('V21_RATE_LIMIT_CONFIG_REQUIRED: staging needs central rate limiting and keyed IP hashing.');
  }
  if (redisRestUrl && !redisRestUrl.startsWith('https://')) throw new Error('V21_REDIS_URL_INVALID');
  if ((redisRestUrl === null) !== (redisRestToken === null)) throw new Error('V21_REDIS_CONFIG_INCOMPLETE');
  return {
    environment,
    port,
    databaseUrl: env.DATABASE_URL!,
    corsOrigins,
    proxyHops,
    redisRestUrl,
    redisRestToken,
    rateLimitHashKey,
  };
}
