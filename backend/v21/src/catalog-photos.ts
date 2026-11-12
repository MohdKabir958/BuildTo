import {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireSupplierPermission} from './permissions';

type Tx=Pick<PrismaClient,'catalogImage'>;
export const MAX_PHOTO_BYTES=8*1024*1024;
const PHOTO_TYPE_MESSAGE='Use a JPEG, PNG, WebP, GIF, BMP, HEIC, or AVIF photo.';
const PHOTO_SIZE_MESSAGE='Choose a photo of 8 MB or smaller.';
const DECLARED_PHOTO_TYPES:Record<string,string>={
 'image/jpeg':'image/jpeg','image/jpg':'image/jpeg','image/pjpeg':'image/jpeg',
 'image/png':'image/png','image/x-png':'image/png',
 'image/webp':'image/webp','image/gif':'image/gif',
 'image/bmp':'image/bmp','image/x-ms-bmp':'image/bmp',
 'image/heic':'image/heic','image/heic-sequence':'image/heic',
 'image/heif':'image/heif','image/heif-sequence':'image/heif',
 'image/avif':'image/avif',
};

export function productPhotoContentType(header:string):string|null {
 return DECLARED_PHOTO_TYPES[header.split(';')[0].trim().toLowerCase()]??null;
}
function isoBrand(bytes:Buffer):string|null {
 if(bytes.length<12||bytes.toString('ascii',4,8)!=='ftyp')return null;
 return bytes.toString('ascii',8,12).toLowerCase();
}
function detectedPhotoType(bytes:Buffer):string|null {
 if(bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)return 'image/jpeg';
 if(bytes.length>=8&&bytes.subarray(0,8).equals(Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])))return 'image/png';
 if(bytes.length>=12&&bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP')return 'image/webp';
 const gif=bytes.length>=6?bytes.toString('ascii',0,6):'';
 if(gif==='GIF87a'||gif==='GIF89a')return 'image/gif';
 if(bytes.length>=2&&bytes[0]===0x42&&bytes[1]===0x4d)return 'image/bmp';
 const brand=isoBrand(bytes);
 if(brand==='avif'||brand==='avis')return 'image/avif';
 if(brand&&['heic','heix','hevc','hevx','heim','heis'].includes(brand))return 'image/heic';
 if(brand&&['heif','mif1','msf1'].includes(brand))return 'image/heif';
 return null;
}
function samePhotoFamily(detected:string,declared:string) {
 return detected===declared||(
  (detected==='image/heic'||detected==='image/heif')&&
  (declared==='image/heic'||declared==='image/heif')
 );
}

export function sniffProductPhoto(bytes:Buffer,declared:string):string {
 const mime=productPhotoContentType(declared);
 const detected=detectedPhotoType(bytes);
 if(!mime||!detected||!samePhotoFamily(detected,mime))
  throw new ApiError(415,'UNSUPPORTED_IMAGE',PHOTO_TYPE_MESSAGE);
 if(bytes.length>MAX_PHOTO_BYTES)throw new ApiError(413,'PAYLOAD_TOO_LARGE',PHOTO_SIZE_MESSAGE);
 return mime;
}
export async function storeProductPhoto(db:PrismaClient,actorId:string,supplierId:string,bytes:Buffer,declared:string) {
 await requireSupplierPermission(db,actorId,supplierId,'CATALOG_WRITE');
 const mimeType=sniffProductPhoto(bytes,declared);
 const row=await db.catalogImage.create({data:{mimeType,bytes},select:{id:true}});
 return {imageUrl:'/api/v2/catalog/images/'+row.id};
}
export async function readProductPhoto(db:PrismaClient,id:string) {
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))
  throw new ApiError(404,'NOT_FOUND','Photo not found.');
 const row=await db.catalogImage.findUnique({where:{id},select:{mimeType:true,bytes:true}});
 if(!row)throw new ApiError(404,'NOT_FOUND','Photo not found.');
 return row;
}
export async function requireCatalogImage(tx:Tx,imageUrl:string) {
 const id=imageUrl.split('/').pop()??'';
 const image=await tx.catalogImage.findUnique({where:{id},select:{id:true}});
 if(!image)throw new ApiError(422,'IMAGE_NOT_FOUND','Choose the photo again.');
}
