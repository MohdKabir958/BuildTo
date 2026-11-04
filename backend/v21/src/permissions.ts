import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';

export type SupplierAction='SUPPLIER_READ'|'CATALOG_WRITE'|'INVENTORY_WRITE'|'ORDERS_FULFILL'|'FINANCE_READ'|'MEMBERS_MANAGE'|'DELIVERY_MANAGE'|'RFQ_QUOTE';
export type AdminAction='ADMIN_READ'|'SUPPLIER_APPROVE'|'CATALOG_APPROVE'|'FINANCE_MANAGE'|'SUPPORT_MANAGE'|'TEAM_MANAGE'|'AUDIT_READ'|'SERVICE_AREA_MANAGE'|'PROMOTION_MANAGE';
export type SupplierRole='OWNER'|'MANAGER'|'CATALOG'|'INVENTORY'|'FULFILLMENT'|'FINANCE'|'VIEWER';
export type AdminRole='OWNER'|'OPERATIONS'|'CATALOG'|'FINANCE'|'SUPPORT'|'AUDITOR';

export const SUPPLIER_PERMISSIONS:Readonly<Record<SupplierRole,readonly SupplierAction[]>>={
 OWNER:['SUPPLIER_READ','CATALOG_WRITE','INVENTORY_WRITE','ORDERS_FULFILL','FINANCE_READ','MEMBERS_MANAGE','DELIVERY_MANAGE','RFQ_QUOTE'],
 MANAGER:['SUPPLIER_READ','CATALOG_WRITE','INVENTORY_WRITE','ORDERS_FULFILL','FINANCE_READ','DELIVERY_MANAGE','RFQ_QUOTE'],
 CATALOG:['SUPPLIER_READ','CATALOG_WRITE','RFQ_QUOTE'],
 INVENTORY:['SUPPLIER_READ','INVENTORY_WRITE'],
 FULFILLMENT:['SUPPLIER_READ','ORDERS_FULFILL','DELIVERY_MANAGE'],
 FINANCE:['SUPPLIER_READ','FINANCE_READ'],
 VIEWER:['SUPPLIER_READ'],
};
export const ADMIN_PERMISSIONS:Readonly<Record<AdminRole,readonly AdminAction[]>>={
 OWNER:['ADMIN_READ','SUPPLIER_APPROVE','CATALOG_APPROVE','FINANCE_MANAGE','SUPPORT_MANAGE','TEAM_MANAGE','AUDIT_READ','SERVICE_AREA_MANAGE','PROMOTION_MANAGE'],
 OPERATIONS:['ADMIN_READ','SUPPLIER_APPROVE','SUPPORT_MANAGE','SERVICE_AREA_MANAGE','PROMOTION_MANAGE'],
 CATALOG:['ADMIN_READ','CATALOG_APPROVE'],
 FINANCE:['ADMIN_READ','FINANCE_MANAGE'],
 SUPPORT:['ADMIN_READ','SUPPORT_MANAGE'],
 AUDITOR:['ADMIN_READ','AUDIT_READ'],
};
export const isUuid=(v:unknown):v is string=>
 typeof v==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);

type SupplierDb=Pick<PrismaClient,'supplierMember'>;
type AdminDb=Pick<PrismaClient,'adminMembership'>;
type MembershipDb=Pick<PrismaClient,'supplierMember'|'adminMembership'>;

export async function requireSupplierPermission(
 db:SupplierDb,userId:string,supplierId:string,action:SupplierAction
):Promise<{supplierId:string;role:SupplierRole}> {
  if(!isUuid(supplierId))throw new ApiError(404,'NOT_FOUND','Resource not found.');
  const member=await db.supplierMember.findUnique({
    where:{supplierId_userId:{supplierId,userId}},
    select:{
      role:true,active:true,revokedAt:true,
      supplier:{select:{approval:true,suspendedAt:true}},
    },
  });
  // Return 404 for other suppliers as well as nonexistent suppliers; no enumeration.
  if(!member || !member.active || member.revokedAt || member.supplier.approval!=='APPROVED' ||
     member.supplier.suspendedAt)throw new ApiError(404,'NOT_FOUND','Resource not found.');
  const role=member.role as SupplierRole;
  if(!SUPPLIER_PERMISSIONS[role]?.includes(action))
    throw new ApiError(403,'PERMISSION_DENIED','Insufficient supplier permission.');
  return {supplierId,role};
}
export async function requireAdminPermission(
 db:AdminDb,userId:string,action:AdminAction
):Promise<{role:AdminRole}> {
  const member=await db.adminMembership.findUnique({
    where:{userId},select:{role:true,active:true,revokedAt:true},
  });
  if(!member || !member.active || member.revokedAt)
    throw new ApiError(403,'ADMIN_NOT_PROVISIONED','Administrator access not granted.');
  const role=member.role as AdminRole;
  if(!ADMIN_PERMISSIONS[role]?.includes(action))
    throw new ApiError(403,'PERMISSION_DENIED','Insufficient administrator permission.');
  return {role};
}
export async function listOwnMemberships(db:MembershipDb,userId:string) {
  const [admin,suppliers]=await Promise.all([
    db.adminMembership.findUnique({where:{userId},select:{role:true,active:true,revokedAt:true}}),
    db.supplierMember.findMany({
      where:{userId,active:true,revokedAt:null,supplier:{approval:'APPROVED',suspendedAt:null}},
      select:{supplierId:true,role:true},
      orderBy:{supplierId:'asc'},
      take:100,
    }),
  ]);
  return {
    adminRole:admin?.active&&!admin.revokedAt?admin.role:null,
    suppliers:suppliers.map(x=>({supplierId:x.supplierId,role:x.role})),
  };
}
