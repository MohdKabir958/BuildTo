import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import type {PrismaClient} from '../../generated/buildto-v21';

// The baseline's SHA256 must match what Prisma officially recorded via migrate
// deploy or migrate resolve. A table named _prisma_migrations is NOT sufficient.
const MIGRATION='20261103_buildto_v21_initial';
const FILE=resolve(__dirname,'../../prisma/v21/migrations',MIGRATION,'migration.sql');
export function expectedBaselineChecksum():string {
 return createHash('sha256').update(readFileSync(FILE)).digest('hex');
}
export async function assertV21BaselineApplied(db:Pick<PrismaClient,'$queryRaw'>):Promise<void> {
 let rows:{checksum:string}[];
 try {
   rows=await db.$queryRaw`
     SELECT checksum FROM "_prisma_migrations"
     WHERE migration_name='20261103_buildto_v21_initial'
       AND finished_at IS NOT NULL AND rolled_back_at IS NULL
   `;
 }catch {
   throw new Error('V21_MIGRATION_LEDGER_REQUIRED: cannot verify migration baseline.');
 }
 if(rows.length!==1||rows[0]?.checksum!==expectedBaselineChecksum())
   throw new Error('V21_MIGRATION_CHECKSUM_MISMATCH: baseline is not fully applied or has been modified.');
}
