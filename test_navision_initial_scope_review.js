'use strict';
const fs=require('fs');
function assert(value,message){if(!value)throw new Error(message);}
const app=fs.readFileSync('app.js','utf8');
const service=fs.readFileSync('navision-backend-service.js','utf8');
const migration=fs.readFileSync('supabase/staging_only/074_navision_initial_scope_exact_review.sql','utf8');
assert(app.includes("blockingState.safetyReason === 'unproven_empty_dealer_scope' && role === 'administrator'"),'Only an administrator may enter first-scope browser review');
assert(app.includes('service.approveInitialScope(rows, metadata)') && app.includes('service.preview(rows, metadata)'),'Approval must bind and then re-preview the exact rows');
assert(app.includes('It will still reject invalid rows, duplicate identities, cross-dealer matches and stale previews'),'Review confirmation must explain retained safety checks');
assert(service.includes("call('approve_navision_initial_scope'") && service.includes('p_rows: rows') && service.includes('p_dealer_code: dealerCode'),'Service must send exact rows and dealer to protected RPC');
assert(migration.includes("v_role<>'administrator'") && migration.includes("'administrator_required'"),'Server approval must require administrator role');
assert(migration.includes('v_total<100') && migration.includes("'initial_scope_requires_full_snapshot'"),'Tiny first snapshots must remain blocked');
assert(migration.includes('v_cross>0') && migration.includes("'cross_dealer_identity_overlap'"),'Cross-dealer identities must remain blocked');
assert(migration.includes("digest(convert_to(p_rows::text,'UTF8'),'sha256')") && migration.includes('a.approved_by=v_user') && migration.includes('a.expires_at>clock_timestamp()'),'Release must be exact-content, user-bound and expiring');
assert(migration.includes("v_reason='unproven_empty_dealer_scope'") && migration.includes("jsonb_set(v_result,'{blocking}','false'::jsonb,true)"),'Only the empty-scope bootstrap reason may be released');
console.log('Navision exact first-scope administrator review checks passed');
