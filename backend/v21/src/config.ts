import { URL } from 'node:url';

export type V21Environment = 'local' | 'staging';
export interface V21Config {
  environment: V21Environment;
  port: number;
  databaseUrl: string;
  corsOrigins: string[];
  proxyHops: number;
  clerkIssuer: string | null;
  clerkAuthorizedParties: string[];
  clerkSecretKey: string | null;
  clerkJwtKey: string | null;
  clerkAudience: string | null;
  clerkWebhookSecret: string | null;
  clerkAllowNativeWithoutAzp: boolean;
  razorpayKeyId:string|null;
  razorpayKeySecret:string|null;
  razorpayWebhookSecret:string|null;
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
  const razorpayKeyId=env.RAZORPAY_KEY_ID?.trim()||null;
  const razorpayKeySecret=env.RAZORPAY_KEY_SECRET?.trim()||null;
  const razorpayWebhookSecret=env.RAZORPAY_WEBHOOK_SECRET?.trim()||null;
  if([razorpayKeyId,razorpayKeySecret,razorpayWebhookSecret].some(Boolean) &&
     (!razorpayKeyId||!razorpayKeySecret||!razorpayWebhookSecret||
      !/^rzp_(test|live)_[A-Za-z0-9]+$/.test(razorpayKeyId)||
      razorpayWebhookSecret.length<24))
    throw new Error('V21_RAZORPAY_CONFIG_INCOMPLETE');
  if(environment==='staging'&&razorpayKeyId?.startsWith('rzp_live_'))
    throw new Error('V21_RAZORPAY_LIVE_KEY_NOT_ALLOWED_IN_STAGING');
  const clerkIssuer=env.CLERK_ISSUER?.trim()||null;
  const clerkSecretKey=env.CLERK_SECRET_KEY?.trim()||null;
  const clerkJwtKey=env.CLERK_JWT_KEY?.trim()||null;
  const clerkAudience=env.CLERK_AUDIENCE?.trim()||null;
  const clerkWebhookSecret=env.CLERK_WEBHOOK_SIGNING_SECRET?.trim()||null;
  const clerkAuthorizedParties=(env.CLERK_AUTHORIZED_PARTIES||'').split(',').map(x=>x.trim()).filter(Boolean);
  const clerkAllowNativeWithoutAzp=env.CLERK_ALLOW_NATIVE_WITHOUT_AZP==='true';
  if(clerkAuthorizedParties.some(x=>!/^https?:\/\//.test(x)||x.includes('*')))throw new Error('V21_CLERK_PARTIES_INVALID');
  if(clerkAllowNativeWithoutAzp && !clerkAudience)throw new Error('V21_CLERK_NATIVE_AUDIENCE_REQUIRED');
  if(environment==='staging' && (
    !clerkIssuer?.startsWith('https://') || !clerkSecretKey || !clerkWebhookSecret?.startsWith('whsec_') ||
    !clerkAuthorizedParties.length || clerkAuthorizedParties.some(x=>!x.startsWith('https://'))
  ))throw new Error('V21_CLERK_CONFIG_REQUIRED: staging needs issuer, server key, signed webhook secret and HTTPS authorized parties.');
  return {
    clerkIssuer,clerkAuthorizedParties,clerkSecretKey,clerkJwtKey,clerkAudience,clerkWebhookSecret,
    clerkAllowNativeWithoutAzp,razorpayKeyId,razorpayKeySecret,razorpayWebhookSecret,
    environment,
    port,
    databaseUrl: env.DATABASE_URL!,
    corsOrigins,
    proxyHops,
  };
}
