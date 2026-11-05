import {
  BookOpenCheck, ClipboardCheck, FileClock, LayoutDashboard, Landmark,
  MapPin, Package, ShieldCheck, ShoppingCart, Store, UsersRound,
} from 'lucide-react';
import type {LucideIcon} from 'lucide-react';

export type SectionId =
  | 'overview' | 'suppliers' | 'catalog' | 'delivery' | 'orders'
  | 'support' | 'finance' | 'team' | 'audit';

export type Section = {
  id:SectionId;
  label:string;
  caption:string;
  group:'Marketplace'|'Operations'|'Administration';
  icon:LucideIcon;
  plannedPr:string;
};

export const SECTIONS:readonly Section[]=[
  {id:'overview',label:'Overview',caption:'Live operational summary',group:'Marketplace',icon:LayoutDashboard,plannedPr:'A09'},
  {id:'suppliers',label:'Suppliers',caption:'Applications, documents and approval',group:'Marketplace',icon:Store,plannedPr:'A05–A06'},
  {id:'catalog',label:'Catalog',caption:'Construction materials and listings',group:'Marketplace',icon:Package,plannedPr:'A07'},
  {id:'delivery',label:'Delivery areas',caption:'Cities, PIN codes and seller coverage',group:'Marketplace',icon:MapPin,plannedPr:'A08'},
  {id:'orders',label:'Orders',caption:'Marketplace order and shipment oversight',group:'Operations',icon:ShoppingCart,plannedPr:'A10'},
  {id:'support',label:'Customer care',caption:'Support, returns and review moderation',group:'Operations',icon:ClipboardCheck,plannedPr:'A11'},
  {id:'finance',label:'Finance',caption:'Evidence-based reconciliation',group:'Operations',icon:Landmark,plannedPr:'A12–A13'},
  {id:'team',label:'Team & access',caption:'Manage administrator membership',group:'Administration',icon:UsersRound,plannedPr:'A04'},
  {id:'audit',label:'Audit trail',caption:'Read-only review of access and changes',group:'Administration',icon:FileClock,plannedPr:'A14'},
] as const;

export const FEATURE_ORDER:readonly SectionId[]=['suppliers','catalog','delivery','orders'];
export const FEATURE_ICONS={verified:ShieldCheck,contract:BookOpenCheck};
