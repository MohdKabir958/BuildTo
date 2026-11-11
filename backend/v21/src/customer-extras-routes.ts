import type {Express,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {customerWishlist,saveWishlist,removeWishlist,customerNotifications,markCustomerNotificationRead} from './customer-extras-service';
const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
export function registerCustomerExtras(app:Express,db:PrismaClient,auth:RequestHandler){
 app.get('/api/v2/me/wishlist',auth,async(_req,res,next)=>{
  try{res.json({data:await customerWishlist(db,actor(res)),requestId:res.locals.requestId});}catch(e){next(e);}
 });
 app.put('/api/v2/me/wishlist/:listingId',auth,async(req,res,next)=>{
  try{res.json({data:await saveWishlist(db,actor(res),req.params.listingId),requestId:res.locals.requestId});}catch(e){next(e);}
 });
 app.delete('/api/v2/me/wishlist/:listingId',auth,async(req,res,next)=>{
  try{res.json({data:await removeWishlist(db,actor(res),req.params.listingId),requestId:res.locals.requestId});}catch(e){next(e);}
 });
 app.get('/api/v2/me/notifications',auth,async(req,res,next)=>{
  try{
   const cursor=req.query.cursor;
   if(cursor!==undefined&&typeof cursor!=='string')throw new ApiError(400,'INVALID_CURSOR','Invalid notification cursor.');
   res.json({data:await customerNotifications(db,actor(res),cursor),requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
 app.post('/api/v2/me/notifications/:notificationId/read',auth,async(req,res,next)=>{
  try{res.json({data:await markCustomerNotificationRead(db,actor(res),req.params.notificationId),requestId:res.locals.requestId});}catch(e){next(e);}
 });
}
