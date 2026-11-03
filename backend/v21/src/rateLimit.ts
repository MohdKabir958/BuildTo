import {createHmac} from 'node:crypto';
import {ApiError} from './errors';

export interface RateLimiter { check(subject:string,max:number,windowSeconds:number):Promise<{remaining:number}> }
export class RedisRestRateLimiter implements RateLimiter {
  constructor(
    private readonly url:string,
    private readonly token:string,
    private readonly hashKey:string,
    private readonly fetcher:typeof fetch=fetch,
  ) {}
  async check(subject:string,max:number,windowSeconds:number):Promise<{remaining:number}> {
    if(!Number.isInteger(max)||max<1||!Number.isInteger(windowSeconds)||windowSeconds<1)throw new Error('INVALID_RATE_LIMIT_RULE');
    // Store only keyed HMAC, never source IP/email/identity in the Redis key.
    const key='buildto:v21:rl:'+createHmac('sha256',this.hashKey).update(subject).digest('hex');
    const lua="local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]); end; return n";
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),1500);
    let result:unknown;
    try {
      const response=await this.fetcher(this.url,{
        method:'POST',headers:{Authorization:'Bearer '+this.token,'Content-Type':'application/json'},
        body:JSON.stringify(['EVAL',lua,'1',key,String(windowSeconds)]),
        signal:controller.signal
      });
      if(!response.ok)throw new Error('REDIS_RESPONSE_NOT_OK');
      result=(await response.json() as {result?:unknown}).result;
    }catch {
      throw new ApiError(503,'RATE_LIMIT_UNAVAILABLE','Service temporarily unavailable.');
    }finally {clearTimeout(timeout);}
    if(typeof result!=='number'||!Number.isInteger(result)||result<1)
      throw new ApiError(503,'RATE_LIMIT_UNAVAILABLE','Service temporarily unavailable.');
    if(result>max)throw new ApiError(429,'RATE_LIMITED','Too many requests.');
    return {remaining:Math.max(0,max-result)};
  }
}
export class InMemoryTestLimiter implements RateLimiter {
  private buckets=new Map<string,{count:number,expires:number}>();
  async check(subject:string,max:number,windowSeconds:number):Promise<{remaining:number}> {
    const now=Date.now();const old=this.buckets.get(subject);const bucket=old&&old.expires>now?old:{count:0,expires:now+windowSeconds*1000};
    bucket.count++;this.buckets.set(subject,bucket);
    if(bucket.count>max)throw new ApiError(429,'RATE_LIMITED','Too many requests.');
    return {remaining:max-bucket.count};
  }
}
