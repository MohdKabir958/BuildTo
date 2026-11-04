import type {ErrorRequestHandler} from 'express';
import {errorDTO} from './contracts';

export class ApiError extends Error {
  constructor(public readonly status:number,public readonly code:string,message:string) {
    super(message);
    this.name='ApiError';
  }
}
export function normalizeError(error:unknown):ApiError {
  if (error instanceof ApiError) return error;
  if (error && typeof error==='object' && 'code' in error) {
    const code=(error as {code?:unknown}).code;
    if (code==='P2002') return new ApiError(409,'RESOURCE_CONFLICT','Resource already exists.');
    if (code==='P2025') return new ApiError(404,'NOT_FOUND','Resource not found.');
  }
  if (error && typeof error==='object' && 'type' in error) {
    if ((error as {type?:unknown}).type==='entity.too.large') return new ApiError(413,'PAYLOAD_TOO_LARGE','Request body exceeds the allowed size.');
    if ((error as {type?:unknown}).type==='entity.parse.failed') return new ApiError(400,'INVALID_JSON','Request body must contain valid JSON.');
  }
  return new ApiError(500,'INTERNAL_ERROR','An unexpected server error occurred.');
}
export const errorHandler:ErrorRequestHandler=(error,req,res,_next)=>{
  const mapped=normalizeError(error);
  const requestId=typeof res.locals.requestId==='string'?res.locals.requestId:'unknown';
  if (res.headersSent) return;
  res.status(mapped.status).json(errorDTO(mapped.code,mapped.message,requestId));
};
