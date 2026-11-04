import express, {NextFunction,Request,Response} from 'express';
import {randomUUID} from 'node:crypto';
import {PrismaClient} from '../../generated/buildto-v21';
import {ApiError,errorHandler} from './errors';
import {errorDTO} from './contracts';
import {requestContext,LogWriter,jsonLogger} from './logging';
import {RateLimiter} from './rateLimit';
import {IdentityVerifier,requireIdentity} from './identity';
import {requireAdminPermission,requireSupplierPermission,listOwnMemberships} from './permissions';
import {verifyClerkWebhook,synchronizeClerkWebhook} from './clerk-webhooks';
import {registerPublicCatalog,registerProtectedCatalog} from './catalog-routes';
import {registerPublicDelivery,registerProtectedDelivery} from './delivery-routes';
import {registerProtectedInventory} from './inventory-routes';
import {registerRfqAndPromotions} from './rfq-routes';
import {registerProtectedCheckout} from './checkout-routes';
import {registerProtectedPayments} from './payment-routes';
import {registerCodAndInvoices} from './cod-invoice-routes';
import {registerFulfillment} from './fulfillment-routes';
import {registerReturnsSupportReviews,registerPublicReviews} from './customer-care-routes';
import {registerFinance} from './finance-routes';
import {registerReturnsFinance} from './refund-routes';
import {registerPayouts} from './payout-routes';
import {registerAdminTeam} from './admin-team-routes';
import type {PayoutEvidenceGateway} from './payout-gateway';
import {verifyRazorpayWebhook,receiveRazorpayEvent} from './payment-service';
import type {PaymentGateway} from './payment-gateway';

