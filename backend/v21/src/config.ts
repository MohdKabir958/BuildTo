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
  razorpayXKeyId:string|null;
  razorpayXKeySecret:string|null;
  deliveryOtpHmacSecret:string|null;
}
const STAGING_HOST = 'ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech';
function isExactOrigin(value:string):boolean{
 try{
  const url=new URL(value);
  return ['http:','https:'].includes(url.protocol)&&url.origin===value&&
   !url.username&&!url.password&&url.pathname==='/'&&!url.search&&!url.hash;
 }catch{return false;}
}
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
  if(environment==='staging'&&(
   database.searchParams.getAll('sslmode').length!==1||
   !['require','verify-full','verify-ca'].includes(database.searchParams.get('sslmode')??'')||
   env.NODE_TLS_REJECT_UNAUTHORIZED==='0'
  ))throw new Error('V21_STAGING_TLS_REQUIRED: encrypted PostgreSQL and verified TLS are mandatory.');
  if (environment === 'local' && !['localhost', '127.0.0.1', '::1', '[::1]'].includes(database.hostname)) {
    throw new Error('V21_DATABASE_TARGET_DENIED: local must use loopback database.');
  }
  const port = Number(env.PORT ?? '5100');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('V21_PORT_INVALID');
  const proxyHops = Number(env.BUILDTO_V21_TRUST_PROXY_HOPS ?? '0');
  if (!Number.isInteger(proxyHops) || proxyHops < 0 || proxyHops > 1) throw new Error('V21_PROXY_CONFIG_INVALID');
  const corsOrigins = (env.BUILDTO_V21_CORS_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean);
  if (corsOrigins.some(x => !isExactOrigin(x))) {
    throw new Error('V21_CORS_ORIGIN_INVALID');
  }
  if (environment === 'staging' && (corsOrigins.length === 0 || corsOrigins.some(x => !x.startsWith('https://')))) {
    throw new Error('V21_CORS_REQUIRED: staging needs explicit HTTPS origins.');
  }
  const deliveryOtpHmacSecret=env.BUILDTO_V21_DELIVERY_OTP_HMAC_SECRET||null;
  if(deliveryOtpHmacSecret&&Buffer.byteLength(deliveryOtpHmacSecret,'utf8')<32)
    throw new Error('V21_DELIVERY_OTP_SECRET_TOO_SHORT: use at least 32 bytes.');
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
  const razorpayXKeyId=env.RAZORPAYX_READ_ONLY_KEY_ID?.trim()||null;
  const razorpayXKeySecret=env.RAZORPAYX_READ_ONLY_KEY_SECRET?.trim()||null;
  if(Boolean(razorpayXKeyId)!==Boolean(razorpayXKeySecret)||
    razorpayXKeyId&&!/^rzp_(test|live)_[A-Za-z0-9]+$/.test(razorpayXKeyId))
    throw new Error('V21_RAZORPAYX_READ_ONLY_CONFIG_INVALID');
  if(environment==='staging'&&razorpayXKeyId?.startsWith('rzp_live_'))
    throw new Error('V21_RAZORPAYX_STAGING_LIVE_KEY_DENIED');
  const clerkIssuer=env.CLERK_ISSUER?.trim()||null;
  const clerkSecretKey=env.CLERK_SECRET_KEY?.trim()||null;
  const clerkJwtKey=env.CLERK_JWT_KEY?.trim()||null;
  const clerkAudience=env.CLERK_AUDIENCE?.trim()||null;
  const clerkWebhookSecret=env.CLERK_WEBHOOK_SIGNING_SECRET?.trim()||null;
  const clerkAuthorizedParties=(env.CLERK_AUTHORIZED_PARTIES||'').split(',').map(x=>x.trim()).filter(Boolean);
  const clerkAllowNativeWithoutAzp=env.CLERK_ALLOW_NATIVE_WITHOUT_AZP==='true';
  if(clerkAuthorizedParties.some(x=>!isExactOrigin(x)))throw new Error('V21_CLERK_PARTIES_INVALID');
  if(environment==='staging') {
    // Identify only the configuration KEYS that fail validation, never their values.
    const missingOrInvalid: string[]=[];
    if(!clerkIssuer?.startsWith('https://'))missingOrInvalid.push('CLERK_ISSUER');
    if(!clerkSecretKey)missingOrInvalid.push('CLERK_SECRET_KEY');
    if(!clerkWebhookSecret?.startsWith('whsec_'))missingOrInvalid.push('CLERK_WEBHOOK_SIGNING_SECRET');
    if(!clerkAuthorizedParties.length||clerkAuthorizedParties.some(x=>!x.startsWith('https://')))
      missingOrInvalid.push('CLERK_AUTHORIZED_PARTIES');
    if(missingOrInvalid.length)
      throw new Error('V21_CLERK_CONFIG_REQUIRED: invalid or missing '+missingOrInvalid.join(', '));
  }
  return {
    clerkIssuer,clerkAuthorizedParties,clerkSecretKey,clerkJwtKey,clerkAudience,clerkWebhookSecret,
    clerkAllowNativeWithoutAzp,razorpayKeyId,razorpayKeySecret,razorpayWebhookSecret,
    deliveryOtpHmacSecret,razorpayXKeyId,razorpayXKeySecret,
    environment,
    port,
    databaseUrl: env.DATABASE_URL!,
    corsOrigins,
    proxyHops,
  };
}
