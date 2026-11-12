import {S3Client,PutObjectCommand,GetObjectCommand,DeleteObjectCommand} from '@aws-sdk/client-s3';
import type {MediaStore} from './media';

/** Private bucket only: downloads continue through the authenticated API. */
export class PrivateS3MediaStore implements MediaStore {
 constructor(private client:S3Client,private bucket:string){}
 private key(key:string){
  if(!/^[0-9a-f-]{36}$/.test(key))throw new Error('INVALID_STORAGE_KEY');
  return key;
 }
 async put(key:string,bytes:Buffer){
  await this.client.send(new PutObjectCommand({Bucket:this.bucket,Key:this.key(key),Body:bytes,
   ContentType:'application/octet-stream',IfNoneMatch:'*'}));
 }
 async get(key:string){
  const result=await this.client.send(new GetObjectCommand({Bucket:this.bucket,Key:this.key(key)}));
  if(!result.Body)throw new Error('MEDIA_BODY_MISSING');
  return Buffer.from(await result.Body.transformToByteArray());
 }
 async remove(key:string){
  await this.client.send(new DeleteObjectCommand({Bucket:this.bucket,Key:this.key(key)}));
 }
}
export function privateS3MediaStore(env:NodeJS.ProcessEnv):MediaStore|undefined{
 const names=['BUILDTO_V21_MEDIA_S3_ENDPOINT','BUILDTO_V21_MEDIA_S3_REGION',
  'BUILDTO_V21_MEDIA_S3_BUCKET','BUILDTO_V21_MEDIA_S3_ACCESS_KEY_ID',
  'BUILDTO_V21_MEDIA_S3_SECRET_ACCESS_KEY'] as const;
 const values=names.map(name=>env[name]?.trim());
 if(values.every(value=>!value))return undefined;
 if(values.some(value=>!value))throw new Error('V21_MEDIA_S3_CONFIG_INCOMPLETE');
 const [endpoint,region,bucket,accessKeyId,secretAccessKey]=values as string[];
 const url=new URL(endpoint);
 if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash)
  throw new Error('V21_MEDIA_S3_ENDPOINT_INVALID');
 return new PrivateS3MediaStore(new S3Client({endpoint,region,forcePathStyle:true,
  credentials:{accessKeyId,secretAccessKey}}),bucket);
}