export interface AppDependencies {
  db:PrismaClient;
  identityVerifier?:IdentityVerifier;
  clerkWebhookSecret?:string;
  razorpayWebhookSecret?:string;
  paymentGateway?:PaymentGateway;
  payoutEvidenceGateway?:PayoutEvidenceGateway;
  readinessCheck?:()=>Promise<void>;
  deliveryOtpSecret?:string;
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
  // Provider webhooks must use original bytes; register before the JSON parser.
  // Signed provider events use a separate budget from normal app navigation.
  const makeLimit=(bucket:string,max:number):import('express').RequestHandler=>async(req,res,next)=>{
    try {
      const subject=bucket+':'+req.ip+':'+req.method;
      const rate=await deps.limiter.check(subject,max,60);
      res.setHeader('X-RateLimit-Remaining',String(rate.remaining));
      next();
    }catch(error){next(error);}
  };
  const apiLimit=makeLimit('api',300);
  const webhookLimit=makeLimit('clerk-webhook',240);
  if(deps.clerkWebhookSecret){
    app.post('/api/v2/webhooks/clerk',webhookLimit,express.raw({type:'application/json',limit:'64kb'}),async(req,res,next)=>{
      try{
        const header=(name:string)=>req.header('svix-'+name)||req.header('webhook-'+name);
        const verified=verifyClerkWebhook(req.body,{
          id:header('id'),timestamp:header('timestamp'),signature:header('signature')
        },deps.clerkWebhookSecret!);
        if(!verified)return res.status(202).json({accepted:true,ignored:true,requestId:res.locals.requestId});
        const applied=await synchronizeClerkWebhook(deps.db,verified);
        return res.status(200).json({accepted:true,duplicate:applied.duplicate,requestId:res.locals.requestId});
      }catch(error){next(error);}
    });
  }
  if(deps.paymentGateway && deps.razorpayWebhookSecret){
    app.post('/api/v2/webhooks/razorpay',makeLimit('razorpay-webhook',240),
      express.raw({type:'application/json',limit:'128kb'}),async(req,res,next)=>{
       try{
        const event=verifyRazorpayWebhook(req.body,req.header('x-razorpay-signature'),
         req.header('x-razorpay-event-id'),deps.razorpayWebhookSecret!);
        const applied=await receiveRazorpayEvent(deps.db,event);
        if(applied.retry)return res.status(503).json(errorDTO('PAYMENT_EVENT_RETRY',
         'Payment event is awaiting its order record.',res.locals.requestId));
        res.status(200).json({accepted:true,duplicate:applied.duplicate,
         requestId:res.locals.requestId});
       }catch(error){next(error);}
      });
  }
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
      if(deps.readinessCheck)await deps.readinessCheck();
      res.status(200).json({ready:true,requestId:res.locals.requestId});
    }catch {
      res.status(503).json(errorDTO('DATABASE_UNAVAILABLE','Service temporarily unavailable.',res.locals.requestId));
    }
  });
  app.use('/api/v2',apiLimit);
  app.get('/api/v2/system',(_req,res)=>{
    res.status(200).json({
      data:{
        apiVersion:'v2',
        currency:'INR',
        moneyFormat:'decimal-string-paise',
        releaseStage:'unreleased-staging-candidate',
        productionReady:false,
        automaticRefundExecution:false,
        automaticPayoutExecution:false,
        bankStatementAPIReconciled:false,
        partialGstCreditSupported:false,
        capabilities:['catalog.discovery','catalog.supplier','catalog.review','delivery.areas','delivery.flat-fees','inventory.warehouses','inventory.adjustments','inventory.transfers','rfq.requests','rfq.quotes','promotions.admin','cart.customer','checkout.pricing','orders.customer','cod.customer','cod.supplier','cod.finance-review','invoices.supplier','fulfillment.supplier','shipments.tracking','returns.customer','support.cases','reviews.moderated','finance.reconciliation','finance.settlement-proposals','finance.cod-commissions','returns.credit-notes','finance.refund-requests','finance.refund-evidence','finance.payout-beneficiaries','finance.payout-reconciliation',
          ...(deps.deliveryOtpSecret?['shipments.otp']:[]),...(deps.paymentGateway && deps.razorpayWebhookSecret?['payments.razorpay']:[])] as string[],
      },
      requestId:res.locals.requestId,
    });
  });
  registerPublicCatalog(app,deps.db);
  registerPublicDelivery(app,deps.db);
  registerPublicReviews(app,deps.db);
  // These are identity/permission introspection endpoints only. No supplier/admin
  // mutation endpoints are exposed before domain-specific security tests.
  if(deps.identityVerifier){
    const auth=requireIdentity(deps.identityVerifier,deps.db);
    registerProtectedCatalog(app,deps.db,auth);
    registerProtectedDelivery(app,deps.db,auth);
    registerProtectedInventory(app,deps.db,auth);
    registerRfqAndPromotions(app,deps.db,auth);
    registerProtectedCheckout(app,deps.db,auth);
    registerCodAndInvoices(app,deps.db,auth);
    registerFulfillment(app,deps.db,auth,deps.deliveryOtpSecret);
    registerReturnsSupportReviews(app,deps.db,auth);
    registerFinance(app,deps.db,auth);
    registerReturnsFinance(app,deps.db,auth,deps.paymentGateway);
    registerPayouts(app,deps.db,auth,deps.payoutEvidenceGateway);
    registerAdminTeam(app,deps.db,auth);
    if(deps.paymentGateway&&deps.razorpayWebhookSecret)
      registerProtectedPayments(app,deps.db,auth,deps.paymentGateway);
    app.get('/api/v2/me',auth,async(_req,res,next)=>{
      try{
        const principal=res.locals.principal as {id:string;displayName:string};
        const roles=await listOwnMemberships(deps.db,principal.id);
        res.json({data:{id:principal.id,displayName:principal.displayName,
          adminRole:roles.adminRole,suppliers:roles.suppliers},requestId:res.locals.requestId});
      }catch(error){next(error);}
    });
    app.get('/api/v2/suppliers/:supplierId/access',auth,async(req,res,next)=>{
      try{
        const principal=res.locals.principal as {id:string};
        const scope=await requireSupplierPermission(deps.db,principal.id,req.params.supplierId,'SUPPLIER_READ');
        res.json({data:scope,requestId:res.locals.requestId});
      }catch(error){next(error);}
    });
    app.get('/api/v2/admin/access',auth,async(_req,res,next)=>{
      try{
        const principal=res.locals.principal as {id:string};
        const access=await requireAdminPermission(deps.db,principal.id,'ADMIN_READ');
        res.json({data:access,requestId:res.locals.requestId});
      }catch(error){next(error);}
    });
  }
  // Supplier-only dispatch is always gated by provider capture or selected COD; OTP verification requires an HMAC secret.

  app.use((_req,res)=>res.status(404).json(errorDTO('NOT_FOUND','Endpoint not found.',res.locals.requestId||randomUUID())));
  app.use(errorHandler);
  return app;
}
