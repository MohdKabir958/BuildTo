import {ApiError} from './errors';

// Bounded, per-process limiting for Buildto's explicitly single API instance.
// No Redis or network dependency. If we later add replicas, use a shared store.
export interface RateLimiter {
  check(subject:string,max:number,windowSeconds:number):Promise<{remaining:number}>;
}
export class SingleInstanceRateLimiter implements RateLimiter {
  private readonly buckets=new Map<string,{count:number;expires:number}>();
  constructor(private readonly maxSubjects=10000, private readonly clock:()=>number=Date.now) {
    if(!Number.isInteger(maxSubjects)||maxSubjects<10)throw new Error('INVALID_RATE_LIMIT_CAPACITY');
  }
  async check(subject:string,max:number,windowSeconds:number):Promise<{remaining:number}> {
    if(!subject||subject.length>512||!Number.isInteger(max)||max<1||
       !Number.isInteger(windowSeconds)||windowSeconds<1||windowSeconds>86400)
      throw new Error('INVALID_RATE_LIMIT_RULE');
    const now=this.clock();
    let b=this.buckets.get(subject);
    if(b&&b.expires<=now){this.buckets.delete(subject);b=undefined;}
    if(!b){
      if(this.buckets.size>=this.maxSubjects){
        for(const [key,entry] of this.buckets)if(entry.expires<=now)this.buckets.delete(key);
      }
      if(this.buckets.size>=this.maxSubjects)
        throw new ApiError(503,'RATE_LIMIT_CAPACITY','Service temporarily busy.');
      b={count:0,expires:now+windowSeconds*1000};
      this.buckets.set(subject,b);
    }
    b.count++;
    if(b.count>max)throw new ApiError(429,'RATE_LIMITED','Too many requests.');
    return {remaining:max-b.count};
  }
}
export class InMemoryTestLimiter extends SingleInstanceRateLimiter {}
