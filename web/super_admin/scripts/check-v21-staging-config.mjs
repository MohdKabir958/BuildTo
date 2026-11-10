#!/usr/bin/env node
// A15: release build contract, read-only and no credentials or database calls.
import {readFileSync} from 'node:fs';
import {loadEnv} from 'vite';

function assert(value,message){if(!value)throw new Error('A15_STAGING_CONFIG: '+message);}
const env=loadEnv('production',process.cwd(),'VITE_');
assert(env.VITE_ADMIN_VERSION==='v21','VITE_ADMIN_VERSION=v21 required, never silently fall back to Grozo');
assert(env.VITE_AUTH_MODE==='clerk-test','V2.1 staging requires development Clerk, never a live key');
const api=env.VITE_API_BASE_URL;
assert(api==='https://buildto-v21-staging.onrender.com','Exact reviewed V2.1 staging API origin required');
assert(env.VITE_SOCKET_URL===api,'Legacy auth build gate expects exact socket base; V2.1 never connects Socket.IO');
const key=env.VITE_CLERK_PUBLISHABLE_KEY||'';
assert(/^pk_test_[A-Za-z0-9+/=]+$/.test(key),'Development publishable key required');
const decoded=Buffer.from(key.slice('pk_test_'.length),'base64').toString('ascii');
const clerkHost='informed-griffon-7675.clerk.accounts.dev';
assert(decoded===clerkHost+'$','Public Clerk key must belong to the configured V2.1 development instance');

const deployment=JSON.parse(readFileSync(new URL('../vercel.json',import.meta.url),'utf8'));
const headers=deployment.headers?.find(rule=>rule.source==='/(.*)')?.headers||[];
const csp=headers.find(h=>h.key?.toLowerCase()==='content-security-policy')?.value||'';
assert(csp&&!csp.includes('*'),'No permissive/wildcard CSP');
const directives=Object.fromEntries(csp.split(';').filter(Boolean).map(str=>{
 const [name,...values]=str.trim().split(/\s+/);return [name,values];
}));
const clerkOrigin='https://'+clerkHost;
for(const directive of ['script-src','frame-src','connect-src'])
 assert(directives[directive]?.includes(clerkOrigin),'CSP must permit exact Clerk origin in '+directive);
assert(directives['connect-src']?.includes(api),'CSP must permit exact V2.1 API origin');
assert(directives['connect-src']?.includes('wss://buildto-v21-staging.onrender.com'),
 'Hosted auth gate expects exact socket-form origin, even though V2.1 uses HTTP only');
assert(directives['frame-ancestors']?.includes("'none'"),'CSP must prevent admin iframe embedding');
assert(directives['object-src']?.includes("'none'"),'No plugin embeds are permitted');

const html=readFileSync(new URL('../dist/index.html',import.meta.url),'utf8');
assert(html.includes('BuildTo Administration'),'Compiled V2.1 title must be BuildTo');
assert(html.includes('src="/assets/')||html.includes('type="module"'),'Expected Vite output not found');
console.log('PASS: A15 frontend staging contract, exact HTTPS API and Clerk origin, CSP and BuildTo build branding.');
console.log('NOTE: This is an offline build validation, not a live Clerk sign-in or API deployment assertion.');
