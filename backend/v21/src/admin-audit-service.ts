import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {isUuid,requireAdminPermission} from './permissions';

// Audit data may include confidential before/after snapshots. Never send them to the browser.
const SELECT={
  id:true,actorUserId:true,actorRole:true,action:true,
  entityType:true,entityId:true,createdAt:true,
} as const;
const textFilter=(value:unknown,label:string,pattern:RegExp):string|undefined=>{
  if(value===undefined)return undefined;
  if(typeof value!=='string'||!pattern.test(value))
    throw new ApiError(400,'INVALID_QUERY','Invalid '+label+' filter.');
  return value;
};
export interface AuditQuery {limit?:unknown;cursor?:unknown;entityType?:unknown;action?:unknown}
export async function adminAudit(db:PrismaClient,actorId:string,query:AuditQuery) {
  await requireAdminPermission(db,actorId,'AUDIT_READ');
  const limit=query.limit===undefined?25:Number(query.limit);
  if(!Number.isSafeInteger(limit)||limit<1||limit>50)
    throw new ApiError(400,'INVALID_LIMIT','Audit page size must be 1–50.');
  const cursor=textFilter(query.cursor,'cursor',/^[0-9a-fA-F-]{36}$/);
  if(cursor&&!isUuid(cursor))throw new ApiError(400,'INVALID_CURSOR','Invalid audit cursor.');
  const entityType=textFilter(query.entityType,'entity type',/^[A-Za-z][A-Za-z0-9_-]{0,99}$/);
  const action=textFilter(query.action,'action',/^[A-Z][A-Z0-9_]{0,119}$/);
  // Index-friendly bounded pages; individual fields are explicitly projected.
  // No raw headers, IP hashes, request payloads, beforeState or afterState.
  const rows=await db.auditEvent.findMany({
    where:{...(entityType?{entityType}:{}),...(action?{action}:{})},
    select:SELECT,orderBy:[{createdAt:'desc'},{id:'desc'}],
    ...(cursor?{cursor:{id:cursor},skip:1}:{}),take:limit+1,
  });
  const more=rows.length>limit;
  const page=rows.slice(0,limit);
  return {
    items:page.map(row=>({
      id:row.id,createdAt:row.createdAt.toISOString(),
      action:row.action,entityType:row.entityType,entityId:row.entityId,
      actorRole:row.actorRole,actorUserId:row.actorUserId,
    })),
    nextCursor:more?page[page.length-1].id:null,
  };
}
