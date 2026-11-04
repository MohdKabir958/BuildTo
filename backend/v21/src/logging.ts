import {randomUUID} from 'node:crypto';
import type {Request,RequestHandler,Response} from 'express';

export interface SafeLog {
  event:string;
  requestId:string;
  method?:string;
  path?:string;
  statusCode?:number;
  durationMs?:number;
}
export type LogWriter=(event:SafeLog)=>void;
export const jsonLogger:LogWriter=(event)=>process.stdout.write(JSON.stringify({...event,at:new Date().toISOString()})+'\n');
const VALID_REQUEST_ID=/^[a-zA-Z0-9_-]{8,64}$/;
export const requestContext=(log:LogWriter):RequestHandler=>(req:Request,res:Response,next)=>{
  const incoming=req.header('x-request-id');
  const requestId=incoming && VALID_REQUEST_ID.test(incoming)?incoming:randomUUID();
  res.locals.requestId=requestId;
  res.setHeader('X-Request-Id',requestId);
  const start=process.hrtime.bigint();
  res.on('finish',()=>{
    const durationMs=Number((process.hrtime.bigint()-start)/1_000_000n);
    // Do not log request bodies, raw URLs, querystrings, tokens, PII, errors, or connection URLs.
    log({event:'http_request',requestId,method:req.method,path:req.route?.path || req.path,
      statusCode:res.statusCode,durationMs});
  });
  next();
};
