import type {SectionId} from '../navigation';
import type {AdminRole} from './adminSession';

// Presentation restriction only. Backend independently checks AdminMembership on each request.
const VIEWS:Readonly<Record<AdminRole,readonly SectionId[]>>={
 OWNER:['overview','suppliers','catalog','delivery','orders','support','finance','team','audit'],
 OPERATIONS:['overview','suppliers','delivery','orders','support'],
 CATALOG:['overview','catalog'],
 FINANCE:['overview','finance'],
 SUPPORT:['overview','orders','support'],
 AUDITOR:['overview','audit'],
};
export const canViewSection=(role:AdminRole,id:SectionId):boolean=>VIEWS[role].includes(id);
