import express, {NextFunction,Request,Response} from 'express';
import {randomUUID} from 'node:crypto';
import {PrismaClient} from '../../generated/buildto-v21';
import {ApiError,errorHandler} from './errors';
import {errorDTO} from './contracts';
import {requestContext,LogWriter,jsonLogger} from './logging';
import {RateLimiter} from './rateLimit';

export interface AppDependencies {
  db:Pick<PrismaClient,'$queryRaw'>;
  limiter:RateLimiter;
  log?:LogWriter;
  allowedOrigins:string[];
  proxyHops:number;
}
export function createV21App(deps:AppDependencies) {
  const app=express();
  app.disable('x-powered-by');
  app.set('trust proxy',deps.proxyHops);
  app.use(requestContext(deps.log??jsonLogger));
  app.use((req,res,next)=>{
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('X-Frame-Options','DENY');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('Cache-Control','no-store');
    res.setHeader('Content-Security-Policy',"default-src 'none'; frame-ancestors 'none'");
    if(req.secure)res.setHeader('Strict-Transport-Security','max-age=31536000; includeSubDomains');
    const origin=req.header('origin');
    if(origin) {
      if(!deps.allowedOrigins.includes(origin))return next(new ApiError(403,'ORIGIN_NOT_ALLOWED','Origin is not allowed.'));
      res.setHeader('Access-Control-Allow-Origin',origin);
      res.setHeader('Vary','Origin');
      res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization, Idempotency-Key, X-Request-Id');
      res.setHeader('Access-Control-Allow-Methods','GET, POST, PATCH, PUT, DELETE, OPTIONS');
      res.setHeader('Access-Control-Max-Age','600');
    }
    if(req.method==='OPTIONS')return res.status(204).end();
    next();
  });
  app.use(express.json({limit:'64kb',strict:true}));
  app.use((req,res,next)=>{
    if(['POST','PUT','PATCH'].includes(req.method) && req.path.startsWith('/api/v2/') &&
       !req.is('application/json'))return next(new ApiError(415,'JSON_REQUIRED','Content-Type must be application/json.'));
    next();
  });
  app.get('/health',(_req,res)=>res.status(200).json({status:'ok',service:'buildto-v21-api',requestId:res.locals.requestId}));
  app.get('/ready',async(_req,res)=>{
    try {
      await deps.db.$queryRaw`SELECT 1`;
      res.status(200).json({ready:true,requestId:res.locals.requestId});
    }catch {
      res.status(503).json(errorDTO('DATABASE_UNAVAILABLE','Service temporarily unavailable.',res.locals.requestId));
    }
  });
  app.use('/api/v2',async(req:Request,res:Response,next:NextFunction)=>{
    try {
      const subject='public:'+req.ip+':'+req.method+':'+req.path;
      const rate=await deps.limiter.check(subject,60,60);
      res.setHeader('X-RateLimit-Remaining',String(rate.remaining));
      next();
    }catch(e){next(e);}
  });
  app.get('/api/v2/system',(_req,res)=>{
    res.status(200).json({
      data:{
        apiVersion:'v2',
        currency:'INR',
        moneyFormat:'decimal-string-paise',
        releaseStage:'foundation',
        capabilities:[] as string[],
      },
      requestId:res.locals.requestId,
    });
  });
  // Other V2 routes are intentionally absent until Clerk + database RBAC in PR 03.
  app.use((_req,res)=>res.status(404).json(errorDTO('NOT_FOUND','Endpoint not found.',res.locals.requestId||randomUUID())));
  app.use(errorHandler);
  return app;
}
